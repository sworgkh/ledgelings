import AppKit
import AVFoundation
import Foundation
import LedgelingsCore
import Testing
@testable import Ledgelings

/// Tools › Read aloud: its settings, the Tools screen's new tile, the sound
/// pieces and the file, the voice a part is read in, the sheet's choices.
@MainActor
@Suite(.serialized) struct ReadAloudSettingsTests {
    let name = "ledgelings-read-aloud-settings-tests"

    final class Secrets: SecretStore, @unchecked Sendable {
        var key: String?
        init(key: String? = nil) { self.key = key }
        func get(_ account: String) -> String? { key }
        func set(_ value: String?, for account: String) {}
    }

    func fresh(key: String? = nil) -> (UserDefaults, AppSettings) {
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return (defaults, AppSettings(defaults: defaults, keychain: Secrets(key: key)))
    }

    @Test func theDefaultsAndAChangeSurviveARelaunch() {
        let (defaults, s) = fresh()
        defer { defaults.removePersistentDomain(forName: name) }
        #expect(s.readAloudEnabled && s.readAloudShortcutEnabled && s.readAloudShortcut == .readAloud)
        #expect(s.readAloudFromClipboard && s.readAloudStartAtOnce && s.readAloudKeepReading && s.readAloudPickerButton)
        #expect(s.readAloudHelperEnabled && s.readAloudHelper.isEmpty)
        #expect(s.readAloudPresets == ReadAloud.defaultPresets && s.readAloudDefault.name == "Narrator")
        #expect(s.readAloudFolder == "~/Desktop" && s.readAloudFolderURL.path == FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Desktop").path)
        #expect(s.readAloudFormat == .m4a && s.readAloudLongLimit == 3_000)

        s.readAloudEnabled = false; s.readAloudShortcutEnabled = false
        s.readAloudShortcut = Shortcut(keyCode: 15, modifiers: [.command, .option])
        s.readAloudFromClipboard = false; s.readAloudStartAtOnce = false; s.readAloudKeepReading = false; s.readAloudPickerButton = false
        s.readAloudHelperEnabled = false; s.readAloudHelper = "Zed"
        var mine = ReadAloud.Preset(name: "Slow Mossy", engine: .system, character: "Mossy", speed: 0.7, pause: 2, language: "he")
        mine.voice = "com.apple.voice.compact.he-IL.Carmit"
        s.readAloudPresets = [ReadAloud.defaultPresets[2], mine]
        s.readAloudDefaultPreset = mine.id.uuidString
        s.readAloudFolder = "~/Music/Readings"; s.readAloudFormat = .wav; s.readAloudLongLimit = 8_000
        let again = AppSettings(defaults: defaults, keychain: Secrets())
        #expect(!again.readAloudEnabled && !again.readAloudShortcutEnabled && again.readAloudShortcut == Shortcut(keyCode: 15, modifiers: [.command, .option]))
        #expect(!again.readAloudFromClipboard && !again.readAloudStartAtOnce && !again.readAloudKeepReading && !again.readAloudPickerButton)
        #expect(!again.readAloudHelperEnabled && again.readAloudHelper == "Zed")
        #expect(again.readAloudPresets == [ReadAloud.defaultPresets[2], mine] && again.readAloudDefault == mine, "added, renamed and deleted presets are kept")
        #expect(again.readAloudFolder == "~/Music/Readings" && again.readAloudFormat == .wav && again.readAloudLongLimit == 8_000)
    }

