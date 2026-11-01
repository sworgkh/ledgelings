import AppKit
import AVFoundation
import LedgelingsCore
import SwiftUI

/// Settings › Tools › Read aloud: the shortcut and the sound files on the left,
/// the presets and the one being edited on the right.
struct ReadAloudSettingsView: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject var voice: Voice
    let library: SpriteLibrary
    let readAloud: ReadAloudController?
    @State private var editing: UUID?
    @State private var listProblem: String?

    var body: some View {
        TwoColumns {
            Section {
                Toggle(tr("Read aloud"), isOn: $settings.readAloudEnabled)
                LabeledContent(tr("Open the sheet")) {
                    HStack {
                        Toggle("", isOn: $settings.readAloudShortcutEnabled).labelsHidden()
                        ShortcutRecorder(settings: settings, shortcut: $settings.readAloudShortcut)
                    }
                }
                Toggle(tr("Start with the clipboard's text"), isOn: $settings.readAloudFromClipboard)
                Toggle(tr("Start reading at once"), isOn: $settings.readAloudStartAtOnce)
                    .disabled(!settings.readAloudFromClipboard)
                Toggle(tr("Keep reading when the sheet closes"), isOn: $settings.readAloudKeepReading)
                if !settings.readAloudShortcutProblem.isEmpty {
                    Text(settings.readAloudShortcutProblem).foregroundStyle(.red)
                }
            } header: {
                SettingsHeader("Read aloud")
            } footer: {
                Text(tr("The shortcut works in every app: a creature brings a sheet with the clipboard's text in it and reads it out, the parts playing as they come. ⏎ reads and pauses, ⌘. stops, ⌘S saves the sound, ⌘⇧C copies it as a file. With Keep reading on, closing the sheet lets it read on; the menu's Stop Reading ends it."))
            }

            Section {
                LabeledContent(tr("Save in")) {
                    HStack {
                        Text(settings.readAloudFolder).lineLimit(1).truncationMode(.middle).foregroundStyle(.secondary)
                        Button(tr("Choose…")) { chooseFolder() }
                    }
                }
                Picker(tr("Format"), selection: $settings.readAloudFormat) {
                    ForEach(ReadAloud.Format.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                SliderRow(tr("Ask before sending more than"), value: Binding(get: { Double(settings.readAloudLongLimit) }, set: { settings.readAloudLongLimit = Int($0) }),
                          in: Double(ReadAloud.longLimitRange.lowerBound)...Double(ReadAloud.longLimitRange.upperBound), step: 500, unit: "")
                Toggle(tr("Read-aloud button in the clipboard picker"), isOn: $settings.readAloudPickerButton)
                Picker(tr("Who brings the sheet"), selection: Binding(
                    get: { settings.readAloudHelperEnabled ? settings.readAloudHelper : Self.nobody },
                    set: { who in
                        settings.readAloudHelperEnabled = who != Self.nobody
                        if who != Self.nobody { settings.readAloudHelper = who }
                    })) {
                    Text(tr("Whoever is nearest the middle")).tag("")
                    ForEach(onScreen, id: \.self) { Text($0).tag($0) }
                    Text(tr("Nobody: it unfolds by itself")).tag(Self.nobody)
                }
            } header: {
                SettingsHeader("Saving and safety")
            } footer: {
                Text(tr("Save writes the whole reading as one file in this folder, named by the time and its first words. Copy puts the file on the clipboard, to drop into a chat or a mail. Every call to a speech model shows on Costs as Read aloud, a stopped one too. Longer texts wait for ⏎ and say their parts and price first; never more than 50 000 characters. Protected snippets are never read."))
            }
        } right: {
            Section {
                ForEach(settings.readAloudPresets) { preset in
                    HStack {
                        Text(preset.title).fontWeight(preset.id == chosen?.id ? .semibold : .regular)
                        Text(summary(preset)).foregroundStyle(.secondary).lineLimit(1)
                        Spacer()
                        if preset.id.uuidString == settings.readAloudDefaultPreset { Text(tr("Start with")).foregroundStyle(.secondary) }
                    }
                    .contentShape(Rectangle())
                    .onTapGesture { editing = preset.id }
                    .listRowBackground(preset.id == chosen?.id ? Color.accentColor.opacity(0.15) : Color.clear)
                }
                HStack {
                    Button(tr("Add")) { add() }.disabled(settings.readAloudPresets.count >= ReadAloud.mostPresets)
                    Button(tr("Delete")) { delete() }.disabled(settings.readAloudPresets.count <= 1)
                    Button(tr("Start with")) { if let chosen { settings.readAloudDefaultPreset = chosen.id.uuidString } }
                    Spacer()
                    Button(tr("Try it")) { tryIt() }.disabled(readAloud == nil)
                }
                if let chosen { editor(chosen) }
                if let listProblem { Text(listProblem).foregroundStyle(.secondary) }
            } header: {
                SettingsHeader("Presets")
            } footer: {
                Text(tr("A preset is who reads and how: the voice, a character or a narrator, the pace and the rest after each paragraph. ⌘1–9 picks one on the sheet. A character reads in a voice cast from its persona and species, the one it has on the Voice page when that is the same model. Each part's language is told by its letters, and a voice that speaks it is found; if the model has none, the Mac's own voice reads that part, free."))
            }
            .task { await loadModels() }
        }
    }

    // MARK: The preset being edited

    private var chosen: ReadAloud.Preset? {
        settings.readAloudPresets.first { $0.id == editing } ?? settings.readAloudPresets.first
    }

    @ViewBuilder private func editor(_ preset: ReadAloud.Preset) -> some View {
        TextField(tr("Name"), text: field(preset, \.name))
        Picker(tr("Reads with"), selection: field(preset, \.engine)) {
            ForEach(ReadAloud.Engine.allCases, id: \.self) { Text($0.title).tag($0) }
        }
        if preset.engine == .openRouter {
            Picker(tr("Model"), selection: field(preset, \.model)) {
                Text(verbatim: "\(ReadAloud.defaultModel) · \(price(ReadAloud.defaultModel))").tag("")
                if !preset.model.isEmpty, !voice.models.contains(where: { $0.id == preset.model }) { Text(preset.model).tag(preset.model) }
                ForEach(voice.models.filter { $0.id != ReadAloud.defaultModel }) { m in Text(verbatim: "\(m.id) · \(m.priceLabel)").tag(m.id) }
            }
        }
        Picker(tr("Voice"), selection: field(preset, \.voice)) {
            Text(tr("Chosen for the reader")).tag("")
            let all = voices(for: preset)
            if !preset.voice.isEmpty, !all.contains(where: { $0.id == preset.voice }) { Text(preset.voice).tag(preset.voice) }
            ForEach(all, id: \.id) { Text($0.title).tag($0.id) }
        }
        Picker(tr("Reader"), selection: field(preset, \.character)) {
            Text(tr("A narrator")).tag("")
            let all = readAloud?.readers() ?? []
            if !preset.character.isEmpty, !all.contains(preset.character) { Text(preset.character).tag(preset.character) }
            ForEach(all, id: \.self) { Text($0).tag($0) }
        }
        SliderRow(tr("Pace"), value: field(preset, \.speed), in: ReadAloud.speedRange, step: 0.05, unit: "×")
        SliderRow(tr("Rest after a paragraph"), value: field(preset, \.pause), in: ReadAloud.pauseRange, step: 0.1, unit: tr(" s"))
        Picker(tr("Language"), selection: field(preset, \.language)) {
            Text(tr("Told by its letters")).tag("")
            ForEach(Translate.languages) { Text($0.title).tag($0.code) }
        }
    }

    /// One field of one preset, saved as it changes.
    private func field<T>(_ preset: ReadAloud.Preset, _ path: WritableKeyPath<ReadAloud.Preset, T>) -> Binding<T> {
        Binding(get: { settings.readAloudPresets.first { $0.id == preset.id }?[keyPath: path] ?? preset[keyPath: path] },
                set: { value in
                    guard let at = settings.readAloudPresets.firstIndex(where: { $0.id == preset.id }) else { return }
                    var changed = settings.readAloudPresets[at]
                    changed[keyPath: path] = value
                    // A voice belongs to its engine and model: a new one starts with the reader's.
                    if path == \ReadAloud.Preset.engine || path == \ReadAloud.Preset.model { changed.voice = "" }
                    settings.readAloudPresets[at] = path == \ReadAloud.Preset.name ? changed : changed.clamped()
                })
    }

    private func voices(for preset: ReadAloud.Preset) -> [(id: String, title: String)] {
        switch preset.engine {
        case .openRouter:
            return (voice.models.first { $0.id == preset.modelOrDefault }?.voices ?? []).map { ($0, $0) }
        case .local:
            return voice.localVoices.map { ($0, $0) }
        case .system:
            let codes = preset.forcedLanguage.map { [$0.code] } ?? Translate.languages.map(\.code)
            return AVSpeechSynthesisVoice.speechVoices()
                .filter { v in codes.contains { v.language.hasPrefix($0) } && !v.voiceTraits.contains(.isPersonalVoice) }
                .sorted { ($0.language, $0.name) < ($1.language, $1.name) }
                .map { ($0.identifier, "\($0.name) · \($0.language)") }
        }
    }

    private func summary(_ preset: ReadAloud.Preset) -> String {
        let who = preset.character.isEmpty ? (preset.voice.isEmpty ? tr("a narrator") : preset.voice) : preset.character
        return "\(who), \(ReadAloud.speedLabel(preset.speed))" + (preset.forcedLanguage.map { ", " + $0.title } ?? "")
    }

    private func price(_ model: String) -> String {
        voice.models.first { $0.id == model }?.priceLabel ?? tr("price unknown")
    }

    private func add() {
        let base = chosen ?? ReadAloud.defaultPresets[0]
        var made = base
        made.id = UUID()
        made.name = ReadAloud.freeName(tr("My preset"), among: settings.readAloudPresets)
        settings.readAloudPresets.append(made)
        editing = made.id
    }

    private func delete() {
        guard let chosen, settings.readAloudPresets.count > 1 else { return }
        settings.readAloudPresets.removeAll { $0.id == chosen.id }
        if settings.readAloudDefaultPreset == chosen.id.uuidString, let first = settings.readAloudPresets.first {
            settings.readAloudDefaultPreset = first.id.uuidString
        }
        editing = settings.readAloudPresets.first?.id
    }

    /// A line in the preset's voice, so the choice can be heard.
    private func tryIt() {
        guard let chosen, let readAloud else { return }
        let line: String = switch chosen.forcedLanguage?.code {
        case "ru": "Привет! Так я читаю вслух: спокойно, с паузой в конце абзаца."
        case "he": "שלום! ככה אני קורא בקול רם."
        default: tr("Hello! This is how I read aloud, with a rest at the end of each paragraph.")
        }
        readAloud.player.read(line, preset: chosen)
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.directoryURL = settings.readAloudFolderURL
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        settings.readAloudFolder = url.path.hasPrefix(home) ? "~" + url.path.dropFirst(home.count) : url.path
    }

    private func loadModels() async {
        do { try await voice.loadModels(); listProblem = nil }
        catch { listProblem = tr("could not load OpenRouter's speech models: %@", "\(error)") }
    }

    private static let nobody = "\u{0}nobody"

    /// Everyone on screen, by name, each once; a chosen one no longer there is kept in the list.
    private var onScreen: [String] {
        var all: [String] = []
        for i in 0..<settings.creatureCount {
            let name = settings.character(forCreature: i, library: library).name
            if !all.contains(name) { all.append(name) }
        }
        if !settings.readAloudHelper.isEmpty, !all.contains(settings.readAloudHelper) { all.append(settings.readAloudHelper) }
        return all
    }
}
