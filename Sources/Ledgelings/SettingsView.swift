import AppKit
import LedgelingsCore
import SwiftUI

enum SettingsTab: Hashable { case creatures, sprites, talk, chats }

/// Which tab the window shows; the menu can point it at one.
@MainActor
final class SettingsNavigation: ObservableObject {
    @Published var tab: SettingsTab = .creatures
}

struct SettingsView: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject var history: ChatHistory
    @ObservedObject var library: SpriteLibrary
    @ObservedObject var spend: SpendLedger
    @ObservedObject var navigation: SettingsNavigation

    var body: some View {
        TabView(selection: $navigation.tab) {
            creaturesTab.tabItem { Text("Creatures") }.tag(SettingsTab.creatures)
            SpritesSettingsView(settings: settings, library: library).tabItem { Text("Sprites") }.tag(SettingsTab.sprites)
            TalkSettingsView(settings: settings, library: library, spend: spend).tabItem { Text("Talk") }.tag(SettingsTab.talk)
            ChatHistoryView(history: history).tabItem { Text("Chats") }.tag(SettingsTab.chats)
        }
        .frame(width: 560, height: 600)
    }

    private var creaturesTab: some View {
        Form {
            Section {
                Stepper(value: $settings.creatureCount, in: AppSettings.countRange) {
                    LabeledContent("How many", value: "\(settings.creatureCount)")
                }
                SliderRow("Smallest", value: $settings.minSize, in: AppSettings.sizeRange, step: AppSettings.sizeStep, unit: "×")
                SliderRow("Largest", value: $settings.maxSize, in: AppSettings.sizeRange, step: AppSettings.sizeStep, unit: "×")
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
                SliderRow("Day lasts", value: $settings.dayMinutes, in: 0.5...60, step: 0.5, unit: " min")
                SliderRow("Night lasts", value: $settings.nightMinutes, in: 0...60, step: 0.5, unit: " min", zero: "never")
            } header: {
                Text("Day and night")
            } footer: {
                Text("They walk by day and sleep by night. Set the night to 0 and they never sleep. A cursor still startles a sleeper awake.")
            }

            Section {
                Toggle("Start Ledgelings when you log in", isOn: $startsAtLogin)
                    .onChange(of: startsAtLogin) { _, wanted in
                        guard wanted != LaunchAtLogin.isOn else { return }
                        do { try LaunchAtLogin.set(wanted) } catch { loginStatus = "\(error.localizedDescription)" ; return }
                        loginStatus = LaunchAtLogin.status
                        startsAtLogin = LaunchAtLogin.isOn
                    }
                LabeledContent("Status") { Text(loginStatus).foregroundStyle(.secondary) }
            } header: {
                Text("Startup")
            } footer: {
                Text("Uses the system's Login Items list; you can also change it in System Settings › General › Login Items.")
            }
        }
        .formStyle(.grouped)
        .onAppear { startsAtLogin = LaunchAtLogin.isOn; loginStatus = LaunchAtLogin.status }
    }

    @State private var startsAtLogin = false
    @State private var loginStatus = "not checked"

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

/// A labelled slider with its value printed beside it: "3×", "5 min", "14 s".
struct SliderRow: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double
    let unit: String
    /// What to print instead of "0" when zero means off.
    var zero: String? = nil

    init(_ title: String, value: Binding<Double>, in range: ClosedRange<Double>, step: Double, unit: String, zero: String? = nil) {
        self.title = title
        _value = value
        self.range = range
        self.step = step
        self.unit = unit
        self.zero = zero
    }

    var body: some View {
        LabeledContent(title) {
            HStack {
                Slider(value: $value, in: range, step: step)
                Text(value == 0 && zero != nil ? zero! : String(format: "%g", value) + unit)
                    .monospacedDigit()
                    .frame(width: 70, alignment: .trailing)
            }
        }
    }
}

@MainActor
final class SettingsWindowController {
    private var window: NSWindow?
    private let settings: AppSettings
    private let history: ChatHistory
    private let library: SpriteLibrary
    private let spend: SpendLedger
    private let navigation = SettingsNavigation()

    init(settings: AppSettings, history: ChatHistory, library: SpriteLibrary, spend: SpendLedger) {
        self.settings = settings
        self.history = history
        self.library = library
        self.spend = spend
    }

    func show(tab: SettingsTab? = nil) {
        if let tab { navigation.tab = tab }
        if window == nil {
            let hosting = NSHostingController(rootView: SettingsView(settings: settings, history: history, library: library, spend: spend, navigation: navigation))
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
