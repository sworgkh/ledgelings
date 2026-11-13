import AppKit
import LedgelingsCore

/// The monitors to choose from for `homeScreen`, as the menu, the Actions sheet
/// and the Creatures tab list them: every attached one, left to right, by name,
/// and the chosen one too while it is unplugged.
@MainActor
enum ScreenChoice {
    /// Every attached monitor, left to right (top first where two stand in one column).
    static var attached: [HomeScreen.Monitor] {
        Display.attached.map { HomeScreen.Monitor(id: $0.id, name: $0.name, frame: $0.frame) }
            .sorted { ($0.frame.minX, -$0.frame.maxY) < ($1.frame.minX, -$1.frame.maxY) }
    }

    /// One monitor, nothing to choose: the choice is only offered with two or more.
    static var isOffered: Bool { NSScreen.screens.count > 1 }

    /// The chosen monitor is unplugged: they live on every monitor until it is back.
    static func isAway(_ settings: AppSettings) -> Bool {
        HomeScreen.isAway(settings.homeScreen, among: attached)
    }

    /// The choice in words: "All screens", the monitor's name, or its name and that it is unplugged.
    static func current(_ settings: AppSettings) -> String {
        if settings.homeScreen == HomeScreen.all { return tr("All screens") }
        let name = attached.first { $0.id == settings.homeScreen }?.name ?? settings.homeScreenName
        return isAway(settings) ? tr("%@ (unplugged: all screens till it is back)", name) : name
    }
}
