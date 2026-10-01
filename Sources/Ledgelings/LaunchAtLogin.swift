import ServiceManagement
import LedgelingsCore

/// Start with the Mac, through the system's own login-items list. Only an
/// installed .app can register; a `swift run` binary is "not found".
enum LaunchAtLogin {
    static var isOn: Bool { SMAppService.mainApp.status == .enabled }

    static var status: String { describe(SMAppService.mainApp.status) }

    static func set(_ on: Bool) throws {
        if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
    }

    static func describe(_ status: SMAppService.Status) -> String {
        switch status {
        case .enabled: tr("on")
        case .notRegistered: tr("off")
        case .requiresApproval: tr("waiting for your approval in System Settings › General › Login Items")
        case .notFound: tr("not available here; use the installed Ledgelings.app")
        @unknown default: tr("unknown")

        }
    }
}
