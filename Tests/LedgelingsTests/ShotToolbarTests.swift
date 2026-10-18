import Testing
@testable import Ledgelings
@testable import LedgelingsCore

/// Every toolbar control is a picture with a name on hover, never a letter to remember.
@MainActor @Suite struct ShotToolbarTests {
    @Test func everyItemHasATooltip() {
        let model = ShotModel(colour: 0, thickness: 3)
        #expect(ShotToolbar.items.count == Shot.Button.allCases.count + Shot.palette.count)
        for item in ShotToolbar.items {
            #expect(!ShotToolbar.tooltip(item, model).isEmpty, "\(item)")
        }
    }

    @Test func enterFollowsTheSettings() {
        let model = ShotModel(colour: 0, thickness: 3)
        model.entersCopy = false
        model.entersSave = true
        #expect(ShotToolbar.tooltip(.button(.done), model) == Shot.Button.done.tooltip(copies: false, saves: true))
    }
}
