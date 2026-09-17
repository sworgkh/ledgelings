import AppKit
import SwiftUI

struct SettingsView: View {
    @ObservedObject var settings: AppSettings

    var body: some View {
        Form {
            Section {
                Stepper(value: $settings.creatureCount, in: AppSettings.countRange) {
                    LabeledContent("How many", value: "\(settings.creatureCount)")
                }
                size("Smallest", value: $settings.minSize)
                size("Largest", value: $settings.maxSize)
            } header: {
                Text("Creatures")
            } footer: {
                Text("Every creature gets its own size between the two. Set them equal and they all match.")
            }

            Section {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 44), spacing: 10)], alignment: .leading, spacing: 10) {
                    ForEach(settings.colors.indices, id: \.self) { index in
                        ColorPicker("Colour \(index + 1)", selection: colorBinding(index), supportsOpacity: false)
                            .labelsHidden()
                    }
                }
                HStack {
                    Button("Add Colour") { settings.colors.append(AppSettings.defaultColors[settings.colors.count % AppSettings.defaultColors.count]) }
                        .disabled(settings.colors.count >= 12)
                    Button("Remove Last") { settings.colors.removeLast() }
                        .disabled(settings.colors.count <= 1)
                    Spacer()
                    Button("Reset") { settings.colors = AppSettings.defaultColors }
                }
            } header: {
                Text("Colours")
            } footer: {
                Text("Creature 1 wears the first colour, creature 2 the second, and so on, starting over when the colours run out.")
            }

            Section {
                minutes("Day lasts", value: $settings.dayMinutes, range: 0.5...60)
                minutes("Night lasts", value: $settings.nightMinutes, range: 0...60)
            } header: {
                Text("Day and night")
            } footer: {
                Text("They walk by day and sleep by night. Set the night to 0 and they never sleep. A cursor still startles a sleeper awake.")
            }
        }
        .formStyle(.grouped)
        .frame(width: 420)
        .fixedSize(horizontal: false, vertical: true)
    }

    private func size(_ title: String, value: Binding<Double>) -> some View {
        LabeledContent(title) {
            HStack {
                Slider(value: value, in: AppSettings.sizeRange, step: AppSettings.sizeStep)
                Text(String(format: "%g×", value.wrappedValue))
                    .monospacedDigit()
                    .frame(width: 62, alignment: .trailing)
            }
        }
    }

    private func minutes(_ title: String, value: Binding<Double>, range: ClosedRange<Double>) -> some View {
        LabeledContent(title) {
            HStack {
                Slider(value: value, in: range, step: 0.5)
                Text(value.wrappedValue == 0 ? "never" : String(format: "%g min", value.wrappedValue))
                    .monospacedDigit()
                    .frame(width: 62, alignment: .trailing)
            }
        }
    }

    private func colorBinding(_ index: Int) -> Binding<Color> {
        Binding(
            get: {
                let rgb = settings.colors.indices.contains(index) ? RGB(hex: settings.colors[index]) : nil
                let c = rgb ?? .white
                return Color(.sRGB, red: Double(c.r) / 255, green: Double(c.g) / 255, blue: Double(c.b) / 255)
            },
            set: { new in
                guard settings.colors.indices.contains(index),
                      let c = NSColor(new).usingColorSpace(.sRGB) else { return }
                func byte(_ v: CGFloat) -> UInt8 { UInt8((min(max(v, 0), 1) * 255).rounded()) }
                settings.colors[index] = RGB(r: byte(c.redComponent), g: byte(c.greenComponent), b: byte(c.blueComponent)).hex
            }
        )
    }
}

@MainActor
final class SettingsWindowController {
    private var window: NSWindow?
    private let settings: AppSettings

    init(settings: AppSettings) { self.settings = settings }

    func show() {
        if window == nil {
            let hosting = NSHostingController(rootView: SettingsView(settings: settings))
            let made = NSWindow(contentViewController: hosting)
            made.title = "Ledgelings Settings"
            made.styleMask = [.titled, .closable]
            made.isReleasedWhenClosed = false
            made.center()
            window = made
        }
        // A menu-bar-only app is never frontmost on its own.
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}
