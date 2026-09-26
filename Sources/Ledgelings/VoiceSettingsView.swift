import AVFoundation
import AppKit
import LedgelingsCore
import SwiftUI

/// Settings › Voice: how they all sound on the left, each character on the right.
struct VoiceSettingsView: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject var voice: Voice

    var body: some View {
        TwoColumns {
            VoiceSection(settings: settings, voice: voice)
        } right: {
            CharacterVoicesSection(settings: settings, voice: voice)
        }
    }
}

/// One card per character on screen: its own voice, speed and pitch, and a Test.
private struct CharacterVoicesSection: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject var voice: Voice
    @State private var names: [String] = []
    @State private var castingAll = false
    @State private var allNote: String?

    private func castEveryone() async {
        castingAll = true
        defer { castingAll = false }
        var done: [String] = []
        for name in names {
            allNote = "casting \(name)…"
            do { done.append("\(name): \(try await voice.castWithModel(name))") }
            catch { done.append("\(name): \(error)") }
        }
        allNote = done.joined(separator: "\n")
    }

    var body: some View {
        Section {
            if names.isEmpty { Text("Nobody on screen right now.").foregroundStyle(.secondary) }
            ForEach(names, id: \.self) { CharacterVoiceRow(name: $0, settings: settings, voice: voice) }
            HStack {
                Button(castingAll ? "Casting…" : "Cast Everyone with Model") { Task { await castEveryone() } }
                    .disabled(castingAll || settings.brain == .script || names.isEmpty)
                    .help(settings.brain == .script ? "Needs a model brain: LM Studio or OpenRouter, in Settings › Talk" : "")
                Spacer()
            }
            if let allNote { Text(allNote).font(.caption).foregroundStyle(.secondary) }
        } header: {
            Text("Characters")
        } footer: {
            Text("The characters on screen now. Each starts automatic: with \"Voices fit each character's personality\" on, their description and species choose the voice, pitch and speed (old and slow, tiny and quick, a robot, a ghost…); off, voices are only handed out to differ. \"Cast with Model\" asks the brain model instead, which understands any description, and keeps its choice as the character's own; it costs one call. A voice picked here is theirs alone; the automatic ones go round it. Speed and Pitch here multiply the overall sliders on the left; Speed follows pitch can be set for one character alone. \"Auto\" puts a character back to automatic. Settings follow the name, on every engine; an OpenRouter voice the chosen model does not have is ignored. With the Local server, \"Custom blend…\" mixes Kokoro voices, af_bella(2)+am_puck(1) being two parts Bella to one of Puck: endless voices from the 72, free. OpenRouter's Kokoro refuses blends.")
        }
        .onAppear {
            var seen: [String] = []
            for name in voice.cast() where !seen.contains(name) { seen.append(name) }
            names = seen
        }
    }
}

private struct CharacterVoiceRow: View {
    let name: String
    @ObservedObject var settings: AppSettings
    @ObservedObject var voice: Voice

    private var own: CharacterVoice { settings.characterVoices[name] ?? CharacterVoice() }
    @State private var casting = false
    @State private var castNote: String?

    private func cast() async {
        casting = true
        defer { casting = false }
        do { castNote = "cast: " + (try await voice.castWithModel(name)) }
        catch { castNote = "\(error)" }
    }

    /// "Custom blend…" was picked; the field shows even before anything is typed.
    @State private var blending = false
    static let custom = "\u{1}custom"

    /// The character's local voice is not one of the server's own: a blend, or a typed name.
    private var isBlend: Bool { own.localVoice.map { !voice.localVoices.contains($0) } ?? false }

    private var blend: Binding<String> {
        Binding(
            get: { own.localVoice ?? "" },
            set: { typed in
                let clean = typed.trimmingCharacters(in: .whitespaces)
                settings.setVoice(of: name) { $0.localVoice = clean.isEmpty ? nil : clean }
            }
        )
    }

    private var blendOK: Bool { own.localVoice.map { Voices.isUsable($0, among: voice.localVoices) } ?? true }

