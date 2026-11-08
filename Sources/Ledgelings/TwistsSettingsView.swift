import LedgelingsCore
import SwiftUI

/// Settings › Plot twists: on the left whether a newcomer or a departure is news,
/// for how many days and how often it comes up; on the right the gang as the
/// roster knows it, and the news still fresh.
struct TwistsSettingsView: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject var bonds: BondBook

    var body: some View {
        TwoColumns {
            Section {
                Toggle(tr("A newcomer or a departure is news for days"), isOn: $settings.twistsEnabled)
                Toggle(tr("Someone leaving is news too"), isOn: $settings.twistDepartures)
                    .disabled(!settings.twistsEnabled)
                Stepper(value: $settings.twistDays, in: AppSettings.twistDaysRange) {
                    LabeledContent(tr("The news stays a topic for"), value: trCount(settings.twistDays, "day", "days"))
                }
                .disabled(!settings.twistsEnabled)
                SliderRow(tr("Conversations that bring it up at first"), value: $settings.twistChance, in: AppSettings.twistChanceRange, step: 5, unit: "%")
                    .disabled(!settings.twistsEnabled)
            } header: {
                SettingsHeader("Plot twists")
            } footer: {
                Text(tr("When a character new to the gang turns up (a species switched on, more creatures, an imported sprite, a new one in an update), or one leaves, the others talk about it: welcome, suspicion, gossip, missing someone. The chance fades to nothing as the news gets old. Sleeping or moving to another monitor is not leaving."))
            }

            Section {
                Text(tr("The news rides in the prompts already sent (talk, tea, letters, stories, the diary), so it costs a few tokens and no call of its own. Without a model each character has a line of its own about someone new, someone gone and someone back. A newcomer's first meeting with each of the others is kept in their storyline, and a departure in the closest friends' memory."))
                    .font(.callout).foregroundStyle(.secondary)
            } header: {
                SettingsHeader("What it does")
            }
        } right: {
            Section {
                let fresh = bonds.book.gang.fresh(days: settings.twistDays, departures: settings.twistDepartures, now: Date())
                if fresh.isEmpty {
                    Text(tr("No news: the gang is as it was.")).foregroundStyle(.secondary)
                } else {
                    ForEach(Array(fresh.enumerated()), id: \.offset) { _, event in
                        Text(Self.describe(event)).frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                HStack {
                    Spacer()
                    Button(tr("Forget the News")) { bonds.change { $0.gang.forgetNews() } }.disabled(bonds.book.gang.events.isEmpty)
                }
            } header: {
                SettingsHeader("News in the gang")
            } footer: {
                Text(tr("A change counts once it has held for two minutes. Forget the News ends every topic now; the gang is still remembered."))
            }

            Section {
                let members = bonds.book.gang.members.values.filter { !$0.pending }.sorted { $0.name < $1.name }
                if members.isEmpty {
                    Text(tr("Nobody yet: the gang is counted half a minute after launch.")).foregroundStyle(.secondary)
                } else {
                    let here = members.filter { $0.away == nil }.map(\.name), away = members.filter { $0.away != nil }.map(\.name)
                    LabeledContent(tr("On screen"), value: here.joined(separator: ", "))
                    if !away.isEmpty { LabeledContent(tr("Gone"), value: away.joined(separator: ", ")) }
                }
            } header: {
                SettingsHeader("The gang")
            } footer: {
                Text(tr("Everyone who has ever been on screen, kept by name in bonds.json: a rename is a newcomer."))
            }
        }
    }

    /// "Pip joined the gang today", in the current language.
    static func describe(_ event: Gang.Event) -> String {
        let when = Bonds.ago(event.time, now: Date())
        switch event.kind {
        case .joined: return tr("%@ joined the gang %@", event.name, when)
        case .left: return tr("%@ left the gang %@", event.name, when)
        case .returned: return tr("%@ came back %@", event.name, when)
        }
    }
}
