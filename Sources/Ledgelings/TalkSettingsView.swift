import AppKit
import LedgelingsCore
import SwiftUI
import UniformTypeIdentifiers

/// Everything about the creatures talking to each other, and which model does the talking.
struct TalkSettingsView: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject var library: SpriteLibrary
    @ObservedObject var spend: SpendLedger
    @State private var castSpecies = "blocky"

    var body: some View {
        Form {
            Section {
                Toggle("Creatures talk when they bump into each other", isOn: $settings.talkEnabled)
                SliderRow("Bubble stays", value: $settings.bubbleSeconds, in: AppSettings.bubbleRange, step: 1, unit: " s")
                SliderRow("Flower lasts", value: $settings.flowerMinutes, in: AppSettings.flowerRange, step: 0.5, unit: " min")
                Toggle("The one with the flower follows the giver while it lasts", isOn: $settings.followGiver)
            } footer: {
                Text("Two creatures meeting on the same edge trade a line and a reply. Every third meeting of a pair, one gives the other a flower, worn on the head until it wilts; with the box ticked, the wearer trails the giver around the edge until then. \"Make Someone Talk\" in the menu works at any time. Longer lines stay up a little longer; a click on a bubble closes it.")
            }

            Section {
                Picker("Brain", selection: $settings.brain) {
                    ForEach(AppSettings.Brain.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                switch settings.brain {
                case .script: ScriptFields(settings: settings, cast: castInUse)
                case .lmStudio: LMStudioFields(settings: settings)
                case .openRouter: OpenRouterFields(settings: settings)
                }
            } header: {
                Text("Brain")
            } footer: {
                Text(brainFooter)
            }

            if settings.brain != .script { SpendSection(spend: spend) }

            Section {
                Picker("Species", selection: $castSpecies) {
                    ForEach(library.species) { Text($0.name).tag($0.name) }
                }
                Text(library.kind(of: castSpecies)).font(.caption).foregroundStyle(.secondary)
                ForEach(cast.indices, id: \.self) { i in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            TextField("Name", text: member(i, \.name)).font(.headline)
                            Button(role: .destructive) { var c = cast; c.remove(at: i); setCast(c) } label: { Image(systemName: "minus.circle") }
                                .buttonStyle(.borderless).disabled(cast.count <= 1)
                        }
                        TextField("Who they are", text: member(i, \.persona), axis: .vertical).lineLimit(2...4)
                    }
                    .padding(.vertical, 2)
                }
                HStack {
                    Button("Add Character") { setCast(cast + [Character(name: "Newcomer", persona: "Describe the personality here.")]) }
                    Spacer()
                    Button("Reset Cast") { settings.casts.removeValue(forKey: castSpecies) }
                }
            } header: {
                Text("Characters")
            } footer: {
                Text("Every species has its own cast. The first creature wearing a species is its first character, the second its second, and so on, starting over when the cast runs out. The species itself is described to the model, so a frog talks like a frog.")
            }

            if settings.brain != .script { promptsSection }
        }
        .formStyle(.grouped)
    }

    private var promptsSection: some View {
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

    private var brainFooter: String {
        switch settings.brain {
        case .script:
            "No model, no server, no key: the creatures say these lines. One conversation per block, a blank line between blocks; the lines alternate between the one who bumped and the one bumped into. A block may start with [flower], [night], [day] or [night, flower] and is then kept for that moment. {speaker}, {listener} and {flower} are filled in; *asterisks* show as italics. \"Copy Agent Prompt\" puts a request on the clipboard that any chat model answers with more blocks in this format, ready to paste here."
        case .lmStudio:
            "LM Studio's local server, started with `lms server start` or from its Developer tab. The model must be one it has installed; \"Check\" lists them."
        case .openRouter:
            "OpenRouter runs on the internet and charges per word. Make a key at openrouter.ai/keys, ideally with a spending limit; it is kept in your keychain. \"Check\" confirms the key and lists models."
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
            .frame(height: 300)
            .scrollContentBackground(.hidden)
            .padding(4)
            .background(RoundedRectangle(cornerRadius: 6).fill(Color(nsColor: .textBackgroundColor)))
        LabeledContent("Status") {
            Text(notice ?? status).foregroundStyle(isBroken ? .red : .secondary).textSelection(.enabled)
        }
        HStack {
            Button("Import…") { importFile() }
            Button("Export…") { exportFile() }
            Button("Copy Agent Prompt") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(Script.agentPrompt(cast: cast), forType: .string)
                flash("the prompt is on the clipboard; paste it into any chat model and paste its answer here")
            }
            Spacer()
            Button("Reset Lines") { settings.resetScript() }
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
            return "\(c.count) conversations, \(flowers) with a flower, \(nights) at night"
        case .failure(let problem):
            return "\(problem); the creatures stay quiet until this is fixed"
        }
    }

    private func flash(_ text: String) {
        notice = text
        Task { try? await Task.sleep(for: .seconds(6)); if notice == text { notice = nil } }
    }

    private func importFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.plainText, .text]
        panel.message = "Choose a text file of conversations in the built-in format."
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let text = try String(contentsOf: url, encoding: .utf8)
            settings.script = text
            flash("imported \(url.lastPathComponent)")
        } catch {
            flash("could not read \(url.lastPathComponent): \(error.localizedDescription)")
        }
    }

    private func exportFile() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.plainText]
        panel.nameFieldStringValue = "ledgelings-lines.txt"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try settings.script.write(to: url, atomically: true, encoding: .utf8)
            flash("saved \(url.lastPathComponent)")
        } catch {
            flash("could not save: \(error.localizedDescription)")
        }
    }
}

