import AppKit
import AVFoundation
import Combine
import LedgelingsCore

/// Reads a text out loud (§7.16). The text is cut into parts (`ReadAloud.parts`);
/// up to three are asked for at a time and played in order the moment each
/// arrives, a rest after each paragraph. Every part's sound is also kept, in
/// order, so the whole reading can be saved as one file or copied as one.
///
/// Three ways to read, as the voice has: a speech model on OpenRouter (priced
/// per call by its `X-Generation-Id`, under Read aloud on Costs, even when the
/// reading was stopped before its sound came), a speech server on this computer,
/// or the Mac's own voices (free). A part in a language the model has no voice
/// for is read by the Mac's voice for that language instead. With no OpenRouter
/// key the Mac reads it all, and says so.
///
/// The pace is asked of the model; the sheet's − and + change it while it plays
/// (a time stretch on this Mac, the pitch kept), and the next reading asks the
/// new pace.
@MainActor
final class ReadAloudPlayer: ObservableObject {
    enum Phase: Equatable { case idle, preparing, playing, paused, finished, trouble }

    @Published private(set) var phase = Phase.idle
    @Published private(set) var status = ""
    /// Seconds of the reading played, and its length as far as its parts are in.
    @Published private(set) var played = 0.0
    @Published private(set) var length = 0.0
    @Published private(set) var partsReady = 0
    @Published private(set) var partsTotal = 0
    /// Dollars this reading has cost so far, as OpenRouter reports each part.
    @Published private(set) var spent = 0.0
    /// The live pace on top of the one asked: 1 plays the sound as it came.
    @Published private(set) var rate = 1.0
    /// Who is reading, in words: "Kore on google/gemini-3.8-flash-lite-tts".
    @Published private(set) var reader = ""
    /// Seconds from the start to the first sound, once there was one.
    private(set) var firstSound: Double?
    /// What is being read, and how.
    private(set) var text = ""
    private(set) var preset: ReadAloud.Preset?

    var isActive: Bool { phase == .preparing || phase == .playing || phase == .paused }
    /// Every part is in: what is saved is the whole reading.
    var isComplete: Bool { partsTotal > 0 && partsReady == partsTotal }
    var hasSound: Bool { !tape.isEmpty }

    let settings: AppSettings
    let spend: SpendLedger
    /// For the speech models' lists and the local server's voices, as the Voice page loads them.
    let voice: Voice
    /// Who a character is, by name, from any species: its persona and its species' kind.
    var describe: (String) -> (persona: String, kind: String)? = { _ in nil }
    /// Every step, for `--read` and the sheet's film.
    var trace: ((String) -> Void)?
    /// Silent, for a check from a terminal that should not fill the room (`--mute`).
    var muted = false
    /// Phase changes, for the creature by the sheet.
    var changed: (Phase) -> Void = { _ in }

