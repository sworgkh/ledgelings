import Testing
import LedgelingsCore
@testable import Ledgelings

/// The Creature Actions sheet in Russian: every tile says its words in Russian,
/// and they still fit a tile.
@Suite struct ActionsSheetLanguageTests {
    /// Every state a tile's words depend on.
    static var states: [ActionsState] {
        var all: [ActionsState] = []
        for night in [false, true] {
            for nightOff in [false, true] {
                for hiding in [false, true] {
                    for planted in [0, 1, 3, 5, 21] {
                        var s = ActionsState()
                        s.isNight = night; s.nightOff = nightOff; s.hiding = hiding; s.planted = planted
                        s.teaOn = planted == 3; s.teaEnabled = planted != 5; s.planeInAir = hiding
                        s.phaseLeft = 3725; s.hideLeft = 90
                        all.append(s)
                    }
                }
            }
        }
        return all
    }

    static func isRussian(_ text: String) -> Bool {
        !text.unicodeScalars.contains { ("a"..."z").contains($0) || ("A"..."Z").contains($0) }
            && text.unicodeScalars.contains { (0x0400...0x04FF).contains($0.value) }
    }

    @Test func everyTileSpeaksRussian() {
        Language.$override.withValue(.russian) {
            for s in Self.states {
                for tile in ActionsTile.allCases {
                    let title = tile.title(in: s)
                    #expect(Self.isRussian(title), "\(tile): \(title)")
                    if let detail = tile.detail(in: s) { #expect(Self.isRussian(detail), "\(tile): \(detail)") }
                }
            }
            for (title, _) in ActionsSheetView.hideChoices { #expect(Self.isRussian(title), "\(title)") }
        }
    }

    /// A tile has two lines of about 16 letters for its title and one of about 20 for its detail.
    @Test func russianFitsATile() {
        Language.$override.withValue(.russian) {
            for s in Self.states {
                for tile in ActionsTile.allCases {
                    let title = tile.title(in: s)
                    #expect(title.count <= 32 && title.split(separator: " ").allSatisfy { $0.count <= 16 }, "\(title)")
                    if let detail = tile.detail(in: s) { #expect(detail.count <= 20, "\(detail)") }
                }
            }
        }
    }

    @Test func clearingCountsFlowersInRussian() {
        Language.$override.withValue(.russian) {
            var s = ActionsState()
            s.planted = 3
            #expect(ActionsTile.flowers.title(in: s) == "УБРАТЬ 3 ЦВЕТКА")
            s.planted = 5
            #expect(ActionsTile.flowers.title(in: s) == "УБРАТЬ 5 ЦВЕТКОВ")
            s.planted = 21
            #expect(ActionsTile.flowers.title(in: s) == "УБРАТЬ 21 ЦВЕТОК")
        }
        Language.$override.withValue(.english) {
            var s = ActionsState()
            s.planted = 3
            #expect(ActionsTile.flowers.title(in: s) == "CLEAR 3 FLOWERS")
        }
    }
}
