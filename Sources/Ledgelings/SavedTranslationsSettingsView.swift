import LedgelingsCore
import SwiftUI

/// Settings › Tools › Saved translations (§7.14.3): the star and the drawer beside
/// the Translate sheet on the left; how many there are and Delete all on the right.
struct SavedTranslationsSettingsView: View {
    @ObservedObject var settings: AppSettings
    /// The saved translations, for their count and Delete all; nil in a test.
    var saved: SavedTranslations? = nil
    @State private var confirmingDelete = false

    var body: some View {
        TwoColumns {
            Section {
                Toggle(tr("Saved translations"), isOn: $settings.translateSavedEnabled)
                SliderRow(tr("How many to keep"), value: Binding(get: { Double(settings.translateSavedLimit) }, set: { settings.translateSavedLimit = Int($0) }),
                          in: Double(Translate.savedLimitRange.lowerBound)...Double(Translate.savedLimitRange.upperBound), step: 50, unit: "")
                    .disabled(!settings.translateSavedEnabled)
                Toggle(tr("Open the drawer with the sheet"), isOn: $settings.translateSavedOpenDrawer)
                    .disabled(!settings.translateSavedEnabled)
            } header: {
                SettingsHeader("Saved translations")
            } footer: {
                Text(tr("⌘D in the sheet saves the translation on show, as a star does; ⌘L opens the drawer of saved ones beside the sheet, to search, load back, copy or delete. Kept on this Mac; the oldest go beyond the number above. Loading one back costs nothing."))
            }
        } right: {
            Section {
                if let saved { Count(saved: saved) { confirmingDelete = true } }
            } header: {
                SettingsHeader("Kept on this Mac")
            } footer: {
                Text(tr("In translations.json beside the clipboard history. Deleting one is the bin on its row in the drawer, or ⌫."))
            }
            .confirmationDialog(tr("Delete every saved translation?"), isPresented: $confirmingDelete) {
                Button(tr("Delete All"), role: .destructive) { saved?.clear() }
            } message: {
                Text(tr("They cannot be brought back."))
            }
        }
    }

    /// How many are saved, and the button that deletes them all after asking.
    private struct Count: View {
        @ObservedObject var saved: SavedTranslations
        let delete: () -> Void

        var body: some View {
            HStack {
                Text(trCount(saved.book.count, "saved translation", "saved translations")).foregroundStyle(.secondary)
                Spacer()
                Button(tr("Delete All Saved…"), action: delete).disabled(saved.book.isEmpty)
            }
        }
    }
}
