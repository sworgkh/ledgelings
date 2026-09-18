import ServiceManagement

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
        case .enabled: "on"
        case .notRegistered: "off"
        case .requiresApproval: "waiting for your approval in System Settings › General › Login Items"
        case .notFound: "not available here; use the installed Ledgelings.app"
        @unknown default: "unknown"
        }
    }
}
