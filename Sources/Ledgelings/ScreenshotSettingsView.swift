import AppKit
import LedgelingsCore
import SwiftUI

/// Settings › Productivity tools › Screenshots: the tool and its shortcuts on the
/// left; where a shot goes, how marks look and what the creatures do on the right.
struct ScreenshotSettingsView: View {
    @ObservedObject var settings: AppSettings
    @State private var allowed = ShotCapture.allowed

    var body: some View {
        TwoColumns {
            Section {
                Toggle(tr("Screenshot tool"), isOn: $settings.shotEnabled)
                if !allowed {
                    HStack {
                        Text(tr("Needs Screen Recording, to see the screen. Until then a shot only says so.")).foregroundStyle(.orange)
                        Spacer()
                        Button(tr("Allow…")) { ShotCapture.askForPermission() }
                    }
                }
            } header: {
                Text(tr("Screenshots"))
            } footer: {
                Text(tr("Every screen freezes and dims; drag an area (R), draw a loop (L), or take the screen (W) or all of them (A). Then box (B), arrow (→), highlight (H), blur (X) or blur by hand (F), in six colours (1–6); ⌘Z undoes. ⏎ takes it, ⌘C copies, ⌘S saves, ⎋ lets go. Pictures only, never video; nothing leaves this Mac."))
            }

            Section {
                LabeledContent(tr("Capture with the toolbar")) {
                    HStack {
                        Toggle("", isOn: $settings.shotCaptureShortcutEnabled).labelsHidden()
                        ShortcutRecorder(settings: settings, shortcut: $settings.shotCaptureShortcut)
                    }
                }
                LabeledContent(tr("Full screen at once")) {
                    HStack {
                        Toggle("", isOn: $settings.shotFullShortcutEnabled).labelsHidden()
                        ShortcutRecorder(settings: settings, shortcut: $settings.shotFullShortcut)
                    }
                }
                Picker(tr("Full screen takes"), selection: $settings.shotFullScope) {
                    Text(tr("All screens, in one picture")).tag(Shot.FullScope.allScreens)
                    Text(tr("The screen under the cursor")).tag(Shot.FullScope.screenUnderCursor)
                }
                LabeledContent(tr("The last rectangle again")) {
                    HStack {
                        Toggle("", isOn: $settings.shotLastShortcutEnabled).labelsHidden()
                        ShortcutRecorder(settings: settings, shortcut: $settings.shotLastShortcut)
                    }
                }
                if !settings.shotShortcutProblem.isEmpty {
                    Text(settings.shotShortcutProblem).foregroundStyle(.red)
                }
            } header: {
                Text(tr("Shortcuts"))
            } footer: {
                Text(tr("They work in every app. Full screen and the last rectangle go straight to the clipboard or the folder, with no toolbar; with no rectangle taken yet, the last-rectangle keys open the toolbar. All monitors are stitched at each one's own sharpness."))
            }
            .disabled(!settings.shotEnabled)
        } right: {
            Section {
                Toggle(tr("Copy to the clipboard"), isOn: $settings.shotCopy)
                Toggle(tr("Save to a folder"), isOn: $settings.shotSave)
                LabeledContent(tr("Folder")) {
                    HStack {
                        Text(settings.shotFolder).lineLimit(1).truncationMode(.middle)
                        Button(tr("Choose…"), action: chooseFolder)
                        Button(tr("Show")) {
                            let path = Shot.folderPath(settings.shotFolder)
                            if FileManager.default.fileExists(atPath: path) { NSWorkspace.shared.open(URL(fileURLWithPath: path)) } else { NSSound.beep() }
                        }
                    }
                }
            } header: {
                Text(tr("Where a shot goes"))
            } footer: {
                Text(tr("As a PNG named for its time (Screenshot 2026-10-18 14.03.22.png); the folder is made on the first save. ⌘C on the toolbar only copies, ⌘S always saves. A copy also lands in the clipboard history."))
            }
            .disabled(!settings.shotEnabled)

            Section {
                SliderRow(tr("Line thickness"), value: Binding(get: { Double(settings.shotThickness) }, set: { settings.shotThickness = Int($0) }),
                          in: Double(Shot.thicknessRange.lowerBound)...Double(Shot.thicknessRange.upperBound), step: 1, unit: tr(" pt"))
                LabeledContent(tr("Colour")) { ShotSwatches(colour: $settings.shotColour) }
            } header: {
                Text(tr("Marks"))
            } footer: {
                Text(tr("Boxes and arrows are this thick; blurring by hand is four times as wide. A blur is big square blocks, baked into the picture, so the words under it cannot be read back. The toolbar starts on the last colour picked."))
            }
            .disabled(!settings.shotEnabled)

            Section {
                Toggle(tr("Hide the creatures while capturing"), isOn: $settings.shotHideCreatures)
                Toggle(tr("A creature brings the shot home"), isOn: $settings.shotCreatureBrings)
            } header: {
                Text(tr("Creatures"))
            } footer: {
                Text(tr("Hidden, they are out of the picture too. Once it is taken, one hops up to where the toolbar was and carries a tiny picture of it back to its edge."))
            }
            .disabled(!settings.shotEnabled)
        }
        .onAppear { allowed = ShotCapture.allowed }
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = tr("Choose")
        let path = Shot.folderPath(settings.shotFolder)
        panel.directoryURL = URL(fileURLWithPath: FileManager.default.fileExists(atPath: path) ? path : NSHomeDirectory())
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let home = NSHomeDirectory()
        settings.shotFolder = url.path.hasPrefix(home + "/") ? "~" + url.path.dropFirst(home.count) : url.path
    }
}

/// The six colours as pixel squares, each on a pixel plate, the chosen one on the orange: the toolbar's and the settings'.
struct ShotSwatches: View {
    @Binding var colour: Int
    var pick: ((Int) -> Void)? = nil

    var body: some View {
        HStack(spacing: 2) {
            ForEach(Shot.palette.indices, id: \.self) { n in
                let c = Shot.palette[n]
                Button { if let pick { pick(n) } else { colour = n } } label: {
                    Rectangle().fill(Color(red: Double(c.r) / 255, green: Double(c.g) / 255, blue: Double(c.b) / 255))
                        .frame(width: 14, height: 14)
                        .padding(2).background(PixelBox.rim)
                        .frame(width: 30, height: 30)
                        .background(PixelBox(style: colour == n ? .chosen : .raised))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(tr("Colour %d", n + 1))
            }
        }
    }
}