    /// One sound format for every part, whatever each engine sends: 24 kHz mono.
    static let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 24_000, channels: 1, interleaved: false)!

    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private let stretch = AVAudioUnitTimePitch()
    private let renderer = AVSpeechSynthesizer()
    /// Every piece in order, rests included: what Save writes.
    private var tape: [AVAudioPCMBuffer] = []
    private var scheduled: AVAudioFramePosition = 0
    /// The player ran out of sound and waits for the next part, paused so the clock stays true.
    private var starved = false
    private var userPaused = false
    private var epoch = 0
    private var startedAt = Date()
    private var running: Task<Void, Never>?
    private var ticking: Task<Void, Never>?
    /// The format each model sends (PCM unless it refused), and the models that refuse a speed.
    private var formats: [String: String] = [:]
    private var noSpeed: Set<String> = []
    /// What a part could not be read with, said once per reading.
    private var notes: [String] = []

    init(settings: AppSettings, spend: SpendLedger, voice: Voice) {
        self.settings = settings
        self.spend = spend
        self.voice = voice
        engine.attach(player)
        engine.attach(stretch)
        engine.connect(player, to: stretch, format: Self.format)
        engine.connect(stretch, to: engine.mainMixerNode, format: Self.format)
        stretch.bypass = true
    }

    // MARK: Reading

    /// How a reading will be done: the engine after the key and server are
    /// checked, and the client for it.
    struct Plan {
        var engine: ReadAloud.Engine
        var client: SpeechClient?
        var preset: ReadAloud.Preset
        /// Why it is not read the way the preset says (no key): said in the status.
        var note: String?
    }

    func plan(_ preset: ReadAloud.Preset) -> Plan {
        switch preset.engine {
        case .system:
            return Plan(engine: .system, client: nil, preset: preset)
        case .local:
            guard let server = settings.localVoiceURL else {
                return Plan(engine: .system, client: nil, preset: preset, note: tr("The local server's address is not a URL: the Mac's own voice reads it, free"))
            }
            return Plan(engine: .local, client: SpeechClient(key: "", model: settings.localVoiceModel.trimmingCharacters(in: .whitespaces), server: server, timeout: 60), preset: preset)
        case .openRouter:
            let key = settings.openRouterKey.trimmingCharacters(in: .whitespaces)
            guard !key.isEmpty else {
                return Plan(engine: .system, client: nil, preset: preset, note: tr("No OpenRouter key: the Mac's own voice reads it, free. Add one in Settings › Talk."))
            }
            return Plan(engine: .openRouter, client: SpeechClient(key: key, model: preset.modelOrDefault, timeout: 60), preset: preset)
        }
    }

    /// About what reading `text` with `preset` costs, from the model's list price; nil when free or not known.
    func estimate(_ text: String, _ preset: ReadAloud.Preset) -> Double? {
        let plan = plan(preset)
        guard plan.engine == .openRouter else { return nil }
        let characters = ReadAloud.parts(text).reduce(0) { $0 + $1.text.count }
        let model = voice.models.first { $0.id == preset.modelOrDefault }
        // Before the list is loaded: Gemini 3.8 Flash Lite TTS's own price.
        let prompt = model?.inputPerMillion ?? (preset.modelOrDefault == ReadAloud.defaultModel ? 0.5 : nil)
        let completion = model?.outputPerMillion ?? (preset.modelOrDefault == ReadAloud.defaultModel ? 6 : nil)
        return ReadAloud.estimate(characters: characters, promptPerToken: prompt.map { $0 / 1_000_000 }, completionPerToken: completion.map { $0 / 1_000_000 })
    }

    /// Start reading `text` from the top; whatever was being read stops.
    func read(_ text: String, preset: ReadAloud.Preset) {
        stop()
        let plan = plan(preset)
        let parts = ReadAloud.parts(text, forced: preset.forcedLanguage)
        guard !parts.isEmpty else { set(.trouble, ReadAloud.Refusal.empty.line); return }
        self.text = text
        self.preset = preset
        epoch += 1
        tape = []
        scheduled = 0
        played = 0
        length = 0
        spent = 0
        rate = 1
        stretch.rate = 1
        stretch.bypass = true
        firstSound = nil
        starved = false
        userPaused = false
        partsReady = 0
        partsTotal = parts.count
        notes = plan.note.map { [$0] } ?? []
        reader = ""
        startedAt = Date()
        player.reset()
        set(.preparing, plan.note ?? tr("Reading part 1 of %d…", parts.count))
        trace?("read \(parts.count) parts, \(text.count) characters, \(plan.engine.rawValue)\(plan.client.map { " " + $0.model } ?? "") at \(ReadAloud.speedLabel(preset.speed))")
        let epoch = epoch
        let fallback = preset.forcedLanguage ?? Translate.detect(Translate.protect(text).text) ?? Translate.english
        running = Task { [weak self] in await self?.run(parts, plan: plan, fallback: fallback, epoch: epoch) }
        startTicking()
    }

    /// One part's sound. Made on the main actor and only read there: never shared between threads.
    private struct Piece: @unchecked Sendable {
        let buffer: AVAudioPCMBuffer
        let who: String
    }

    private func run(_ parts: [ReadAloud.Part], plan: Plan, fallback: Translate.Language, epoch: Int) async {
        var fetches: [Task<Piece, Error>] = []
        func launch(_ i: Int) {
            let part = parts[i]
            // Not cancelled by a stop: an answer already asked for is still priced.
            fetches.append(Task { [weak self] in
                guard let self else { throw CancellationError() }
                return try await self.sound(for: part, language: part.language ?? fallback, plan: plan)
            })
        }
        for i in 0..<min(parts.count, ReadAloud.partsAhead + 1) { launch(i) }
        for i in parts.indices {
            let piece: Piece
            do { piece = try await fetches[i].value } catch {
                guard self.epoch == epoch else { return }
                let line = (error as? ChatClient.Failure).map { "\($0)" } ?? error.localizedDescription
                set(.trouble, tr("Part %d of %d could not be read: %@", i + 1, parts.count, line))
                trace?("read trouble: \(line)")
                return
            }
            guard self.epoch == epoch else { return }
            if i + ReadAloud.partsAhead + 1 < parts.count { launch(i + ReadAloud.partsAhead + 1) }
            let last = i == parts.count - 1
            append(piece.buffer, last: last)
            if parts[i].paragraphEnd, !last, plan.preset.pause > 0, let rest = Self.silence(seconds: plan.preset.pause) {
                append(rest, last: false)
            }
            partsReady = i + 1
            if reader.isEmpty || !reader.contains(piece.who) { reader = reader.isEmpty ? piece.who : reader + ", " + piece.who }
            trace?(String(format: "read part %d/%d ready at %.2f s: %.1f s of sound, %@", i + 1, parts.count,
                          Date().timeIntervalSince(startedAt), Double(piece.buffer.frameLength) / Self.format.sampleRate, piece.who))
            if firstSound == nil { startPlaying() }
            if starved, !userPaused { starved = false; player.play() }
            updateStatus()
        }
    }

    /// One piece onto the tape and into the player; the last one ends the reading once it has been heard.
    private func append(_ buffer: AVAudioPCMBuffer, last: Bool) {
        tape.append(buffer)
        scheduled += AVAudioFramePosition(buffer.frameLength)
        length = Double(scheduled) / Self.format.sampleRate
        let epoch = epoch, total = scheduled
        player.scheduleBuffer(buffer, completionCallbackType: .dataPlayedBack) { [weak self] _ in
            Task { @MainActor in self?.heard(upTo: total, last: last, epoch: epoch) }
        }
    }

    /// A piece has been heard: the end, or the player waits for a part still on its way.
    private func heard(upTo frames: AVAudioFramePosition, last: Bool, epoch: Int) {
        guard self.epoch == epoch, isActive else { return }
        if last { finish(); return }
        if frames >= scheduled, !isComplete {
            starved = true
            player.pause()
            status = tr("Waiting for part %d of %d…", partsReady + 1, partsTotal)
        }
    }

    private func startPlaying() {
        firstSound = Date().timeIntervalSince(startedAt)
        do {
            if !engine.isRunning { try engine.start() }
            player.volume = muted ? 0 : Float(settings.voiceVolume)
            player.play()
            set(.playing, nil)
            trace?(String(format: "read first sound after %.2f s", firstSound ?? 0))
        } catch {
            set(.trouble, tr("The sound could not start: %@", error.localizedDescription))
        }
    }

    private func finish() {
        ticking?.cancel()
        played = length
        player.stop()
        set(.finished, nil)
        updateStatus()
        trace?(String(format: "read done: %.1f s of sound, %d parts, %@", length, partsTotal, Spend.label(spent)))
    }

    func pause() {
        guard phase == .playing else { return }
        userPaused = true
        player.pause()
        set(.paused, nil)
        updateStatus()
    }

    func resume() {
        guard phase == .paused else { return }
        userPaused = false
        if !starved { player.play() }
        set(.playing, nil)
        updateStatus()
    }

    /// Silence now; what is on its way is still priced, its sound dropped.
    func stop() {
        guard isActive else { return }
        epoch += 1
        running = nil
        ticking?.cancel()
        player.stop()
        set(.idle, partsReady > 0 ? tr("Stopped after %@ of %@", ReadAloud.clock(played / rate), ReadAloud.clock(length / rate)) : tr("Stopped"))
        trace?("read stopped")
    }

    /// The live pace, on top of the pace asked: `wanted` over `asked`.
    func setPace(_ wanted: Double) {
        guard let asked = preset?.speed, asked > 0 else { return }
        rate = min(max(wanted / asked, 0.25), 4)
        stretch.rate = Float(rate)
        stretch.bypass = abs(rate - 1) < 0.001
        updateStatus()
    }

    private func startTicking() {
        ticking?.cancel()
        ticking = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(100))
                guard let self, self.isActive else { continue }
                if let node = self.player.lastRenderTime, let time = self.player.playerTime(forNodeTime: node) {
                    self.played = min(Double(time.sampleTime) / Self.format.sampleRate, self.length)
                }
            }
        }
    }

    private func set(_ phase: Phase, _ line: String?) {
        let was = self.phase
        self.phase = phase
        if let line { status = line }
        if was != phase { changed(phase) }
    }

    private func updateStatus() {
        var line: String
        switch phase {
        case .finished:
            line = tr("Read: %@ · %@", ReadAloud.clock(length), trCount(partsTotal, "part", "parts"))
            if let firstSound { line += " · " + tr("first sound after %.1f s", firstSound) }
        case .paused:
            line = tr("Paused at %@", ReadAloud.clock(played / rate))
        default:
            line = partsReady < partsTotal ? tr("Part %d of %d in", partsReady, partsTotal) : trCount(partsTotal, "part", "parts")
        }
        if !reader.isEmpty { line += " · " + reader }
        if spent > 0 { line += " · " + Spend.label(spent) }
        if !notes.isEmpty { line += " · " + notes.joined(separator: " · ") }
        status = line
    }

    // MARK: One part's sound

    private func sound(for part: ReadAloud.Part, language: Translate.Language, plan: Plan) async throws -> Piece {
        let speed = plan.preset.speed
        if plan.engine != .system, let client = plan.client {
            let voices = await voiceList(plan)
            let pool = ReadAloud.voices(voices, speaking: language)
            if voices.isEmpty || !pool.isEmpty {
                let name = onlineVoice(plan, pool: pool, all: voices)
                return try await speakOnline(part.text, client: client, voice: name, speed: speed, local: plan.engine == .local)
            }
            note(tr("%@ has no %@ voice: the Mac's reads it", client.model, language.title))
        }
        return try await speakHere(part.text, language: language, plan: plan, speed: speed)
    }

    private func note(_ line: String) {
        if !notes.contains(line) { notes.append(line) }
    }

    /// The model's voices, or the local server's; empty when the list cannot be had (then the voice is sent as chosen).
    private func voiceList(_ plan: Plan) async -> [String] {
        if plan.engine == .local { return (try? await voice.loadLocalVoices()) ?? [] }
        return (try? await voice.voices(of: plan.client?.model ?? "")) ?? []
    }

    /// The voice for a part: the preset's own; else the character's (its own on
    /// the Voice page for the same model, or cast from its persona); else the first.
    func onlineVoice(_ plan: Plan, pool: [String], all: [String]) -> String? {
        let preset = plan.preset
        if !preset.voice.isEmpty, all.isEmpty || pool.contains(preset.voice) { return preset.voice }
        guard !preset.character.isEmpty else { return pool.first }
        let own = settings.characterVoices[preset.character]
        let mine = plan.engine == .local ? (settings.localVoiceModel == plan.client?.model ? own?.localVoice : nil)
            : (settings.voiceModel == plan.client?.model ? own?.openRouterVoice : nil)
        if let mine, pool.contains(mine) { return mine }
        let name = preset.character
        let traits = describe(name).map { Casting.traits(persona: $0.persona, kind: $0.kind) } ?? .neutral
        let tags = Dictionary(pool.map { ($0, Casting.tags(ofVoice: $0)) }, uniquingKeysWith: { a, _ in a })
        return Casting.assign([name], traits: [name: traits], pool: pool, tags: tags, fixed: [:])[name] ?? pool.first
    }

    private func speakOnline(_ text: String, client: SpeechClient, voice name: String?, speed: Double, local: Bool) async throws -> Piece {
        var format = formats[client.model] ?? (local ? "wav" : "pcm")
        var sendSpeed = !noSpeed.contains(client.model)
        var reply: (audio: Data, generation: String?)?
        for attempt in 0..<3 where reply == nil {
            do {
                reply = try await client.speak(text, voice: name, speed: sendSpeed ? speed : nil, format: format)
            } catch let paid as SpeechClient.Unusable {
                // Paid for, though there is nothing to play: priced, then the trouble said.
                if !local { charge(client, paid.generation) }
                throw paid.failure
            } catch ChatClient.Failure.refused(let message) where attempt < 2 {
                if let other = SpeechClient.otherFormat(after: message, tried: format) {
                    format = other
                    formats[client.model] = other
                } else if sendSpeed, SpeechClient.refusesSpeed(message) {
                    sendSpeed = false
                    noSpeed.insert(client.model)
                } else {
                    throw ChatClient.Failure.refused(message)
                }
            }
        }
        guard let (audio, generation) = reply else { throw ChatClient.Failure.badReply(tr("no audio")) }
        // Priced before anything can go wrong with the sound: it was paid for.
        if !local { charge(client, generation) }
        guard var buffer = Self.decode(audio) else { throw ChatClient.Failure.badReply(tr("the sound could not be read")) }
        if !sendSpeed, abs(speed - 1) > 0.01, let faster = Self.stretched(buffer, by: speed) { buffer = faster }
        let who = (name ?? tr("its own voice")) + (local ? " " + tr("on local %@", client.model) : " " + tr("on %@", client.model))
        return Piece(buffer: buffer, who: who)
    }

    /// Into the spend file under Read aloud, priced once OpenRouter says what it cost.
    private func charge(_ client: SpeechClient, _ generation: String?) {
        guard let generation else {
            spend.record(provider: .openRouter, model: client.model, usage: Spend.Usage(promptTokens: 0, completionTokens: 0, cost: nil), purpose: .readAloud)
            return
        }
        Task { [weak self] in
            let usage = await client.cost(of: generation) ?? Spend.Usage(promptTokens: 0, completionTokens: 0, cost: nil)
            guard let self else { return }
            self.spend.record(provider: .openRouter, model: client.model, usage: usage, purpose: .readAloud)
            if let cost = usage.cost {
                self.spent += cost
                self.trace?("read priced \(Spend.label(cost)): \(usage.promptTokens) tokens in, \(usage.completionTokens) out")
                if self.phase != .preparing { self.updateStatus() }
            }
        }
    }

    // MARK: The Mac's own voices

    private func speakHere(_ text: String, language: Translate.Language, plan: Plan, speed: Double) async throws -> Piece {
        let chosen = Self.macVoice(for: language, plan: plan, settings: settings, describe: describe)
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = chosen
        utterance.rate = min(max(AVSpeechUtteranceDefaultSpeechRate * Float(speed), AVSpeechUtteranceMinimumSpeechRate), AVSpeechUtteranceMaximumSpeechRate)
        let pieces = await render(utterance)
        let converted = pieces.compactMap(Self.convert)
        guard let joined = Self.join(converted) else { throw ChatClient.Failure.badReply(tr("the Mac's voice said nothing")) }
        return Piece(buffer: joined, who: chosen?.name ?? tr("the Mac's voice"))
    }

    /// A Mac voice for `language`: the preset's own when it speaks it; for a
    /// character, its own voice on the Voice page, else one cast from its persona;
    /// for a narrator, the best-sounding one, the user's region first.
    static func macVoice(for language: Translate.Language, plan: Plan, settings: AppSettings,
                         describe: (String) -> (persona: String, kind: String)?) -> AVSpeechSynthesisVoice? {
        let all = AVSpeechSynthesisVoice.speechVoices().filter { $0.language.hasPrefix(language.code) }
        let plain = all.filter { !$0.voiceTraits.contains(.isNoveltyVoice) && !$0.voiceTraits.contains(.isPersonalVoice) }
        let preset = plan.preset
        if preset.engine == .system, !preset.voice.isEmpty, let own = all.first(where: { $0.identifier == preset.voice }) { return own }
        if !preset.character.isEmpty {
            let name = preset.character
            if let own = settings.characterVoices[name]?.systemVoice, let v = all.first(where: { $0.identifier == own }) { return v }
            let traits = describe(name).map { Casting.traits(persona: $0.persona, kind: $0.kind) } ?? .neutral
            let tags = Dictionary(plain.map { ($0.identifier, Voice.tags(of: $0)) }, uniquingKeysWith: { a, _ in a })
            if let id = Casting.assign([name], traits: [name: traits], pool: plain.map(\.identifier), tags: tags, fixed: [:])[name],
               let v = plain.first(where: { $0.identifier == id }) { return v }
        }
        let region = Locale.current.region?.identifier ?? ""
        return plain.sorted {
            ($0.quality.rawValue, $0.language.hasSuffix(region) ? 1 : 0, $1.name) > ($1.quality.rawValue, $1.language.hasSuffix(region) ? 1 : 0, $0.name)
        }.first ?? all.first
    }

    private func render(_ utterance: AVSpeechUtterance) async -> [AVAudioPCMBuffer] {
        final class Collected: @unchecked Sendable { var buffers: [AVAudioPCMBuffer] = []; var done = false }
        let collected = Collected()
        return await withCheckedContinuation { finished in
            renderer.write(utterance) { piece in
                guard !collected.done else { return }
                if let pcm = piece as? AVAudioPCMBuffer, pcm.frameLength > 0 {
                    collected.buffers.append(pcm)
                } else {
                    collected.done = true
                    finished.resume(returning: collected.buffers)
                }
            }
        }
    }

    // MARK: Sound pieces

    /// An MP3 or WAV reply as one buffer in `format`.
    static func decode(_ audio: Data) -> AVAudioPCMBuffer? {
        let isWAV = audio.prefix(4) == Data("RIFF".utf8)
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("ledgelings-read-\(UUID().uuidString).\(isWAV ? "wav" : "mp3")")
        guard (try? audio.write(to: file)) != nil else { return nil }
        defer { try? FileManager.default.removeItem(at: file) }
        guard let clip = try? AVAudioFile(forReading: file),
              let raw = AVAudioPCMBuffer(pcmFormat: clip.processingFormat, frameCapacity: AVAudioFrameCount(max(clip.length, 1))),
              (try? clip.read(into: raw)) != nil else { return nil }
        return convert(raw)
    }

    /// Any buffer as 24 kHz mono float.
    static func convert(_ buffer: AVAudioPCMBuffer) -> AVAudioPCMBuffer? {
        if buffer.format == format { return buffer }
        guard let converter = AVAudioConverter(from: buffer.format, to: format) else { return nil }
        let ratio = format.sampleRate / buffer.format.sampleRate
        guard let out = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 1024) else { return nil }
        final class Once: @unchecked Sendable { var given = false }
        let once = Once()
        var error: NSError?
        converter.convert(to: out, error: &error) { _, status in
            if once.given { status.pointee = .endOfStream; return nil }
            once.given = true
            status.pointee = .haveData
            return buffer
        }
        return error == nil ? out : nil
    }

    static func silence(seconds: Double) -> AVAudioPCMBuffer? {
        let frames = AVAudioFrameCount(seconds * format.sampleRate)
        guard frames > 0, let quiet = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames) else { return nil }
        quiet.frameLength = frames
        return quiet
    }

    static func join(_ buffers: [AVAudioPCMBuffer]) -> AVAudioPCMBuffer? {
        let total = buffers.reduce(0) { $0 + $1.frameLength }
        guard total > 0, let out = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: total), let into = out.floatChannelData?[0] else { return nil }
        var at = 0
        for b in buffers {
            guard let from = b.floatChannelData?[0] else { continue }
            into.advanced(by: at).update(from: from, count: Int(b.frameLength))
            at += Int(b.frameLength)
        }
        out.frameLength = AVAudioFrameCount(at)
        return out
    }

    /// The buffer played `rate` times faster with its pitch kept, rendered here
    /// offline: for a model that refuses to be asked a speed.
    static func stretched(_ buffer: AVAudioPCMBuffer, by rate: Double) -> AVAudioPCMBuffer? {
        let engine = AVAudioEngine(), player = AVAudioPlayerNode(), pitch = AVAudioUnitTimePitch()
        pitch.rate = Float(rate)
        engine.attach(player)
        engine.attach(pitch)
        engine.connect(player, to: pitch, format: format)
        engine.connect(pitch, to: engine.mainMixerNode, format: format)
        guard (try? engine.enableManualRenderingMode(.offline, format: format, maximumFrameCount: 4096)) != nil,
              (try? engine.start()) != nil else { return nil }
        player.scheduleBuffer(buffer, completionHandler: nil)
        player.play()
        let wanted = AVAudioFrameCount(Double(buffer.frameLength) / rate)
        guard let chunk = AVAudioPCMBuffer(pcmFormat: engine.manualRenderingFormat, frameCapacity: 4096) else { return nil }
        var pieces: [AVAudioPCMBuffer] = []
        var made: AVAudioFrameCount = 0
        while made < wanted {
            guard (try? engine.renderOffline(min(4096, wanted - made), to: chunk)) == .success, chunk.frameLength > 0 else { break }
            if let copy = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: chunk.frameLength), let from = chunk.floatChannelData?[0], let to = copy.floatChannelData?[0] {
                to.update(from: from, count: Int(chunk.frameLength))
                copy.frameLength = chunk.frameLength
                pieces.append(copy)
            }
            made += chunk.frameLength
        }
        engine.stop()
        return join(pieces)
    }

    // MARK: Saving and copying

    /// The reading so far as one file: AAC in an M4A box, or 16-bit WAV.
    func write(to url: URL, format: ReadAloud.Format) throws {
        guard !tape.isEmpty else { throw ChatClient.Failure.badReply(tr("nothing read yet")) }
        try? FileManager.default.removeItem(at: url)
        let settings: [String: Any] = switch format {
        case .m4a: [AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: Self.format.sampleRate, AVNumberOfChannelsKey: 1, AVEncoderBitRateKey: 64_000]
        case .wav: [AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: Self.format.sampleRate, AVNumberOfChannelsKey: 1,
                    AVLinearPCMBitDepthKey: 16, AVLinearPCMIsFloatKey: false, AVLinearPCMIsBigEndianKey: false]
        }
        let file = try AVAudioFile(forWriting: url, settings: settings, commonFormat: .pcmFormatFloat32, interleaved: false)
        for buffer in tape { try file.write(from: buffer) }
    }

    /// A reading's sound set straight, as if read: for the tests of Save and Copy.
    func load(tape pieces: [AVAudioPCMBuffer]) {
        tape = pieces
        partsTotal = 1
        partsReady = 1
        length = Double(pieces.reduce(0) { $0 + $1.frameLength }) / Self.format.sampleRate
    }

    /// Where Copy writes the file it puts on the clipboard: beside the app's other caches, kept until the next copy.
    static var copyFolder: URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("Ledgelings/Read aloud", isDirectory: true)
    }
}
