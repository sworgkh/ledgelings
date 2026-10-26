import AppKit
import LedgelingsCore
import SwiftUI
import UniformTypeIdentifiers

/// Settings › Sprites: which creature sheets are in use, and the sprite kit: a
/// small form, a prompt built from it for an image model, the two pictures to
/// attach, and the import that reads back whatever picture the model paints.
struct SpritesSettingsView: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject var library: SpriteLibrary
    @ObservedObject var spend: SpendLedger
    @State private var status = ""
    @State private var copied = ""
    @State private var showPrompt = false
    @State private var refining = false
    @State private var refineNote = ""

    var body: some View {
        TwoColumns {
            Section {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 104), spacing: 12)], spacing: 12) {
                    ForEach(library.species) { species in card(species) }
                }
                .padding(.vertical, 4)
                HStack {
                    Button(tr("Open Folder")) { library.openFolder() }
                    Spacer()
                    Text(status).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                }
            } header: {
                SettingsHeader("Creatures")
            } footer: {
                Text(tr("Click a creature to put it in the colony or take it out. Creature 1 wears the first one chosen, creature 2 the second, and so on, starting over when they run out. New ones come from the sprite kit. Imported creatures live in %@.", library.directory.path))
            }
        } right: {
            form
            pictures
        }
    }

    // MARK: The form

    private var form: some View {
        Section {
            VStack(alignment: .leading, spacing: 8) {
                TextField(tr("What it is"), text: $settings.spriteKitForm.kind,
                          prompt: Text(tr("What it is: a fat green frog with big eyes")), axis: .vertical)
                    .lineLimit(1...2)
                HStack {
                    TextField(tr("Name"), text: $settings.spriteKitForm.name, prompt: Text(tr("Name (the model chooses)")))
                    Text(tr("Own colour")).fixedSize()
                    Toggle(tr("Own colour"), isOn: hasColour)
                    ColorPicker(tr("Body colour"), selection: colour, supportsOpacity: false)
                        .labelsHidden()
                        .disabled(!hasColour.wrappedValue)
                }
                ForEach(0..<SpriteKit.Form.castSize, id: \.self) { i in
                    HStack {
                        TextField(tr("Character %d", i + 1), text: $settings.spriteKitForm.cast[i].name, prompt: Text(tr("Character %d", i + 1)))
                            .frame(width: 120)
                        TextField(tr("Personality"), text: $settings.spriteKitForm.cast[i].persona,
                                  prompt: Text(tr("who they are, how they sound")))
                    }
                }
                HStack {
                    Button(tr("Refine with AI")) { Task { await refine() } }
                        .disabled(refining || !canRefine)
                    if refining { ProgressView().controlSize(.small) }
                    Text(refineNote).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                    Spacer()
                    Button(tr("Clear")) { settings.spriteKitForm = SpriteKit.Form(); refineNote = "" }
                }
            }
            .textFieldStyle(.roundedBorder)
            .labelsHidden()
        } header: {
            SettingsHeader("Sprite kit: the new creature")
        } footer: {
            Text(tr("Anything empty is the model's to choose. On import the name, colour and characters come from here; the picture gives only the looks.")
                 + " " + (canRefine
                     ? tr("Refine with AI turns your words into a whole creature in Blocky's style, with three characters who say how they sound: one OpenRouter call with the Talk tab's model (Costs › Sprite kit: Refine with AI).")
                     : tr("Refine with AI needs an OpenRouter key (Settings › Talk), with OpenRouter as the brain or the voice.")))
        }
    }

    private var canRefine: Bool { settings.openRouterConnected }

    private func refine() async {
        guard let client = settings.refineClient() else { refineNote = tr("Refine with AI needs an OpenRouter key (Settings › Talk), with OpenRouter as the brain or the voice."); return }
        refining = true
        refineNote = ""
        defer { refining = false }
        do {
            settings.spriteKitForm = try await SpriteKitRefine.refine(settings.spriteKitForm, client: client, spend: spend)
            refineNote = tr("refined; edit anything you like")
        } catch {
            refineNote = "\(error)"
        }
    }

    private var hasColour: Binding<Bool> {
        Binding(
            get: { settings.spriteKitForm.tint != nil },
            set: { on in settings.spriteKitForm.colour = on ? (settings.spriteKitForm.tint?.hex ?? "#6cbf4a") : "" }
        )
    }

    private var colour: Binding<Color> {
        Binding(
            get: {
                let t = settings.spriteKitForm.tint ?? SpriteText.Tint(hex: "#6cbf4a")!
                return Color(.sRGB, red: Double(t.r) / 255, green: Double(t.g) / 255, blue: Double(t.b) / 255)
            },
            set: { picked in
                guard let c = NSColor(picked).usingColorSpace(.sRGB) else { return }
                func byte(_ v: CGFloat) -> UInt8 { UInt8(max(0, min(255, (v * 255).rounded()))) }
                settings.spriteKitForm.colour = SpriteText.Tint(r: byte(c.redComponent), g: byte(c.greenComponent), b: byte(c.blueComponent)).hex
            }
        )
    }

    // MARK: The pictures and the prompt

    private var pictures: some View {
        Section {
            ForEach(Array(library.kitImages.enumerated()), id: \.offset) { _, item in
                Image(nsImage: Self.nsImage(item.image))
                    .interpolation(.none)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .help(item.name)
            }
            HStack {
                Button(copied == "prompt" ? tr("Copied") : tr("Copy Prompt")) { copyPrompt() }
                Button(tr("Show")) { showPrompt.toggle() }
                    .popover(isPresented: $showPrompt, arrowEdge: .bottom) {
                        ScrollView {
                            Text(verbatim: library.prompt(settings.spriteKitForm))
                                .font(.callout)
                                .textSelection(.enabled)
                                .padding()
                        }
                        .frame(width: 560, height: 520)
                    }
                Spacer()
                Button(tr("Import…")) { importSheet() }
            }
            HStack {
                Button(tr("Save Images…")) { saveImages() }
                Button(copied == "images" ? tr("Copied") : tr("Copy Images")) { copyImages() }
                Spacer()
            }
        } header: {
            SettingsHeader("Ask an image model")
        } footer: {
            Text(tr("Give an image model (ChatGPT, Gemini…) the prompt and both pictures, in order: 1 the poses to copy, 2 the sheet to paint on. Import… what it paints, at any size; a text sheet (.txt) imports too."))
        }
    }

    private func copyPrompt() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(library.prompt(settings.spriteKitForm), forType: .string)
        flash("prompt")
    }

    /// The two pictures as files, the way Finder copies them, so a chat in the browser takes both at one paste.
    private func copyImages() {
        do {
            let files = try library.saveKitImages(to: FileManager.default.temporaryDirectory.appendingPathComponent("ledgelings-sprite-kit"))
            NSPasteboard.general.clearContents()
            NSPasteboard.general.writeObjects(files as [NSURL])
            flash("images")
        } catch { status = "\(error)" }
    }

    private func flash(_ what: String) {
        copied = what
        Task { try? await Task.sleep(for: .seconds(2)); if copied == what { copied = "" } }
    }

    private func saveImages() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.prompt = tr("Save Here")
        panel.message = tr("A folder for 1-poses.png and 2-template.png.")
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, let folder = panel.url else { return }
        do { try library.saveKitImages(to: folder); status = tr("saved %@", folder.lastPathComponent) } catch { status = "\(error)" }
    }

    private func importSheet() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.png, .jpeg, .webP, .plainText, UTType(filenameExtension: "md") ?? .plainText]
        panel.message = tr("The picture the image model painted, or a hand-written text sheet.")
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let name = try library.importFile(url, form: settings.spriteKitForm)
            if !settings.species.contains(name) { settings.species.append(name) }
            status = tr("imported %@", name)
        } catch {
            status = "\(error)"
        }
    }

    static func nsImage(_ image: SpriteText.Image) -> NSImage {
        var bytes = image.rgba
        let cg: CGImage? = bytes.withUnsafeMutableBytes { raw in
            CGContext(data: raw.baseAddress, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: image.width * 4,
                      space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)?.makeImage()
        }
        return cg.map { NSImage(cgImage: $0, size: NSSize(width: image.width, height: image.height)) } ?? NSImage()
    }

    // MARK: Cards

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
                        .buttonStyle(.borderless).help(tr("Delete this imported creature"))
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
        // In its own colour when the sheet chose one, otherwise as painted.
        let own = atlas.meta.colour.flatMap(RGB.init(hex:))
        guard let cg = atlas.frames(body: own).frame(animation: "idle", time: 0) else { return NSImage() }
        return NSImage(cgImage: cg, size: NSSize(width: 32, height: 32))
    }
}
