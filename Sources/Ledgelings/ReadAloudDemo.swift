import AppKit
import AVFoundation
import LedgelingsCore

/// Read aloud from a terminal (§7.16):
///
///     Ledgelings --read "text" [--preset name] [--engine system] [--out file.m4a] [--mute]
///     Ledgelings --read-bench [--models a,b,c]
///     Ledgelings --read-sheet "text" [--preset name] [--snapshot out.png] [--mute]
///
/// The first reads the text through the real calls and prints the provider,
/// the voice, the time to the first sound, the length and the price. The bench
/// asks each candidate model for the same English, Russian and Hebrew paragraph
/// without playing it, prints the time and price, and has the dictation model
/// write each sound down again, so a model that mumbles a language shows. The
/// sheet opens on the real screen with the text, reads it, writes the paper to
/// a PNG and closes. All are priced on Costs under Read aloud.
@MainActor
enum ReadAloudDemo {
    /// The preset named (else the default), read with `--engine system|local|openRouter` when given:
    /// `system` checks the sheet and the sound with no key, no keychain prompt and no cost.
    static func preset(named name: String?, settings: AppSettings) -> ReadAloud.Preset {
        let wanted = name?.lowercased()
        var preset = wanted.flatMap { w in settings.readAloudPresets.first { $0.name.lowercased() == w || $0.title.lowercased() == w } } ?? settings.readAloudDefault
        let args = CommandLine.arguments
        if let at = args.firstIndex(of: "--engine"), args.indices.contains(at + 1),
           let engine = ReadAloud.Engine.allCases.first(where: { $0.rawValue.lowercased() == args[at + 1].lowercased() }), engine != preset.engine {
            preset.engine = engine
            preset.voice = ""
        }
        return preset
    }

    static var muted: Bool { CommandLine.arguments.contains("--mute") }

    static func once(_ text: String, preset name: String?, out: URL?, controller: ReadAloudController, settings: AppSettings, spend: SpendLedger) async -> Bool {
        let player = controller.player
        player.muted = muted
        player.trace = { say("  \($0)") }
        if let refusal = ReadAloud.refusal(text, snippets: .init()) { say("read: \(refusal.line)"); return false }
        let preset = preset(named: name, settings: settings)
        let plan = player.plan(preset)
        say("read preset \(preset.name): \(plan.engine.rawValue)\(plan.client.map { " " + $0.model } ?? ""), reader \(preset.character.isEmpty ? "narrator" : preset.character), voice \(preset.voice.isEmpty ? "chosen for the reader" : preset.voice), \(ReadAloud.speedLabel(preset.speed))\(plan.note.map { " (\($0))" } ?? "")")
        if let estimate = player.estimate(text, preset) { say("read estimate \(Spend.label(estimate))") }
        let before = spend.summary.allTime
        player.read(text, preset: preset)
        let start = Date()
        while player.isActive, Date().timeIntervalSince(start) < 600 { try? await Task.sleep(for: .milliseconds(100)) }
        guard player.phase == .finished else { say("read trouble: \(player.status)"); return false }
        // OpenRouter fills in each part's price a few seconds after the call.
        if plan.engine.isPaid {
            let wait = Date()
            while spend.summary.allTime.calls - before.calls < player.partsTotal, Date().timeIntervalSince(wait) < 30 { try? await Task.sleep(for: .milliseconds(250)) }
        }
        let after = spend.summary.allTime
        say(String(format: "read provider %@ · %@ · first sound after %.2f s · %.1f s long · %@ · %@ (%d calls, %d tokens in, %d out)",
                   plan.engine.rawValue, player.reader, player.firstSound ?? 0, player.length, trCount(player.partsTotal, "part", "parts"),
                   Spend.label(after.cost - before.cost), after.calls - before.calls, after.promptTokens - before.promptTokens,
                   after.completionTokens - before.completionTokens))
        if let out {
            let format = ReadAloud.Format(rawValue: out.pathExtension.lowercased()) ?? .m4a
            do { try player.write(to: out, format: format); say("read saved \(out.path)") }
            catch { say("read could not save: \(error)"); return false }
        }
        return true
    }

    static let candidates = [ReadAloud.defaultModel, "hexgrad/kokoro-82m", "microsoft/mai-voice-2.1-flash"]
    static let paragraphs: [(Translate.Language, String)] = [
        (Translate.english, "The meeting moved to Thursday at ten. Please bring the quarterly numbers, and remember that the projector in room four still needs its cable. We will finish by noon."),
        (Translate.russian, "Встреча перенесена на четверг, на десять утра. Пожалуйста, возьмите квартальные цифры и не забудьте, что проектору в четвёртой комнате всё ещё нужен кабель. Закончим к полудню."),
        (Translate.hebrew, "הפגישה עברה ליום חמישי בעשר. בבקשה תביאו את המספרים של הרבעון, ותזכרו שהמקרן בחדר ארבע עדיין צריך כבל. נסיים עד הצהריים."),
    ]

