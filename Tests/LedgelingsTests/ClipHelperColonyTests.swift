import Foundation
import LedgelingsCore
import Testing
@testable import Ledgelings

/// §7.11.1 in the colony: a creature leaps to the paper's corner, holds it, says
/// its line, leaps home and is free again; the settings that steer it.
@MainActor
@Suite(.serialized) struct ClipHelperColonyTests {
    @Test func aCreatureLeapsToTheCornerHoldsItAndGoesHome() async throws {
        let w = try ColonyTalkTests.World()
        defer { w.forget() }
        w.settings.talkEnabled = true
        var lines: [String] = []
        w.colony.trace = { lines.append($0) }
        let paper = CGRect(x: 100, y: 60, width: 600, height: 484)
        let wait = try #require(w.colony.clipHelperCome(paper: paper, centre: CGPoint(x: 400, y: 300)))
        #expect(wait > 0 && wait <= 0.5, "quick: the picker is waiting")
        let help = try #require(w.colony.clipHelp)
        let i = help.index
        #expect(w.colony.busy.contains(i), "nothing else starts with it")
        let perch = try #require(w.colony.clipHelperPerch)
        w.step(wait + 0.1)
        guard case .holding = w.colony.clipHelp?.stage else { Issue.record("not holding"); return }
        #expect(hypot(w.colony.creatures[i].position.x - perch.x, w.colony.creatures[i].position.y - perch.y) < 1)
        #expect(w.colony.bubbles[i] != nil, "a line of its own as the sheet unfolds")
        w.colony.clipHelperGoHome(after: 0)
        for _ in 0..<40 where w.colony.clipHelp != nil {
            try await Task.sleep(for: .milliseconds(10))
            w.step(0.05)
        }
        #expect(w.colony.clipHelp == nil && !w.colony.busy.contains(i))
        #expect(hypot(w.colony.creatures[i].position.x - help.home.x, w.colony.creatures[i].position.y - help.home.y) < 40, "back where it was")
        #expect(lines.contains { $0.contains("holds the corner") } && lines.contains { $0.contains("is back at") })
    }

    @Test func theNamedOneComesAndNobodyComesWhenSwitchedOffOrHiding() throws {
        let w = try ColonyTalkTests.World()
        defer { w.forget() }
        let second = w.colony.character(forCreature: 1).name
        w.settings.clipHelper = second
        let paper = CGRect(x: 100, y: 60, width: 600, height: 484)
        _ = w.colony.clipHelperCome(paper: paper, centre: .zero)
        #expect(w.colony.clipHelp?.index == 1)
        _ = w.colony.clipHelperCome(paper: paper, centre: .zero)
        #expect(w.colony.clipHelp?.index == 1, "called again, the same one comes, cut short and sent anew")
        w.settings.talkEnabled = false
        w.step(1)
        #expect(w.colony.bubbles[1] == nil, "no line with talk off")
    }

    @Test func theHelperSettingsSurviveARelaunch() {
        let name = "ledgelings-clip-helper-settings-tests"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        defer { defaults.removePersistentDomain(forName: name) }
        let s = AppSettings(defaults: defaults, keychain: SettingsTests.SpyStore())
        #expect(s.clipHelperEnabled && s.clipHelper.isEmpty && s.clipHelperTalks)
        s.clipHelperEnabled = false; s.clipHelper = "Zed"; s.clipHelperTalks = false
        let again = AppSettings(defaults: defaults, keychain: SettingsTests.SpyStore())
        #expect(!again.clipHelperEnabled && again.clipHelper == "Zed" && !again.clipHelperTalks)
    }
}
