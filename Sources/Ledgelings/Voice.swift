import AppKit
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
/// Every line a speech model says is kept in the `VoiceArchive` (with Keep on),
/// and a line already kept in the same voice and speed is played from there,
/// free, instead of being asked for again.
///
/// Lines are said one at a time, in the order they came. When talk runs ahead
/// of the voice (several pairs at once, a slow network), lines past
/// `mostWaiting` are skipped rather than read out long after their bubble is gone.
@MainActor
final class Voice: NSObject, ObservableObject {
    static let mostWaiting = 4

    let settings: AppSettings
    let spend: SpendLedger
    /// Where each paid line's cost is noted beside its conversation. Nil: nowhere.
    let history: ChatHistory?
    let archive: VoiceArchive
    /// Everything in the archive, loaded once and added to as lines are kept.
    @Published private(set) var clips: [VoiceArchive.Clip]
    /// The last thing that happened, for the settings window.
    @Published private(set) var status = "not tried yet"
    /// OpenRouter's speech models, once fetched.
    @Published private(set) var models: [SpeechClient.Model] = []

    private let synthesizer = AVSpeechSynthesizer()
    /// OpenRouter's clips play through a varispeed, the tape-machine way: faster
    /// is higher. A time-stretching pitch shifter was tried first and smeared
    /// every line into an echo. To keep the pace, the line is asked for that
    /// much slower (`SpeechClient.speed`), then sped back up here.
    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private let shifter = AVAudioUnitVarispeed()
    /// The audio format each speech model sends: PCM unless it refused.
    private var formats: [String: String] = [:]
    /// Lines queued or being said, both engines.
    private var waiting = 0
    /// The names of the creatures on screen, in order. Voices are handed out
    /// over this whole list, so Test and the live talk agree on who sounds how.
    var cast: () -> [String] = { [] }
    /// What happens to one line's sound, for its bubble: dots until `started`,
    /// then the text types out, fully shown at `done`. `dropped` means it will
    /// not be said after all (stopped, failed): show the text at once.
    enum Cue: Equatable {
        /// With the clip's length when it is known up front (OpenRouter); nil for
        /// a voice that reports its progress instead (the Mac's own).
        case started(duration: Double?)
        /// Share of the line said so far, the Mac's voices only.
        case progress(Double)
        case done
        case dropped
    }
    typealias CueHandler = @MainActor (Cue) -> Void

    /// Bumped by `stop()`: an OpenRouter line from before it gives up instead of playing.
    private var epoch = 0
    /// The bubbles waiting on the Mac's voice, by utterance, with the line's length.
    private var spoken: [ObjectIdentifier: (cue: CueHandler, length: Int)] = [:]
    /// The OpenRouter line being said; the next one waits for it.
    private var chain: Task<Void, Never>?
    private var watchers: Set<AnyCancellable> = []

    static var defaultArchive: URL { SpendLedger.defaultDirectory.appendingPathComponent("voices", isDirectory: true) }

    init(settings: AppSettings, spend: SpendLedger, history: ChatHistory? = nil, archive: URL = Voice.defaultArchive) {
        self.settings = settings
        self.spend = spend
        self.history = history
        self.archive = VoiceArchive(directory: archive)
        clips = self.archive.clips()
        super.init()
        synthesizer.delegate = self
        engine.attach(player)
        engine.attach(shifter)
        // Switching voice off silences whatever is still being said.
        settings.$voiceEnabled.sink { [weak self] on in if !on { self?.stop() } }.store(in: &watchers)
        settings.$voiceEngine.dropFirst().sink { [weak self] _ in self?.stop() }.store(in: &watchers)
    }

    // MARK: Speaking

    /// A creature's line, if voice is on. `name` is who says it. True when the
    /// line will be said, and `cue` will hear how it goes (always ending in
    /// `done` or `dropped`); false when it will not, so show the text now.
    @discardableResult
    func say(_ text: String, as name: String, cue: CueHandler? = nil) -> Bool {
        guard settings.voiceEnabled else { return false }
        return speak(text, as: name, cast: cast(), cue: cue)
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
        epoch += 1
        let pending = spoken.values.map(\.cue)
        spoken.removeAll()
        synthesizer.stopSpeaking(at: .immediate)
        chain?.cancel()
        chain = nil
        player.stop()
        waiting = 0
        pending.forEach { $0(.dropped) }
    }

    @discardableResult
    private func speak(_ text: String, as name: String, cast: [String], cue: CueHandler? = nil) -> Bool {
        let line = Voices.speakable(text)
        guard !line.isEmpty else { return false }
        guard waiting < Self.mostWaiting else { status = "skipped a line: still saying the ones before it"; return false }
        switch settings.voiceEngine {
        case .system: return speakHere(line, as: name, cast: cast, cue: cue)
        case .openRouter: return speakOnline(line, as: name, cast: cast, cue: cue)
        }
    }

