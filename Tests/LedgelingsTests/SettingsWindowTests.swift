import Foundation
import LedgelingsCore
import Testing
@testable import Ledgelings

/// The settings window's sidebar: its pictures, its search, where it opens.
@MainActor
struct SettingsWindowTests {
    @Test func everyGroupAndTheSearchHaveAPixelPicture() {
        let pictures = SettingsGroup.allCases.map(SettingsSidebar.icon) + [SettingsSidebar.searchIcon, SettingsSidebar.clearIcon]
        for rows in pictures {
            #expect(rows.count == 11)
            #expect(rows.allSatisfy { $0.count == 11 && $0.allSatisfy { ".#".contains($0) } })
            #expect(rows.joined().contains("#"))
        }
        #expect(Set(SettingsGroup.allCases.map(SettingsSidebar.icon)).count == SettingsGroup.allCases.count, "each group its own picture")
    }

    @Test func theClearButtonSaysWhatItDoesAndItsKey() {
        #expect(SettingsSidebar.clearTip.contains("⎋"))
        Language.$override.withValue(.russian) {
            #expect(tr("Clear the search (⎋)").contains("⎋"))
            #expect(tr("Clear the search (⎋)") != "Clear the search (⎋)")
        }
    }

    @Test func itOpensOnCreaturesAndAHitOpensItsPage() async throws {
        let navigation = SettingsNavigation()
        #expect(navigation.page == .creatures)
        #expect(navigation.query.isEmpty)
        navigation.open(SettingsIndex.Hit(page: .clipboard, section: "History", text: "Keep images"))
        #expect(navigation.page == .clipboard)
        // The main actor is shared with the other tests, so wait for each step rather than a fixed time.
        var lit = false
        for _ in 0..<200 where !lit { try await Task.sleep(for: .milliseconds(25)); lit = navigation.flash == "History" }
        #expect(lit, "its heading lights up")
        for _ in 0..<400 where navigation.flash != nil { try await Task.sleep(for: .milliseconds(25)) }
        #expect(navigation.flash == nil, "for a moment only")
    }

    @Test func theWindowFitsALaptopScreen() {
        #expect(SettingsWindowController.size.width <= 1280)
        #expect(SettingsWindowController.size.height <= 800 - 37, "under the menu bar of a 1280×800 screen")
        #expect((SettingsWindowController.size.width - SettingsSidebar.width) / 2 >= 500, "two columns of 500 or more")
    }
}