    private var blendNote: String {
        guard let typed = own.localVoice else {
            return "Voices joined with +, each with an optional weight: af_bella(2)+am_puck(1) is two parts Bella, one part Puck."
        }
        let unknown = Voices.blendParts(typed).filter { !voice.localVoices.contains($0) }
        if unknown.isEmpty || voice.localVoices.isEmpty { return "Blends \(Voices.blendParts(typed).joined(separator: ", ")). Test to hear it." }
        return "Not on the server: \(unknown.joined(separator: ", ")). Until fixed, this character uses its automatic voice."
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(name).font(.headline)
                Spacer()
                Button("Test") { voice.introduce(name) }
                Button(casting ? "Casting…" : "Cast with Model") { Task { await cast() } }
                    .disabled(casting || settings.brain == .script)
                    .help(settings.brain == .script ? "Needs a model brain: LM Studio or OpenRouter, in Settings › Talk" : "")
                Button("Auto") { settings.setVoice(of: name) { $0 = CharacterVoice() } }.disabled(own.isAutomatic)
            }
            if let castNote { Text(castNote).font(.caption).foregroundStyle(.secondary).textSelection(.enabled) }
            Picker("Voice", selection: voiceChoice) {
                Text("Automatic (\(voice.automaticVoice(for: name)))").tag("")
                switch settings.voiceEngine {
                case .system:
                    ForEach(Voice.systemVoices, id: \.identifier) { v in Text("\(v.name) · \(v.language)").tag(v.identifier) }
                case .openRouter:
                    if let mine = own.openRouterVoice, !voice.modelVoices.contains(mine) { Text("\(mine) (not in this model)").tag(mine) }
                    ForEach(voice.modelVoices, id: \.self) { Text($0).tag($0) }
                case .local:
                    Text("Custom blend…").tag(Self.custom)
                    ForEach(voice.localVoices, id: \.self) { Text($0).tag($0) }
                }
            }
            if settings.voiceEngine == .local && (blending || isBlend) {
                TextField("Blend", text: blend, prompt: Text("af_bella(2)+am_puck(1)"))
                    .font(.system(.body, design: .monospaced))
                Text(blendNote).font(.caption).foregroundStyle(blendOK ? Color.secondary : Color.red)
            }
            SliderRow("Speed", value: speed, in: AppSettings.voiceSpeedRange, step: 0.05, unit: "×")
            SliderRow("Pitch", value: pitch, in: AppSettings.voicePitchRange, step: 0.05, unit: "×")
            Picker("Speed follows pitch", selection: follow) {
                Text("As overall (\(settings.speedFollowsPitch ? "on" : "off"))").tag(0)
                Text("On: no echo").tag(1)
                Text("Off: exact pace").tag(2)
            }
        }
        .padding(.vertical, 4)
    }

    private var voiceChoice: Binding<String> {
        Binding(
            get: {
                switch settings.voiceEngine {
                case .system: own.systemVoice ?? ""
                case .openRouter: own.openRouterVoice ?? ""
                case .local: blending || isBlend ? Self.custom : own.localVoice ?? ""
                }
            },
            set: { picked in
                if picked == Self.custom {
                    blending = true
                    // Start from the voice it has now, so the blend begins as something heard.
                    if own.localVoice == nil { settings.setVoice(of: name) { $0.localVoice = voice.automaticVoice(for: name) } }
                    return
                }
                blending = false
                let value = picked.isEmpty ? nil : picked
                settings.setVoice(of: name) { v in
                    switch settings.voiceEngine {
                    case .system: v.systemVoice = value
                    case .openRouter: v.openRouterVoice = value
                    case .local: v.localVoice = value
                    }
                }
            }
        )
    }

    private var speed: Binding<Double> {
        Binding(get: { (voice.ownSpeed(for: name) * 100).rounded() / 100 }, set: { new in settings.setVoice(of: name) { $0.speed = new } })
    }

    /// 0 follows the overall setting, 1 on, 2 off.
    private var follow: Binding<Int> {
        Binding(
            get: { own.followPitch.map { $0 ? 1 : 2 } ?? 0 },
            set: { choice in settings.setVoice(of: name) { $0.followPitch = choice == 0 ? nil : choice == 1 } }
        )
    }

    /// Shows the automatic pitch until moved, so the slider starts where the voice is.
    private var pitch: Binding<Double> {
        Binding(get: { (voice.ownPitch(for: name) * 100).rounded() / 100 }, set: { new in settings.setVoice(of: name) { $0.pitch = new } })
    }
}

