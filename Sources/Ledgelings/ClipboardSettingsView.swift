import AppKit
import LedgelingsCore
import SwiftUI

/// Settings › Productivity tools › Clipboard: the history and the shortcuts on the
/// left, pasting, the snippets and the apps never watched on the right.
struct ClipboardSettingsView: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject var clips: ClipBook
    /// For the names of the creatures on screen, who could bring the picker.
    let library: SpriteLibrary
    /// Opens Edit Snippets….
    let editSnippets: () -> Void
    @State private var trusted = ClipPaster.trusted

    var body: some View {
        TwoColumns {
            Section {
                Toggle(tr("Clipboard manager"), isOn: $settings.clipboardEnabled)
                Toggle(tr("Keep a history of what is copied"), isOn: $settings.clipHistoryEnabled)
                SliderRow(tr("Copies kept"), value: Binding(get: { Double(settings.clipHistoryLimit) }, set: { settings.clipHistoryLimit = Int($0) }),
                          in: Double(AppSettings.clipHistoryLimitRange.lowerBound)...Double(AppSettings.clipHistoryLimitRange.upperBound), step: 10, unit: "")
                SliderRow(tr("Kept for"), value: Binding(get: { Double(settings.clipKeepDays) }, set: { settings.clipKeepDays = Int($0) }),
                          in: Double(AppSettings.clipKeepDaysRange.lowerBound)...Double(AppSettings.clipKeepDaysRange.upperBound), step: 1,
                          unit: tr(" d"), zero: tr("always"))
                Toggle(tr("Keep formatting (rich text)"), isOn: $settings.clipKeepFormatting)
                Toggle(tr("Keep files copied in Finder"), isOn: $settings.clipKeepFiles)
                Toggle(tr("Keep images"), isOn: $settings.clipKeepImages)
                SliderRow(tr("Largest image kept"), value: Binding(get: { Double(settings.clipLargestImageMB) }, set: { settings.clipLargestImageMB = Int($0) }),
                          in: Double(AppSettings.clipLargestImageRange.lowerBound)...Double(AppSettings.clipLargestImageRange.upperBound), step: 1,
                          unit: tr(" MB"))
                    .disabled(!settings.clipKeepImages)
            } header: {
                Text(tr("History"))
            } footer: {
                Text(tr("Every copy goes into the history, newest first; copying the same thing again moves it to the top. Pinned copies stay whatever the limits say. Pictures count as copies; one bigger than the largest size is left out. Nothing copied ever leaves this Mac or reaches a model."))
            }
            .disabled(!settings.clipboardEnabled)

            Section {
                LabeledContent(tr("History picker")) {
                    HStack {
                        Toggle("", isOn: $settings.clipHistoryShortcutEnabled).labelsHidden()
                        ShortcutRecorder(settings: settings, shortcut: $settings.clipHistoryShortcut)
                    }
                }
                LabeledContent(tr("Snippets picker")) {
                    HStack {
                        Toggle("", isOn: $settings.clipSnippetsShortcutEnabled).labelsHidden()
                        ShortcutRecorder(settings: settings, shortcut: $settings.clipSnippetsShortcut)
                    }
                }
                Toggle(tr("A snippet's own shortcut pastes it at once"), isOn: $settings.clipSnippetShortcutsEnabled)
                if !settings.clipShortcutProblem.isEmpty {
                    Text(settings.clipShortcutProblem).foregroundStyle(.red)
                }
            } header: {
                Text(tr("Shortcuts"))
            } footer: {
                Text(tr("They work in every app. In the picker: type to search copies and snippets at once, ↑↓ to choose, ⌘1–9 for the first nine, ⇥ between the groups, ⌘P to pin, ⌫ to forget a copy, ⎋ to close."))
            }
            .disabled(!settings.clipboardEnabled)
        } right: {
            Section {
                Toggle(tr("Paste into the app I was in"), isOn: $settings.clipAutoPaste)
                if settings.clipAutoPaste && !trusted {
                    HStack {
                        Text(tr("Needs Accessibility, to press ⌘V for you. Until then it only copies.")).foregroundStyle(.orange)
                        Spacer()
                        Button(tr("Allow…")) { ClipPaster.askForTrust() }
                    }
                }
                Toggle(tr("Paste as plain text"), isOn: $settings.clipPlainText)
                Toggle(tr("Unfold and collapse the picker"), isOn: $settings.clipAnimate)
                SliderRow(tr("Animation speed"), value: $settings.clipAnimationSpeed, in: AppSettings.clipAnimationSpeedRange, step: 0.25, unit: "×")
                    .disabled(!settings.clipAnimate)
                Picker(tr("Who brings it"), selection: Binding(
                    get: { settings.clipHelperEnabled ? settings.clipHelper : Self.nobody },
                    set: { who in
                        settings.clipHelperEnabled = who != Self.nobody
                        if who != Self.nobody { settings.clipHelper = who }
                    })) {
                    Text(tr("Whoever is nearest the middle")).tag("")
                    ForEach(names, id: \.self) { Text($0).tag($0) }
                    Text(tr("Nobody: it unfolds by itself")).tag(Self.nobody)
                }
                .disabled(!settings.clipAnimate)
                Toggle(tr("It says a line as the sheet unfolds"), isOn: $settings.clipHelperTalks)
                    .disabled(!settings.clipAnimate || !settings.clipHelperEnabled)
            } header: {
                Text(tr("Pasting"))
            } footer: {
                Text(tr("⏎ pastes, ⌥⏎ the other way (plain or formatted). A creature brings the sheet and holds its corner; it collapses into the text cursor and the creature leaps back. The paste never waits."))
            }
            .disabled(!settings.clipboardEnabled)
            Section {
                HStack {
                    Text(trCount(clips.snippets.all.count, "snippet", "snippets"))
                    Spacer()
                    Button(tr("Edit Snippets…"), action: editSnippets)
                }
            } header: {
                Text(tr("Snippets"))
            } footer: {
                Text(tr("A protected snippet's words live in the Keychain, never in a file: shown as dots, pasted or shown only after your fingerprint (Touch ID, no password instead), kept out of the history and taken off the clipboard a second after pasting."))
            }
            .disabled(!settings.clipboardEnabled)

            Section {
                Text(settings.clipExcludedApps.isEmpty ? tr("No app.") : settings.clipExcludedApps.map(Self.name).joined(separator: ", "))
                    .fixedSize(horizontal: false, vertical: true)
                HStack {
                    Button(tr("Add App…"), action: addApp)
                    Menu(tr("Remove")) {
                        ForEach(settings.clipExcludedApps, id: \.self) { app in
                            Button(Self.name(of: app)) { settings.clipExcludedApps.removeAll { $0 == app } }
                        }
                    }
                    .fixedSize()
                    .disabled(settings.clipExcludedApps.isEmpty)
                    Spacer()
                    Button(tr("Clear History (%d)", clips.history.clips.filter { !$0.pinned }.count)) { clips.clearHistory() }
                }
            } header: {
                Text(tr("Never kept"))
            } footer: {
                Text(tr("Nothing copied in these apps is kept, nor anything a password manager marks as secret. Clear History keeps pinned copies."))
            }
            .disabled(!settings.clipboardEnabled)
        }
        .onAppear { trusted = ClipPaster.trusted }
    }

    /// The picker's tag for no creature at all: not a name anyone can have.
    private static let nobody = "\u{0}nobody"

    /// Everyone on screen, by name, each once; a chosen one no longer there is kept in the list.
    private var names: [String] {
        var all: [String] = []
        for i in 0..<settings.creatureCount {
            let name = settings.character(forCreature: i, library: library).name
            if !all.contains(name) { all.append(name) }
        }
        if !settings.clipHelper.isEmpty, !all.contains(settings.clipHelper) { all.append(settings.clipHelper) }
        return all
    }

    /// The password managers excluded by default, by name, for when they are not installed here.
    static let knownNames = [
        "com.1password.1password": "1Password", "com.agilebits.onepassword7": "1Password 7", "com.bitwarden.desktop": "Bitwarden",
        "org.keepassxc.keepassxc": "KeePassXC", "com.apple.keychainaccess": "Keychain Access", "com.apple.Passwords": "Passwords",
        "com.lastpass.LastPass": "LastPass", "com.dashlane.dashlanephonefinal": "Dashlane", "in.sinew.Enpass-Desktop": "Enpass",
        "com.markmcguill.strongbox.mac": "Strongbox",
    ]

    /// The app's name when it is installed, else its known name, else its bundle id.
    static func name(of bundleID: String) -> String {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return knownNames[bundleID] ?? bundleID }
        return FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
    }

    private func addApp() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        guard panel.runModal() == .OK, let url = panel.url, let id = Bundle(url: url)?.bundleIdentifier,
              !settings.clipExcludedApps.contains(id) else { return }
        settings.clipExcludedApps.append(id)
    }
}
