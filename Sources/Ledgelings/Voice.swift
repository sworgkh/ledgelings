import AVFoundation
import Combine
import LedgelingsCore

/// The creatures' lines, out loud. Every bubble that goes up is handed here;
/// with voice on, it is read in the speaker's own voice.
///
/// Two engines. The Mac's own voices (`AVSpeechSynthesizer`) are free, offline
/// and instant. OpenRouter's speech models sound far better, cost a little per
/// line, and need the same key as the brain; each line is fetched as MP3 and
/// played in order, and its price is looked up afterwards for the spend file.
///
/// Lines are said one at a time, in the order they came. When talk runs ahead
/// of the voice (several pairs at once, a slow network), lines past
/// `mostWaiting` are skipped rather than read out long after their bubble is gone.
@MainActor
final class Voice: NSObject, ObservableObject {
    static let mostWaiting = 4

    let settings: AppSettings
    let spend: SpendLedger
    /// The last thing that happened, for the settings window.
    @Published private(set) var status = "not tried yet"
    /// OpenRouter's speech models, once fetched.
    @Published private(set) var models: [SpeechClient.Model] = []

    private let synthesizer = AVSpeechSynthesizer()
    private var player: AVAudioPlayer?
    /// Lines queued or being said, both engines.
    private var waiting = 0
    /// The names of the creatures on screen, in order. Voices are handed out
    /// over this whole list, so Test and the live talk agree on who sounds how.
    var cast: () -> [String] = { [] }
    /// The OpenRouter line being said; the next one waits for it.
    private var chain: Task<Void, Never>?
    private var watchers: Set<AnyCancellable> = []

    init(settings: AppSettings, spend: SpendLedger) {
        self.settings = settings
        self.spend = spend
        super.init()
        synthesizer.delegate = self
        // Switching voice off silences whatever is still being said.
        settings.$voiceEnabled.sink { [weak self] on in if !on { self?.stop() } }.store(in: &watchers)
        settings.$voiceEngine.dropFirst().sink { [weak self] _ in self?.stop() }.store(in: &watchers)
    }

    // MARK: Speaking

    /// A creature's line, if voice is on. `name` is who says it.
    func say(_ text: String, as name: String) {
        guard settings.voiceEnabled else { return }
        speak(text, as: name, cast: cast())
    }

    /// The settings window's Test: the first three on screen introduce themselves, voice on or off.
    func introduce() {
        stop()
        let everyone = cast()
        var seen: [String] = []
        for name in everyone where !seen.contains(name) && seen.count < 3 { seen.append(name) }
        guard !seen.isEmpty else { status = "nobody on screen to test with"; return }
        for (i, name) in seen.enumerated() {
            speak(i == 0 ? "Hi, I'm \(name). This is how I sound." : "And I'm \(name).", as: name, cast: everyone)
        }
    }

    func stop() {
        synthesizer.stopSpeaking(at: .immediate)
        chain?.cancel()
        chain = nil
        player?.stop()
        player = nil
        waiting = 0
    }

    private func speak(_ text: String, as name: String, cast: [String]) {
        let line = Voices.speakable(text)
        guard !line.isEmpty else { return }
        guard waiting < Self.mostWaiting else { status = "skipped a line: still saying the ones before it"; return }
        switch settings.voiceEngine {
        case .system: speakHere(line, as: name, cast: cast)
        case .openRouter: speakOnline(line, as: name, cast: cast)
        }
    }

    private func speakHere(_ line: String, as name: String, cast: [String]) {
        let utterance = AVSpeechUtterance(string: line)
        if settings.voicePerCharacter {
            let pool = Self.characterVoices.map(\.identifier)
            utterance.voice = Voices.assign(cast + [name], pool: pool)[name].flatMap(AVSpeechSynthesisVoice.init(identifier:))
            utterance.pitchMultiplier = Float(min(max(settings.voicePitch * Voices.pitchNudge(for: name), 0.5), 2))
        } else {
            utterance.voice = settings.systemVoice.isEmpty ? nil : AVSpeechSynthesisVoice(identifier: settings.systemVoice)
            utterance.pitchMultiplier = Float(settings.voicePitch)
        }
        utterance.rate = min(max(AVSpeechUtteranceDefaultSpeechRate * Float(settings.voiceSpeed), AVSpeechUtteranceMinimumSpeechRate),
                             AVSpeechUtteranceMaximumSpeechRate)
        utterance.volume = Float(settings.voiceVolume)
        waiting += 1
        synthesizer.speak(utterance)
        status = "\(name): \(utterance.voice?.name ?? "system voice")"
    }

