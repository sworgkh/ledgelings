import LedgelingsCore
import SwiftUI

/// The Actions tab: how the Creature Actions sheet behaves, and the shortcut
/// that brings it (or the whole menu) up from any app. They left the Creatures
/// tab when the shortcut made it too long for one screen.
struct ActionsSettingsView: View {
    @ObservedObject var settings: AppSettings

    var body: some View {
        TwoColumns {
            Section {
                Toggle(tr("Keep the sheet up after an action"), isOn: $settings.actionsStayOpen)
            } header: {
                Text(tr("Creature Actions"))
            } footer: {
                Text(tr("On, the Creature Actions sheet stays up until you press Done; off, it folds away after one action."))
            }
        } right: {
            Section {
                Toggle(tr("Shortcut from any app"), isOn: $settings.shortcutEnabled)
                LabeledContent(tr("Shortcut")) { ShortcutRecorder(settings: settings) }
                    .disabled(!settings.shortcutEnabled)
                Picker(tr("It opens"), selection: $settings.shortcutOpens) {
                    ForEach(Shortcut.Opens.allCases, id: \.self) { Text(verbatim: $0.title).tag($0) }
                }
                .disabled(!settings.shortcutEnabled)
                if !settings.shortcutProblem.isEmpty {
                    Text(settings.shortcutProblem).font(.callout).foregroundStyle(.red)
                }
            } header: {
                Text(tr("When the icon is hidden"))
            } footer: {
                Text(tr("macOS hides menu bar icons it has no room for. The shortcut reaches the creatures anyway, whichever app is in front. It opens the Creature Actions sheet, and pressed again puts it away; or the whole menu under the cursor, with Settings and Quit. Click the shortcut to record another: a key with Command, Control or Option held. Esc keeps the old one."))
            }
        }
    }
}
