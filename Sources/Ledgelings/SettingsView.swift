import AppKit
import LedgelingsCore
import SwiftUI

struct SettingsView: View {
    @ObservedObject var settings: AppSettings

    var body: some View {
        TabView {
            creaturesTab.tabItem { Text("Creatures") }
            TalkSettingsView(settings: settings).tabItem { Text("Talk") }
        }
        .frame(width: 520, height: 600)
    }

    private var creaturesTab: some View {
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

/// Everything about the creatures talking to each other through LM Studio.
struct TalkSettingsView: View {
    @ObservedObject var settings: AppSettings
    @State private var check = "not checked"
    @State private var models: [String] = []

    var body: some View {
        Form {
            Section {
                Toggle("Creatures talk to each other", isOn: $settings.talkEnabled)
                LabeledContent("Every") {
                    HStack {
                        Slider(value: $settings.talkEveryMinutes, in: 0...180, step: 5)
                        Text(settings.talkEveryMinutes == 0 ? "on request" : String(format: "%g min", settings.talkEveryMinutes))
                            .monospacedDigit().frame(width: 76, alignment: .trailing)
                    }
                }
            } footer: {
                Text("\"Make Someone Talk\" in the menu works at any time. Set the slider to 0 to talk only on request.")
            }

            Section {
                TextField("Server", text: $settings.talkServer, prompt: Text(AppSettings.defaultTalkServer))
                HStack {
                    TextField("Model", text: $settings.talkModel, prompt: Text(AppSettings.defaultTalkModel))
                    if !models.isEmpty {
                        Menu("Installed") {
                            ForEach(models, id: \.self) { id in Button(id) { settings.talkModel = id } }
                        }
                        .fixedSize()
                    }
                    Button("Check") { Task { await checkServer() } }
                }
                LabeledContent("Status") { Text(check).foregroundStyle(.secondary).textSelection(.enabled) }
            } header: {
                Text("LM Studio")
            } footer: {
                Text("LM Studio's local server, started with `lms server start` or from its Developer tab. The model must be one it has installed; \"Check\" lists them.")
            }

            Section {
                ForEach(settings.characters.indices, id: \.self) { i in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            TextField("Name", text: binding(\.characters[i].name)).font(.headline)
                            Button(role: .destructive) { settings.characters.remove(at: i) } label: { Image(systemName: "minus.circle") }
                                .buttonStyle(.borderless).disabled(settings.characters.count <= 2)
                        }
                        TextField("Who they are", text: binding(\.characters[i].persona), axis: .vertical).lineLimit(2...4)
                    }
                    .padding(.vertical, 2)
                }
                HStack {
                    Button("Add Character") { settings.characters.append(Character(name: "Newcomer", persona: "Describe the personality here.")) }
                    Spacer()
                    Button("Reset Cast") { settings.characters = Banter.defaultCharacters }
                }
            } header: {
                Text("Characters")
            } footer: {
                Text("Creature 1 is character 1, creature 2 is character 2, and so on, starting over when the cast runs out. The colours follow the same rule, so creature 1 is always the first colour and the first character.")
            }

            Section {
                prompt("Who is speaking (system prompt)", text: $settings.systemPrompt)
                prompt("Opening line", text: $settings.linePrompt)
                prompt("Reply", text: $settings.replyPrompt)
                HStack { Spacer(); Button("Reset Prompts") { settings.resetPrompts() } }
            } header: {
                Text("Prompts")
            } footer: {
                Text("Placeholders: " + Banter.placeholders.map { "{\($0)}" }.joined(separator: " ") + ". {situation} is written by the app: time of day and where each creature is. {line} is what was just said, for the reply.")
            }
        }
        .formStyle(.grouped)
    }

    private func prompt(_ title: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.subheadline.weight(.semibold))
            TextEditor(text: text)
                .font(.system(.body, design: .monospaced))
                .frame(minHeight: 72)
                .scrollContentBackground(.hidden)
                .padding(4)
                .background(RoundedRectangle(cornerRadius: 6).fill(Color(nsColor: .textBackgroundColor)))
        }
    }

    private func binding<T>(_ path: ReferenceWritableKeyPath<AppSettings, T>) -> Binding<T> {
        Binding(get: { settings[keyPath: path] }, set: { settings[keyPath: path] = $0 })
    }

    private func checkServer() async {
        guard let url = settings.talkServerURL else { check = "that is not a URL"; return }
        check = "checking…"
        do {
            let found = try await TalkService(baseURL: url, model: settings.talkModel).listModels()
            models = found
            check = found.contains(settings.talkModel)
                ? "ready: \(settings.talkModel) is installed"
                : "server is up, but \(settings.talkModel) is not installed. Pick one under \"Installed\"."
        } catch {
            models = []
            check = "\(error)"
        }
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
