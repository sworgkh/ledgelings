import AppKit
import LedgelingsCore
import SwiftUI
import UniformTypeIdentifiers

/// Everything about the creatures talking to each other, and which model does the talking.
struct TalkSettingsView: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject var library: SpriteLibrary
    @ObservedObject var voice: Voice
    @State private var castSpecies = "blocky"

    var body: some View {
        TwoColumns {
            Section {
                Toggle(tr("Creatures talk when they bump into each other"), isOn: $settings.talkEnabled)
                SliderRow(tr("Bubble stays"), value: $settings.bubbleSeconds, in: AppSettings.bubbleRange, step: 1, unit: tr(" s"))
                Stepper(value: $settings.lineMemory, in: AppSettings.lineMemoryRange) {
                    LabeledContent(tr("Not repeating their last"), value: settings.lineMemory == 0 ? tr("off") : trCount(settings.lineMemory, "line", "lines"))
                }
                Toggle(tr("Paper planes"), isOn: $settings.planesEnabled)
                SliderRow(tr("A paper plane every"), value: $settings.planeMinutes, in: AppSettings.planeRange, step: 0.5, unit: tr(" min"))
                    .disabled(!settings.planesEnabled)
            } footer: {
                Text(tr("Two creatures meeting on the same edge trade a line and a reply. Every third meeting of a pair, one gives the other a flower (the Flowers tab). Every so often one folds a note into a paper plane and throws it to another; its own wind swirls it across the screen, the catcher reads it out, thinks aloud about it and throws one answer back. \"Make Someone Talk\" and \"Send a Paper Plane\" in the menu work at any time. Longer lines stay up a little longer; a click on a bubble closes it. Each creature remembers its last lines and says something else until it has run through the rest; a model is shown them and asked for something new."))
            }

            Section {
                Picker(tr("Brain"), selection: $settings.brain) {
                    ForEach(AppSettings.Brain.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                switch settings.brain {
                case .script: ScriptFields(settings: settings, cast: castInUse)
                case .lmStudio: LMStudioFields(settings: settings)
                case .openRouter: OpenRouterFields(settings: settings)
                }
                if settings.brain != .script {
                    Stepper(value: $settings.lineTokens, in: AppSettings.lineTokensRange, step: 100) {
                        LabeledContent(tr("Room for each line"), value: trCount(settings.lineTokens, "token", "tokens"))
                    }
                }
            } header: {
                Text(tr("Brain"))
            } footer: {
                Text(brainFooter)
            }

        } right: {
            Section {
                Picker(tr("Species"), selection: $castSpecies) {
                    ForEach(library.species) { Text($0.name).tag($0.name) }
                }
                Text(Banter.spoken(library.kind(of: castSpecies))).font(.caption).foregroundStyle(.secondary)
                ForEach(cast.indices, id: \.self) { i in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            TextField(tr("Name"), text: member(i, \.name)).font(.headline)
                            Button(role: .destructive) { var c = cast; c.remove(at: i); setCast(c) } label: { Image(systemName: "minus.circle") }
                                .buttonStyle(.borderless).disabled(cast.count <= 1)
                        }
                        TextField(tr("Who they are"), text: member(i, \.persona), axis: .vertical).lineLimit(2...4)
                    }
                    .padding(.vertical, 2)
                }
                HStack {
                    Button(tr("Add Character")) { setCast(cast + [Character(name: "Newcomer", persona: "Describe the personality here.")]) }
                    Spacer()
                    Button(tr("Reset Cast")) { settings.casts.removeValue(forKey: castSpecies) }
                }
            } header: {
                Text(tr("Characters"))
            } footer: {
                Text(tr("Every species has its own cast. The first creature wearing a species is its first character, the second its second, and so on, starting over when the cast runs out. The species itself is described to the model, so a frog talks like a frog."))
            }

            if settings.brain != .script { promptsSection }
        }
    }

    private var promptsSection: some View {
            Section {
                prompt(tr("Who is speaking (system prompt)"), text: $settings.systemPrompt)
                prompt(tr("Opening line"), text: $settings.linePrompt)
                prompt(tr("Reply"), text: $settings.replyPrompt)
                HStack { Spacer(); Button(tr("Reset Prompts")) { settings.resetPrompts() } }
            } header: {
                Text(tr("Prompts"))
            } footer: {
                Text(tr("Placeholders: %@. {situation} is written by the app: your time, date and holidays (Calendar tab), the colony's day or night, and where each creature is. {line} is what was just said, for the reply. {relationship} is how the two get on and the story between them (Bonds tab); left out, it goes at the end of the prompt.", Banter.placeholders.map { "{\($0)}" }.joined(separator: " ")))
            }
    }

    private var brainFooter: String {
        switch settings.brain {
        case .script:
            tr("No model, no server, no key: the creatures say these lines. The format is explained at the top of the text. \"Copy Agent Prompt\" puts a request on the clipboard that any chat model answers with more blocks in this format, ready to paste here.")
        case .lmStudio:
            tr("LM Studio's local server, started with `lms server start` or from its Developer tab. The model must be one it has installed; \"Check\" lists them. \"Room for each line\": tokens per line, thinking included; too few and a thinking model stops mid-sentence.")
        case .openRouter:
            tr("OpenRouter runs on the internet and charges per word. Make a key at openrouter.ai/keys, ideally with a spending limit; it is kept in your keychain. \"Check\" confirms the key and lists models. \"Room for each line\": tokens per line, thinking included; too few and a thinking model stops mid-sentence.")
        }
    }

    /// Everyone who could be talking right now, for the agent prompt.
    private var castInUse: [Character] {
        var seen: [Character] = []
        for species in Set(settings.species) {
            for member in settings.cast(of: species, fallback: library.cast(of: species)) where !seen.contains(member) { seen.append(member) }
        }
        return seen
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

    private var cast: [Character] { settings.cast(of: castSpecies, fallback: library.cast(of: castSpecies)) }

    private func setCast(_ new: [Character]) { settings.casts[castSpecies] = new }

    private func member(_ i: Int, _ path: WritableKeyPath<Character, String>) -> Binding<String> {
        Binding(
            get: { cast.indices.contains(i) ? cast[i][keyPath: path] : "" },
            set: { value in var c = cast; guard c.indices.contains(i) else { return }; c[i][keyPath: path] = value; setCast(c) }
        )
    }

}

