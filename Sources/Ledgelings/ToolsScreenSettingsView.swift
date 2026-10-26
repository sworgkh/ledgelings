import LedgelingsCore
import SwiftUI

/// Settings › Tools › Tools screen: the screen and its shortcut on the left,
/// which tools it shows and in what order on the right.
struct ToolsScreenSettingsView: View {
    @ObservedObject var settings: AppSettings

    var body: some View {
        TwoColumns {
            Section {
                Toggle(tr("Tools screen"), isOn: $settings.toolsScreenEnabled)
                LabeledContent(tr("Open it from any app")) {
                    HStack {
                        Toggle("", isOn: $settings.toolsScreenShortcutEnabled).labelsHidden()
                        ShortcutRecorder(settings: settings, shortcut: $settings.toolsScreenShortcut)
                    }
                }
                if !settings.toolsScreenShortcutProblem.isEmpty {
                    Text(settings.toolsScreenShortcutProblem).foregroundStyle(.red)
                }
            } header: {
                SettingsHeader("Tools screen")
            } footer: {
                Text(tr("Every tool on one sheet, a big picture each: click one, press its number, or choose with the arrows and ⏎; ⎋ closes. The Creature Actions sheet opens it too (K). A tool switched off is greyed, and a click opens the page that switches it on."))
            }
        } right: {
            Section {
                List {
                    ForEach(order, id: \.self) { tool in
                        Toggle(isOn: shownBinding(tool)) {
                            HStack(spacing: 8) {
                                PixelGlyph(rows: tool.icon)
                                Text(tool.does)
                            }
                        }
                    }
                    .onMove { from, to in
                        var all = order
                        all.move(fromOffsets: from, toOffset: to)
                        let shown = Set(Tools.shown(settings.toolsScreenTools))
                        settings.toolsScreenTools = all.filter(shown.contains).map(\.rawValue)
                    }
                }
                .frame(height: 8 * 34)
            } header: {
                SettingsHeader("On the screen")
            } footer: {
                Text(tr("Drag to change the order: the first is 1, the next 2. Switched off here, a tool is not on the screen."))
            }
        }
    }

    /// The shown tools in their order, then the others.
    private var order: [Tools.Tool] {
        let shown = Tools.shown(settings.toolsScreenTools)
        return shown + Tools.Tool.allCases.filter { !shown.contains($0) }
    }

    private func shownBinding(_ tool: Tools.Tool) -> Binding<Bool> {
        Binding(get: { Tools.shown(settings.toolsScreenTools).contains(tool) }, set: { on in
            var shown = Tools.shown(settings.toolsScreenTools)
            if on { if !shown.contains(tool) { shown = order.filter { shown.contains($0) || $0 == tool } } } else { shown.removeAll { $0 == tool } }
            settings.toolsScreenTools = shown.map(\.rawValue)
        })
    }
}
