import AppKit
import LedgelingsCore
import SwiftUI

/// Settings › Beds: whether they sleep in beds and how they find their place on
/// the left; everyone's bed and favourite place on the right, with a way to
/// forget one character's place or everyone's.
struct BedsSettingsView: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject var library: SpriteLibrary
    @ObservedObject var beds: BedBook
    @State private var confirmForget = false

    /// The bed pictures, cut once.
    private static let pictures: SpriteAtlas.Frames? = (try? SpriteAtlas(named: "beds"))?.frames()

    var body: some View {
        TwoColumns {
            Section {
                Toggle(tr("Each one sleeps in its own bed"), isOn: $settings.bedsEnabled)
            } header: {
                Text(tr("Beds"))
            } footer: {
                Text(tr("Every character has a bed of its own, picked for who it is: a crate for Blocky, a basket for Mittens, a lily pad for Hopper. Falling asleep, it puts the bed down and sleeps on it; waking, it folds it away. Off, they sleep on the bare edge as before."))
            }

            Section {
                SliderRow(tr("Pull of the favourite place"), value: $settings.bedPull, in: AppSettings.bedPullRange, step: 5, unit: "%")
                SliderRow(tr("Walks to it at most"), value: $settings.bedWalkDistance, in: AppSettings.bedWalkRange, step: 100, unit: tr(" pt"))
            } header: {
                Text(tr("The favourite place"))
            } footer: {
                Text(tr("At nightfall a creature gets up and walks to its favourite place, if it is on the same screen outline and no further along the edge than this. The first night it picks a place its character likes (Blocky the bottom edge, Pip the ceiling). Each night there makes it likelier to go back, up to this pull; a night slept elsewhere wears the habit down, and enough of them move it. A nap you ask for is slept where it is."))
            }
            .disabled(!settings.bedsEnabled)

            Section {
                Toggle(tr("Say something about it now and then"), isOn: $settings.bedTalk)
            } header: {
                Text(tr("Talking about it"))
            } footer: {
                Text(tr("Some nights a creature says a line as it lies down, in its own voice, and it mumbles something when you move its bed. Built-in lines: no model calls."))
            }
            .disabled(!settings.bedsEnabled)
        } right: {
            Section {
                list
            } header: {
                Text(tr("Who sleeps where"))
            } footer: {
                Text(tr("Drag a sleeper's bed, by its edge or the part under its feet, to anywhere on an edge: it lands there, still asleep, and that is its favourite place from now on. Dragging a bed is not a chase. Kept by name: rename a character and it looks for a place afresh."))
            }

            Section {
                HStack {
                    Text(beds.file.path).font(.caption).foregroundStyle(.tertiary).lineLimit(1).truncationMode(.middle)
                        .textSelection(.enabled)
                    Spacer()
                    Button(tr("Forget All Places…")) { confirmForget = true }.disabled(beds.book.spots.isEmpty)
                }
            } header: {
                Text(tr("The file"))
            }
        }
        .confirmationDialog(tr("Forget where everyone likes to sleep?"), isPresented: $confirmForget) {
            Button(tr("Forget All Places"), role: .destructive) { beds.forget() }
        }
    }

    /// Everyone on screen, once each.
    private var who: [(name: String, bed: Beds.Kind)] {
        var seen = Set<String>(), out: [(String, Beds.Kind)] = []
        for i in 0..<settings.creatureCount {
            let c = settings.character(forCreature: i, library: library)
            guard seen.insert(c.name).inserted else { continue }
            let kind = library.kind(of: settings.species(forCreature: i))
            out.append((c.name, Beds.kind(name: c.name, persona: c.persona, kind: kind)))
        }
        return out
    }

    private var list: some View {
        let screens = NSScreen.screens.map(\.frame)
        return Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 4) {
            ForEach(who, id: \.name) { row in
                GridRow {
                    picture(row.bed)
                    VStack(alignment: .leading, spacing: 0) {
                        Text(verbatim: row.name)
                        Text(verbatim: row.bed.title).font(.caption).foregroundStyle(.secondary)
                    }
                    Text(verbatim: whereItSleeps(row.name, screens: screens)).font(.caption)
                    Button(tr("Forget")) { beds.forget(row.name) }
                        .buttonStyle(.link).font(.caption)
                        .disabled(beds.spot(of: row.name) == nil)
                }
            }
        }
    }

    private func whereItSleeps(_ name: String, screens: [CGRect]) -> String {
        guard let spot = beds.spot(of: name) else { return tr("no place yet") }
        return Beds.place(of: spot.point, screens: screens) + ", " + trCount(spot.nights, "night", "nights")
    }

    @ViewBuilder private func picture(_ bed: Beds.Kind) -> some View {
        if let image = Self.pictures?.frame(animation: bed.rawValue, time: 0) {
            Image(decorative: image, scale: 0.5).interpolation(.none)
        } else {
            Text(verbatim: "")
        }
    }
}
