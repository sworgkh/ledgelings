import Foundation

/// Every line a speech model said, kept as a sound file beside the chats, with
/// an index of who said what in which voice. Two uses: the sounds are there to
/// reuse later, and a line that comes round again (the built-in lines repeat)
/// is played from here instead of being paid for twice.
///
/// Layout, under `directory` (normally `Application Support/Ledgelings/voices`):
///
///     voices.jsonl                          one `Clip` per line, oldest first
///     2026-09-25/221530-Blocky-3f9a1c2e.wav the sound, named by day, time, speaker, key
///
/// A clip is found again by its `key`: the text, model, voice and speed, hashed.
/// The same words in another voice or at another speed are another clip.
public struct VoiceArchive: Sendable {
    public struct Clip: Codable, Equatable, Sendable {
        public var time: Date
        public var speaker: String
        public var text: String
        public var model: String
        public var voice: String
        public var speed: Double
        /// Relative to the archive's folder.
        public var file: String
        public var key: String
        public init(time: Date, speaker: String, text: String, model: String, voice: String, speed: Double, file: String, key: String) {
            self.time = time; self.speaker = speaker; self.text = text; self.model = model
            self.voice = voice; self.speed = speed; self.file = file; self.key = key
        }
    }

    public let directory: URL
    public init(directory: URL) { self.directory = directory }

    public var index: URL { directory.appendingPathComponent("voices.jsonl") }

    /// Speed is rounded to the slider's step, so 1.0 and 1.0000001 are one clip.
    public static func key(text: String, model: String, voice: String, speed: Double) -> String {
        let hash = Voices.stableHash([text, model, voice, String(format: "%.2f", speed)].joined(separator: "\u{1F}"))
        return String(format: "%016llx", hash)
    }

    /// The sound kept for these words in this voice, if its file is still there.
    public func find(key: String, in clips: [Clip]) -> URL? {
        clips.last { $0.key == key }
            .map { directory.appendingPathComponent($0.file) }
            .flatMap { FileManager.default.fileExists(atPath: $0.path) ? $0 : nil }
    }

    /// Write the sound and add it to the index. Returns what was indexed.
    @discardableResult
    public func keep(_ audio: Data, speaker: String, text: String, model: String, voice: String, speed: Double,
                     extension ext: String = "wav", at time: Date = Date(), calendar: Calendar = .current) throws -> Clip {
        let key = Self.key(text: text, model: model, voice: voice, speed: speed)
        let time = Date(timeIntervalSince1970: time.timeIntervalSince1970.rounded(.down))   // the index keeps whole seconds
        let c = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: time)
        let day = String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
        let name = String(format: "%02d%02d%02d", c.hour ?? 0, c.minute ?? 0, c.second ?? 0)
            + "-\(Self.safe(speaker))-\(key.prefix(8)).\(ext)"
        let folder = directory.appendingPathComponent(day, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try audio.write(to: folder.appendingPathComponent(name))
        let clip = Clip(time: time, speaker: speaker, text: text, model: model, voice: voice, speed: speed, file: "\(day)/\(name)", key: key)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        var line = try encoder.encode(clip)
        line.append(0x0A)
        if let handle = try? FileHandle(forWritingTo: index) {
            defer { try? handle.close() }
            try handle.seekToEnd()
            try handle.write(contentsOf: line)
        } else {
            try line.write(to: index)
        }
        return clip
    }

    /// Every clip in the order it was kept. A damaged line is skipped.
    public func clips() -> [Clip] {
        guard let data = try? Data(contentsOf: index) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return data.split(separator: 0x0A).compactMap { try? decoder.decode(Clip.self, from: $0) }
    }

    /// Letters, digits, `-` and `_` only, so any name makes a safe file name.
    static func safe(_ name: String) -> String {
        let kept = name.unicodeScalars.map { CharacterSet.alphanumerics.contains($0) || $0 == "-" || $0 == "_" ? Swift.Character($0) : "_" as Swift.Character }
        let text = String(kept.prefix(24))
        return text.isEmpty ? "someone" : text
    }
}
