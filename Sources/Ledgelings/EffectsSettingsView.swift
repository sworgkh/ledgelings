import LedgelingsCore
import SwiftUI

/// Settings › Effects: the master switch, Reduce motion, how often and how long the styles play, and a switch
/// and a Play button for each of the five styles. The twenty moments have their own page (`MomentsSettingsView`):
/// twenty-five switches with their buttons do not fit one laptop-sized page.
struct EffectsSettingsView: View {
    @ObservedObject var settings: AppSettings
    /// Plays a style or a moment on a creature now; nil in a snapshot.
    var preview: ((String) -> Void)?

    var body: some View {
        TwoColumns {
            Section {
                Toggle(tr("Effects on"), isOn: $settings.effectsEnabled)
                Picker(tr("Reduce motion"), selection: $settings.effectsReduceMotion) {
                    ForEach(Effects.ReduceMotion.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                Picker(tr("Styles play on their own"), selection: $settings.effectsFrequency) {
                    ForEach(Effects.Frequency.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                SliderRow(tr("A style lasts"), value: $settings.effectStyleSeconds, in: AppSettings.effectStyleSecondsRange, step: 1, unit: tr(" s"))
            } header: {
                SettingsHeader("Effects")
            } footer: {
                Text(tr("Pixel effects on the creatures, drawn in their own square pixels: styles they wear for a while, and moments in the features they mark. They are only drawn: clicks go through them. Reduce motion follows the Mac's Accessibility setting unless you choose, and turns the busy ones off (sparks, flames, confetti, the falling particles)."))
            }

            Section {
                ForEach(Effects.Style.allCases, id: \.self) { style in
                    EffectRow(title: style.title, detail: style.detail, key: style.key, settings: settings,
                              busy: style.busy, play: preview.map { p in { p(style.rawValue) } })
                }
            } header: {
                SettingsHeader("Styles")
            } footer: {
                Text(tr("Each comes on when something happens, by chance as often as you chose, and comes off by itself. Play puts it on a creature now. Creature Actions › Styles puts any style on anyone."))
            }
        } right: {
            Section {
                SliderRow(tr("Left alone for"), value: $settings.effectsAloneMinutes, in: AppSettings.effectsAloneMinutesRange, step: 5, unit: tr(" min"))
                Stepper(value: $settings.effectsTypingKeys, in: AppSettings.effectsTypingKeysRange, step: 500) {
                    LabeledContent(tr("A fast hour of typing"), value: tr("%d keys", settings.effectsTypingKeys))
                }
            } header: {
                SettingsHeader("When styles come")
            } footer: {
                Text(tr("Frost: now and then from December to February, or on a creature nobody has met for that long. Smitten: two friends meet, or a letter's invitation is accepted. Charged: grabbing the cursor, or a whole hour with at least that many keys pressed (counted by the Mac, nothing is recorded). Fired up: grumpy at the cursor, or losing a game. Haunted: now and then from 25 October to 1 November, or Boo spooking a friend."))
            }

            Section {
                SliderRow(tr("Out for"), value: $settings.effectsAmbientSeconds, in: AppSettings.effectsAmbientSecondsRange, step: 10, unit: tr(" s"))
                SliderRow(tr("Once every"), value: $settings.effectsAmbientEveryMinutes, in: AppSettings.effectsAmbientEveryRange, step: 1, unit: tr(" min"))
            } header: {
                SettingsHeader("Along the bottom edge")
            } footer: {
                Text(tr("Fireflies after dark, and the season's particles: snow from December to February, petals from March to May, leaves from September to November. They drift along the bottom of the creatures' monitors for a while, then go. Each has its switch on the Moments page."))
            }
        }
    }
}

/// Settings › Moments: a switch and a Play button for each of the twenty moments, grouped by the feature
/// they belong to, with the calendar and the budget that two of them need.
struct MomentsSettingsView: View {
    @ObservedObject var settings: AppSettings
    var preview: ((String) -> Void)?
    /// Asks for the calendar; nil in a snapshot.
    var allowCalendar: (() -> Void)?

    static let left: [Effects.Moment] = [.leaveScreen, .arriveScreen, .hardLanding, .dizzy, .goal, .friends, .newArrival, .poof, .bloom, .asleep]
    static let ambient: [Effects.Moment] = [.night, .winter, .autumn, .spring]
    static let tools: [Effects.Moment] = [.heyLook, .clockTicking, .listening, .translating, .copied, .moneySpent]

    var body: some View {
        TwoColumns {
            Section {
                rows(Self.left)
            } header: {
                SettingsHeader("The creatures")
            } footer: {
                Text(tr("Each marks a moment of a feature with an effect on the creature it happens to, at most every so often."))
            }
        } right: {
            Section {
                rows(Self.ambient)
            } header: {
                SettingsHeader("Night and the seasons")
            }
            Section {
                rows(Self.tools)
                LabeledContent(tr("Look at my calendar")) {
                    HStack {
                        Toggle("", isOn: $settings.effectsCalendar).labelsHidden().toggleStyle(.switch)
                        if settings.effectsCalendar, let allowCalendar {
                            Button(tr("Allow…"), action: allowCalendar).help(tr("Ask the Mac for the calendar"))
                        }
                    }
                }
                SliderRow(tr("Daily budget"), value: $settings.effectsDailyBudget, in: AppSettings.effectsDailyBudgetRange, step: 0.1, unit: " $")
            } header: {
                SettingsHeader("The tools")
            } footer: {
                Text(tr("Clock ticking reads the start of your next meeting from the Mac's calendar, and only once you allow it; nothing leaves the Mac. Money spent drops the coins once a day, when the day's spend on Settings › Costs passes the budget."))
            }
        }
    }

    @ViewBuilder private func rows(_ moments: [Effects.Moment]) -> some View {
        ForEach(moments, id: \.self) { m in
            EffectRow(title: m.title, detail: m.detail, key: m.key, settings: settings, busy: m.busy,
                      feature: m.feature.title, play: preview.map { p in { p(m.rawValue) } })
        }
    }
}

/// One style's or moment's row: its switch, the feature it belongs to, and Play.
struct EffectRow: View {
    let title: String
    let detail: String
    let key: String
    @ObservedObject var settings: AppSettings
    var busy = false
    var feature: String? = nil
    var play: (() -> Void)?

    var body: some View {
        HStack(spacing: 8) {
            Toggle(isOn: Binding(get: { settings.effectOn(key) }, set: { settings.setEffect(key, on: $0) })) {
                HStack(spacing: 6) {
                    Text(title)
                    if let feature { Text(feature).foregroundStyle(.secondary).font(.caption) }
                }
            }
            .help(busy ? detail + " · " + tr("off with Reduce motion") : detail)
            Spacer(minLength: 4)
            if let play {
                Button(tr("Play"), action: play)
                    .controlSize(.small)
                    .help(tr("Play %@ on a creature now", title))
            }
        }
    }
}
