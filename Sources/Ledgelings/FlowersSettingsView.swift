import LedgelingsCore
import SwiftUI

/// The flowers a meeting brings: how long one is worn, whether the wearer trails
/// its giver, and the planting of it, with who on screen plants where.
struct FlowersSettingsView: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject var library: SpriteLibrary

    var body: some View {
        TwoColumns {
            Section {
                SliderRow("Flower lasts", value: $settings.flowerMinutes, in: AppSettings.flowerRange, step: 0.5, unit: " min")
                Toggle("The one with the flower follows the giver while it lasts", isOn: $settings.followGiver)
            } header: {
                Text("Wearing")
            } footer: {
                Text("Every third meeting of a pair, one gives the other a flower, worn on the head until it wilts or is planted. With the box ticked, the wearer trails the giver around the edge meanwhile. A creature wearing a flower walks past everyone without bumping.")
            }

            Section {
                Toggle("They plant their flowers where they like", isOn: $settings.plantFlowers)
                SliderRow("A planted flower lasts", value: $settings.gardenMinutes, in: AppSettings.gardenMinutesRange, step: 1, unit: " min")
                    .disabled(!settings.plantFlowers)
                Stepper(value: $settings.gardenSize, in: AppSettings.gardenSizeRange) {
                    LabeledContent("Flowers in the ground at most", value: "\(settings.gardenSize)")
                }
                .disabled(!settings.plantFlowers)
            } header: {
                Text("Planting")
            } footer: {
                Text("After wearing it a while, each one stops following its giver, goes looking for the kind of spot its character likes and plants the flower in the edge there. What it likes comes from who it is: Blocky wants the bottom edge, Pip the ceiling, Ruth a neat row beside the others, Dot plants at once, Zed waits for dark. If nowhere suits before the flower would wilt, it plants it where it stands. Planting one more than the most wilts the oldest. Planted flowers are not kept when the app quits.")
            }
        } right: {
            Section {
                ForEach(0..<settings.creatureCount, id: \.self) { i in
                    let who = settings.character(forCreature: i, library: library)
                    let kind = library.kind(of: settings.species(forCreature: i))
                    LabeledContent(who.name) {
                        Text(Garden.describe(Garden.temper(persona: who.persona, kind: kind)))
                            .multilineTextAlignment(.trailing)
                    }
                }
            } header: {
                Text("Who plants where")
            } footer: {
                Text("Read from each character's description and its species on the Talk tab, the same way voices are cast: words like bottom, ceiling, corner, quiet, cheerful, counts, sleepy or fast. Edit a description and this changes with it.")
            }
        }
    }
}
