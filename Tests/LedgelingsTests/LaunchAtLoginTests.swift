import ServiceManagement
import Testing
@testable import Ledgelings

@Suite struct LaunchAtLoginTests {
    @Test func everyStatusHasWordsTheUserCanActOn() {
        #expect(LaunchAtLogin.describe(.enabled) == "on")
        #expect(LaunchAtLogin.describe(.notRegistered) == "off")
        #expect(LaunchAtLogin.describe(.requiresApproval).contains("Login Items"))
        #expect(LaunchAtLogin.describe(.notFound).contains("installed"))
    }

    @Test func askingOutsideAnAppBundleDoesNotCrash() {
        // The test binary is not Ledgelings.app; whatever macOS answers, it must be a sentence.
        #expect(!LaunchAtLogin.status.isEmpty)
    }
}
