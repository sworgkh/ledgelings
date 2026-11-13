import Foundation
import LedgelingsCore
import Testing
@testable import Ledgelings

/// The shared look (docs/DESIGN.md): its scale, its pages, and words that fit.
@MainActor
struct DesignTests {
    @Test func everyGapIsOnTheScale() {
        #expect([Look.Space.xs, Look.Space.s, Look.Space.m, Look.Space.l, Look.Space.xl] == [4, 8, 12, 16, 24])
    }

    @Test func theSettingsWindowIsTheSharedSize() {
        #expect(SettingsWindowController.size == Look.settingsSize)
        #expect(SettingsSidebar.width == Look.sidebarWidth)
    }

    /// Voice outgrew its page: the character cards have their own, findable by the search.
    @Test func characterVoicesHaveTheirOwnPage() {
        #expect(SettingsPage.named("charactervoices") == .characterVoices)
        #expect(SettingsPage.characterVoices.group == .talkAndFriends)
        #expect(SettingsIndex.search("Cast Everyone with Model").contains { $0.page == .characterVoices })
        #expect(SettingsIndex.search("Volume").contains { $0.page == .voice && $0.section == "How they sound" })
        Language.$override.withValue(.russian) {
            #expect(SettingsPage.characterVoices.title == "Голоса персонажей")
            #expect(tr("How they sound") != "How they sound")
        }
    }

    /// The Russian of the settings buttons that ran out of room before.
    @Test func russianButtonsThatTruncatedAreShort() {
        Language.$override.withValue(.russian) {
            for english in ["Open Relationships", "Add Reminder", "Delete All Saved…"] {
                #expect(tr(english).count <= 14, "\(english): \(tr(english))")
            }
        }
    }

    @Test func measuringWordsInThePixelFont() {
        #expect(Pixel.textWidth("", size: 11) == 0)
        #expect(Pixel.textWidth("DONE", size: 13) > Pixel.textWidth("DONE", size: 11))
        #expect(Pixel.fits("OK", size: 13, width: 40))
        #expect(!Pixel.fits("A MUCH LONGER LABEL", size: 13, width: 40))
    }
}