/// The script itself, what is wrong with it if anything, and the ways to get more of it.
private struct ScriptFields: View {
    @ObservedObject var settings: AppSettings
    let cast: [Character]
    @State private var notice: String?

    var body: some View {
        TextEditor(text: $settings.script)
            .font(.system(.body, design: .monospaced))
            .frame(height: 210)
            .scrollContentBackground(.hidden)
            .padding(4)
            .background(RoundedRectangle(cornerRadius: 6).fill(Color(nsColor: .textBackgroundColor)))
        LabeledContent(tr("Status")) {
            Text(notice ?? status).foregroundStyle(isBroken ? .red : .secondary).textSelection(.enabled)
        }
        HStack {
            Button(tr("Import…")) { importFile() }
            Button(tr("Export…")) { exportFile() }
            Button(tr("Copy Agent Prompt")) {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(Script.agentPrompt(cast: cast), forType: .string)
                flash(tr("the prompt is on the clipboard; paste it into any chat model and paste its answer here"))
            }
            Spacer()
            Button(tr("Reset Lines")) { settings.resetScript() }
        }
    }

    private var parsed: Result<Script, Script.ParseError> {
        Result { try Script.parse(settings.script) }.mapError { $0 as! Script.ParseError }
    }

    private var isBroken: Bool { if case .failure = parsed { true } else { false } }

    private var status: String {
        switch parsed {
        case .success(let script):
            let c = script.conversations
            let flowers = c.filter { $0.tags.contains("flower") }.count, nights = c.filter { $0.tags.contains("night") }.count
            return tr("%d conversations, %d with a flower, %d at night", c.count, flowers, nights)
        case .failure(let problem):
            return tr("%@; the creatures stay quiet until this is fixed", "\(problem)")
        }
    }

    private func flash(_ text: String) {
        notice = text
        Task { try? await Task.sleep(for: .seconds(6)); if notice == text { notice = nil } }
    }

    private func importFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.plainText, .text]
        panel.message = tr("Choose a text file of conversations in the built-in format.")
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let text = try String(contentsOf: url, encoding: .utf8)
            settings.script = text
            flash(tr("imported %@", url.lastPathComponent))
        } catch {
            flash(tr("could not read %@: %@", url.lastPathComponent, error.localizedDescription))
        }
    }

    private func exportFile() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.plainText]
        panel.nameFieldStringValue = "ledgelings-lines.txt"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try settings.script.write(to: url, atomically: true, encoding: .utf8)
            flash(tr("saved %@", url.lastPathComponent))
        } catch {
            flash(tr("could not save: %@", error.localizedDescription))
        }
    }
}

/// Server, model, Check. The model must be one LM Studio has installed.
private struct LMStudioFields: View {
    @ObservedObject var settings: AppSettings
    @State private var check = tr("not checked")
    @State private var models: [String] = []

    var body: some View {
        TextField(tr("Server"), text: $settings.talkServer, prompt: Text(AppSettings.defaultTalkServer))
        HStack {
            TextField(tr("Model"), text: $settings.talkModel, prompt: Text(AppSettings.defaultTalkModel))
            ModelMenu(title: tr("Installed"), models: models, typed: settings.talkModel) { settings.talkModel = $0 }
            Button(tr("Check")) { Task { await run() } }
        }
        LabeledContent(tr("Status")) { Text(check).foregroundStyle(.secondary).textSelection(.enabled) }
    }