/// Server, model, Check. The model must be one LM Studio has installed.
private struct LMStudioFields: View {
    @ObservedObject var settings: AppSettings
    @State private var check = "not checked"
    @State private var models: [String] = []

    var body: some View {
        TextField("Server", text: $settings.talkServer, prompt: Text(AppSettings.defaultTalkServer))
        HStack {
            TextField("Model", text: $settings.talkModel, prompt: Text(AppSettings.defaultTalkModel))
            ModelMenu(title: "Installed", models: models, typed: settings.talkModel) { settings.talkModel = $0 }
            Button("Check") { Task { await run() } }
        }
        LabeledContent("Status") { Text(check).foregroundStyle(.secondary).textSelection(.enabled) }
    }

    private func run() async {
        guard let client = settings.chatClient() else { check = settings.brainProblem; return }
        check = "checking…"
        do {
            let found = try await client.listModels()
            models = found
            check = found.contains(client.model)
                ? "ready: \(client.model) is installed"
                : "server is up, but \(client.model) is not installed. Pick one under \"Installed\"."
        } catch {
            models = []
            check = "\(error)"
        }
    }
}

/// Key, model, Check, and a live browser of everything OpenRouter offers.
private struct OpenRouterFields: View {
    @ObservedObject var settings: AppSettings
    @State private var check = "not checked"

    var body: some View {
        SecureField("API key", text: $settings.openRouterKey, prompt: Text("sk-or-…"))
        HStack {
            TextField("Model", text: $settings.openRouterModel, prompt: Text(AppSettings.defaultOpenRouterModel))
            Button("Check") { Task { await run() } }
        }
        LabeledContent("Status") { Text(check).foregroundStyle(.secondary).textSelection(.enabled) }
        ModelBrowser(chosen: $settings.openRouterModel)
    }

    private func run() async {
        guard let client = settings.chatClient() else { check = settings.brainProblem; return }
        check = "checking…"
        do {
            let key = try await client.describeKey()
            let models = try await client.listModels()
            check = models.contains(client.model)
                ? "ready: \(key); \(client.model) is available"
                : "\(key), but there is no model \(client.model). Search below and click one."
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
    @State private var status = "loading models…"

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                TextField("Search models", text: $query, prompt: Text("e.g. flash lite, gemma, free"))
                    .textFieldStyle(.roundedBorder)
                Button { Task { await load() } } label: { Image(systemName: "arrow.clockwise") }
                    .help("Fetch the list again")
            }
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(shown) { model in row(model) }
                    if hits.count > Self.most {
                        Text("\(hits.count - Self.most) more; add a word to narrow it down")
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
        status = "loading models…"
        do {
            let found = try await ChatClient.openRouterPublic.catalog()
            catalog = found
            status = "\(found.models.count) models on OpenRouter, cheapest first. Prices are dollars per million tokens."
        } catch {
            status = "could not load the list: \(error)"
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
                if shown.count == Self.most { Text("… type more to narrow the list") }
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

/// What the talking has cost: today, this month, ever, and the dearest models.
private struct SpendSection: View {
    @ObservedObject var spend: SpendLedger

    var body: some View {
        Section {
            let s = spend.summary
            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 4) {
                GridRow {
                    Text("")
                    Text("Cost").font(.caption).foregroundStyle(.secondary)
                    Text("Calls").font(.caption).foregroundStyle(.secondary)
                    Text("Tokens").font(.caption).foregroundStyle(.secondary)
                }
                row("Today", s.today)
                row("This month", s.month)
                row("All time", s.allTime)
            }
            ForEach(s.byModel.prefix(5), id: \.model) { m in
                LabeledContent(m.model) {
                    Text("\(Spend.label(m.total.cost)) · \(m.total.calls) calls").foregroundStyle(.secondary).monospacedDigit()
                }
                .font(.caption)
            }
            HStack {
                Text(spend.file.path).font(.caption).foregroundStyle(.tertiary).lineLimit(1).truncationMode(.middle)
                Spacer()
                Button("Reveal in Finder") { spend.revealInFinder() }
            }
        } header: {
            Text("Spend")
        } footer: {
            Text(footer(spend.summary))
        }
    }

    private func row(_ name: String, _ t: Spend.Total) -> some View {
        GridRow {
            Text(name)
            Text(Spend.label(t.cost) + (t.unpriced > 0 ? "+" : "")).monospacedDigit()
            Text("\(t.calls)").monospacedDigit()
            Text("\(t.tokens)").monospacedDigit()
        }
    }

    private func footer(_ s: Spend.Summary) -> String {
        var text = "Every call to the model is written to spend.jsonl with its tokens and, for OpenRouter, the price it reported. LM Studio is free. One conversation is two calls."
        if s.allTime.unpriced > 0 { text += " \(s.allTime.unpriced) calls had no price; a + marks a total that is missing some." }
        return text
    }
}