    private func speakHere(_ line: String, as name: String, cast: [String], cue: CueHandler?) -> Bool {
        let utterance = AVSpeechUtterance(string: line)
        if settings.voicePerCharacter {
            let fun = settings.cartoonVoices ? Self.cartoonVoices : []
            let pool = (fun.count >= 2 ? fun : Self.characterVoices).map(\.identifier)
            utterance.voice = Voices.assign(cast + [name], pool: pool)[name].flatMap(AVSpeechSynthesisVoice.init(identifier:))
        } else {
            utterance.voice = settings.systemVoice.isEmpty ? nil : AVSpeechSynthesisVoice(identifier: settings.systemVoice)
        }
        utterance.pitchMultiplier = Float(min(max(pitch(for: name), 0.5), 2))
        utterance.rate = min(max(AVSpeechUtteranceDefaultSpeechRate * Float(settings.voiceSpeed), AVSpeechUtteranceMinimumSpeechRate),
                             AVSpeechUtteranceMaximumSpeechRate)
        utterance.volume = Float(settings.voiceVolume)
        waiting += 1
        if let cue { spoken[ObjectIdentifier(utterance)] = (cue, (line as NSString).length) }
        synthesizer.speak(utterance)
        status = "\(name): \(utterance.voice?.name ?? "system voice")"
        return true
    }

    private func speakOnline(_ line: String, as name: String, cast: [String], cue: CueHandler?) -> Bool {
        let key = settings.openRouterKey.trimmingCharacters(in: .whitespaces)
        guard !key.isEmpty else { status = "no OpenRouter API key; add one in Settings › Talk"; return false }
        let client = SpeechClient(key: key, model: settings.voiceModel.trimmingCharacters(in: .whitespaces))
        let perCharacter = settings.voicePerCharacter, chosen = settings.openRouterVoice, speed = settings.voiceSpeed
        let keep = settings.keepVoices, saidAt = Date(), cartoon = settings.cartoonVoices, pitch = pitch(for: name)
        waiting += 1
        // Fetch now, while the line before is still playing; play in turn.
        let fetch = Task { [weak self] () async throws -> (audio: Data, generation: String?, voice: String?, kept: Bool) in
            let voices = (try? await self?.voices(of: client.model)) ?? []
            let pool = Voices.englishFirst(voices)
            let voice = perCharacter ? Voices.assign(cast + [name], pool: cartoon ? Voices.cartoonFirst(pool) : pool)[name]
                                     : (chosen.isEmpty ? voices.first : chosen)
            // Asked slower by the pitch, sped back up by it as it plays: the pace stays.
            let asked = speed / pitch
            let key = VoiceArchive.key(text: line, model: client.model, voice: voice ?? "", speed: asked)
            if let self, let file = archive.find(key: key, in: clips), let audio = try? Data(contentsOf: file) {
                return (audio, nil, voice, true)
            }
            let format = self?.formats[client.model] ?? "pcm"
            let audio: Data, generation: String?
            do {
                (audio, generation) = try await client.speak(line, voice: voice, speed: asked, format: format)
            } catch ChatClient.Failure.refused(let message) {
                guard let other = SpeechClient.otherFormat(after: message, tried: format) else { throw ChatClient.Failure.refused(message) }
                self?.formats[client.model] = other
                (audio, generation) = try await client.speak(line, voice: voice, speed: asked, format: other)
            }
            if keep, let self { self.keep(audio, speaker: name, text: line, model: client.model, voice: voice ?? "", speed: asked) }
            return (audio, generation, voice, false)
        }
        let before = chain, epoch = epoch
        chain = Task { [weak self] in
            await before?.value
            // Every way out tells the bubble: said, or not said after all.
            var ending = Cue.dropped
            defer {
                cue?(ending)
                if let self, self.epoch == epoch, self.waiting > 0 { self.waiting -= 1 }
            }
            do {
                let said = try await fetch.value
                guard let self, self.epoch == epoch, !Task.isCancelled else { return }
                if said.kept {
                    self.history?.recordVoice(.init(time: saidAt, speaker: name, text: line, model: client.model, cost: 0, kept: true))
                } else if let generation = said.generation {
                    self.charge(client, generation, speaker: name, text: line, at: saidAt)
                }
                self.status = "\(name): \(said.voice ?? "default voice") on \(client.model)" + (said.kept ? ", kept copy, free" : "")
                try await self.play(said.audio, pitch: pitch) { cue?(.started(duration: $0)) }
                ending = .done
            } catch is CancellationError {
            } catch {
                self?.status = "\(error)"
                FileHandle.standardError.write(Data("Ledgelings voice: \(error)\n".utf8))
            }
        }
        return true
    }

