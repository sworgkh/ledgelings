import LedgelingsCore
import SwiftUI

/// Settings › Chases: whether the cursor's hunts are counted and how the
/// creatures use the count on the left; revenge, then the count itself on the
/// right, per character and in total, with a reset for each and for all.
struct ChasesSettingsView: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject var library: SpriteLibrary
    @ObservedObject var hunts: HuntBook
    @State private var confirmReset = false

    var body: some View {
        TwoColumns {
            Section {
                Toggle(tr("Count chases and pick-ups"), isOn: $settings.huntCountEnabled)
            } header: {
                Text(tr("Counting"))
            } footer: {
                Text(tr("Every time the cursor chases a creature off its edge or picks it up, it counts, by character: today, this week and in all. Days and weeks follow your calendar. Off, nothing is counted and the numbers stay as they are."))
            }

            Section {
                Toggle(tr("They know their count"), isOn: $settings.huntTalkEnabled)
                SliderRow(tr("How often it comes up"), value: $settings.huntTalkChance, in: AppSettings.huntTalkChanceRange, step: 5, unit: "%")
                    .disabled(!settings.huntTalkEnabled)
            } header: {
                Text(tr("Talking about it"))
            } footer: {
                Text(tr("This share of conversations, tea stories and paper planes carries the numbers: with a model they go into its prompt, compared with yesterday and the week, with any record; with the built-in lines a creature says its count in its own voice. A complaint always knows them, and a round number or a record day is said out loud. How they take it follows the cursor mood: a score, a fact, or a grudge. No extra model calls."))
            }

            Section {
                Toggle(tr("Much-chased creatures keep their distance"), isOn: $settings.huntWary)
                Stepper(value: $settings.huntWaryAfter, in: AppSettings.huntWaryAfterRange, step: 5) {
                    LabeledContent(tr("After"), value: tr("%d in a day", settings.huntWaryAfter))
                }
                .disabled(!settings.huntWary)
            } header: {
                Text(tr("Wariness"))
            } footer: {
                Text(tr("When the cursor is a menace, a creature chased this often today jumps away from further off, until tomorrow."))
            }
            .disabled(!settings.huntCountEnabled)

        } right: {
            Section {
                Toggle(tr("Grab the cursor in revenge"), isOn: $settings.revengeEnabled)
                Group {
                    Stepper(value: $settings.revengeAfter, in: AppSettings.revengeAfterRange) {
                        LabeledContent(tr("After"), value: trCount(settings.revengeAfter, "time", "times"))
                    }
                    SliderRow(tr("Within"), value: $settings.revengeWindowSeconds, in: AppSettings.revengeWindowRange, step: 30, unit: tr(" s"))
                    SliderRow(tr("Holds on for at most"), value: $settings.revengeHoldSeconds, in: AppSettings.revengeHoldRange, step: 1, unit: tr(" s"))
                    Stepper(value: $settings.revengeShakes, in: AppSettings.revengeShakesRange) {
                        LabeledContent(tr("Shakes to break free"), value: "\(settings.revengeShakes)")
                    }
                    SliderRow(tr("Then peace for"), value: $settings.revengeCooldownMinutes, in: AppSettings.revengeCooldownRange, step: 1, unit: tr(" min"))
                }
                .disabled(!settings.revengeEnabled)
            } header: {
                Text(tr("Revenge"))
            } footer: {
                Text(tr("Chased or picked up this often in that time, a creature jumps on the cursor and holds it while it tells you off, in its own words and the cursor mood. Shake the mouse hard, back and forth, to throw it off. Escape lets go too, and it never holds on past the limit. Moving the pointer needs no permission; Escape outside Ledgelings works only with Accessibility allowed."))
            }

            Section {
                tally
            } header: {
                Text(tr("The count"))
            } footer: {
                Text(since)
            }

            Section {
                HStack {
                    Text(hunts.file.path).font(.caption).foregroundStyle(.tertiary).lineLimit(1).truncationMode(.middle)
                        .textSelection(.enabled)
                    Spacer()
                    Button(tr("Reset All…")) { confirmReset = true }.disabled(hunts.book.tallies.isEmpty)
                }
            } header: {
                Text(tr("The file"))
            }
        }
        .confirmationDialog(tr("Reset every creature's count to zero?"), isPresented: $confirmReset) {
            Button(tr("Reset All"), role: .destructive) { hunts.reset() }
        }
    }

    /// Everyone on screen, then anyone else ever counted, most hunted first.
    private var names: [String] {
        let onScreen = (0..<settings.creatureCount).map { settings.character(forCreature: $0, library: library).name }
        var seen = Set<String>(), out: [String] = []
        for name in onScreen where seen.insert(name).inserted { out.append(name) }
        let others = hunts.book.tallies.filter { !seen.contains($0.key) }.sorted { ($0.value.all, $1.key) > ($1.value.all, $0.key) }
        return out + others.map(\.key)
    }

    private var tally: some View {
        Grid(alignment: .trailing, horizontalSpacing: 18, verticalSpacing: 6) {
            GridRow {
                Text(tr("Creature")).gridColumnAlignment(.leading)
                Text(tr("Today"))
                Text(tr("This week"))
                Text(tr("In all"))
                Text(verbatim: "")
            }
            .font(.caption).foregroundStyle(.secondary)
            Divider()
            ForEach(names, id: \.self) { name in
                let n = hunts.numbers(of: name)
                GridRow {
                    Text(verbatim: name)
                    Text(verbatim: "\(n.today)")
                    Text(verbatim: "\(n.week)")
                    Text(verbatim: "\(n.all)")
                    Button(tr("Reset")) { hunts.reset(name) }
                        .buttonStyle(.link).font(.caption)
                        .disabled(hunts.book.tallies[name] == nil)
                }
                .monospacedDigit()
            }
            Divider()
            let total = hunts.total
            GridRow {
                Text(tr("Everyone"))
                Text(verbatim: "\(total.today)")
                Text(verbatim: "\(total.week)")
                Text(verbatim: "\(total.all)")
                Text(verbatim: "")
            }
            .font(.headline).monospacedDigit()
        }
    }

    private var since: String {
        guard let date = hunts.book.since else { return tr("Nothing counted yet. Chase someone with the cursor.") }
        let when = date.formatted(Date.FormatStyle(date: .long, time: .shortened).locale(Locale(identifier: settings.language.code)))
        return tr("Counting since %@. Kept by name: rename a character and it starts from zero.", when)
    }
}