    private func speakOnline(_ line: String, as name: String, cast: [String]) {
        let key = settings.openRouterKey.trimmingCharacters(in: .whitespaces)
        guard !key.isEmpty else { status = "no OpenRouter API key; add one in Settings › Talk"; return }
        let client = SpeechClient(key: key, model: settings.voiceModel.trimmingCharacters(in: .whitespaces))
        let perCharacter = settings.voicePerCharacter, chosen = settings.openRouterVoice, speed = settings.voiceSpeed
        waiting += 1
        // Fetch now, while the line before is still playing; play in turn.
        let fetch = Task { [weak self] () async throws -> (audio: Data, generation: String?, voice: String?) in
            let voices = (try? await self?.voices(of: client.model)) ?? []
            let voice = perCharacter ? Voices.assign(cast + [name], pool: Voices.englishFirst(voices))[name]
                                     : (chosen.isEmpty ? voices.first : chosen)
            let (audio, generation) = try await client.speak(line, voice: voice, speed: speed)
            return (audio, generation, voice)
        }
        let before = chain
        chain = Task { [weak self] in
            await before?.value
            defer { if let self, self.waiting > 0 { self.waiting -= 1 } }
            do {
                let said = try await fetch.value
                guard let self, !Task.isCancelled else { return }
                if let generation = said.generation { self.charge(client, generation) }
                self.status = "\(name): \(said.voice ?? "default voice") on \(client.model)"
                try await self.play(said.audio)
            } catch is CancellationError {
            } catch {
                self?.status = "\(error)"
                FileHandle.standardError.write(Data("Ledgelings voice: \(error)\n".utf8))
            }
        }
    }

    private func play(_ audio: Data) async throws {
        let player = try AVAudioPlayer(data: audio)
        player.volume = Float(settings.voiceVolume)
        self.player = player
        player.play()
        try await Task.sleep(for: .seconds(player.duration + 0.15))
    }

    /// Into the spend file, priced once OpenRouter says what it cost.
    private func charge(_ client: SpeechClient, _ generation: String) {
        Task { [weak self] in
            let usage = await client.cost(of: generation) ?? Spend.Usage(promptTokens: 0, completionTokens: 0, cost: nil)
            self?.spend.record(provider: .openRouter, model: client.model, usage: usage)
        }
    }

    // MARK: What there is to choose from

    /// Every speech model on OpenRouter, fetched once and kept.
    @discardableResult
    func loadModels(again: Bool = false) async throws -> [SpeechClient.Model] {
        if !again, !models.isEmpty { return models }
        models = try await SpeechClient.models()
        return models
    }

    func voices(of model: String) async throws -> [String] {
        try await loadModels().first { $0.id == model }?.voices ?? []
    }

    /// The Mac's voices in the user's language (English when there are none),
    /// novelty voices such as Bells and Zarvox included, for choosing one.
    static var systemVoices: [AVSpeechSynthesisVoice] {
        let language = Locale.current.language.languageCode?.identifier ?? "en"
        let all = AVSpeechSynthesisVoice.speechVoices()
        let mine = all.filter { $0.language.hasPrefix(language) }
        return (mine.isEmpty ? all.filter { $0.language.hasPrefix("en") } : mine)
            .sorted { ($0.name, $0.language) < ($1.name, $1.language) }
    }

    /// The voices handed out one per character: no novelty voices, and each
    /// name once, the user's own region first (Eddy in en-US over Eddy in en-GB).
    static var characterVoices: [AVSpeechSynthesisVoice] {
        let region = Locale.current.region?.identifier ?? "US"
        var byName: [String: AVSpeechSynthesisVoice] = [:]
        for voice in systemVoices where !voice.voiceTraits.contains(.isNoveltyVoice) && !voice.voiceTraits.contains(.isPersonalVoice) {
            if let kept = byName[voice.name], kept.language.hasSuffix(region) || !voice.language.hasSuffix(region) { continue }
            byName[voice.name] = voice
        }
        return byName.values.sorted { $0.identifier < $1.identifier }
    }
}

extension Voice: AVSpeechSynthesizerDelegate {
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in if self.waiting > 0 { self.waiting -= 1 } }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        Task { @MainActor in if self.waiting > 0 { self.waiting -= 1 } }
    }
}
