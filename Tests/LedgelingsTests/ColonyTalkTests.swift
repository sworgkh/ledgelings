import AppKit
import Foundation
import LedgelingsCore
import Testing
@testable import Ledgelings

/// A colony on a virtual display, stepped by hand, talking from the built-in lines.
@MainActor
@Suite(.serialized) struct ColonyTalkTests {
    @MainActor final class World {
        static let suite = "ledgelings-colony-tests"
        let dir: URL
        let defaults: UserDefaults
        let settings: AppSettings
        let history: ChatHistory
        let colony: Colony
        init() throws {
            dir = FileManager.default.temporaryDirectory.appendingPathComponent("ledgelings-colony-\(UUID().uuidString)")
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
        }
        func step(_ seconds: Double) {
            var left = seconds
            while left > 0 { colony.advance(dt: min(left, 0.05), cursor: CGPoint(x: -500, y: -500), shift: true); left -= 0.05 }
        }
        /// Called from a `defer` at the top of each test, like `SettingsTests.Sandbox`.
        func forget() {
            defaults.synchronize()
            defaults.removePersistentDomain(forName: Self.suite)
            defaults.synchronize()
            try? FileManager.default.removeItem(at: dir)
        }
    }

    @Test func aScriptedConversationPlaysOutLineByLineAndIsLogged() throws {
        let w = try World()
        defer { w.forget() }
        w.settings.script = "Hey {listener}, {speaker} here.\nHello {listener}.\nStill here.\n"
        w.colony.talkNow(from: 0)
        #expect(w.colony.bubbles[0]?.text == "Hey \(w.colony.character(forCreature: 1).name), \(w.colony.character(forCreature: 0).name) here.")
        #expect(w.colony.bubbles[1] == nil, "the answer waits a moment")
        #expect(w.colony.busy == [0, 1])
        w.step(Banter.showTime("Hey x, y here.", base: w.settings.bubbleSeconds) * 0.6 + 0.1)
        #expect(w.colony.bubbles[1]?.text == "Hello \(w.colony.character(forCreature: 0).name).")
        w.step(Banter.showTime("Hello x.", base: w.settings.bubbleSeconds) * 0.6 + 0.1)
        #expect(w.colony.bubbles[0]?.text == "Still here.")
        w.step(2)
        #expect(w.colony.busy.isEmpty, "free again once the last line is out")
        let logged = w.history.exchanges(on: ChatLog.day(of: Date()))
        #expect(logged.count == 1 && logged.first?.lines.count == 3)
        #expect(logged.first?.provider == AppSettings.Brain.script.title && logged.first?.cost == nil)
    }

    @Test func aBrokenScriptSaysSoInTheStatusInsteadOfTalking() throws {
        let w = try World()
        defer { w.forget() }
        w.settings.script = "[loud]\nHello."
        w.colony.talkNow(from: 0)
        #expect(w.colony.bubbles.isEmpty)
        #expect(w.colony.talkStatus.contains("line 1"))
        #expect(w.colony.busy.isEmpty)
    }

    @Test func aFlowerMeetingPicksAFlowerLine() throws {
        let w = try World()
        defer { w.forget() }
        w.settings.script = "Plain.\nPlain back.\n\n[flower]\nA {flower} for you.\nThanks."
        w.colony.talkNow(from: 0)
        #expect(w.colony.bubbles[0]?.text == "Plain.")
        w.step(3)
        w.colony.releaseChat(); w.colony.busy.removeAll(); w.colony.bubbles.removeAll()
        #expect(w.colony.talk(from: 1, to: 0, because: "gift", flower: "tulip"))
        #expect(w.colony.bubbles[1]?.text == "A tulip for you.")
    }
}
