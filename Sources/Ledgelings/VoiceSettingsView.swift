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

    var body: some View {
        Section {
            if names.isEmpty { Text("Nobody on screen right now.").foregroundStyle(.secondary) }
            ForEach(names, id: \.self) { CharacterVoiceRow(name: $0, settings: settings, voice: voice) }
        } header: {
            Text("Characters")
        } footer: {
            Text("The characters on screen now. Each starts automatic: a voice handed out for them, the overall speed, and a pitch of their own (the cartoon lift with Cartoon voices on). A voice picked here is theirs alone; the automatic ones go round it. Speed and Pitch here multiply the overall sliders on the left; Speed follows pitch can be set for one character alone. \"Auto\" puts a character back to automatic. Settings follow the name, on both engines; an OpenRouter voice the chosen model does not have is ignored.")
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

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(name).font(.headline)
                Spacer()
                Button("Test") { voice.introduce(name) }
                Button("Auto") { settings.setVoice(of: name) { $0 = CharacterVoice() } }.disabled(own.isAutomatic)
            }
            Picker("Voice", selection: voiceChoice) {
                Text("Automatic (\(voice.automaticVoice(for: name)))").tag("")
                switch settings.voiceEngine {
                case .system:
                    ForEach(Voice.systemVoices, id: \.identifier) { v in Text("\(v.name) · \(v.language)").tag(v.identifier) }
                case .openRouter:
                    if let mine = own.openRouterVoice, !voice.modelVoices.contains(mine) { Text("\(mine) (not in this model)").tag(mine) }
                    ForEach(voice.modelVoices, id: \.self) { Text($0).tag($0) }
                case .local:
                    if let mine = own.localVoice, !voice.localVoices.contains(mine) { Text("\(mine) (not on the server)").tag(mine) }
                    ForEach(voice.localVoices, id: \.self) { Text($0).tag($0) }
                }
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
                case .local: own.localVoice ?? ""
                }
            },
            set: { picked in
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
        Binding(get: { own.speed ?? 1 }, set: { new in settings.setVoice(of: name) { $0.speed = new } })
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
            switch settings.voiceEngine {
            case .system: systemFields
            case .openRouter: openRouterFields
            case .local: localFields
            }
            SliderRow("Speed", value: $settings.voiceSpeed, in: AppSettings.voiceSpeedRange, step: 0.05, unit: "×")
            SliderRow("Pitch", value: $settings.voicePitch, in: AppSettings.voicePitchRange, step: 0.05, unit: "×")
            Toggle("Speed follows pitch: no echo, higher talks a little faster", isOn: $settings.speedFollowsPitch)
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
        let shared = "Speed follows pitch: a higher voice also talks a little faster (by the square root of its lift: 1.18× at 1.4×), because a voice asked to talk slowly to make up for the lift smears into an echo. Off keeps the pace exact. Cartoon voices lifts every character's pitch by an amount of its own (1.15 to 1.6 times, on top of Pitch) and picks the playful voices first. Every bubble is read out, in order; when talk runs far ahead of the voice, lines are skipped rather than read late. \"Hear Them Talk\" in the menu turns it on and off."
        switch settings.voiceEngine {
        case .system:
            return "The Mac's own voices: free, offline, instant. More, and better ones, are in System Settings › Accessibility › Spoken Content › System Voice › Manage Voices. With a voice each and Cartoon voices on, they are the Mac's character voices (Grandma, Rocko, Shelley…) and talking novelty ones (Zarvox, Bubbles, Junior…), never the singing ones (Bells, Organ, Superstar…); off, the plain voices, each at a slightly different pitch. " + shared
        case .local:
            return "Any speech server on this Mac that answers like OpenAI's /v1/audio/speech and lists voices at /v1/audio/voices, such as Kokoro-FastAPI (port 8880, model \"kokoro\", the same voices as OpenRouter's Kokoro). Free, offline once set up, and nothing is kept or priced. \"Copy Setup Command\" puts Kokoro-FastAPI's install-and-start line on the clipboard; it needs git and uv, and downloads about a gigabyte the first time. LM Studio cannot speak: its server has no speech endpoint. " + shared
        case .openRouter:
            return "Speech models on OpenRouter sound far more alive, and cost a little per line: Kokoro is about $0.00003 a line. Uses the same key as the brain. What each line cost goes to the spend file a few seconds after it is said. Kept lines are WAV files in the voices folder beside the chats, listed in voices.jsonl with who said what; a line already kept in the same voice and speed is played from there, free. A voice each takes the model's English voices where it says which they are, and with Cartoon voices the playful ones among them (MiniMax's AnimeCharacter or PlayfulGirl, Voxtral's excited and cheerful). The pitch is shifted on this Mac as the clip plays, so it costs nothing extra. " + shared
        }
    }
}
