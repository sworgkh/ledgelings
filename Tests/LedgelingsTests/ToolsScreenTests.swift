import AppKit
import Foundation
import LedgelingsCore
import Testing
@testable import Ledgelings

/// The Tools screen: its tiles, its keys, its settings, its place on the Creature Actions sheet.
@MainActor
@Suite(.serialized) struct ToolsScreenTests {
    let name = "ledgelings-tools-screen-tests"

    final class Secrets: SecretStore, @unchecked Sendable {
        func get(_ account: String) -> String? { nil }
        func set(_ value: String?, for account: String) {}
    }

    /// AGENTS rule 4: every tile is a picture, and its tag names its keys.
    @Test func everyTileHasItsPictureAndATooltipNamingItsKey() {
        for (i, tool) in Tools.Tool.allCases.enumerated() {
            #expect(tool.icon.count == 11 && tool.icon.allSatisfy { $0.count == 11 && $0.allSatisfy { ".#".contains($0) } }, "\(tool)")
            #expect(tool.icon.joined().contains("#"))
            #expect(tool.tooltip(number: i + 1, shortcut: "⌃⌥T", on: true).contains("\(i + 1) · ⌃⌥T"), "\(tool)")
            #expect(tool.tooltip(number: i + 1, shortcut: nil, on: true).contains("(\(i + 1))"))
            #expect(tool.tooltip(number: i + 1, shortcut: nil, on: false).contains(tool.page.title), "off: says where to switch it on")
            #expect(!tool.title.isEmpty && !tool.does.isEmpty)
        }
        #expect(Set(Tools.Tool.allCases.map(\.icon)).count == Tools.Tool.allCases.count, "each its own picture")
        #expect(ActionsLink.toolsTooltip(shortcut: "⌃⌥K").contains("K · ⌃⌥K"))
        #expect(Tools.sheetIcon.count == 11)
    }

    @Test func theDefaultsAndAChangeSurviveARelaunch() {
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        defer { defaults.removePersistentDomain(forName: name) }
        let s = AppSettings(defaults: defaults, keychain: Secrets())
        #expect(s.toolsScreenEnabled && s.toolsScreenShortcutEnabled && s.toolsScreenShortcut == .tools)
        #expect(Shortcut.tools == Shortcut(keyCode: 40, modifiers: [.control, .option]), "⌃⌥K")
        #expect(s.toolsScreenTools == Tools.Tool.allCases.map(\.rawValue))
        s.toolsScreenEnabled = false; s.toolsScreenShortcutEnabled = false
        s.toolsScreenShortcut = Shortcut(keyCode: 40, modifiers: [.command, .option])
        s.toolsScreenTools = ["reminder", "translate"]
        let again = AppSettings(defaults: defaults, keychain: Secrets())
        #expect(!again.toolsScreenEnabled && !again.toolsScreenShortcutEnabled)
        #expect(again.toolsScreenShortcut == Shortcut(keyCode: 40, modifiers: [.command, .option]))
        #expect(again.toolsScreenTools == ["reminder", "translate"])
        defaults.set(["translate", "nonsense", "translate", "dictation"], forKey: "toolsScreenTools")
        #expect(AppSettings(defaults: defaults, keychain: Secrets()).toolsScreenTools == ["translate", "dictation"], "unknown and doubled ones go")
    }

    @Test func theArrowsMoveInsideTheGrid() {
        #expect(Tools.step(from: 0, by: .right, count: 8) == 1)
        #expect(Tools.step(from: 0, by: .left, count: 8) == 0, "at the edge it stays")
        #expect(Tools.step(from: 1, by: .down, count: 8) == 5)
        #expect(Tools.step(from: 5, by: .down, count: 8) == 5)
        #expect(Tools.step(from: 6, by: .up, count: 8) == 2)
        #expect(Tools.step(from: 3, by: .down, count: 6) == 3, "no tile under it")
    }

    @Test func aNumberOrEnterStartsATileAndAnOffOneOpensItsSettings() async {
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        defer { defaults.removePersistentDomain(forName: name) }
        let s = AppSettings(defaults: defaults, keychain: Secrets())
        let screen = ToolsScreenController(settings: s)
        var started: [Tools.Tool] = [], opened: [SettingsPage] = []
        screen.start = { started.append($0) }
        screen.openSettings = { opened.append($0) }
        screen.isOn = { $0 != .dictation }
        screen.model.tiles = Tools.Tool.allCases.enumerated().map { .init(tool: $1, number: $0 + 1, on: screen.isOn($1), shortcut: nil) }
        screen.choose(0)
        screen.choose(1)
        for _ in 0..<50 where started.isEmpty { try? await Task.sleep(for: .milliseconds(20)) }
        #expect(started == [.translate])
        #expect(opened == [.dictation])
    }

    @Test func theScreenIsAPageUnderTools() {
        #expect(SettingsGroup.tools.pages.first == .tools)
        #expect(SettingsPage.named("tools") == .tools)
        #expect(ToolsScreenController.size(tiles: 8).height < 500 && ToolsScreenController.size(tiles: 8).width < 700)
    }
}