    private func run() async {
        guard let client = settings.chatClient() else { check = settings.brainProblem; return }
        check = tr("checking…")
        do {
            let found = try await client.listModels()
            models = found
            check = found.contains(client.model)
                ? tr("ready: %@ is installed", client.model)
                : tr("server is up, but %@ is not installed. Pick one under \"Installed\".", client.model)
        } catch {
            models = []
            check = "\(error)"
        }
    }
}

/// Key, model, Check, and a live browser of everything OpenRouter offers.
private struct OpenRouterFields: View {
    @ObservedObject var settings: AppSettings
    @State private var check = tr("not checked")

    var body: some View {
        SecureField(tr("API key"), text: $settings.openRouterKey, prompt: Text(verbatim: "sk-or-…"))
        HStack {
            TextField(tr("Model"), text: $settings.openRouterModel, prompt: Text(AppSettings.defaultOpenRouterModel))
            Button(tr("Check")) { Task { await run() } }
        }
        LabeledContent(tr("Status")) { Text(check).foregroundStyle(.secondary).textSelection(.enabled) }
        ModelBrowser(chosen: $settings.openRouterModel)
    }

    private func run() async {
        guard let client = settings.chatClient() else { check = settings.brainProblem; return }
        check = tr("checking…")
        do {
            let key = try await client.describeKey()
            let models = try await client.listModels()
            check = models.contains(client.model)
                ? tr("ready: %@; %@ is available", key, client.model)
                : tr("%@, but there is no model %@. Search below and click one.", key, client.model)
        } catch {
            check = "\(error)"
        }
    }
}

/// OpenRouter's whole model list, fetched from its API when this appears, searched
/// by any words from the id or name, cheapest first. A click picks the model.
private struct ModelBrowser: View {
    static let most = 60
    @Binding var chosen: String
    @State private var query = ""
    @State private var catalog: ModelCatalog?
    @State private var status = tr("loading models…")

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                TextField(tr("Search models"), text: $query, prompt: Text(tr("e.g. flash lite, gemma, free")))
                    .textFieldStyle(.roundedBorder)
                Button { Task { await load() } } label: { Image(systemName: "arrow.clockwise") }
                    .help(tr("Fetch the list again"))
            }
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(shown) { model in row(model) }
                    if hits.count > Self.most {
                        Text(tr("%d more; add a word to narrow it down", hits.count - Self.most))
                            .font(.caption).foregroundStyle(.secondary).padding(6)
                    }
                }
            }
            .frame(height: 220)
            .background(RoundedRectangle(cornerRadius: 6).fill(Color(nsColor: .textBackgroundColor)))
            Text(status).font(.caption).foregroundStyle(.secondary)
        }
        .task { await load() }
    }

    private var hits: [ModelCatalog.Model] { catalog?.search(query) ?? [] }
    private var shown: ArraySlice<ModelCatalog.Model> { hits.prefix(Self.most) }

    private func row(_ model: ModelCatalog.Model) -> some View {
        Button { chosen = model.id } label: {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(model.id).font(.system(.body, design: .monospaced))
                    if model.name != model.id { Text(model.name).font(.caption).foregroundStyle(.secondary) }
                }
                Spacer()
                Text(model.priceLabel).font(.caption).monospacedDigit().foregroundStyle(model.isFree ? .green : .secondary)
            }
            .padding(.horizontal, 8).padding(.vertical, 4)
            .contentShape(Rectangle())
            .background(model.id == chosen ? Color.accentColor.opacity(0.18) : .clear)
        }
        .buttonStyle(.plain)
    }

    private func load() async {
        status = tr("loading models…")
        do {
            let found = try await ChatClient.openRouterPublic.catalog()
            catalog = found
            status = tr("%d models on OpenRouter, cheapest first. Prices are dollars per million tokens.", found.models.count)
        } catch {
            status = tr("could not load the list: %@", "\(error)")
        }
    }
}

/// A menu of model ids, narrowed to those containing what is typed so far, because
/// OpenRouter lists hundreds. Hidden until a Check has fetched the list.
private struct ModelMenu: View {
    static let most = 40
    let title: String
    let models: [String]
    let typed: String
    let pick: (String) -> Void

    var body: some View {
        if !models.isEmpty {
            Menu(title) {
                ForEach(shown, id: \.self) { id in Button(id) { pick(id) } }
                if shown.count == Self.most { Text(tr("… type more to narrow the list")) }
            }
            .fixedSize()
        }
    }

    private var shown: [String] {
        let needle = typed.trimmingCharacters(in: .whitespaces).lowercased()
        let matching = needle.isEmpty || models.contains(typed) ? models : models.filter { $0.lowercased().contains(needle) }
        return Array(matching.prefix(Self.most))
    }
}
