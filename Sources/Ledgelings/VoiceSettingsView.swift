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
            allNote = tr("casting %@…", name)
            do { done.append("\(name): \(try await voice.castWithModel(name))") }
            catch { done.append("\(name): \(error)") }
        }
        allNote = done.joined(separator: "\n")
    }

    var body: some View {
        Section {
            if names.isEmpty { Text(tr("Nobody on screen right now.")).foregroundStyle(.secondary) }
            ForEach(names, id: \.self) { CharacterVoiceRow(name: $0, settings: settings, voice: voice) }
            HStack {
                Button(castingAll ? tr("Casting…") : tr("Cast Everyone with Model")) { Task { await castEveryone() } }
                    .disabled(castingAll || !settings.hasModel || names.isEmpty)
                Spacer()
            }
            // Said once for every greyed Cast button, not hidden in a tooltip.
            if !settings.hasModel { NeedsModelNote() }
            if let allNote { Text(allNote).font(.caption).foregroundStyle(.secondary) }
        } header: {
            Text(tr("Characters"))
        } footer: {
            Text(tr("The characters on screen now. Each starts automatic: with \"Voices fit each character's personality\" on, their description and species choose the voice, pitch and speed (old and slow, tiny and quick, a robot, a ghost…); off, voices are only handed out to differ. \"Cast with Model\" asks the brain model instead, which understands any description, and keeps its choice as the character's own; it costs one call. A voice picked here is theirs alone; the automatic ones go round it. Speed and Pitch here multiply the overall sliders on the left; Speed follows pitch can be set for one character alone. \"Auto\" puts a character back to automatic. Settings follow the name, on every engine; an OpenRouter voice the chosen model does not have is ignored. With the Local server, \"Custom blend…\" mixes Kokoro voices, af_bella(2)+am_puck(1) being two parts Bella to one of Puck: endless voices from the 72, free. OpenRouter's Kokoro refuses blends."))
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
        do { let picked = try await voice.castWithModel(name); castNote = tr("cast: %@", picked) }
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
            return tr("Voices joined with +, each with an optional weight: af_bella(2)+am_puck(1) is two parts Bella, one part Puck.")
        }
        let unknown = Voices.blendParts(typed).filter { !voice.localVoices.contains($0) }
        if unknown.isEmpty || voice.localVoices.isEmpty { return tr("Blends %@. Test to hear it.", Voices.blendParts(typed).joined(separator: ", ")) }
        return tr("Not on the server: %@. Until fixed, this character uses its automatic voice.", unknown.joined(separator: ", "))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(name).font(.headline)
                Spacer()
                Button(tr("Test")) { voice.introduce(name) }
                Button(casting ? tr("Casting…") : tr("Cast with Model")) { Task { await cast() } }
                    .disabled(casting || !settings.hasModel)
                Button(tr("Auto")) { settings.setVoice(of: name) { $0 = CharacterVoice() } }.disabled(own.isAutomatic)
            }
            if let castNote { Text(castNote).font(.caption).foregroundStyle(.secondary).textSelection(.enabled) }
            Picker(tr("Voice"), selection: voiceChoice) {
                Text(tr("Automatic (%@)", voice.automaticVoice(for: name))).tag("")
                switch settings.voiceEngine {
                case .system:
                    ForEach(Voice.systemVoices, id: \.identifier) { v in Text(verbatim: "\(v.name) · \(v.language)").tag(v.identifier) }
                case .openRouter:
                    if let mine = own.openRouterVoice, !voice.modelVoices.contains(mine) { Text(tr("%@ (not in this model)", mine)).tag(mine) }
                    ForEach(voice.modelVoices, id: \.self) { Text($0).tag($0) }
                case .local:
                    Text(tr("Custom blend…")).tag(Self.custom)
                    ForEach(voice.localVoices, id: \.self) { Text($0).tag($0) }
                }
            }
            if settings.voiceEngine == .local && (blending || isBlend) {
                TextField(tr("Blend"), text: blend, prompt: Text(verbatim: "af_bella(2)+am_puck(1)"))
                    .font(.system(.body, design: .monospaced))
                Text(blendNote).font(.caption).foregroundStyle(blendOK ? Color.secondary : Color.red)
            }
            SliderRow(tr("Speed"), value: speed, in: AppSettings.voiceSpeedRange, step: 0.05, unit: "×")
            SliderRow(tr("Pitch"), value: pitch, in: AppSettings.voicePitchRange, step: 0.05, unit: "×")
            Picker(tr("Speed follows pitch"), selection: follow) {
                Text(tr("As overall (%@)", settings.speedFollowsPitch ? tr("on") : tr("off"))).tag(0)
                Text(tr("On: no echo")).tag(1)
                Text(tr("Off: exact pace")).tag(2)
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
            Toggle(tr("Hear them talk out loud"), isOn: $settings.voiceEnabled)
            Picker(tr("Voices"), selection: $settings.voiceEngine) {
                ForEach(AppSettings.VoiceEngine.allCases, id: \.self) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            Toggle(tr("Every character gets a voice of their own"), isOn: $settings.voicePerCharacter)
            Toggle(tr("Cartoon voices: squeakier, sillier"), isOn: $settings.cartoonVoices)
            Toggle(tr("Voices fit each character's personality"), isOn: $settings.castByPersonality)
            switch settings.voiceEngine {
            case .system: systemFields
            case .openRouter: openRouterFields
            case .local: localFields
            }
            SliderRow(tr("Speed"), value: $settings.voiceSpeed, in: AppSettings.voiceSpeedRange, step: 0.05, unit: "×")
            SliderRow(tr("Pitch"), value: $settings.voicePitch, in: AppSettings.voicePitchRange, step: 0.05, unit: "×")
            Toggle(tr("Speed follows pitch: no echo, higher talks a little faster"), isOn: $settings.speedFollowsPitch)
            SliderRow(tr("Pause before the answer"), value: $settings.voiceTurnPause, in: AppSettings.voiceTurnPauseRange, step: 0.05, unit: tr(" s"))
            SliderRow(tr("Volume"), value: $settings.voiceVolume, in: 0...1, step: 0.05, unit: "")
            HStack {
                Button(tr("Test")) { voice.introduce() }
                Button(tr("Stop")) { voice.stop() }
                Spacer()
            }
            LabeledContent(tr("Status")) { Text(voice.status).foregroundStyle(.secondary).textSelection(.enabled) }
        } header: {
            Text(tr("Voice"))
        } footer: {
            Text(footer)
        }
    }

    @ViewBuilder private var systemFields: some View {
        Picker(tr("Voice"), selection: $settings.systemVoice) {
            Text(tr("System default")).tag("")
            ForEach(Voice.systemVoices, id: \.identifier) { v in
                Text(verbatim: v.voiceTraits.contains(.isNoveltyVoice) ? tr("%@ · %@ · novelty", v.name, v.language) : "\(v.name) · \(v.language)").tag(v.identifier)
            }
        }
        .disabled(settings.voicePerCharacter)
    }

    @ViewBuilder private var openRouterFields: some View {
        if settings.brain != .openRouter {
            SecureField(tr("API key"), text: $settings.openRouterKey, prompt: Text(verbatim: "sk-or-…"))
        }
        Picker(tr("Model"), selection: $settings.voiceModel) {
            if !voice.models.contains(where: { $0.id == settings.voiceModel }) { Text(settings.voiceModel).tag(settings.voiceModel) }
            ForEach(voice.models) { m in Text(verbatim: "\(m.id) · \(m.priceLabel)").tag(m.id) }
        }
        .onChange(of: settings.voiceModel) { _, _ in settings.openRouterVoice = "" }
        Picker(tr("Voice"), selection: $settings.openRouterVoice) {
            Text(tr("The model's first")).tag("")
            if !settings.openRouterVoice.isEmpty && !modelVoices.contains(settings.openRouterVoice) {
                Text(settings.openRouterVoice).tag(settings.openRouterVoice)
            }
            ForEach(modelVoices, id: \.self) { Text($0).tag($0) }
        }
        .disabled(settings.voicePerCharacter)
        Toggle(tr("Keep every line it says"), isOn: $settings.keepVoices)
            .task { await load() }
        LabeledContent(tr("Kept")) {
            HStack {
                Text(trCount(voice.clips.count, "line", "lines")).foregroundStyle(.secondary).monospacedDigit()
                Button(tr("Reveal in Finder")) { voice.revealArchive() }
            }
        }
        lineVoiceFields
        if let listProblem { Text(listProblem).font(.caption).foregroundStyle(.red) }
    }

    @State private var localCheck = tr("not checked")

    @ViewBuilder private var localFields: some View {
        TextField(tr("Server"), text: $settings.localVoiceServer, prompt: Text(AppSettings.defaultLocalVoiceServer))
        TextField(tr("Model"), text: $settings.localVoiceModel, prompt: Text(AppSettings.defaultLocalVoiceModel))
        Picker(tr("Voice"), selection: $settings.localVoice) {
            Text(tr("The server's first")).tag("")
            if !settings.localVoice.isEmpty && !voice.localVoices.contains(settings.localVoice) {
                Text(settings.localVoice).tag(settings.localVoice)
            }
            ForEach(voice.localVoices, id: \.self) { Text($0).tag($0) }
        }
        .disabled(settings.voicePerCharacter)
        HStack {
            Button(tr("Check")) { Task { await checkLocal() } }
            Button(tr("Copy Setup Command")) {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(VoiceSection.kokoroSetup, forType: .string)
                localCheck = tr("copied; paste it into Terminal, wait for \"Uvicorn running\", then Check")
            }
            Spacer()
        }
        LabeledContent(tr("Status")) { Text(localCheck).foregroundStyle(.secondary).textSelection(.enabled) }
            .task { await checkLocal() }
        lineVoiceFields
    }

    /// The built-in lines, made once in each voice and played from disk after that.
    @ViewBuilder private var lineVoiceFields: some View {
        Toggle(tr("Save the built-in lines' voices"), isOn: $settings.reuseLineVoices)
        LabeledContent(tr("Saved")) {
            HStack {
                Text(trCount(voice.lineClips.count, "line", "lines")).foregroundStyle(.secondary).monospacedDigit()
                Button(tr("Reveal in Finder")) { voice.revealLineArchive() }
                Button(tr("Clear")) { voice.clearLineArchive() }.disabled(voice.lineClips.isEmpty)
            }
        }
    }

    /// Kokoro-FastAPI on a Mac: fetch it once, then start it (on Apple's GPU).
    static let kokoroSetup = "[ -d ~/Kokoro-FastAPI ] || git clone https://github.com/remsky/Kokoro-FastAPI.git ~/Kokoro-FastAPI; cd ~/Kokoro-FastAPI && { [ -d .venv ] || uv venv; } && HOST=127.0.0.1 ./start-gpu_mac.sh"

    private func checkLocal() async {
        localCheck = tr("checking…")
        do {
            let found = try await voice.loadLocalVoices(again: true)
            localCheck = tr("ready: %@", trCount(found.count, "voice", "voices"))
        } catch {
            localCheck = "\(error)"
        }
    }

    private var modelVoices: [String] { voice.models.first { $0.id == settings.voiceModel }?.voices ?? [] }

    private func load() async {
        do { try await voice.loadModels(); listProblem = nil }
        catch { listProblem = tr("could not load OpenRouter's speech models: %@", "\(error)") }
    }

    private var footer: String {
        let lines = tr("The built-in lines (and the Test lines) are saved once said, in the line-voices folder beside the chats, and played from there the next time the same words come in the same voice and speed, so each is made only once: no wait on the server, nothing paid again. Clear forgets them all; each is made again when next said.") + " "
        let shared = tr("Out loud, each line of a conversation waits for the one before to be said, then follows after the pause set here, its sound fetched while the other was talking; the silent bubble timing is not used. Speed follows pitch: a higher voice also talks a little faster (by the square root of its lift: 1.18× at 1.4×), because a voice asked to talk slowly to make up for the lift smears into an echo. Off keeps the pace exact. Cartoon voices lifts every character's pitch by an amount of its own (1.15 to 1.6 times, on top of Pitch) and picks the playful voices first. Every bubble is read out, in order; when talk runs far ahead of the voice, lines are skipped rather than read late. \"Hear Them Talk\" in the menu turns it on and off.")
        switch settings.voiceEngine {
        case .system:
            return tr("The Mac's own voices: free, offline, instant. More, and better ones, are in System Settings › Accessibility › Spoken Content › System Voice › Manage Voices. With a voice each and Cartoon voices on, they are the Mac's character voices (Grandma, Rocko, Shelley…) and talking novelty ones (Zarvox, Bubbles, Junior…), never the singing ones (Bells, Organ, Superstar…); off, the plain voices, each at a slightly different pitch.") + " " + shared
        case .local:
            return tr("Any speech server on this Mac that answers like OpenAI's /v1/audio/speech and lists voices at /v1/audio/voices, such as Kokoro-FastAPI (port 8880, model \"kokoro\", the same voices as OpenRouter's Kokoro). Free, offline once set up, and nothing is priced. \"Copy Setup Command\" puts Kokoro-FastAPI's install-and-start line on the clipboard; it needs git and uv, and downloads about a gigabyte the first time. LM Studio cannot speak: its server has no speech endpoint.") + " " + lines + shared
        case .openRouter:
            return tr("Speech models on OpenRouter sound far more alive, and cost a little per line: Kokoro is about $0.00003 a line. Uses the same key as the brain. What each line cost goes to the spend file a few seconds after it is said. Kept lines are WAV files in the voices folder beside the chats, listed in voices.jsonl with who said what; a line already kept in the same voice and speed is played from there, free. A voice each takes the model's English voices where it says which they are, and with Cartoon voices the playful ones among them (MiniMax's AnimeCharacter or PlayfulGirl, Voxtral's excited and cheerful). The pitch is shifted on this Mac as the clip plays, so it costs nothing extra.") + " " + lines + shared
        }
    }
}