    @Test func nonsenseIsClampedOnLoad() {
        let (defaults, _) = fresh()
        defer { defaults.removePersistentDomain(forName: name) }
        defaults.set(10, forKey: "readAloudLongLimit"); defaults.set("ogg", forKey: "readAloudFormat"); defaults.set("  ", forKey: "readAloudFolder")
        defaults.set(Data(#"[{"name":"Loud","speed":40}]"#.utf8), forKey: "readAloudPresets")
        defaults.set("not-an-id", forKey: "readAloudDefaultPreset")
        var s = AppSettings(defaults: defaults, keychain: Secrets())
        #expect(s.readAloudLongLimit == 500 && s.readAloudFormat == .m4a && s.readAloudFolder == "~/Desktop")
        #expect(s.readAloudPresets.count == 1 && s.readAloudPresets[0].speed == 2 && s.readAloudDefault.name == "Loud", "an unknown default is the first")
        defaults.set(Data("[]".utf8), forKey: "readAloudPresets")
        s = AppSettings(defaults: defaults, keychain: Secrets())
        #expect(s.readAloudPresets == ReadAloud.defaultPresets, "never none")
        defaults.set(999_999, forKey: "readAloudLongLimit")
        #expect(AppSettings(defaults: defaults, keychain: Secrets()).readAloudLongLimit == 20_000)
    }

    @Test func aToolsScreenArrangedBeforeGetsTheNewTileOnceAndItCanBeSwitchedOff() {
        let (defaults, _) = fresh()
        defer { defaults.removePersistentDomain(forName: name) }
        defaults.set(["translate", "dictation", "reminder"], forKey: "toolsScreenTools")
        defaults.removeObject(forKey: "toolsScreenKnown")    // as 0.62 left it
        let s = AppSettings(defaults: defaults, keychain: Secrets())
        #expect(s.toolsScreenTools == ["translate", "dictation", "reminder", "readAloud"])
        s.toolsScreenTools = ["translate", "dictation", "reminder"]
        #expect(AppSettings(defaults: defaults, keychain: Secrets()).toolsScreenTools == ["translate", "dictation", "reminder"], "off stays off")
        #expect(SettingsGroup.tools.pages.last == .readAloud)
    }

    // MARK: Sound

    @Test func soundPiecesAreJoinedAndWrittenAsOneFile() throws {
        let rate = Int(ReadAloudPlayer.format.sampleRate)
        var pcm = Data()
        for i in 0..<rate / 2 {
            let v = Int16(sin(Double(i) / 20) * 12_000)
            withUnsafeBytes(of: v.littleEndian) { pcm.append(contentsOf: $0) }
        }
        let wav = SpeechClient.wav(pcm: pcm, rate: 16_000, channels: 1)
        let tone = try #require(ReadAloudPlayer.decode(wav), "a WAV reply is read")
        #expect(tone.format == ReadAloudPlayer.format)
        #expect(abs(Double(tone.frameLength) - Double(rate) * 0.75) < 600, "16 kHz becomes 24 kHz, the length kept")
        let rest = try #require(ReadAloudPlayer.silence(seconds: 0.5))
        #expect(Int(rest.frameLength) == rate / 2)
        let joined = try #require(ReadAloudPlayer.join([tone, rest, tone]))
        #expect(joined.frameLength == tone.frameLength * 2 + rest.frameLength)
        let faster = try #require(ReadAloudPlayer.stretched(joined, by: 2))
        #expect(abs(Double(faster.frameLength) - Double(joined.frameLength) / 2) < 5_000, "twice as fast, half as long")

        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("ledgelings-read-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let (defaults, s) = fresh()
        defer { defaults.removePersistentDomain(forName: name) }
        let player = ReadAloudPlayer(settings: s, spend: SpendLedger(directory: folder), voice: Voice(settings: s, spend: SpendLedger(directory: folder),
                                                                                                        archive: folder.appendingPathComponent("v"), lineArchive: folder.appendingPathComponent("l")))
        #expect(throws: (any Error).self) { try player.write(to: folder.appendingPathComponent("none.m4a"), format: .m4a) }
        player.load(tape: [tone, rest, tone])
        for format in ReadAloud.Format.allCases {
            let url = folder.appendingPathComponent("out.\(format.rawValue)")
            try player.write(to: url, format: format)
            let back = try AVAudioFile(forReading: url)
            let seconds = Double(back.length) / back.fileFormat.sampleRate
            #expect(abs(seconds - 2.0) < 0.1, "\(format): \(seconds) s")
        }
    }

    // MARK: Who reads

    @Test func thePartsVoiceIsThePresetsTheCharactersOrTheFirst() {
        let (defaults, s) = fresh(key: "sk-test")
        defer { defaults.removePersistentDomain(forName: name) }
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("ledgelings-read-voice-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: folder) }
        let spend = SpendLedger(directory: folder)
        let player = ReadAloudPlayer(settings: s, spend: spend, voice: Voice(settings: s, spend: spend, archive: folder.appendingPathComponent("v"), lineArchive: folder.appendingPathComponent("l")))
        player.describe = { name in name == "Mortimer" ? ("Old and philosophical. Speaks slowly.", "a boxy creature") : nil }
        let pool = ["am_adam", "af_bella", "am_michael"]
        var narrator = ReadAloud.defaultPresets[0]
        narrator.voice = "af_bella"
        #expect(player.onlineVoice(player.plan(narrator), pool: pool, all: pool) == "af_bella", "the preset's own voice")
        narrator.voice = "Charon"
        #expect(player.onlineVoice(player.plan(narrator), pool: pool, all: pool) == "am_adam", "not among them: the first")
        #expect(player.onlineVoice(player.plan(narrator), pool: [], all: []) == "Charon", "no list to check: sent as chosen")
        var old = ReadAloud.Preset(name: "Old", character: "Mortimer")
        let cast = player.onlineVoice(player.plan(old), pool: pool, all: pool)
        #expect(cast == "am_adam" || cast == "am_michael", "an old man's voice for an old man")
        s.voiceModel = ReadAloud.defaultModel
        s.setVoice(of: "Mortimer") { $0.openRouterVoice = "af_bella" }
        old.model = ""
        #expect(player.onlineVoice(player.plan(old), pool: pool, all: pool) == "af_bella", "his own voice from the Voice page, same model")
    }

    @Test func noKeyMeansTheMacReadsItFree() {
        let (defaults, s) = fresh()
        defer { defaults.removePersistentDomain(forName: name) }
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("ledgelings-read-plan-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: folder) }
        let spend = SpendLedger(directory: folder)
        let player = ReadAloudPlayer(settings: s, spend: spend, voice: Voice(settings: s, spend: spend, archive: folder.appendingPathComponent("v"), lineArchive: folder.appendingPathComponent("l")))
        let plan = player.plan(ReadAloud.defaultPresets[0])
        #expect(plan.engine == .system && plan.note != nil && !plan.engine.isPaid)
        #expect(player.estimate("Hello there.", ReadAloud.defaultPresets[0]) == nil, "free: no price to show")
    }

    @Test func theMacsVoiceSpeaksThePartsLanguage() throws {
        let (defaults, s) = fresh()
        defer { defaults.removePersistentDomain(forName: name) }
        let plan = ReadAloudPlayer.Plan(engine: .system, client: nil, preset: ReadAloud.defaultPresets[0])
        for language in Translate.languages where AVSpeechSynthesisVoice.speechVoices().contains(where: { $0.language.hasPrefix(language.code) }) {
            let voice = try #require(ReadAloudPlayer.macVoice(for: language, plan: plan, settings: s, describe: { _ in nil }))
            #expect(voice.language.hasPrefix(language.code), "\(language.code): \(voice.name)")
        }
    }

    @Test func theSheetsReaderAndPaceGoIntoThePreset() {
        let model = ReadAloudSheetModel()
        model.presetID = ReadAloud.defaultPresets[0].id
        model.reader = ""
        model.speed = 1.3
        #expect(model.preset.voice == "Charon" && model.preset.speed == 1.3 && model.readerTitle == tr("NARRATOR"))
        model.reader = "Blorp"
        #expect(model.preset.character == "Blorp" && model.preset.voice.isEmpty, "another reader gets a voice cast for it")
        #expect(ReadAloudSheetView.tag(ReadAloud.defaultPresets[2], number: 3).contains("Zed") && ReadAloudSheetView.tag(ReadAloud.defaultPresets[2], number: 3).contains("(⌘3)"))
    }
}