    /// How high `name` speaks: the Pitch slider, times a cartoon lift or a small
    /// nudge of its own when every character has a voice of their own.
    private func pitch(for name: String) -> Double {
        let own = settings.cartoonVoices ? Voices.cartoonPitch(for: name)
            : settings.voicePerCharacter ? Voices.pitchNudge(for: name) : 1
        return settings.voicePitch * own
    }

    /// Play a clip to its end, `pitch` times faster and so that much higher.
    /// `started` hears how long it takes the moment it starts.
    private func play(_ audio: Data, pitch: Double, started: (Double) -> Void) async throws {
        // AVAudioFile reads from a file only; the name tells it WAV from MP3.
        let isWAV = audio.prefix(4) == Data("RIFF".utf8)
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("ledgelings-\(UUID().uuidString).\(isWAV ? "wav" : "mp3")")
        try audio.write(to: file)
        defer { try? FileManager.default.removeItem(at: file) }
        let clip = try AVAudioFile(forReading: file)
        engine.connect(player, to: shifter, format: clip.processingFormat)
        engine.connect(shifter, to: engine.mainMixerNode, format: clip.processingFormat)
        let rate = min(max(pitch, 0.25), 4)
        shifter.rate = Float(rate)
        player.volume = Float(settings.voiceVolume)
        if !engine.isRunning { try engine.start() }
        let duration = Double(clip.length) / clip.processingFormat.sampleRate / rate
        player.scheduleFile(clip, at: nil, completionHandler: nil)
        player.play()
        started(duration)
        try await Task.sleep(for: .seconds(duration + 0.15))
        player.stop()
    }

    /// Into the spend file, and beside its conversation in the chat log, priced
    /// once OpenRouter says what it cost.
    private func charge(_ client: SpeechClient, _ generation: String, speaker: String, text: String, at time: Date) {
        Task { [weak self] in
            let usage = await client.cost(of: generation) ?? Spend.Usage(promptTokens: 0, completionTokens: 0, cost: nil)
            self?.spend.record(provider: .openRouter, model: client.model, usage: usage)
            self?.history?.recordVoice(.init(time: time, speaker: speaker, text: text, model: client.model, cost: usage.cost))
        }
    }

    private func keep(_ audio: Data, speaker: String, text: String, model: String, voice: String, speed: Double) {
        do { clips.append(try archive.keep(audio, speaker: speaker, text: text, model: model, voice: voice, speed: speed)) }
        catch { FileHandle.standardError.write(Data("Ledgelings voice archive: \(error)\n".utf8)) }
    }

    func revealArchive() {
        try? FileManager.default.createDirectory(at: archive.directory, withIntermediateDirectories: true)
        NSWorkspace.shared.open(archive.directory)
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

    /// Mac voices that sing their lines rather than say them: fun once, not all day.
    static let singers: Set<String> = ["Bells", "Cellos", "Organ", "Good News", "Bad News"]

    /// The voices handed out with Cartoon voices on: the Mac's character voices
    /// (Grandma, Grandpa, Rocko, Shelley…) and the old talking novelty voices
    /// (Zarvox, Bubbles, Junior, Trinoids…), minus the ones that sing.
    static var cartoonVoices: [AVSpeechSynthesisVoice] {
        let region = Locale.current.region?.identifier ?? "US"
        var byName: [String: AVSpeechSynthesisVoice] = [:]
        for voice in systemVoices where !singers.contains(voice.name)
            && (voice.identifier.contains(".eloquence.") || voice.identifier.contains(".speech.synthesis.voice.")) {
            if let kept = byName[voice.name], kept.language.hasSuffix(region) || !voice.language.hasSuffix(region) { continue }
            byName[voice.name] = voice
        }
        return byName.values.sorted { $0.identifier < $1.identifier }
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
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didStart utterance: AVSpeechUtterance) {
        let id = ObjectIdentifier(utterance)
        Task { @MainActor in self.spoken[id]?.cue(.started(duration: nil)) }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, willSpeakRangeOfSpeechString range: NSRange,
                                       utterance: AVSpeechUtterance) {
        let id = ObjectIdentifier(utterance), end = range.location + range.length
        Task { @MainActor in
            guard let waiting = self.spoken[id], waiting.length > 0 else { return }
            waiting.cue(.progress(Double(end) / Double(waiting.length)))
        }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        let id = ObjectIdentifier(utterance)
        Task { @MainActor in self.finished(id, .done) }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        let id = ObjectIdentifier(utterance)
        Task { @MainActor in self.finished(id, .dropped) }
    }

    private func finished(_ id: ObjectIdentifier, _ how: Cue) {
        if waiting > 0 { waiting -= 1 }
        spoken.removeValue(forKey: id)?.cue(how)
    }
}
