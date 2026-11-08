import AppKit
import Foundation
import LedgelingsCore
import Testing
@testable import Ledgelings

/// Remember where windows were moved: the setting, the saved places, and the windows that move.
@MainActor
@Suite(.serialized) struct WindowPlacesSettingsTests {
    let name = "ledgelings-window-places-tests"

    @Test func theDefaultAndAChangeSurviveARelaunch() {
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        defer { defaults.removePersistentDomain(forName: name) }
        let s = AppSettings(defaults: defaults, keychain: Keychain(service: name))
        #expect(s.rememberWindowPlaces)
        #expect(s.windowPlaces.isEmpty)
        s.moved(.tools, topLeft: CGPoint(x: 120.4, y: 700.6))
        s.moved(.overlay, topLeft: CGPoint(x: 5, y: 5))
        let again = AppSettings(defaults: defaults, keychain: Keychain(service: name))
        #expect(again.place(of: .tools) == CGPoint(x: 120, y: 701))
        #expect(again.place(of: .overlay) == nil, "the creatures' layer never moves")
        again.rememberWindowPlaces = false
        again.moved(.settings, topLeft: CGPoint(x: 10, y: 10))
        let off = AppSettings(defaults: defaults, keychain: Keychain(service: name))
        #expect(!off.rememberWindowPlaces)
        #expect(off.place(of: .tools) == nil && off.windowPlaces["settings"] == nil, "off: nothing is used or kept")
        defaults.set(["tools": [1.0]], forKey: "windowPlaces")
        #expect(AppSettings(defaults: defaults, keychain: Keychain(service: name)).windowPlaces.isEmpty, "a broken place is dropped on load")
    }

    @Test func theNoteWindowsMoveByTheirPaper() {
        let note = NoteWindow(size: CGSize(width: 300, height: 200))
        #expect(note.isMovableByWindowBackground && note.isMovable)
    }

    @Test func aPaperSheetOpensWhereItWasLetGo() throws {
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        defer { defaults.removePersistentDomain(forName: name) }
        let s = AppSettings(defaults: defaults, keychain: Keychain(service: name))
        let screen = try #require(NSScreen.main)
        let room = screen.visibleFrame
        let size = CGSize(width: 400, height: 300)
        let first = WindowPlacer.paper(.translate, size: size, screen: screen, settings: s)
        #expect(first.paper == CGRect(x: (room.width - 400) / 2, y: (room.height - 300) / 2, width: 400, height: 300).integral, "centred before any drag")
        WindowPlacer.paperMoved(.translate, paper: CGRect(x: 20, y: 30, width: 400, height: 300), room: room, settings: s)
        let again = WindowPlacer.paper(.translate, size: size, screen: screen, settings: s)
        #expect(again.screen == screen)
        #expect(again.paper == CGRect(x: 20, y: 30, width: 400, height: 300))
    }
}
