import LedgelingsCore
import SwiftUI

/// Settings › Talk › Chat with you: the window and how they answer on the left,
/// what they remember of you on the right.
struct ChatSettingsView: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject var memory: OwnerChatBook
    @State private var chosen = ""

    var body: some View {
        TwoColumns {
            Section {
                Toggle(tr("Chat with the creatures"), isOn: $settings.chatEnabled)
                LabeledContent(tr("Open the chat")) {
                    HStack {
                        Toggle("", isOn: $settings.chatShortcutEnabled).labelsHidden()
                        ShortcutRecorder(settings: settings, shortcut: $settings.chatShortcut)
                    }
                }
                if !settings.chatShortcutProblem.isEmpty {
                    Text(settings.chatShortcutProblem).foregroundStyle(.red)
                }
            } header: {
                SettingsHeader("Chat with you")
            } footer: {
                Text(tr("%@ opens a paper window from any app, and so do the menu, the Tools screen and Creature Actions. Write to one creature, or to Everyone; ⏎ sends, ⇧⏎ makes a new line, ⎋ closes.", GlobalShortcut.spoken(settings.chatShortcut)))
            }

            Section {
                SliderRow(tr("How many answer Everyone"), value: Binding(get: { Double(settings.chatEveryone) }, set: { settings.chatEveryone = Int($0) }),
                          in: Double(OwnerChat.everyoneRange.lowerBound)...Double(OwnerChat.everyoneRange.upperBound), step: 1, unit: "")
                Picker(tr("Reply length"), selection: $settings.chatLength) {
                    ForEach(OwnerChat.Length.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                Toggle(tr("Speak replies aloud"), isOn: $settings.chatSpeak)
                Toggle(tr("Show bubbles on screen"), isOn: $settings.chatBubbles)
            } header: {
                SettingsHeader("Answers")
            } footer: {
                Text(tr("Each answers through the brain model in its own persona and species, turned to face the window while it talks. To Everyone, a few answer one after another, each hearing the ones before. Out loud only when voice is on too (Talk › Voice). Every call shows on Costs as Chat with you, and each talk on Chats."))
            }
        } right: {
            Section {
                Toggle(tr("Remember talks"), isOn: $settings.chatRemember)
                SliderRow(tr("Past exchanges kept word for word"), value: Binding(get: { Double(settings.chatMemoryExchanges) }, set: { settings.chatMemoryExchanges = Int($0) }),
                          in: Double(OwnerChat.exchangesRange.lowerBound)...Double(OwnerChat.exchangesRange.upperBound), step: 1, unit: "")
                    .disabled(!settings.chatRemember)
                let names = memory.book.names
                if names.isEmpty {
                    Text(tr("Nobody remembers a talk with you yet.")).foregroundStyle(.secondary)
                } else {
                    Picker(tr("Who"), selection: $chosen) {
                        ForEach(names, id: \.self) { Text($0).tag($0) }
                    }
                    if let m = memory.memory(of: shown(names)) {
                        Text(tr("%@ kept, summary: %@", trCount(m.exchanges.count, "exchange", "exchanges"), m.summary ?? tr("none yet")))
                            .foregroundStyle(.secondary).lineLimit(4)
                    }
                    HStack {
                        Button(tr("Forget this one")) { memory.forget(shown(names)); chosen = "" }
                        Button(tr("Forget everyone's")) { memory.forgetAll(); chosen = "" }
                    }
                }
            } header: {
                SettingsHeader("Memory")
            } footer: {
                Text(tr("Each creature keeps its last talks with you word for word and a short summary of the older ones, and both go into its next answer: it remembers what you told it yesterday. When a talk falls out of the kept ones, one call rewrites the summary (on Costs as Chat with you). Off: nothing new is kept or sent. --memory prints it all."))
            }
        }
    }

    private func shown(_ names: [String]) -> String { names.contains(chosen) ? chosen : names[0] }
}
