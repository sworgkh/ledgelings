import Foundation
import LedgelingsCore
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

    @MainActor @Test func theShortcutBringsTheSheetUpAndPressedAgainPutsItAway() {
        let defaults = UserDefaults(suiteName: "ledgelings-actions-tests")!
        defer { defaults.removePersistentDomain(forName: "ledgelings-actions-tests") }
        let sheet = ActionsController(settings: AppSettings(defaults: defaults, keychain: Keychain(service: "ledgelings-tests")), colony: { nil }, addReminder: {})
        #expect(!sheet.isUp)
        sheet.toggle()
        #expect(sheet.isUp)
        sheet.toggle()
        #expect(!sheet.isUp)
    }

    @MainActor @Test func openingTheAppAgainShowsTheSheetUnlessToldOtherwise() {
        let defaults = UserDefaults(suiteName: "ledgelings-actions-tests")!
        defer { defaults.removePersistentDomain(forName: "ledgelings-actions-tests") }
        let settings = AppSettings(defaults: defaults, keychain: Keychain(service: "ledgelings-tests"))
        let sheet = ActionsController(settings: settings, colony: { nil }, addReminder: {})
        settings.reopenShowsActions = false
        sheet.reopened()
        #expect(!sheet.isUp)
        settings.reopenShowsActions = true
        sheet.reopened()
        #expect(sheet.isUp)
        // Opened once more while it is up: it stays up, it does not blink away.
        sheet.reopened()
        #expect(sheet.isUp)
        sheet.toggle()
    }

    /// Everything the menu bar menu offers besides the actions is on the sheet too.
    @Test func theMenusSwitchesSayHowTheyStandAndTheLinksAreThere() {
        var s = ActionsState()
        #expect(ActionsSwitch.allCases.count == 5 && ActionsLink.allCases.count == 3)
        #expect(ActionsSwitch.talk.title(in: s) == "TALK ON" && ActionsSwitch.talk.isOn(in: s))
        #expect(ActionsSwitch.voice.title(in: s) == "VOICE OFF" && !ActionsSwitch.voice.isOn(in: s))
        #expect(ActionsSwitch.cursor.title(in: s) == "CURSOR: A MENACE")
        #expect(ActionsSwitch.language.title(in: s) == "ENGLISH")
        s.talkOn = false; s.revengeOn = false; s.mood = .good; s.language = .russian
        #expect(ActionsSwitch.talk.title(in: s) == "TALK OFF" && ActionsSwitch.revenge.title(in: s) == "REVENGE OFF")
        #expect(ActionsSwitch.cursor.title(in: s) == "CURSOR: A PLAYMATE")
        #expect(ActionsSwitch.language.title(in: s) == "РУССКИЙ")
        #expect(ActionsSwitch.talk.said(in: s) == "They keep quiet.")
    }

    @MainActor @Test func aSwitchOnTheSheetChangesTheSettingAndGoesRoundItsChoices() {
        #expect(ActionsController.next(after: CursorMood.good) == .neutral)
        #expect(ActionsController.next(after: CursorMood.allCases.last!) == CursorMood.allCases.first!)
        #expect(ActionsController.next(after: Language.english) == .russian && ActionsController.next(after: Language.russian) == .english)
    }
}
