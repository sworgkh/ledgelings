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
                Toggle("Pairs who live together get a story", isOn: $settings.plotsEnabled)
                SliderRow("First story after", value: $settings.plotAfterHours, in: AppSettings.plotAfterRange, step: 0.25, unit: " h")
                    .disabled(!settings.plotsEnabled)
                Stepper(value: $settings.plotLength, in: AppSettings.plotLengthRange) {
                    LabeledContent("A story lasts", value: "\(settings.plotLength) conversations")
                }
                .disabled(!settings.plotsEnabled)
            } header: {
                Text("Stories")
            } footer: {
                Text(footer)
            }

            Section {
                TextEditor(text: $settings.plotPrompt)
                    .font(.system(.callout, design: .monospaced))
                    .frame(minHeight: 200)
                    .scrollContentBackground(.hidden)
                    .padding(4)
                    .background(RoundedRectangle(cornerRadius: 6).fill(Color(nsColor: .textBackgroundColor)))
                HStack { Spacer(); Button("Reset Prompt") { settings.resetPlotPrompt() } }
            } header: {
                Text("The prompt that writes a story")
            } footer: {
                Text("Placeholders: \(Bonds.placeholders.map { "{\($0)}" }.joined(separator: " ")). The answer needs a PLOT: line, and may have a BOND: line. {relationship} in the Talk prompt places the story; without it, it goes at the end.")
            }
        } right: {
            Section {
                let pairs = bonds.book.closest
                if pairs.isEmpty { Text("Nobody has shared the screen yet.").foregroundStyle(.secondary) }
                ForEach(pairs, id: \.names) { bond in pair(bond) }
            } header: {
                Text("Who lives with whom")
            } footer: {
                Text("Time counts while both are on screen, and is kept by name: rename a character and it starts again as a stranger.")
            }

            Section {
                HStack {
                    Text(bonds.file.path).font(.caption).foregroundStyle(.tertiary).lineLimit(1).truncationMode(.middle)
                        .textSelection(.enabled)
                    Spacer()
                    Button("Reveal in Finder") { bonds.revealInFinder() }
                    Button("Forget All") { bonds.forgetAll() }.disabled(bonds.book.bonds.isEmpty)
                }
            } header: {
                Text("The file")
            }
        }
    }

    private var footer: String {
        var text = "Once two characters have shared the screen this long, the model writes them a small story and a line on how they get on. A few dozen words of it go into their prompts; when it has run its course, the next grows from the last. One short call per story (Costs › Relationship plots)."
        if settings.brain == .script { text += " The built-in lines have no model, so no stories: choose a model on the Talk tab." }
        return text
    }

    private func pair(_ bond: Bonds.Bond) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .firstTextBaseline) {
                Text(bond.names.joined(separator: " & ")).font(.headline)
                Spacer()
                Button("Forget") { bonds.forget(Bonds.key(bond.names[0], bond.names[bond.names.count - 1])) }
                    .buttonStyle(.link).font(.caption)
            }
            Text(details(bond)).font(.caption).foregroundStyle(.secondary).monospacedDigit()
            if let summary = bond.summary { Text(summary).font(.callout) }
            if let plot = bond.plot {
                Text("Part \(min(plot.told + 1, plot.length)) of \(plot.length): \(plot.text)").font(.callout).italic()
            } else if let last = bond.lastPlot {
                Text("Last story: \(last)").font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }

    private func details(_ bond: Bonds.Bond) -> String {
        var parts = ["together \(Bonds.duration(bond.together))", "\(bond.talks) talk\(bond.talks == 1 ? "" : "s")"]
        if bond.plots > 0 { parts.append("\(bond.plots) stor\(bond.plots == 1 ? "y" : "ies")") }
        if let cost = bond.cost { parts.append(Spend.label(cost)) }
        return parts.joined(separator: " · ")
    }
}
