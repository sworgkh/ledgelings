import AppKit
import LedgelingsCore
import SwiftUI
import UniformTypeIdentifiers

/// Settings › Sprites: which creature sheets are in use, importing new ones,
/// and the sprite kit: a prompt for any chat model plus a template for image models.
struct SpritesSettingsView: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject var library: SpriteLibrary
    @State private var status = ""
    @State private var copied = false

    var body: some View {
        Form {
            Section {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 104), spacing: 12)], spacing: 12) {
                    ForEach(library.species) { species in card(species) }
                }
                .padding(.vertical, 4)
                HStack {
                    Button("Import Sheet…") { importSheet() }
                    Button("Open Folder") { library.openFolder() }
                    Spacer()
                    Text(status).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                }
            } header: {
                Text("Creatures")
            } footer: {
                Text("Click a creature to put it in the colony or take it out. Creature 1 wears the first one chosen, creature 2 the second, and so on, starting over when they run out. Import a text sheet (.txt) from the kit below, or a 288×96 PNG painted on magenta from the template. Sheets live in \(library.directory.path).")
            }

            Section {
                Text("Copy the prompt, paste it into any chat model, replace the placeholder with a description of the creature you want, and save the model's answer as a .txt file. Then Import Sheet…")
                    .font(.callout)
                HStack {
                    Button(copied ? "Copied" : "Copy Prompt") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(library.prompt, forType: .string)
                        copied = true
                        Task { try? await Task.sleep(for: .seconds(2)); copied = false }
                    }
                    Button("Save Example Sheet…") { saveText(library.exampleText, as: "blocky.txt") }
                    Button("Save PNG Template…") { savePNG(library.templateImage(), as: "ledgelings-template.png") }
                }
                TextEditor(text: .constant(library.prompt))
                    .font(.system(.caption, design: .monospaced))
                    .frame(minHeight: 220)
                    .scrollContentBackground(.hidden)
                    .padding(4)
                    .background(RoundedRectangle(cornerRadius: 6).fill(Color(nsColor: .textBackgroundColor)))
            } header: {
                Text("Sprite kit")
            } footer: {
                Text("The example sheet is the built-in creature written in the same letters: a good thing to show the model, or to edit by hand. The PNG template marks the cells and the body box for an image model or a paint program; the app cuts the magenta away on import.")
            }
        }
        .formStyle(.grouped)
    }

    /// One creature: its idle pose at 3×, its name, a check when it is in the colony.
    private func card(_ species: SpriteLibrary.Species) -> some View {
        let chosen = settings.species.contains(species.name)
        return Button { toggle(species.name) } label: {
            VStack(spacing: 6) {
                ZStack(alignment: .topTrailing) {
                    Image(nsImage: preview(species.atlas))
                        .interpolation(.none)
                        .resizable()
                        .frame(width: 96, height: 96)
                    Image(systemName: chosen ? "checkmark.circle.fill" : "circle")
                        .font(.title2)
                        .foregroundStyle(chosen ? Color.accentColor : Color.secondary.opacity(0.5))
                        .padding(4)
                }
                HStack(spacing: 4) {
                    Text(species.name).font(.callout.weight(chosen ? .semibold : .regular)).lineLimit(1)
                    if !species.isBuiltIn {
                        Button { library.remove(species.name); settings.species.removeAll { $0 == species.name } } label: {
                            Image(systemName: "trash").font(.caption)
                        }
                        .buttonStyle(.borderless).help("Delete this imported creature")
                    }
                }
            }
            .padding(8)
            .frame(maxWidth: .infinity)
            .background(RoundedRectangle(cornerRadius: 10).fill(chosen ? Color.accentColor.opacity(0.14) : Color(nsColor: .controlBackgroundColor)))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(chosen ? Color.accentColor : Color.clear, lineWidth: 2))
        }
        .buttonStyle(.plain)
    }

    private func toggle(_ name: String) {
        if settings.species.contains(name) { settings.species.removeAll { $0 == name } }
        else { settings.species.append(name) }
    }

    private func preview(_ atlas: SpriteAtlas) -> NSImage {
        guard let cg = atlas.frames().frame(animation: "idle", time: 0) else { return NSImage() }
        return NSImage(cgImage: cg, size: NSSize(width: 32, height: 32))
    }

    private func importSheet() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.plainText, .png, UTType(filenameExtension: "md") ?? .plainText]
        panel.message = "A sprite text file from the kit, or a 288×96 PNG on magenta."
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let name = try library.importFile(url)
            if !settings.species.contains(name) { settings.species.append(name) }
            status = "imported \(name)"
        } catch {
            status = "\(error)"
        }
    }

    private func saveText(_ text: String, as name: String) {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = name
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do { try text.write(to: url, atomically: true, encoding: .utf8); status = "saved \(url.lastPathComponent)" } catch { status = "\(error)" }
    }

    private func savePNG(_ image: SpriteText.Image, as name: String) {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = name
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do { try SpriteLibrary.writePNG(image, to: url); status = "saved \(url.lastPathComponent)" } catch { status = "\(error)" }
    }
}