/// Voice on or off, which engine, which voice, how fast, how high, how loud,
/// and a Test that lets the cast introduce themselves.
struct VoiceSection: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject var voice: Voice
    @State private var listProblem: String?

    var body: some View {
        Section {
            Toggle("Hear them talk out loud", isOn: $settings.voiceEnabled)
            Picker("Voices", selection: $settings.voiceEngine) {
                ForEach(AppSettings.VoiceEngine.allCases, id: \.self) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            Toggle("Every character gets a voice of their own", isOn: $settings.voicePerCharacter)
            Toggle("Cartoon voices: squeakier, sillier", isOn: $settings.cartoonVoices)
            Toggle("Voices fit each character's personality", isOn: $settings.castByPersonality)
            switch settings.voiceEngine {
            case .system: systemFields
            case .openRouter: openRouterFields
            case .local: localFields
            }
            SliderRow("Speed", value: $settings.voiceSpeed, in: AppSettings.voiceSpeedRange, step: 0.05, unit: "×")
            SliderRow("Pitch", value: $settings.voicePitch, in: AppSettings.voicePitchRange, step: 0.05, unit: "×")
            Toggle("Speed follows pitch: no echo, higher talks a little faster", isOn: $settings.speedFollowsPitch)
            SliderRow("Pause before the answer", value: $settings.voiceTurnPause, in: AppSettings.voiceTurnPauseRange, step: 0.05, unit: " s")
            SliderRow("Volume", value: $settings.voiceVolume, in: 0...1, step: 0.05, unit: "")
            HStack {
                Button("Test") { voice.introduce() }
                Button("Stop") { voice.stop() }
                Spacer()
            }
            LabeledContent("Status") { Text(voice.status).foregroundStyle(.secondary).textSelection(.enabled) }
        } header: {
            Text("Voice")
        } footer: {
            Text(footer)
        }
    }

    @ViewBuilder private var systemFields: some View {
        Picker("Voice", selection: $settings.systemVoice) {
            Text("System default").tag("")
            ForEach(Voice.systemVoices, id: \.identifier) { v in
                Text(v.voiceTraits.contains(.isNoveltyVoice) ? "\(v.name) · \(v.language) · novelty" : "\(v.name) · \(v.language)").tag(v.identifier)
            }
        }
        .disabled(settings.voicePerCharacter)
    }

    @ViewBuilder private var openRouterFields: some View {
        if settings.brain != .openRouter {
            SecureField("API key", text: $settings.openRouterKey, prompt: Text("sk-or-…"))
        }
        Picker("Model", selection: $settings.voiceModel) {
            if !voice.models.contains(where: { $0.id == settings.voiceModel }) { Text(settings.voiceModel).tag(settings.voiceModel) }
            ForEach(voice.models) { m in Text("\(m.id) · \(m.priceLabel)").tag(m.id) }
        }
        .onChange(of: settings.voiceModel) { _, _ in settings.openRouterVoice = "" }
        Picker("Voice", selection: $settings.openRouterVoice) {
            Text("The model's first").tag("")
            if !settings.openRouterVoice.isEmpty && !modelVoices.contains(settings.openRouterVoice) {
                Text(settings.openRouterVoice).tag(settings.openRouterVoice)
            }
            ForEach(modelVoices, id: \.self) { Text($0).tag($0) }
        }
        .disabled(settings.voicePerCharacter)
        Toggle("Keep every line it says", isOn: $settings.keepVoices)
            .task { await load() }
        LabeledContent("Kept") {
            HStack {
                Text("\(voice.clips.count) lines").foregroundStyle(.secondary).monospacedDigit()
                Button("Reveal in Finder") { voice.revealArchive() }
            }
        }
        lineVoiceFields
        if let listProblem { Text(listProblem).font(.caption).foregroundStyle(.red) }
    }

    @State private var localCheck = "not checked"

    @ViewBuilder private var localFields: some View {
        TextField("Server", text: $settings.localVoiceServer, prompt: Text(AppSettings.defaultLocalVoiceServer))
        TextField("Model", text: $settings.localVoiceModel, prompt: Text(AppSettings.defaultLocalVoiceModel))
        Picker("Voice", selection: $settings.localVoice) {
            Text("The server's first").tag("")
            if !settings.localVoice.isEmpty && !voice.localVoices.contains(settings.localVoice) {
                Text(settings.localVoice).tag(settings.localVoice)
            }
            ForEach(voice.localVoices, id: \.self) { Text($0).tag($0) }
        }
        .disabled(settings.voicePerCharacter)
        HStack {
            Button("Check") { Task { await checkLocal() } }
            Button("Copy Setup Command") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(VoiceSection.kokoroSetup, forType: .string)
                localCheck = "copied; paste it into Terminal, wait for \"Uvicorn running\", then Check"
            }
            Spacer()
        }
        LabeledContent("Status") { Text(localCheck).foregroundStyle(.secondary).textSelection(.enabled) }
            .task { await checkLocal() }
        lineVoiceFields
    }

    /// The built-in lines, made once in each voice and played from disk after that.
    @ViewBuilder private var lineVoiceFields: some View {
        Toggle("Save the built-in lines' voices", isOn: $settings.reuseLineVoices)
        LabeledContent("Saved") {
            HStack {
                Text("\(voice.lineClips.count) lines").foregroundStyle(.secondary).monospacedDigit()
                Button("Reveal in Finder") { voice.revealLineArchive() }
                Button("Clear") { voice.clearLineArchive() }.disabled(voice.lineClips.isEmpty)
            }
        }
    }

    /// Kokoro-FastAPI on a Mac: fetch it once, then start it (on Apple's GPU).
    static let kokoroSetup = "[ -d ~/Kokoro-FastAPI ] || git clone https://github.com/remsky/Kokoro-FastAPI.git ~/Kokoro-FastAPI; cd ~/Kokoro-FastAPI && { [ -d .venv ] || uv venv; } && HOST=127.0.0.1 ./start-gpu_mac.sh"

    private func checkLocal() async {
        localCheck = "checking…"
        do {
            let found = try await voice.loadLocalVoices(again: true)
            localCheck = "ready: \(found.count) voices"
        } catch {
            localCheck = "\(error)"
        }
    }

    private var modelVoices: [String] { voice.models.first { $0.id == settings.voiceModel }?.voices ?? [] }

    private func load() async {
        do { try await voice.loadModels(); listProblem = nil }
        catch { listProblem = "could not load OpenRouter's speech models: \(error)" }
    }

    private var footer: String {
        let lines = "The built-in lines (and the Test lines) are saved once said, in the line-voices folder beside the chats, and played from there the next time the same words come in the same voice and speed, so each is made only once: no wait on the server, nothing paid again. Clear forgets them all; each is made again when next said. "
        let shared = "Out loud, each line of a conversation waits for the one before to be said, then follows after the pause set here, its sound fetched while the other was talking; the silent bubble timing is not used. Speed follows pitch: a higher voice also talks a little faster (by the square root of its lift: 1.18× at 1.4×), because a voice asked to talk slowly to make up for the lift smears into an echo. Off keeps the pace exact. Cartoon voices lifts every character's pitch by an amount of its own (1.15 to 1.6 times, on top of Pitch) and picks the playful voices first. Every bubble is read out, in order; when talk runs far ahead of the voice, lines are skipped rather than read late. \"Hear Them Talk\" in the menu turns it on and off."
        switch settings.voiceEngine {
        case .system:
            return "The Mac's own voices: free, offline, instant. More, and better ones, are in System Settings › Accessibility › Spoken Content › System Voice › Manage Voices. With a voice each and Cartoon voices on, they are the Mac's character voices (Grandma, Rocko, Shelley…) and talking novelty ones (Zarvox, Bubbles, Junior…), never the singing ones (Bells, Organ, Superstar…); off, the plain voices, each at a slightly different pitch. " + shared
        case .local:
            return "Any speech server on this Mac that answers like OpenAI's /v1/audio/speech and lists voices at /v1/audio/voices, such as Kokoro-FastAPI (port 8880, model \"kokoro\", the same voices as OpenRouter's Kokoro). Free, offline once set up, and nothing is priced. \"Copy Setup Command\" puts Kokoro-FastAPI's install-and-start line on the clipboard; it needs git and uv, and downloads about a gigabyte the first time. LM Studio cannot speak: its server has no speech endpoint. " + lines + shared
        case .openRouter:
            return "Speech models on OpenRouter sound far more alive, and cost a little per line: Kokoro is about $0.00003 a line. Uses the same key as the brain. What each line cost goes to the spend file a few seconds after it is said. Kept lines are WAV files in the voices folder beside the chats, listed in voices.jsonl with who said what; a line already kept in the same voice and speed is played from there, free. A voice each takes the model's English voices where it says which they are, and with Cartoon voices the playful ones among them (MiniMax's AnimeCharacter or PlayfulGirl, Voxtral's excited and cheerful). The pitch is shifted on this Mac as the clip plays, so it costs nothing extra. " + lines + shared
        }
    }
}
