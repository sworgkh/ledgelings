import Testing
@testable import Ledgelings

/// The Productivity tools tab: where the old Reminders tab went.
@MainActor
struct ProductivitySettingsTests {
    @Test func scriptsNameTheTabOrItsOldName() {
        #expect(SettingsTab.named("productivity") == .productivity)
        #expect(SettingsTab.named("reminders") == .productivity, "old scripts still open it")
        #expect(SettingsTab.named("nonsense") == nil)
    }

    @Test func remindersIsTheFirstToolAndOpensByDefault() {
        #expect(ProductivityTool.allCases.first == .reminders)
        #expect(SettingsNavigation().tool == .reminders)
    }
}
