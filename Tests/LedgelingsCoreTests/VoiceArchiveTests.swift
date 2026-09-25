import Foundation
import Testing
@testable import LedgelingsCore

@Suite struct VoiceArchiveTests {
    func scratch() -> VoiceArchive {
        VoiceArchive(directory: FileManager.default.temporaryDirectory.appendingPathComponent("voices-\(UUID().uuidString)"))
    }

    @Test func aKeptLineIsFoundAgainByItsWordsVoiceAndSpeed() throws {
        let archive = scratch()
        defer { try? FileManager.default.removeItem(at: archive.directory) }
        let sound = Data([1, 2, 3, 4])
        let clip = try archive.keep(sound, speaker: "Blocky", text: "Nice edge.", model: "hexgrad/kokoro-82m", voice: "am_puck", speed: 1)
        let clips = archive.clips()
        #expect(clips == [clip])
        let found = try #require(archive.find(key: VoiceArchive.key(text: "Nice edge.", model: "hexgrad/kokoro-82m", voice: "am_puck", speed: 1.0000001), in: clips))
        #expect(try Data(contentsOf: found) == sound)
        // Another voice, another speed, other words: another clip.
        #expect(archive.find(key: VoiceArchive.key(text: "Nice edge.", model: "hexgrad/kokoro-82m", voice: "af_bella", speed: 1), in: clips) == nil)
        #expect(archive.find(key: VoiceArchive.key(text: "Nice edge.", model: "hexgrad/kokoro-82m", voice: "am_puck", speed: 1.5), in: clips) == nil)
        #expect(archive.find(key: VoiceArchive.key(text: "Nice ledge.", model: "hexgrad/kokoro-82m", voice: "am_puck", speed: 1), in: clips) == nil)
    }

    @Test func filesAreFiledByDayTimeAndSpeaker() throws {
        let archive = scratch()
        defer { try? FileManager.default.removeItem(at: archive.directory) }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let time = Date(timeIntervalSince1970: 1_790_375_730)          // 2026-09-25 22:35:30 UTC
        let clip = try archive.keep(Data([0]), speaker: "Unit 7/ö", text: "Beep.", model: "m", voice: "v", speed: 1, at: time, calendar: calendar)
        #expect(clip.file.hasPrefix("2026-09-25/223530-Unit_7_ö-"))
        #expect(clip.file.hasSuffix(".wav"))
    }

    @Test func aClipWhoseFileWasDeletedIsNotFound() throws {
        let archive = scratch()
        defer { try? FileManager.default.removeItem(at: archive.directory) }
        let clip = try archive.keep(Data([0]), speaker: "Pip", text: "Hi!", model: "m", voice: "v", speed: 1)
        try FileManager.default.removeItem(at: archive.directory.appendingPathComponent(clip.file))
        #expect(archive.find(key: clip.key, in: archive.clips()) == nil)
    }
}
