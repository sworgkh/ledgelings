import LedgelingsCore
import SwiftUI

/// Settings › Tools › Translate: the shortcuts and the languages on the left,
/// the model, the guessing and the clipboard on the right.
struct TranslateSettingsView: View {
    @ObservedObject var settings: AppSettings
    /// For the names of the creatures on screen, who could bring the sheet.
    let library: SpriteLibrary

    var body: some View {
        TwoColumns {
            Section {
                Toggle(tr("Translator"), isOn: $settings.translateEnabled)
                LabeledContent(tr("Type to translate")) {
                    HStack {
                        Toggle("", isOn: $settings.translateShortcutEnabled).labelsHidden()
                        ShortcutRecorder(settings: settings, shortcut: $settings.translateShortcut)
                    }
                }
                LabeledContent(tr("Translate the last copy")) {
                    HStack {
                        Toggle("", isOn: $settings.translateClipShortcutEnabled).labelsHidden()
                        ShortcutRecorder(settings: settings, shortcut: $settings.translateClipShortcut)
                    }
                }
                Picker(tr("The last copy"), selection: $settings.translateClipMode) {
                    ForEach(Translate.ClipMode.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                if !settings.translateShortcutProblem.isEmpty {
                    Text(settings.translateShortcutProblem).foregroundStyle(.red)
                }
            } header: {
                SettingsHeader("Translate")
            } footer: {
                Text(tr("Both work in every app. Type to translate opens the sheet: your words on the left, the translation on the right as you type. The last copy opens in the sheet already translated, or quietly replaces the clipboard with its translation and says so by the text cursor. ⏎ copies the translation, ⌘⏎ pastes it into the app you were in."))
            }

            Section {
                ForEach(Translate.languages) { language in
                    Toggle(language.title, isOn: languageBinding(language))
                        .disabled(on.contains(language) && on.count <= 2)
                }
                // Ids of their own: the switches above already use the languages' codes.
                ForEach(on.map { "into-" + $0.code }, id: \.self) { id in
                    let language = Translate.language(String(id.dropFirst(5)))!
                    Picker(tr("%@ goes into", language.title), selection: targetBinding(language)) {
                        ForEach(on.filter { $0 != language }) { Text($0.title).tag($0.code) }
                    }
                }
            } header: {
                SettingsHeader("Languages")
            } footer: {
                Text(tr("Told apart by their letters, Latin, Cyrillic or Hebrew, on this Mac and for free, before anything is sent. A text already in its target goes into the target's own language instead. At least two stay on."))
            }
        } right: {
            Section {
                TextField(tr("Model"), text: $settings.translateModel, prompt: Text(Translate.defaultModel))
                ModelBrowser(chosen: $settings.translateModel, height: 110)
                Toggle(tr("Guess the rest of the phrase"), isOn: $settings.translateAutocomplete)
                TextField(tr("Guess model"), text: $settings.translateAutocompleteModel, prompt: Text(tr("the same model")))
                    .disabled(!settings.translateAutocomplete)
                SliderRow(tr("Wait after typing"), value: Binding(get: { Double(settings.translateDelayMs) }, set: { settings.translateDelayMs = Int($0) }),
                          in: Double(Translate.delayRange.lowerBound)...Double(Translate.delayRange.upperBound), step: 50, unit: tr(" ms"))
            } header: {
                SettingsHeader("Model")
            } footer: {
                Text(tr("An OpenRouter model, with the key from Settings › Talk; with LM Studio as the brain and no key, its model, free. Cheap and fast is best: about a cent a day. Every call shows on Costs as Translation, every guess as Autocomplete. ⇥ takes the grey words."))
            }

            Section {
                Toggle(tr("Translate button in the clipboard picker"), isOn: $settings.translatePickerButton)
                Toggle(tr("Keep translations in the clipboard history"), isOn: $settings.translateKeepInHistory)
                SliderRow(tr("Ask before sending more than"), value: Binding(get: { Double(settings.translateLiveLimit) }, set: { settings.translateLiveLimit = Int($0) }),
                          in: Double(Translate.liveLimitRange.lowerBound)...Double(Translate.liveLimitRange.upperBound), step: 500, unit: "")
                Picker(tr("Who brings the sheet"), selection: Binding(
                    get: { settings.translateHelperEnabled ? settings.translateHelper : Self.nobody },
                    set: { who in
                        settings.translateHelperEnabled = who != Self.nobody
                        if who != Self.nobody { settings.translateHelper = who }
                    })) {
                    Text(tr("Whoever is nearest the middle")).tag("")
                    ForEach(names, id: \.self) { Text($0).tag($0) }
                    Text(tr("Nobody: it unfolds by itself")).tag(Self.nobody)
                }
            } header: {
                SettingsHeader("Clipboard and safety")
            } footer: {
                Text(tr("Text goes to the model only when you translate it. Protected snippets and copies of their words never do, and get no button. Links, e-mails, code and numbers are kept as they are. Longer texts wait for ⏎ and say their parts and price first; never more than 50 000 characters."))
            }
        }
    }

    private var on: [Translate.Language] { settings.translateLanguagesOn }

    private func languageBinding(_ language: Translate.Language) -> Binding<Bool> {
        Binding(get: { on.contains(language) }, set: { wanted in
            var codes = on.map(\.code)
            if wanted { codes.append(language.code) } else { codes.removeAll { $0 == language.code } }
            guard codes.count >= 2 else { return }
            settings.translateLanguages = Translate.on(codes).map(\.code)
        })
    }

    private func targetBinding(_ language: Translate.Language) -> Binding<String> {
        Binding(get: { Translate.target(for: language, targets: settings.translateTargets, on: on).code },
                set: { settings.translateTargets[language.code] = $0 })
    }

    private static let nobody = "\u{0}nobody"

    /// Everyone on screen, by name, each once; a chosen one no longer there is kept in the list.
    private var names: [String] {
        var all: [String] = []
        for i in 0..<settings.creatureCount {
            let name = settings.character(forCreature: i, library: library).name
            if !all.contains(name) { all.append(name) }
        }
        if !settings.translateHelper.isEmpty, !all.contains(settings.translateHelper) { all.append(settings.translateHelper) }
        return all
    }
}
