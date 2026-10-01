import LedgelingsCore
import SwiftUI

/// Settings › Calendar: what the creatures know of the user's day on the left
/// (the clock, the date, whose holidays); on the right, what that comes to
/// right now, word for word, and the holidays coming up.
struct CalendarSettingsView: View {
    @ObservedObject var settings: AppSettings

    var body: some View {
        TwoColumns {
            Section {
                // The built-in lines are written ahead of time: they cannot say what time it is.
                if !settings.hasModel { NeedsModelNote() }
                Toggle(tr("They know the time of day"), isOn: $settings.knowsTimeOfDay)
                    .disabled(!settings.hasModel)
                Toggle(tr("They know the day of the week and the date"), isOn: $settings.knowsDate)
                    .disabled(!settings.hasModel)
            } header: {
                Text(tr("The day"))
            } footer: {
                Text(tr("Your Mac's clock and calendar, told to the model before every line and paper plane: \"late evening (22:40)\", \"Saturday, 26 September 2026\". This is apart from the colony's own day and night, which only says when they sleep."))
            }

            Section {
                Toggle(tr("Jewish holidays"), isOn: $settings.jewishHolidays)
                Toggle(tr("Christian holidays"), isOn: $settings.christianHolidays)
                Toggle(tr("Muslim holidays"), isOn: $settings.muslimHolidays)
                Stepper(value: $settings.holidayLookAhead, in: AppSettings.holidayLookAheadRange) {
                    LabeledContent(tr("Mention a holiday"), value: settings.holidayLookAhead == 0
                                   ? tr("only on the day") : trCount(settings.holidayLookAhead, "day ahead", "days ahead"))
                }
                .disabled(settings.awareness.faiths.isEmpty || !settings.hasModel)
            } header: {
                Text(tr("Holidays"))
            } footer: {
                Text(tr("On a holiday they know it, and which day of it (\"day 3 of Sukkot\"); before one, how far off it is. Jewish dates come from the Hebrew calendar and Muslim ones from the Islamic (Umm al-Qura) calendar, both built into macOS, so nothing is looked up online; a holiday that starts at sundown \"begins this evening\" the evening before. Where the new moon is sighted locally, a Muslim date can fall a day apart. With the built-in lines, one conversation in three on a holiday is about it; they only know a holiday on the day, so how far ahead to mention one needs a model."))
            }
        } right: {
            // Each section keeps its own clock: a TimelineView round both
            // sections would fold them into one box.
            Section {
                TimelineView(.periodic(from: .now, by: 30)) { context in
                    let sentence = Almanac.sentence(at: context.date, settings.awareness)
                    Text(sentence.isEmpty ? tr("Nothing: every box is off.") : sentence)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            } header: {
                Text(tr("What they know right now"))
            } footer: {
                Text(settings.hasModel
                     ? tr("This goes into {situation} in the Talk prompts, and at the top of a paper plane's note.")
                     : tr("What a model would be told. The built-in lines use only today's holiday, when there is one."))
            }

            Section {
                TimelineView(.periodic(from: .now, by: 60)) { context in
                    let faiths = settings.awareness.faiths
                    let ahead = Almanac.upcoming(from: context.date, within: 60, faiths: faiths)
                    VStack(alignment: .leading, spacing: 8) {
                        if faiths.isEmpty {
                            Text(tr("No holidays ticked.")).foregroundStyle(.secondary)
                        } else if ahead.isEmpty {
                            Text(tr("Nothing in the next 60 days.")).foregroundStyle(.secondary)
                        }
                        ForEach(ahead, id: \.name) { holiday in
                            LabeledContent(holiday.name) {
                                Text(verbatim: "\(holiday.faith.title), \(when(holiday.days, from: context.date))").foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            } header: {
                Text(tr("Coming up in the next 60 days"))
            }
        }
    }

    /// "tomorrow", "in 12 days · Sat 3 Oct".
    private func when(_ days: Int, from now: Date) -> String {
        guard days > 1 else { return tr("tomorrow") }
        let date = Calendar.current.date(byAdding: .day, value: days, to: now) ?? now
        return tr("in %@", trCount(days, "day", "days")) + " · " + date.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated).locale(Locale(identifier: Language.current.code)))
    }
}
