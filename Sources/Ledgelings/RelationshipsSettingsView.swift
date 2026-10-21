import LedgelingsCore
import SwiftUI

/// Settings › Relationships: deeds from talk on the left (which deeds, how often,
/// the built-in lines' share), long-term memory on the right (what a prompt
/// carries, the nightly diary, the seed from the chat log), and a button to the
/// Relationships window, where each pair's memory can be read.
struct RelationshipsSettingsView: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject var bonds: BondBook
    /// Opens the Relationships window.
    var open: () -> Void = {}
    /// Reads the chat log into the memory (`dryRun`: only says what it would send); returns a summary.
    var seed: (_ dryRun: Bool) async -> String = { _ in "" }
    @State private var seedNews = ""
    @State private var seeding = false

    var body: some View {
        TwoColumns {
            Section {
                Toggle(tr("What they say can turn into what they do"), isOn: $settings.deedsEnabled)
                LazyVGrid(columns: [GridItem(.flexible(), alignment: .leading), GridItem(.flexible(), alignment: .leading)], alignment: .leading, spacing: 6) {
                    Toggle(tr("Invite to a game"), isOn: $settings.deedGames)
                    Toggle(tr("Invite to tea"), isOn: $settings.deedTea)
                    Toggle(tr("Give a flower"), isOn: $settings.deedFlower)
                    Toggle(tr("Send a letter"), isOn: $settings.deedLetter)
                    Toggle(tr("Walk over to someone"), isOn: $settings.deedVisit)
                    Toggle(tr("Follow someone"), isOn: $settings.deedFollow)
                    Toggle(tr("Go to sleep"), isOn: $settings.deedSleep)
                }
                .disabled(!settings.deedsEnabled)
            } header: {
                Text(tr("Deeds from talk"))
            } footer: {
                Text(tr("A line or a letter may end in a deed: \"soccer?\" answered \"yes\" starts the match. Each prompt offers only what is possible right now, and anything else is ignored. About 40 more tokens a line."))
            }

            Section {
                SliderRow(tr("After a deed, the next waits"), value: $settings.deedGapMinutes, in: AppSettings.deedGapRange, step: 0.5, unit: tr(" min"), zero: tr("no wait"))
                SliderRow(tr("Most deeds an hour"), value: double($settings.deedsPerHour), in: Double(AppSettings.deedsPerHourRange.lowerBound)...Double(AppSettings.deedsPerHourRange.upperBound), step: 1, unit: "", zero: tr("no limit"))
                SliderRow(tr("Same pair, same deed again after"), value: $settings.deedPairGapMinutes, in: AppSettings.deedPairGapRange, step: 1, unit: tr(" min"), zero: tr("no wait"))
                SliderRow(tr("An invitation stays open"), value: $settings.inviteOpenMinutes, in: AppSettings.inviteOpenRange, step: 1, unit: tr(" min"))
                SliderRow(tr("A yes waits for both to be free"), value: $settings.deedWaitMinutes, in: AppSettings.deedWaitRange, step: 0.5, unit: tr(" min"))
                SliderRow(tr("Following lasts"), value: $settings.followSeconds, in: AppSettings.followSecondsRange, step: 5, unit: tr(" s"))
                SliderRow(tr("Built-in letters and talks that invite"), value: $settings.builtInInviteShare, in: AppSettings.percentRange, step: 5, unit: "%")
                SliderRow(tr("Built-in answers that say yes"), value: $settings.builtInAcceptChance, in: AppSettings.percentRange, step: 5, unit: "%")
            } header: {
                Text(tr("How often"))
            } footer: {
                Text(tr("Zero turns a limit off; the same two never do two things within 15 seconds. Without a model each character invites and answers in its own words, close friends saying yes more often."))
            }
            .disabled(!settings.deedsEnabled)
        } right: {
            Section {
                Toggle(tr("Pairs remember each other"), isOn: $settings.memoryEnabled)
                SliderRow(tr("Memory sent with each line"), value: double($settings.memoryTokens), in: Double(AppSettings.memoryTokensRange.lowerBound)...Double(AppSettings.memoryTokensRange.upperBound), step: 10, unit: tr(" tokens"), zero: tr("none"))
                HStack(spacing: 24) {
                    Stepper(value: $settings.memoryFacts, in: AppSettings.memoryFactsRange) {
                        LabeledContent(tr("Facts kept per pair"), value: "\(settings.memoryFacts)")
                    }
                    Stepper(value: $settings.memoryDays, in: AppSettings.memoryDaysRange, step: 7) {
                        LabeledContent(tr("Days of timeline kept"), value: "\(settings.memoryDays)")
                    }
                }
                Toggle(tr("The model may note facts as it speaks"), isOn: $settings.memoryNotes)
                HStack(spacing: 24) {
                    Toggle(tr("Each knows what it did today"), isOn: $settings.dayContextEnabled)
                    Stepper(value: $settings.dayContextItems, in: AppSettings.dayContextItemsRange) {
                        LabeledContent(tr("Things from today it mentions"), value: "\(settings.dayContextItems)")
                    }
                    .disabled(!settings.dayContextEnabled)
                }
            } header: {
                Text(tr("Long-term memory"))
            } footer: {
                Text(tr("Every conversation, letter and tea party carries what the two remember, cut to the tokens set here. The timeline is for you; only today and yesterday are sent."))
            }

            Section {
                Toggle(tr("At nightfall the model writes their memory down"), isOn: $settings.diaryEnabled)
                SliderRow(tr("A pair's memory at most every"), value: $settings.diaryEveryHours, in: AppSettings.diaryEveryRange, step: 1, unit: tr(" h"))
                Stepper(value: $settings.diaryPairsPerNight, in: AppSettings.diaryPairsRange) {
                    LabeledContent(tr("Pairs a night"), value: "\(settings.diaryPairsPerNight)")
                }
            } header: {
                Text(tr("The diary"))
            } footer: {
                Text(tr("One call a pair (Costs › Long-term memory): their story, the facts that still matter, the day in a line. Without a model days are counted and facts come from deeds and games."))
            }
            .disabled(!settings.memoryEnabled)

            Section {
                HStack(spacing: 24) {
                    Stepper(value: $settings.seedDays, in: AppSettings.seedDaysRange) {
                        LabeledContent(tr("Days read back"), value: "\(settings.seedDays)")
                    }
                    Stepper(value: $settings.seedLines, in: AppSettings.seedLinesRange, step: 5) {
                        LabeledContent(tr("Lines shown per pair"), value: "\(settings.seedLines)")
                    }
                }
                HStack {
                    Button(tr("Check First")) { run(dryRun: true) }.disabled(seeding)
                    Button(tr("Read the Past In")) { run(dryRun: false) }.disabled(seeding)
                    Spacer()
                    Button(tr("Open Relationships")) { open() }
                }
                if !seedNews.isEmpty { Text(seedNews).font(.caption).foregroundStyle(.secondary) }
            } header: {
                Text(tr("Their past"))
            } footer: {
                Text(tr("Builds each pair's memory from what they said on this Mac, one call a pair (Costs › Memory: reading the past); only their own lines are sent. Check First sends nothing. bonds.json is copied first."))
            }
            .disabled(!settings.memoryEnabled)
        }
    }

    private func run(dryRun: Bool) {
        seeding = true
        seedNews = tr("Reading…")
        Task { @MainActor in
            seedNews = await seed(dryRun)
            seeding = false
        }
    }

    private func double(_ value: Binding<Int>) -> Binding<Double> {
        Binding(get: { Double(value.wrappedValue) }, set: { value.wrappedValue = Int($0.rounded()) })
    }
}
