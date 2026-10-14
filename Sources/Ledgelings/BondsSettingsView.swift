import LedgelingsCore
import SwiftUI

/// Settings › Bonds: when pairs get a story and how long it lasts on the left,
/// with the prompt that writes it; every pair's bond and story on the right.
struct BondsSettingsView: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject var bonds: BondBook

    var body: some View {
        TwoColumns {
            Section {
                Toggle(tr("Pairs who live together get a story"), isOn: $settings.plotsEnabled)
                SliderRow(tr("First story after"), value: $settings.plotAfterHours, in: AppSettings.plotAfterRange, step: 0.25, unit: tr(" h"))
                    .disabled(!writesStories)
                Stepper(value: $settings.plotLength, in: AppSettings.plotLengthRange) {
                    LabeledContent(tr("A story lasts"), value: trCount(settings.plotLength, "conversation", "conversations"))
                }
                .disabled(!writesStories)
            } header: {
                Text(tr("Stories"))
            } footer: {
                Text(footer)
            }

            Section {
                Toggle(tr("Each story grows from their whole history"), isOn: $settings.storylinesEnabled)
                    .disabled(!settings.plotsEnabled)
                Stepper(value: $settings.storyWords, in: AppSettings.storyWordsRange, step: 10) {
                    LabeledContent(tr("Their story so far is kept to"), value: trCount(settings.storyWords, "word", "words"))
                }
                .disabled(!keepsStorylines)
                Stepper(value: $settings.storyMoments, in: AppSettings.storyMomentsRange) {
                    LabeledContent(tr("Latest moments told one by one"), value: "\(settings.storyMoments)")
                }
                .disabled(!keepsStorylines)
            } header: {
                Text(tr("Storylines"))
            } footer: {
                Text(tr("Every talk, tea party, flower, paper plane and cursor grab two characters share is kept. A new story is written from their story so far (a short chronicle, rewritten in the same call) and the latest moments, so it can bring back what happened and never contradicts it. About 300 more tokens per story. With the built-in lines, stories are made from these moments without a model."))
            }

            // Like the Talk tab's prompts: nothing to edit until there is a model to read it.
            if settings.hasModel { Section {
                TextEditor(text: $settings.plotPrompt)
                    .font(.system(.callout, design: .monospaced))
                    .frame(minHeight: 200)
                    .scrollContentBackground(.hidden)
                    .padding(4)
                    .background(RoundedRectangle(cornerRadius: 6).fill(Color(nsColor: .textBackgroundColor)))
                HStack { Spacer(); Button(tr("Reset Prompt")) { settings.resetPlotPrompt() } }
            } header: {
                Text(tr("The prompt that writes a story"))
            } footer: {
                Text(tr("Placeholders: %@. The answer needs a PLOT: line, and may have BOND: and STORY: lines (their story so far, rewritten). {relationship} in the Talk prompt places the story; without it, it goes at the end.", Bonds.placeholders.map { "{\($0)}" }.joined(separator: " ")))
            } }
        } right: {
            Section {
                let pairs = bonds.book.closest
                if pairs.isEmpty { Text(tr("Nobody has shared the screen yet.")).foregroundStyle(.secondary) }
                ForEach(pairs, id: \.names) { bond in pair(bond) }
            } header: {
                Text(tr("Who lives with whom"))
            } footer: {
                Text(tr("Time counts while both are on screen, and is kept by name: rename a character and it starts again as a stranger."))
            }

            Section {
                HStack {
                    Text(bonds.file.path).font(.caption).foregroundStyle(.tertiary).lineLimit(1).truncationMode(.middle)
                        .textSelection(.enabled)
                    Spacer()
                    Button(tr("Reveal in Finder")) { bonds.revealInFinder() }
                    Button(tr("Reset All Stories")) { bonds.resetAllStories() }.disabled(bonds.book.bonds.isEmpty)
                    Button(tr("Forget All")) { bonds.forgetAll() }.disabled(bonds.book.bonds.isEmpty)
                }
            } header: {
                Text(tr("The file"))
            }
        }
    }

    private var footer: String {
        if !settings.hasModel {
            return tr("Once two characters have shared the screen this long, they get a small story and a line on how they get on. With the built-in lines there is no model: the story is made from what they lived through, at no cost; choose a model in Settings › Talk for written ones.")
        }
        return tr("Once two characters have shared the screen this long, the model writes them a small story and a line on how they get on. A few dozen words of it go into their prompts; when it has run its course, the next grows from the last. One short call per story (Costs › Relationship plots).")
    }

    private var writesStories: Bool { settings.plotsEnabled }
    private var keepsStorylines: Bool { settings.plotsEnabled && settings.storylinesEnabled }

    private func pair(_ bond: Bonds.Bond) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .firstTextBaseline) {
                Text(bond.names.joined(separator: " & ")).font(.headline)
                Spacer()
                Button(tr("Reset Story")) { bonds.resetStory(Bonds.key(bond.names[0], bond.names[bond.names.count - 1])) }
                    .buttonStyle(.link).font(.caption)
                Button(tr("Forget")) { bonds.forget(Bonds.key(bond.names[0], bond.names[bond.names.count - 1])) }
                    .buttonStyle(.link).font(.caption)
            }
            Text(details(bond)).font(.caption).foregroundStyle(.secondary).monospacedDigit()
            if let summary = bond.summary { Text(summary).font(.callout) }
            if let plot = bond.plot {
                Text(tr("Part %d of %d: %@", min(plot.told + 1, plot.length), plot.length, plot.text)).font(.callout).italic()
            } else if let last = bond.lastPlot {
                Text(tr("Last story: %@", last)).font(.caption).foregroundStyle(.secondary)
            }
            if let chronicle = bond.chronicle {
                Text(tr("So far: %@", chronicle)).font(.caption).foregroundStyle(.secondary).lineLimit(3)
                    .help(chronicle)
            }
        }
        .padding(.vertical, 2)
    }

    private func details(_ bond: Bonds.Bond) -> String {
        var parts = [tr("together %@", Bonds.duration(bond.together)), trCount(bond.talks, "talk", "talks")]
        if bond.plots > 0 { parts.append(trCount(bond.plots, "story", "stories")) }
        if let cost = bond.cost { parts.append(Spend.label(cost)) }
        return parts.joined(separator: " · ")
    }
}
