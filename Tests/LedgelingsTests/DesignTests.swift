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

    /// A row of small pixel buttons and one big one, as wide as SwiftUI lays it out.
    static func rowWidth(small: [String], big: [String] = [], gap: CGFloat = 6, spacer: CGFloat = Look.Space.s) -> CGFloat {
        let smalls = small.map { Pixel.textWidth($0, size: 11) + 2 * PixelButtonStyle.inset(small: true) }
        let bigs = big.map { Pixel.textWidth($0, size: 13) + 2 * PixelButtonStyle.inset(small: false) }
        return (smalls + bigs).reduce(0, +) + gap * CGFloat(small.count + big.count - 1) + spacer
    }

    /// Creature Actions' two rows of buttons fit the sheet in both languages, in every
    /// state: "ЗАНЯТ ИЯ…" and "ГОТО ВО" wrapped there once.
    @Test func theActionsSheetsButtonsFitOnOneLineEach() {
        let room = ActionsController.size.width - 2 * 33 - 24
        for language in Language.allCases {
            Language.$override.withValue(language) {
                var s = ActionsState()
                for (talk, voice) in [(true, true), (false, false), (true, false), (false, true)] {
                    s.talkOn = talk; s.voiceOn = voice
                    let first = Self.rowWidth(small: [ActionsSwitch.talk.title(in: s), ActionsSwitch.voice.title(in: s),
                                                      ActionsLink.chats.title, ActionsLink.quit.title])
                    #expect(first <= room, "\(language): switches row \(first) > \(room)")
                }
                let second = Self.rowWidth(small: [tr("ACTIVITIES…"), tr("STYLES…"), tr("WEATHER…"), ActionsLink.settings.title], big: [tr("DONE")])
                #expect(second <= room, "\(language): pages row \(second) > \(room)")
            }
        }
    }

    /// The pixel paper takes its sizes from `Pixel.Font` and never shrinks words to fit.
    @Test func thePaperUsesTheSharedFonts() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let paper = ["ActionsSheet", "ChatWindow", "ClipPicker", "ReminderNote", "ReadAloudSheet", "ToolsScreen", "TranslateSheet"]
        for name in paper {
            let text = try String(contentsOf: root.appendingPathComponent("Sources/Ledgelings/\(name).swift"), encoding: .utf8)
            #expect(!text.contains("minimumScaleFactor"), "\(name) shrinks words to fit")
            let own = text.matches(of: /\.system\(size: \d+/).count
            #expect(own == 0, "\(name) sets \(own) font size(s) of its own; use Pixel.Font")
        }
    }
}
