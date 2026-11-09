import LedgelingsCore
import SwiftUI

/// Settings › Diving: the water and the dive on the left; Stop activity, the
/// way to end a dive, a surf or a game from any app, on the right. A dive only
/// ever starts by hand: from Creature Actions, the Tools screen or the menu.
struct DivingSettingsView: View {
    @ObservedObject var settings: AppSettings
    /// Start one now; nil in a snapshot.
    var start: (() -> Void)?

    var body: some View {
        TwoColumns {
            Section {
                SliderRow(tr("Water height"), value: $settings.diveWaterShare, in: AppSettings.diveWaterShareRange, step: 0.01, unit: "%",
                          scale: 100)
                SliderRow(tr("Water shows"), value: $settings.diveWaterOpacity, in: AppSettings.diveWaterOpacityRange, step: 0.05, unit: "%", scale: 100)
                Picker(tr("Water on"), selection: $settings.diveAllScreens) {
                    Text(tr("The creatures' home monitor")).tag(false)
                    Text(tr("Every monitor")).tag(true)
                }
            } header: {
                SettingsHeader("The water")
            } footer: {
                Text(tr("It rises from the bottom edge and is only drawn: clicks and keys go through it to the apps below. The less it shows, the more of them you see through it."))
            }

            Section {
                SliderRow(tr("A dive lasts"), value: $settings.diveMinutes, in: AppSettings.diveMinutesRange, step: 0.5, unit: tr(" min"))
                Stepper(value: $settings.diveDivers, in: AppSettings.diveDiversRange) {
                    LabeledContent(tr("Divers at most"), value: "\(settings.diveDivers)")
                }
                Stepper(value: $settings.diveSeaLife, in: AppSettings.diveSeaLifeRange) {
                    LabeledContent(tr("Fish"), value: "\(settings.diveSeaLife)")
                }
                Toggle(tr("The divers say what they see"), isOn: $settings.diveTalk)
                if let start {
                    Button(tr("Start a dive now"), action: start)
                }
            } header: {
                SettingsHeader("The dive")
            } footer: {
                Text(tr("Whoever is free puts on a mask and a tank and jumps in; they swim among the fish, a jellyfish, a crab, a turtle and an octopus, come up for air now and then, and climb out dripping when it is over. What they saw together goes into their memory. It never starts by itself."))
            }
        } right: {
            Section {
                LabeledContent(tr("Stop activity")) {
                    HStack {
                        Toggle("", isOn: $settings.stopActivityShortcutEnabled).labelsHidden()
                        ShortcutRecorder(settings: settings, shortcut: $settings.stopActivityShortcut)
                    }
                }
                Toggle(tr("Stop when I use the computer"), isOn: $settings.stopOnUse)
                if !settings.stopActivityShortcutProblem.isEmpty {
                    Text(settings.stopActivityShortcutProblem).foregroundStyle(.red)
                }
            } header: {
                SettingsHeader("Stop activity")
            } footer: {
                Text(tr("The shortcut works in every app and ends whatever is running at once: a dive, a surf, a game. The water, the fish and the gear are gone within half a second. With Stop when I use the computer on, a key press, or a click anywhere but on a creature, ends it too; moving the mouse does not. The menu has Stop activity as well."))
            }

            Section {
                HStack(spacing: 14) {
                    ForEach(["fish-a", "fish-b", "fish-c", "jelly", "crab", "turtle", "octopus"], id: \.self) { picture($0) }
                }
            } header: {
                SettingsHeader("Under the water")
            } footer: {
                Text(tr("Drawn like the creatures. The sea life is not a character: it says nothing, but fish scatter from a diver, the crab raises its claws and the octopus inks and jets off."))
            }
        }
    }

    static let sea = try? SpriteAtlas(named: "sea").frames()

    @ViewBuilder private func picture(_ animation: String) -> some View {
        if let image = Self.sea?.frame(animation: animation, time: 0).flatMap(ActionIcons.trimmed) {
            Image(decorative: image, scale: 0.5).interpolation(.none)
        }
    }
}
