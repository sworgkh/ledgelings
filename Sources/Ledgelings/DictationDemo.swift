import AVFoundation
import AppKit
import LedgelingsCore

/// Dictation on the real pipeline, from a script.
///
/// `--mic-check` says whether this build may use the microphone and records a
/// second and a half, printing how loud it was: a refused or dead microphone
/// hears nothing. Started from a terminal it borrows the terminal's permission;
/// `open build/Ledgelings.app --stderr /dev/stdout --args --mic-check` asks for the app's own.
///
/// `--dictate-demo [--model id]` has the Mac say a test line into a file, turns
/// it into the 16 kHz WAV the microphone would give, and sends it through the
/// real call to the chosen model (or `--model`), with the creature on screen.
/// It checks the words land on the clipboard and in the history, prints each
/// step with its time and the price, then puts the clipboard and the history
/// back. Exit 1 if anything is wrong. It needs the OpenRouter key.
@MainActor
enum DictationDemo {
    static let line = "Please send me the quarterly report by Friday, and book the meeting room for ten thirty."
    /// Words the transcript must hold, any case, for the demo to pass.
    static let expected = ["send", "report", "friday", "meeting", "room"]

    static func check() async -> Bool {
        func log(_ line: String) { FileHandle.standardError.write(Data("mic \(line)\n".utf8)) }
        let permission = DictationRecorder.permission
        log("microphone \(permission == .granted ? "granted" : permission == .notAsked ? "not asked yet" : "NOT granted to this build")")
        log("device: \(DictationRecorder.microphoneName ?? "none")")
        if permission == .notAsked {
            log("asking…")
            log(await DictationRecorder.askForPermission() ? "allowed" : "refused")
        }
        guard DictationRecorder.permission == .granted else { return false }
        let recorder = DictationRecorder()
        do { try recorder.start() } catch { log("would not start: \(error)"); return false }
        var loudest = 0.0
        for _ in 0..<30 {
            try? await Task.sleep(for: .milliseconds(50))
            loudest = max(loudest, recorder.level)
        }
        let samples = recorder.stop()
        let seconds = Double(samples.count) / Double(Dictation.sampleRate)
        log(String(format: "heard %.2f s, %d samples at %d Hz, loudest %.2f", seconds, samples.count, Dictation.sampleRate, loudest))
        let ok = seconds > 1 && samples.contains { $0 != 0 }
        log(ok ? "microphone works" : "the microphone gave silence: refused, or muted?")
        return ok
    }

    static func run(settings: AppSettings, controller: DictationController, clips: ClipBook, model: String?) async -> Bool {
        let start = Date()
        func log(_ line: String) { FileHandle.standardError.write(Data(String(format: "dictate %5.2f  %@\n", Date().timeIntervalSince(start), line).utf8)) }
        let board = ClipPaster.saved()
        let keptModel = settings.dictationModel, keptPaste = settings.dictationPaste
        let before = Set(clips.history.clips.map(\.id))
        defer {
            ClipPaster.restore(board)
            for clip in clips.history.clips where !before.contains(clip.id) { clips.remove(clip.id) }
            settings.dictationModel = keptModel
            settings.dictationPaste = keptPaste
            log("clipboard, history and settings put back")
        }
        if let model { settings.dictationModel = model }
        settings.dictationPaste = false
        controller.trace = { log($0) }

        log("the Mac says: \"\(line)\"")
        let wav: Data, seconds: Double
        do {
            let samples = try said(line)
            seconds = Double(samples.count) / Double(Dictation.sampleRate)
            wav = Dictation.wav(samples)
            log(String(format: "%.1f s of speech, %.0f KB of WAV", seconds, Double(wav.count) / 1024))
        } catch {
            log("could not make the clip: \(error)")
            return false
        }
        let result: Result<String, DictationController.DictationFailure> = await withCheckedContinuation { done in
            controller.finished = { done.resume(returning: $0) }
            Task { @MainActor in await controller.transcribe(wav, seconds: seconds) }
        }
        controller.finished = nil
        switch result {
        case .failure(let failure):
            log("FAILED: \(failure.trouble.line)")
            return false
        case .success(let text):
            let onBoard = NSPasteboard.general.string(forType: .string) ?? ""
            let missing = expected.filter { !text.lowercased().contains($0) }
            // The same words copied before are moved up, not added again: there, whatever their id.
            let inHistory = clips.history.clips.contains { $0.text == text }
            log("transcript: \(text)")
            log(onBoard == text ? "ok: on the clipboard" : "WRONG: the clipboard holds \"\(onBoard.prefix(60))\"")
            log(!settings.clipboardEnabled || !settings.clipHistoryEnabled ? "history is off: not checked" : inHistory ? "ok: in the clipboard history" : "WRONG: not in the history")
            log(missing.isEmpty ? "ok: every expected word is there" : "WRONG: missing \(missing.joined(separator: ", "))")
            // Long enough for the creature to say it and hop home.
            try? await Task.sleep(for: .seconds(4))
            return onBoard == text && missing.isEmpty && (inHistory || !settings.clipboardEnabled || !settings.clipHistoryEnabled)
        }
    }

    /// The Mac's voice saying `text`, as the 16 kHz mono samples the microphone would give.
    static func said(_ text: String) throws -> [Int16] {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("ledgelings-dictate-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let file = folder.appendingPathComponent("line.aiff")
        let say = Process()
        say.executableURL = URL(fileURLWithPath: "/usr/bin/say")
        say.arguments = ["-o", file.path, text]
        try say.run()
        say.waitUntilExit()
        let audio = try AVAudioFile(forReading: file)
        let source = audio.processingFormat
        guard let all = AVAudioPCMBuffer(pcmFormat: source, frameCapacity: AVAudioFrameCount(audio.length)) else { return [] }
        try audio.read(into: all)
        let target = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: Double(Dictation.sampleRate), channels: 1, interleaved: true)!
        guard let converter = AVAudioConverter(from: source, to: target),
              let out = AVAudioPCMBuffer(pcmFormat: target, frameCapacity: AVAudioFrameCount(Double(all.frameLength) * target.sampleRate / source.sampleRate) + 64)
        else { return [] }
        var given = false
        var error: NSError?
        converter.convert(to: out, error: &error) { _, status in
            if given { status.pointee = .endOfStream; return nil }
            given = true
            status.pointee = .haveData
            return all
        }
        if let error { throw error }
        guard let ints = out.int16ChannelData?[0] else { return [] }
        return Array(UnsafeBufferPointer(start: ints, count: Int(out.frameLength)))
    }
}
