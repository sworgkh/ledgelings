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
/// free, instead of being asked for again. The built-in lines (the script's,
/// the ready-made notes) are kept apart in `lineArchive`, on both OpenRouter and
/// the local server, with `reuseLineVoices`: they come round again and again, so
/// each is made once in each voice and played from disk after that.
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
    /// The built-in lines' sounds, kept beside the script rather than in the archive.
    let lineArchive: VoiceArchive
    @Published private(set) var lineClips: [VoiceArchive.Clip]
    /// The last thing that happened, for the settings window.
    @Published private(set) var status = "not tried yet"
    /// OpenRouter's speech models, once fetched.
    @Published private(set) var models: [SpeechClient.Model] = []
    /// The local server's voices, once fetched.
    @Published private(set) var localVoices: [String] = []

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
    /// Speech models that refused the speed parameter; asked without it.
    private var noSpeed: Set<String> = []
    /// Lines queued or being said, both engines.
    private var waiting = 0
    /// The names of the creatures on screen, in order. Voices are handed out
    /// over this whole list, so Test and the live talk agree on who sounds how.
    var cast: () -> [String] = { [] }
    /// Who a character is, by name: its description and its species' kind, for casting.
    var describe: (String) -> (persona: String, kind: String)? = { _ in nil }
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
    static var defaultLineArchive: URL { SpendLedger.defaultDirectory.appendingPathComponent("line-voices", isDirectory: true) }

    init(settings: AppSettings, spend: SpendLedger, history: ChatHistory? = nil,
         archive: URL = Voice.defaultArchive, lineArchive: URL = Voice.defaultLineArchive) {
        self.settings = settings
        self.spend = spend
        self.history = history
        self.archive = VoiceArchive(directory: archive)
        clips = self.archive.clips()
        self.lineArchive = VoiceArchive(directory: lineArchive)
        lineClips = self.lineArchive.clips()
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
    /// `builtIn`: a line written in advance, whose sound is worth keeping for next time.
    @discardableResult
    func say(_ text: String, as name: String, builtIn: Bool = false, cue: CueHandler? = nil) -> Bool {
        guard settings.voiceEnabled else { return false }
        return speak(text, as: name, cast: cast(), builtIn: builtIn, cue: cue)
    }

    /// The settings window's Test: the first three on screen introduce themselves, voice on or off.
    func introduce() {
        stop()
        let everyone = cast()
        var seen: [String] = []
        for name in everyone where !seen.contains(name) && seen.count < 3 { seen.append(name) }
        guard !seen.isEmpty else { status = "nobody on screen to test with"; return }
        for (i, name) in seen.enumerated() {
            speak(i == 0 ? "Hi, I'm \(name). This is how I sound." : "And I'm \(name).", as: name, cast: everyone, builtIn: true)
        }
    }

    func stop() {
        epoch += 1
        prefetched.values.forEach { $0.task.cancel() }
        prefetched.removeAll()
        prefetchOrder.removeAll()
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
    private func speak(_ text: String, as name: String, cast: [String], builtIn: Bool = false, cue: CueHandler? = nil) -> Bool {
        let line = Voices.speakable(text)
        guard !line.isEmpty else { return false }
        guard waiting < Self.mostWaiting else { status = "skipped a line: still saying the ones before it"; return false }
        switch settings.voiceEngine {
        case .system: return speakHere(line, as: name, cast: cast, cue: cue)
        case .openRouter, .local: return speakOnline(line, as: name, cast: cast, builtIn: builtIn, cue: cue)
        }
    }

    private func speakHere(_ line: String, as name: String, cast: [String], cue: CueHandler?) -> Bool {
        if followsPitch(name) { return speakHereLikeTape(line, as: name, cast: cast, cue: cue) }
        let utterance = AVSpeechUtterance(string: line)
        utterance.voice = systemVoice(for: name, cast: cast).flatMap(AVSpeechSynthesisVoice.init(identifier:))
        utterance.pitchMultiplier = Float(min(max(pitch(for: name), 0.5), 2))
        utterance.rate = min(max(AVSpeechUtteranceDefaultSpeechRate * Float(speed(for: name)), AVSpeechUtteranceMinimumSpeechRate),
                             AVSpeechUtteranceMaximumSpeechRate)
        utterance.volume = Float(settings.voiceVolume)
        waiting += 1
        if let cue { spoken[ObjectIdentifier(utterance)] = (cue, (line as NSString).length) }
        synthesizer.speak(utterance)
        status = "\(name): \(utterance.voice?.name ?? "system voice")"
        return true
    }

    /// OpenRouter, or a speech server on this Mac: fetched, then played in turn.
    /// A local line is free, so it is neither kept, priced nor looked up in the
    /// archive; a built-in one is still kept in `lineArchive`, as making it takes time.
    /// One line's sound on its way: the fetch already running, and what playing it needs.
    private struct Fetch {
        let task: Task<(audio: Data, generation: String?, voice: String?, kept: Bool), Error>
        let client: SpeechClient
        let pitch: Double
        let local: Bool
        let keep: Bool
        let saidAt: Date
    }

    /// Lines whose sound was asked for before their turn (`prefetch`), by speaker and words.
    private var prefetched: [String: Fetch] = [:]
    private var prefetchOrder: [String] = []
    private static let mostPrefetched = 8

    private static func prefetchKey(_ name: String, _ line: String) -> String { name + "\u{1F}" + line }

    /// Start fetching a line's sound before its turn comes, so it plays the moment
    /// the line before it ends instead of after a wait for the network. The Mac's
    /// own voices need no head start.
    func prefetch(_ text: String, as name: String, builtIn: Bool = false) {
        guard settings.voiceEnabled, settings.voiceEngine != .system else { return }
        let line = Voices.speakable(text)
        let key = Self.prefetchKey(name, line)
        guard !line.isEmpty, prefetched[key] == nil, let fetch = startFetch(line, as: name, cast: cast(), builtIn: builtIn) else { return }
        prefetched[key] = fetch
        prefetchOrder.append(key)
        while prefetchOrder.count > Self.mostPrefetched { prefetched.removeValue(forKey: prefetchOrder.removeFirst())?.task.cancel() }
    }

    /// The fetch for one line, started now; nil (with `status` saying why) when it cannot be.
    private func startFetch(_ line: String, as name: String, cast: [String], builtIn: Bool) -> Fetch? {
        let local = settings.voiceEngine == .local
        let client: SpeechClient
        if local {
            guard let server = settings.localVoiceURL else { status = "the local server's address is not a URL"; return nil }
            client = SpeechClient(key: "", model: settings.localVoiceModel.trimmingCharacters(in: .whitespaces), server: server)
        } else {
            let key = settings.openRouterKey.trimmingCharacters(in: .whitespaces)
            guard !key.isEmpty else { status = "no OpenRouter API key; add one in Settings › Talk"; return nil }
            client = SpeechClient(key: key, model: settings.voiceModel.trimmingCharacters(in: .whitespaces))
        }
        let speed = speed(for: name)
        let reuse = builtIn && settings.reuseLineVoices
        let keep = settings.keepVoices && !local && !reuse, saidAt = Date(), pitch = pitch(for: name), follow = followsPitch(name)
        let task = Task { [weak self] () async throws -> (audio: Data, generation: String?, voice: String?, kept: Bool) in
            let voices = local ? ((try? await self?.loadLocalVoices()) ?? []) : ((try? await self?.voices(of: client.model)) ?? [])
            let voice = self?.onlineVoice(for: name, cast: cast, among: voices)
            // Asked slower by the pitch, sped back up by it as it plays: the pace stays.
            let asked = Voices.askedSpeed(speed: speed, pitch: pitch, followPitch: follow)
            let key = VoiceArchive.key(text: line, model: client.model, voice: voice ?? "", speed: asked)
            if reuse, let self, let file = lineArchive.find(key: key, in: lineClips), let audio = try? Data(contentsOf: file) {
                return (audio, nil, voice, true)
            }
            if !local, let self, let file = archive.find(key: key, in: clips), let audio = try? Data(contentsOf: file) {
                return (audio, nil, voice, true)
            }
            // A refusal about the format or the speed is answered once each, and remembered.
            var format = self?.formats[client.model] ?? (local ? "wav" : "pcm")
            var sendSpeed = !(self?.noSpeed.contains(client.model) ?? false)
            var reply: (audio: Data, generation: String?)?
            for attempt in 0..<3 where reply == nil {
                do {
                    reply = try await client.speak(line, voice: voice, speed: sendSpeed ? asked : nil, format: format)
                } catch ChatClient.Failure.refused(let message) where attempt < 2 {
                    if let other = SpeechClient.otherFormat(after: message, tried: format) {
                        format = other
                        self?.formats[client.model] = other
                    } else if sendSpeed, SpeechClient.refusesSpeed(message) {
                        sendSpeed = false
                        self?.noSpeed.insert(client.model)
                    } else {
                        throw ChatClient.Failure.refused(message)
                    }
                }
            }
            guard let (audio, generation) = reply else { throw ChatClient.Failure.badReply("no audio") }
            if keep, let self { self.keep(audio, speaker: name, text: line, model: client.model, voice: voice ?? "", speed: asked) }
            if reuse, let self { self.keepLine(audio, speaker: name, text: line, model: client.model, voice: voice ?? "", speed: asked) }
            return (audio, generation, voice, false)
        }
        return Fetch(task: task, client: client, pitch: pitch, local: local, keep: keep, saidAt: saidAt)
    }

    /// One line's sound, fetched or found as `say` would, without playing it.
    /// Kept: it came from disk. Nil when it could not even be asked for.
    func sound(for text: String, as name: String, builtIn: Bool) async throws -> (audio: Data, kept: Bool)? {
        guard let fetch = startFetch(Voices.speakable(text), as: name, cast: cast(), builtIn: builtIn) else { return nil }
        let said = try await fetch.task.value
        return (said.audio, said.kept)
    }

    private func speakOnline(_ line: String, as name: String, cast: [String], builtIn: Bool, cue: CueHandler?) -> Bool {
        let key = Self.prefetchKey(name, line)
        let fetch: Fetch
        if let ready = prefetched.removeValue(forKey: key) {
            fetch = ready
            prefetchOrder.removeAll { $0 == key }
        } else {
            guard let started = startFetch(line, as: name, cast: cast, builtIn: builtIn) else { return false }
            fetch = started
        }
        let client = fetch.client, pitch = fetch.pitch, local = fetch.local, saidAt = fetch.saidAt
        waiting += 1
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
                let said = try await fetch.task.value
                guard let self, self.epoch == epoch, !Task.isCancelled else { return }
                if said.kept, !local {
                    self.history?.recordVoice(.init(time: saidAt, speaker: name, text: line, model: client.model, cost: 0, kept: true))
                } else if !local, let generation = said.generation {
                    self.charge(client, generation, speaker: name, text: line, at: saidAt)
                }
                self.status = "\(name): \(said.voice ?? "default voice") on \(local ? "local " : "")\(client.model)" + (said.kept ? ", kept copy, free" : "")
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

    // MARK: Who sounds how

    /// How high `name` speaks: the Pitch slider, times the character's own pitch
    /// if set by hand, else a cartoon lift, or a small nudge with a voice each.
    func pitch(for name: String) -> Double { settings.voicePitch * ownPitch(for: name) }

    /// The character's own share of `pitch`, before the global slider.
    func ownPitch(for name: String) -> Double {
        if let set = settings.characterVoices[name]?.pitch { return set }
        if settings.castByPersonality {
            // The personality sets the pitch; a cartoon sits higher overall; a small
            // nudge keeps two alike characters apart.
            let nudge = 1 + (Voices.pitchNudge(for: name) - 1) / 2
            return (settings.cartoonVoices ? 1.3 : 1) * traits(for: name).pitch * nudge
        }
        return settings.cartoonVoices ? Voices.cartoonPitch(for: name)
            : settings.voicePerCharacter ? Voices.pitchNudge(for: name) : 1
    }

    /// How `name` should sound, from its description; neutral with casting off.
    func traits(for name: String) -> Casting.Traits {
        guard settings.castByPersonality, let who = describe(name) else { return .neutral }
        return Casting.traits(persona: who.persona, kind: who.kind)
    }

    /// The character's own share of `speed`, before the global slider.
    func ownSpeed(for name: String) -> Double { settings.characterVoices[name]?.speed ?? traits(for: name).speed }

    /// Whether `name`'s speed follows its pitch: its own choice, else the overall one.
    func followsPitch(_ name: String) -> Bool { settings.characterVoices[name]?.followPitch ?? settings.speedFollowsPitch }

    /// How fast `name` speaks: the Speed slider times its own.
    func speed(for name: String) -> Double { settings.voiceSpeed * ownSpeed(for: name) }

    /// The Mac voice identifier `name` speaks with; nil is the system default.
    /// `automatic`: what it would get with no voice of its own chosen.
    func systemVoice(for name: String, cast: [String], automatic: Bool = false) -> String? {
        if !automatic, let own = settings.characterVoices[name]?.systemVoice { return own }
        guard settings.voicePerCharacter else { return settings.systemVoice.isEmpty ? nil : settings.systemVoice }
        let voices = systemPool
        let pool = voices.map(\.identifier)
        var fixed = settings.characterVoices.compactMapValues(\.systemVoice)
        if automatic { fixed[name] = nil }
        guard settings.castByPersonality else { return Voices.assign(cast + [name], pool: pool, fixed: fixed)[name] }
        let tags = Dictionary(voices.map { ($0.identifier, Self.tags(of: $0)) }, uniquingKeysWith: { a, _ in a })
        return Casting.assign(cast + [name], traits: castTraits(cast + [name]), pool: pool, tags: tags, fixed: fixed)[name]
    }

    /// The voice `name` speaks with on OpenRouter or the local server, from that
    /// model's `voices`; nil lets the model choose.
    func onlineVoice(for name: String, cast: [String], among voices: [String], automatic: Bool = false) -> String? {
        let local = settings.voiceEngine == .local
        let mine = { (v: CharacterVoice) in local ? v.localVoice : v.openRouterVoice }
        let chosen = local ? settings.localVoice : settings.openRouterVoice
        // A local server (Kokoro) also takes blends of its voices; OpenRouter does not.
        let usable = { (v: String?) in
            v.flatMap { local ? (Voices.isUsable($0, among: voices) ? $0 : nil) : (voices.isEmpty || voices.contains($0) ? $0 : nil) }
        }
        if !automatic, let own = usable(settings.characterVoices[name].flatMap(mine)) { return own }
        guard settings.voicePerCharacter else { return chosen.isEmpty ? voices.first : chosen }
        let english = Voices.englishFirst(voices)
        var fixed = settings.characterVoices.compactMapValues { usable(mine($0)) }
        if automatic { fixed[name] = nil }
        guard settings.castByPersonality else {
            let pool = settings.cartoonVoices ? Voices.cartoonFirst(english) : english
            return Voices.assign(cast + [name], pool: pool, fixed: fixed)[name]
        }
        let tags = Dictionary(english.map { ($0, Casting.tags(ofVoice: $0)) }, uniquingKeysWith: { a, _ in a })
        return Casting.assign(cast + [name], traits: castTraits(cast + [name]), pool: english, tags: tags, fixed: fixed)[name]
    }

    private func castTraits(_ names: [String]) -> [String: Casting.Traits] {
        Dictionary(names.map { ($0, traits(for: $0)) }, uniquingKeysWith: { a, _ in a })
    }

    /// The Mac voices handed out one per character.
    var systemPool: [AVSpeechSynthesisVoice] {
        let fun = settings.cartoonVoices ? Self.cartoonVoices : []
        return fun.count >= 2 ? fun : Self.characterVoices
    }

    /// A Mac voice's tags: from its name, and the sex the system reports.
    static func tags(of voice: AVSpeechSynthesisVoice) -> Set<Casting.Tag> {
        var tags = Casting.tags(ofVoice: voice.identifier, name: voice.name)
        switch voice.gender {
        case .female: tags.insert(.female)
        case .male: tags.insert(.male)
        default: break
        }
        return tags
    }

    /// The voices of the chosen OpenRouter model, as far as the list is loaded.
    var modelVoices: [String] { models.first { $0.id == settings.voiceModel }?.voices ?? [] }

    /// What `name` would sound like with no voice of its own chosen, in words, for the Voice tab.
    func automaticVoice(for name: String) -> String {
        switch settings.voiceEngine {
        case .system:
            return systemVoice(for: name, cast: cast(), automatic: true)
                .flatMap(AVSpeechSynthesisVoice.init(identifier:))?.name ?? "system default"
        case .openRouter:
            return onlineVoice(for: name, cast: cast(), among: modelVoices, automatic: true) ?? "the model's own"
        case .local:
            return onlineVoice(for: name, cast: cast(), among: localVoices, automatic: true) ?? "the server's own"
        }
    }

    /// The local server's voices, fetched once per session and again on `again`.
    @discardableResult
    func loadLocalVoices(again: Bool = false) async throws -> [String] {
        if !again, !localVoices.isEmpty { return localVoices }
        guard let server = settings.localVoiceURL else { throw ChatClient.Failure.serverDown("the address is not a URL") }
        localVoices = try await SpeechClient(key: "", model: settings.localVoiceModel, server: server).voices()
        return localVoices
    }

    /// `--say`: one line as `name`, voice on or off, for trying an engine from a script.
    @discardableResult
    func sayOnce(_ text: String, as name: String, cue: CueHandler?) -> Bool {
        speak(text, as: name, cast: cast(), cue: cue)
    }

    /// Settings › Voice's per-character Test.
    func introduce(_ name: String) {
        stop()
        speak("Hi, I'm \(name). This is how I sound.", as: name, cast: cast(), builtIn: true)
    }

    /// A Mac voice without its own pitch shifter, which smears high voices: the
    /// line is rendered to sound at the asked speed and natural pitch, then
    /// played `pitch` times faster through the varispeed, like an OpenRouter clip.
    /// The bubble types over the clip's length, as the voice cannot report
    /// its progress once rendered.
    private func speakHereLikeTape(_ line: String, as name: String, cast: [String], cue: CueHandler?) -> Bool {
        let utterance = AVSpeechUtterance(string: line)
        utterance.voice = systemVoice(for: name, cast: cast).flatMap(AVSpeechSynthesisVoice.init(identifier:))
        let pitch = pitch(for: name)
        let asked = Voices.askedSpeed(speed: speed(for: name), pitch: pitch, followPitch: true)
        utterance.rate = min(max(AVSpeechUtteranceDefaultSpeechRate * Float(asked), AVSpeechUtteranceMinimumSpeechRate),
                             AVSpeechUtteranceMaximumSpeechRate)
        waiting += 1
        let rendered = Task { await self.render(utterance) }
        let before = chain, epoch = epoch
        chain = Task { [weak self] in
            await before?.value
            var ending = Cue.dropped
            defer {
                cue?(ending)
                if let self, self.epoch == epoch, self.waiting > 0 { self.waiting -= 1 }
            }
            let buffers = await rendered.value.buffers
            guard let self, self.epoch == epoch, !Task.isCancelled, !buffers.isEmpty else { return }
            self.status = "\(name): \(utterance.voice?.name ?? "system voice")"
            do {
                try await self.play(buffers, pitch: pitch) { cue?(.started(duration: $0)) }
                ending = .done
            } catch {
                self.status = "\(error)"
            }
        }
        return true
    }

    /// Separate from `synthesizer`, whose delegate drives the live voice.
    private let renderer = AVSpeechSynthesizer()

    /// The utterance as sound, not played. The synthesizer hands it over in
    /// pieces and ends with an empty one.
    private func render(_ utterance: AVSpeechUtterance) async -> Rendered {
        let collected = Rendered()
        return await withCheckedContinuation { finished in
            renderer.write(utterance) { piece in
                guard !collected.done else { return }
                if let pcm = piece as? AVAudioPCMBuffer, pcm.frameLength > 0 {
                    collected.buffers.append(pcm)
                } else {
                    collected.done = true
                    finished.resume(returning: collected)
                }
            }
        }
    }

    /// The pieces of one rendered line. Filled on the synthesizer's queue, read
    /// on the main actor only once `done`; never both at once.
    private final class Rendered: @unchecked Sendable {
        var buffers: [AVAudioPCMBuffer] = []
        var done = false
    }

    /// Play rendered pieces to their end, `pitch` times faster.
    private func play(_ buffers: [AVAudioPCMBuffer], pitch: Double, started: (Double) -> Void) async throws {
        let format = buffers[0].format
        let frames = buffers.reduce(0) { $0 + Double($1.frameLength) }
        let rate = try route(format, pitch: pitch)
        for buffer in buffers { player.scheduleBuffer(buffer, completionHandler: nil) }
        let duration = frames / format.sampleRate / rate
        player.play()
        started(duration)
        try await Task.sleep(for: .seconds(duration + 0.15))
        player.stop()
    }

    /// Player → varispeed → mixer for sound in `format`; returns the rate set.
    private func route(_ format: AVAudioFormat, pitch: Double) throws -> Double {
        engine.connect(player, to: shifter, format: format)
        engine.connect(shifter, to: engine.mainMixerNode, format: format)
        let rate = min(max(pitch, 0.25), 4)
        shifter.rate = Float(rate)
        player.volume = Float(settings.voiceVolume)
        if !engine.isRunning { try engine.start() }
        return rate
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
        let rate = try route(clip.processingFormat, pitch: pitch)
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
            self?.spend.record(provider: .openRouter, model: client.model, usage: usage, purpose: .voice)
            self?.history?.recordVoice(.init(time: time, speaker: speaker, text: text, model: client.model, cost: usage.cost))
        }
    }

    private func keep(_ audio: Data, speaker: String, text: String, model: String, voice: String, speed: Double) {
        do { clips.append(try archive.keep(audio, speaker: speaker, text: text, model: model, voice: voice, speed: speed)) }
        catch { FileHandle.standardError.write(Data("Ledgelings voice archive: \(error)\n".utf8)) }
    }

    private func keepLine(_ audio: Data, speaker: String, text: String, model: String, voice: String, speed: Double) {
        do { lineClips.append(try lineArchive.keep(audio, speaker: speaker, text: text, model: model, voice: voice, speed: speed)) }
        catch { FileHandle.standardError.write(Data("Ledgelings line voices: \(error)\n".utf8)) }
    }

    func revealLineArchive() {
        try? FileManager.default.createDirectory(at: lineArchive.directory, withIntermediateDirectories: true)
        NSWorkspace.shared.open(lineArchive.directory)
    }

    /// Forget every built-in line's sound; each is made again the next time it is said.
    func clearLineArchive() {
        try? FileManager.default.removeItem(at: lineArchive.directory)
        lineClips = []
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
    static let singers: Set<String> = ["Bells", "Cellos", "Organ", "Good News", "Bad News", "Superstar"]

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

// MARK: Casting by the brain model

extension Voice {
    /// Ask the brain model which voice, pitch and speed fit `name`, and keep its
    /// answer as the character's own, as if picked by hand. Returns the model's
    /// reason. Needs a model brain (LM Studio or OpenRouter); the call is priced
    /// into the spend file like any other.
    @discardableResult
    func castWithModel(_ name: String) async throws -> String {
        guard let client = settings.chatClient() else { throw ChatClient.Failure.refused(settings.brainProblem) }
        let who = describe(name) ?? (persona: "", kind: "")
        // Choices for the engine in use, by the id the model sees, with what is known of each.
        var choices: [(id: String, hints: String, value: String)] = []
        func hints(_ tags: Set<Casting.Tag>) -> String { tags.map(\.rawValue).sorted().joined(separator: ", ") }
        switch settings.voiceEngine {
        case .system:
            choices = systemPool.map { ($0.name, hints(Self.tags(of: $0)), $0.identifier) }
        case .openRouter:
            let all = modelVoices.isEmpty ? try await voices(of: settings.voiceModel) : modelVoices
            choices = Voices.englishFirst(all).map { ($0, hints(Casting.tags(ofVoice: $0)), $0) }
        case .local:
            let all = localVoices.isEmpty ? try await loadLocalVoices() : localVoices
            choices = Voices.englishFirst(all).map { ($0, hints(Casting.tags(ofVoice: $0)), $0) }
        }
        guard !choices.isEmpty else { throw ChatClient.Failure.badReply("no voices to choose from") }
        let prompt = Casting.modelPrompt(name: name, persona: who.persona, kind: who.kind,
                                         voices: choices.map { ($0.id, $0.hints) }, cartoon: settings.cartoonVoices)
        // Room for a thinking model to reason before it answers; the answer itself is short.
        let answer = try await client.reply(system: Casting.modelSystem, user: prompt, maxTokens: 2000, temperature: 0.3)
        if let usage = answer.usage { spend.record(provider: client.provider, model: client.model, usage: usage, purpose: .casting) }
        guard let pick = Casting.parsePick(answer.text),
              let chosen = choices.first(where: { $0.id.caseInsensitiveCompare(pick.voice) == .orderedSame })
        else { throw ChatClient.Failure.badReply(String(answer.text.prefix(120))) }
        let engine = settings.voiceEngine
        settings.setVoice(of: name) { v in
            switch engine {
            case .system: v.systemVoice = chosen.value
            case .openRouter: v.openRouterVoice = chosen.value
            case .local: v.localVoice = chosen.value
            }
            if let p = pick.pitch { v.pitch = min(max(p, AppSettings.voicePitchRange.lowerBound), AppSettings.voicePitchRange.upperBound) }
            if let s = pick.speed { v.speed = min(max(s, AppSettings.voiceSpeedRange.lowerBound), AppSettings.voiceSpeedRange.upperBound) }
        }
        return "\(chosen.id)" + (pick.why.map { ": \($0)" } ?? "")
    }
}
