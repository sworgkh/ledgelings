import Testing
@testable import Ledgelings

@Suite struct ActionsSheetTests {
    @Test func everyTileHasItsOwnLetterAndAPicture() async {
        #expect(Set(ActionsTile.allCases.map(\.key)).count == ActionsTile.allCases.count)
        let pictures = await ActionIcons.pictures
        for tile in ActionsTile.allCases { #expect(pictures[tile] != nil, "\(tile) has no picture") }
    }

    @Test func tilesGreyOutWhenThereIsNothingToDo() {
        var s = ActionsState()
        #expect(ActionsTile.allCases.filter { !$0.isEnabled(in: s) } == [.flowers])
        #expect(ActionsTile.flowers.detail(in: s) == "none planted")
        s.planted = 3
        #expect(ActionsTile.flowers.title(in: s) == "CLEAR 3 FLOWERS" && ActionsTile.flowers.isEnabled(in: s))
        s.nightOff = true
        #expect(!ActionsTile.sleep.isEnabled(in: s) && ActionsTile.sleep.detail(in: s) == "night is set to 0")
        s.teaEnabled = false
        #expect(!ActionsTile.tea.isEnabled(in: s) && ActionsTile.tea.detail(in: s) == "off in settings")
    }

    @Test func whileTheyHideOnlyTheHouseAndTheNotesAndTheClockWork() {
        var s = ActionsState()
        s.hiding = true
        s.hideLeft = 299
        #expect(ActionsTile.allCases.filter { $0.isEnabled(in: s) } == [.reminder, .hide, .sleep])
        #expect(ActionsTile.hide.title(in: s) == "BRING THEM BACK" && ActionsTile.hide.detail(in: s) == "4:59 left")
    }

    @Test func theSleepTileSaysWhichWayTheClockGoes() {
        var s = ActionsState()
        s.phaseLeft = 75
        #expect(ActionsTile.sleep.title(in: s) == "PUT THEM TO SLEEP" && ActionsTile.sleep.detail(in: s) == "dusk in 1:15")
        s.isNight = true
        #expect(ActionsTile.sleep.title(in: s) == "WAKE THEM UP" && ActionsTile.sleep.detail(in: s) == "dawn in 1:15")
    }
}
