import AppKit
import AVFoundation
import Foundation
import LedgelingsCore
import Testing
@testable import Ledgelings

/// What the app says while it runs, and who says it out loud, in Russian:
/// statuses and situations in Russian, and lines read by voices that can.
@MainActor
@Suite(.serialized) struct RuntimeLanguageTests {
    static func hasVoice(_ code: String) -> Bool {
        AVSpeechSynthesisVoice.speechVoices().contains { $0.language.hasPrefix(code) }
    }

    /// A colony of two on a virtual display, with defaults of its own.
    @MainActor final class World {
        static let suite = "ledgelings-runtime-language-tests"
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("ledgelings-runtime-language-\(UUID().uuidString)")
        let defaults: UserDefaults
        let settings: AppSettings
        let history: ChatHistory
        let colony: Colony
        init() throws {
            defaults = UserDefaults(suiteName: Self.suite)!
            defaults.removePersistentDomain(forName: Self.suite)
            settings = AppSettings(defaults: defaults, keychain: SettingsTests.SpyStore())
            settings.creatureCount = 2
            settings.brain = .script
            history = ChatHistory(directory: dir.appendingPathComponent("chats"))
            colony = try Colony(settings: settings, history: history,
                                library: SpriteLibrary(directory: dir.appendingPathComponent("sprites")),
                                spend: SpendLedger(directory: dir.appendingPathComponent("spend")),
                                stage: Display(frame: CGRect(x: 0, y: 0, width: 800, height: 600), scale: 1))
            colony.meetings = Meetings(gap: -1e6)
        }
        func forget() {
            defaults.removePersistentDomain(forName: Self.suite)
            try? FileManager.default.removeItem(at: dir)
        }
    }

    static func voice(_ settings: AppSettings) -> Voice {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("ledgelings-runtime-language-\(UUID().uuidString)")
        return Voice(settings: settings, spend: SpendLedger(directory: dir.appendingPathComponent("spend")),
                     archive: dir.appendingPathComponent("voices"), lineArchive: dir.appendingPathComponent("line-voices"))
    }

    @Test func theMacsVoicesAreTheAppsLanguage() {
        let russian = Language.$override.withValue(.russian) { Voice.systemVoices }
        let code = Self.hasVoice("ru") ? "ru" : "en"
        #expect(!russian.isEmpty && russian.allSatisfy { $0.language.hasPrefix(code) }, "Russian voices, or English when there are none")
        let english = Language.$override.withValue(.english) { Voice.systemVoices }
        #expect(english.allSatisfy { $0.language.hasPrefix("en") })
    }

    @Test func anEnglishVoiceChosenByHandDoesNotReadRussian() throws {
        let english = try #require(AVSpeechSynthesisVoice.speechVoices().first { $0.language.hasPrefix("en") })
        try #require(Self.hasVoice("ru"), "this Mac has no Russian voice")
        let w = try World()
        defer { w.forget() }
        w.settings.voiceEngine = .system
        w.settings.voicePerCharacter = true
        w.settings.setVoice(of: "Blocky") { $0.systemVoice = english.identifier }
        let voice = Self.voice(w.settings)
        #expect(Language.$override.withValue(.english) { voice.systemVoice(for: "Blocky", cast: ["Blocky", "Pip"]) } == english.identifier)
        let russian = Language.$override.withValue(.russian) { voice.systemVoice(for: "Blocky", cast: ["Blocky", "Pip"]) }
        let picked = try #require(russian.flatMap(AVSpeechSynthesisVoice.init(identifier:)))
        #expect(picked.language.hasPrefix("ru"))
        // One voice for everyone: an English one gives way to the Russian default.
        w.settings.voicePerCharacter = false
        w.settings.systemVoice = english.identifier
        #expect(Language.$override.withValue(.russian) { voice.systemVoice(for: "Blocky", cast: []) } == nil)
        #expect(Language.$override.withValue(.russian) { Voice.defaultVoice.map { $0.language.hasPrefix("ru") } ?? true })
    }

    @Test func anOnlineVoiceOfAnotherLanguageGivesWayToARussianOne() throws {
        let w = try World()
        defer { w.forget() }
        w.settings.voiceEngine = .openRouter
        w.settings.voicePerCharacter = true
        w.settings.setVoice(of: "Blocky") { $0.openRouterVoice = "en_paul" }
        let voice = Self.voice(w.settings)
        let voices = ["en_paul", "en_jane", "ru_olga", "ru_ivan"]
        #expect(Language.$override.withValue(.english) { voice.onlineVoice(for: "Blocky", cast: ["Blocky"], among: voices) } == "en_paul")
        let russian = Language.$override.withValue(.russian) { voice.onlineVoice(for: "Blocky", cast: ["Blocky"], among: voices) }
        #expect(russian?.hasPrefix("ru_") == true)
        // Voices that say nothing of their language keep the one chosen.
        w.settings.setVoice(of: "Blocky") { $0.openRouterVoice = "alloy" }
        #expect(Language.$override.withValue(.russian) { voice.onlineVoice(for: "Blocky", cast: ["Blocky"], among: ["alloy", "echo"]) } == "alloy")
    }

    @Test func whatIsGoingOnIsSaidInRussian() throws {
        let w = try World()
        defer { w.forget() }
        w.settings.script = "Привет.\nПока.\n"
        Language.$override.withValue(.russian) { w.colony.talkNow(from: 0) }
        let exchange = try #require(w.history.exchanges(on: ChatLog.day(of: Date())).last)
        #expect(exchange.situation.contains("На краю сейчас"), "\(exchange.situation)")
        #expect(exchange.provider == "Встроенные реплики")
        let cyrillic = { (s: String) in s.unicodeScalars.contains { (0x0400...0x04FF).contains($0.value) } }
        Language.$override.withValue(.russian) {
            #expect(cyrillic(AppSettings.needsModel))
            #expect(cyrillic(AppSettings.Brain.script.title) && cyrillic(AppSettings.VoiceEngine.system.title))
            #expect(cyrillic(ChatClient.Failure.serverDown("x").description))
            #expect(cyrillic(LaunchAtLogin.describe(.requiresApproval)))
        }
        Language.$override.withValue(.english) { #expect(AppSettings.Brain.script.title == "Built-in lines") }
    }
}
