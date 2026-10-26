import AppKit
import LedgelingsCore
import SwiftUI

/// Settings › Productivity tools › Dictation: the tool, its shortcut and the
/// microphone on the left; the model that listens, how it writes and who holds
/// the microphone on the right.
struct DictationSettingsView: View {
    @ObservedObject var settings: AppSettings
    let library: SpriteLibrary
    @State private var microphone = DictationRecorder.permission
    @State private var trusted = ClipPaster.trusted
    @State private var models: [Dictation.Model] = []
    @State private var modelsProblem = ""
    @State private var hasKey = true

    var body: some View {
        TwoColumns {
            Section {
                Toggle(tr("Dictation"), isOn: $settings.dictationEnabled)
                if !hasKey {
                    Text(tr("Uses the OpenRouter key from Settings › Talk, and none is in use there yet. Without one a creature only says so.")).foregroundStyle(.orange)
                }
                if microphone != .granted {
                    HStack {
                        Text(microphone == .refused ? tr("The microphone is not allowed. Allow… opens System Settings on its switch.")
                                                    : tr("Needs the microphone. macOS asks once; until then nothing is heard."))
                            .foregroundStyle(.orange)
                        Spacer()
                        Button(tr("Allow…")) {
                            Task { @MainActor in
                                await DictationRecorder.askForPermission()
                                microphone = DictationRecorder.permission
                            }
                        }
                    }
                } else {
                    LabeledContent(tr("Microphone")) { Text(DictationRecorder.microphoneName ?? tr("none found")) }
                }
            } header: {
                Text(tr("Dictation"))
            } footer: {
                Text(tr("Press the shortcut and speak; press it again (or ⏎) and the words land on the clipboard and in the clipboard history. ⎋ lets it go and sends nothing. The sound is kept in memory only and never saved."))
            }

            Section {
                LabeledContent(tr("Start and stop")) {
                    HStack {
                        Toggle("", isOn: $settings.dictationShortcutEnabled).labelsHidden()
                        ShortcutRecorder(settings: settings, shortcut: $settings.dictationShortcut)
                    }
                }
                Toggle(tr("Hold to talk"), isOn: $settings.dictationHoldToTalk)
                SliderRow(tr("Longest recording"), value: Binding(get: { Double(settings.dictationMaxSeconds) }, set: { settings.dictationMaxSeconds = Int($0) }),
                          in: Double(Dictation.maxSecondsRange.lowerBound)...Double(Dictation.maxSecondsRange.upperBound), step: 10, unit: tr(" s"))
                if !settings.dictationShortcutProblem.isEmpty {
                    Text(settings.dictationShortcutProblem).foregroundStyle(.red)
                }
            } header: {
                Text(tr("Shortcut"))
            } footer: {
                Text(tr("It works in every app. Holding to talk, it listens while the keys are down and writes it down when you let go. At the longest length it stops by itself and sends what it heard."))
            }
            .disabled(!settings.dictationEnabled)
        } right: {
            Section {
                Picker(tr("Model"), selection: $settings.dictationModel) {
                    ForEach(choices) { model in Text(verbatim: "\(model.name) — \(model.priceLabel)").tag(model.id) }
                }
                if !modelsProblem.isEmpty { Text(modelsProblem).foregroundStyle(.orange) }
                Picker(tr("Spoken in"), selection: $settings.dictationLanguage) {
                    ForEach(Dictation.Spoken.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                Toggle(tr("Tidy it up"), isOn: $settings.dictationCleanUp)
            } header: {
                Text(tr("Writing it down"))
            } footer: {
                Text(tr("OpenRouter's models that listen to sound, cheapest first; each recording is priced in Settings › Costs as Dictation. Tidying leaves out um and uh, stutters and false starts, and adds punctuation, in the same call."))
            }
            .disabled(!settings.dictationEnabled)

            Section {
                Toggle(tr("Paste into the app I was in"), isOn: $settings.dictationPaste)
                if settings.dictationPaste && !trusted {
                    HStack {
                        Text(tr("Needs Accessibility, to press ⌘V for you. Until then it only copies.")).foregroundStyle(.orange)
                        Spacer()
                        Button(tr("Allow…")) { ClipPaster.askForTrust() }
                    }
                }
                Picker(tr("Who holds the microphone"), selection: Binding(
                    get: { settings.dictationCreature ? settings.dictationHelper : Self.nobody },
                    set: { who in
                        settings.dictationCreature = who != Self.nobody
                        if who != Self.nobody { settings.dictationHelper = who }
                    })) {
                    Text(tr("Anyone free, by chance")).tag("")
                    ForEach(names, id: \.self) { Text($0).tag($0) }
                    Text(tr("Nobody: a note says how it went")).tag(Self.nobody)
                }
            } header: {
                Text(tr("The words and the creature"))
            } footer: {
                Text(tr("A creature leaps to the middle of the screen holding a microphone whose bars follow your voice, the clock over its head; it thinks while the words are written, says the first of them and hops home."))
            }
            .disabled(!settings.dictationEnabled)
        }
        .onAppear {
            microphone = DictationRecorder.permission
            trusted = ClipPaster.trusted
            // Asked only of someone using OpenRouter already, so the keychain is not touched for nothing.
            hasKey = settings.openRouterConnected
        }
        .task { await loadModels() }
    }

    /// The models that listen, with the chosen one always among them.
    private var choices: [Dictation.Model] {
        var all = models
        if !all.contains(where: { $0.id == settings.dictationModel }) {
            all.insert(Dictation.Model(id: settings.dictationModel, name: settings.dictationModel, audioPerToken: nil, completionPerToken: nil), at: 0)
        }
        return all
    }

    private func loadModels() async {
        do {
            models = try await DictationClient.listeningModels()
            modelsProblem = ""
        } catch {
            modelsProblem = tr("Could not load OpenRouter's models: %@", String(describing: error))
        }
    }

    /// The picker's tag for no creature at all: not a name anyone can have.
    private static let nobody = "\u{0}nobody"

    /// Everyone on screen, by name, each once; a chosen one no longer there is kept in the list.
    private var names: [String] {
        var all: [String] = []
        for i in 0..<settings.creatureCount {
            let name = settings.character(forCreature: i, library: library).name
            if !all.contains(name) { all.append(name) }
        }
        if !settings.dictationHelper.isEmpty, !all.contains(settings.dictationHelper) { all.append(settings.dictationHelper) }
        return all
    }
}
