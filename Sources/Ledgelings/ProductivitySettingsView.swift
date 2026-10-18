import LedgelingsCore
import SwiftUI

/// One tool on the Productivity tools tab. Adding a tool is three lines: a case
/// here, its `title`, and its view in `ProductivitySettingsView.page`. The picker
/// at the top lists every case in order; `SettingsWindowController.show(tool:)`
/// opens the tab on one.
enum ProductivityTool: String, CaseIterable, Hashable {
    case reminders

    var title: String {
        switch self {
        case .reminders: tr("Reminders")
        }
    }
}

/// Settings › Productivity tools: things the creatures do for you rather than
/// for themselves. A picker of tools along the top, the chosen tool's own two
/// columns below.
struct ProductivitySettingsView: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject var reminders: ReminderBook
    @ObservedObject var navigation: SettingsNavigation
    /// Deliver a reminder now.
    let send: (Reminders.Reminder) -> Void

    var body: some View {
        VStack(spacing: 0) {
            Picker(tr("Tool"), selection: $navigation.tool) {
                ForEach(ProductivityTool.allCases, id: \.self) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
            .padding(.top, 12)
            page(navigation.tool)
        }
    }

    @ViewBuilder private func page(_ tool: ProductivityTool) -> some View {
        switch tool {
        case .reminders: RemindersSettingsView(settings: settings, reminders: reminders, send: send)
        }
    }
}
