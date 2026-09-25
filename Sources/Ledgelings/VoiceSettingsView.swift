import AVFoundation
import SwiftUI

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
            switch settings.voiceEngine {
            case .system: systemFields
            case .openRouter: openRouterFields
            }
            SliderRow("Speed", value: $settings.voiceSpeed, in: AppSettings.voiceSpeedRange, step: 0.05, unit: "×")
            if settings.voiceEngine == .system {
                SliderRow("Pitch", value: $settings.voicePitch, in: AppSettings.voicePitchRange, step: 0.05, unit: "×")
            }
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
        if let listProblem { Text(listProblem).font(.caption).foregroundStyle(.red) }
        Color.clear.frame(height: 0).task { await load() }
    }

    private var modelVoices: [String] { voice.models.first { $0.id == settings.voiceModel }?.voices ?? [] }

    private func load() async {
        do { try await voice.loadModels(); listProblem = nil }
        catch { listProblem = "could not load OpenRouter's speech models: \(error)" }
    }

    private var footer: String {
        let shared = "Every bubble is read out, in order; when talk runs far ahead of the voice, lines are skipped rather than read late. \"Hear Them Talk\" in the menu turns it on and off."
        switch settings.voiceEngine {
        case .system:
            return "The Mac's own voices: free, offline, instant. More, and better ones, are in System Settings › Accessibility › Spoken Content › System Voice › Manage Voices. With a voice each, the novelty voices (Bells, Zarvox…) are left out, and each character also gets a slightly different pitch. " + shared
        case .openRouter:
            return "Speech models on OpenRouter sound far more alive, and cost a little per line: Kokoro is about $0.00003 a line. Uses the same key as the brain. What each line cost goes to the spend file a few seconds after it is said. A voice each takes the model's English voices where it says which they are. " + shared
        }
    }
}