    /// Each candidate on the same paragraph in each language: the wait for the
    /// whole sound, its length, the price, and the words heard back.
    static func bench(models list: String?, controller: ReadAloudController, settings: AppSettings, spend: SpendLedger) async -> Bool {
        let key = settings.openRouterKey.trimmingCharacters(in: .whitespaces)
        guard !key.isEmpty else { say("read-bench: no OpenRouter key"); return false }
        let models = list.map { $0.split(separator: ",").map(String.init) } ?? candidates
        let all = (try? await controller.player.voice.loadModels()) ?? []
        for model in models {
            let info = all.first { $0.id == model }
            let voices = info?.voices ?? []
            say("bench \(model) · \(info?.priceLabel ?? "price unknown") · \(voices.count) voices")
            for (language, text) in paragraphs {
                let pool = ReadAloud.voices(voices, speaking: language)
                guard voices.isEmpty || !pool.isEmpty else { say("bench   \(language.code): no \(language.englishName) voice"); continue }
                let client = SpeechClient(key: key, model: model, timeout: 90)
                let start = Date()
                var format = model.contains("kokoro") ? "mp3" : "pcm"
                var reply: (audio: Data, generation: String?)?
                for _ in 0..<2 where reply == nil {
                    do { reply = try await client.speak(text, voice: pool.first, speed: 1, format: format) }
                    catch ChatClient.Failure.refused(let message) {
                        guard let other = SpeechClient.otherFormat(after: message, tried: format) else { say("bench   \(language.code): refused: \(message)"); break }
                        format = other
                    } catch { say("bench   \(language.code): \(error)"); break }
                }
                guard let reply else { continue }
                let seconds = Date().timeIntervalSince(start)
                var usage: Spend.Usage?
                if let generation = reply.generation { usage = await client.cost(of: generation) }
                spend.record(provider: .openRouter, model: model, usage: usage ?? Spend.Usage(promptTokens: 0, completionTokens: 0, cost: nil), purpose: .readAloud)
                let buffer = ReadAloudPlayer.decode(reply.audio)
                let length = buffer.map { Double($0.frameLength) / ReadAloudPlayer.format.sampleRate } ?? 0
                var heard: String?
                if let buffer { heard = await hearBack(buffer, key: key, spend: spend) }
                say(String(format: "bench   %@ %@: whole sound in %.2f s, %.1f s long, %@ · heard: %@", language.code, pool.first ?? "-", seconds, length,
                           usage?.cost.map(Spend.label) ?? "price unknown", heard ?? "-"))
            }
        }
        return true
    }

    /// The sound written down again by the dictation model, priced under Read aloud.
    static func hearBack(_ buffer: AVAudioPCMBuffer, key: String, spend: SpendLedger) async -> String? {
        guard let samples = buffer.floatChannelData?[0] else { return nil }
        var pcm = Data(capacity: Int(buffer.frameLength) * 2)
        for i in 0..<Int(buffer.frameLength) {
            let v = Int16(max(-1, min(1, samples[i])) * 32_767)
            withUnsafeBytes(of: v.littleEndian) { pcm.append(contentsOf: $0) }
        }
        let wav = SpeechClient.wav(pcm: pcm, rate: Int(ReadAloudPlayer.format.sampleRate), channels: 1)
        let client = DictationClient(key: key, model: Dictation.defaultModel)
        guard let answer = try? await client.transcribe(wav: wav, instruction: Dictation.instruction(language: .auto, cleanUp: false),
                                                        seconds: Double(buffer.frameLength) / ReadAloudPlayer.format.sampleRate) else { return nil }
        if let usage = answer.usage { spend.record(provider: .openRouter, model: client.model, usage: usage, purpose: .readAloud) }
        return String(answer.text.prefix(90))
    }

    /// The sheet on the real screen with `text`, read; written to a PNG while it reads, then closed.
    static func sheet(_ text: String, preset name: String?, snapshot: URL?, controller: ReadAloudController, settings: AppSettings) async -> Bool {
        let sheet = controller.sheet, player = controller.player
        player.muted = muted
        sheet.show(text: text, start: true, preset: preset(named: name, settings: settings))
        let start = Date()
        while player.phase != .playing, player.phase != .trouble, Date().timeIntervalSince(start) < 30 { try? await Task.sleep(for: .milliseconds(100)) }
        try? await Task.sleep(for: .seconds(2.5))
        say("read sheet: \(player.phase) · \(player.status)")
        for button in ReadAloud.Button.allCases { say("read button \(button.rawValue): \(button.tooltip)") }
        if let snapshot { try? sheet.snapshot(to: snapshot); say("read sheet written to \(snapshot.path)") }
        sheet.close()
        player.stop()
        return player.phase != .trouble
    }

    private static func say(_ line: String) { FileHandle.standardError.write(Data((line + "\n").utf8)) }
}
