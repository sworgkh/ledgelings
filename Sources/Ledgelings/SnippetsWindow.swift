import AppKit
import LedgelingsCore
import SwiftUI
import UniformTypeIdentifiers

/// Edit Snippets…: the folders and snippets on the left, the chosen one on the
/// right. Add, rename, move up and down, delete; import Clipy's XML and export
/// it. A protected snippet shows dots until Show is pressed (Touch ID first, when
/// the setting asks), and its words go to the keychain, never to the file.
@MainActor
final class SnippetsWindowController {
    static let size = CGSize(width: 860, height: 540)
    private let settings: AppSettings
    private let book: ClipBook
    private var window: NSWindow?

    init(settings: AppSettings, book: ClipBook) {
        self.settings = settings
        self.book = book
    }

    func show() {
        if window == nil {
            let made = NSWindow(contentViewController: NSHostingController(rootView: SnippetsView(settings: settings, book: book)))
            made.title = tr("Snippets")
            made.styleMask = [.titled, .closable, .resizable]
            made.isReleasedWhenClosed = false
            made.setContentSize(Self.size)
            made.center()
            window = made
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    func snapshot(to url: URL) throws {
        guard let view = window?.contentView, let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
        view.cacheDisplay(in: view.bounds, to: rep)
        try rep.representation(using: .png, properties: [:])?.write(to: url)
    }
}

struct SnippetsView: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject var book: ClipBook
    @State private var selected: UUID?
    @State private var problem = ""

    var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                List(selection: $selected) {
                    ForEach(book.snippets.folders) { folder in
                        Label(folder.title.isEmpty ? tr("Untitled folder") : folder.title, systemImage: "folder")
                            .font(.headline).tag(folder.id)
                        ForEach(folder.snippets) { snippet in
                            Label(snippet.title.isEmpty ? tr("Untitled snippet") : snippet.title,
                                  systemImage: snippet.protected ? "lock" : "text.alignleft")
                                .padding(.leading, 18).tag(snippet.id)
                        }
                    }
                }
                Divider()
                buttons.padding(8)
            }
            .frame(width: 300)
            Divider()
            editor.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading).padding(16)
        }
        .frame(minWidth: 700, minHeight: 420)
    }

    private var buttons: some View {
        HStack(spacing: 6) {
            Button(tr("+ Folder")) { selected = book.addFolder(tr("New folder")) }
            Button(tr("+ Snippet")) {
                let folder = book.snippets.folders.first { $0.id == selected }?.id ?? selected.flatMap { book.snippets.folder(of: $0)?.id }
                selected = book.addSnippet(title: tr("New snippet"), text: "", to: folder)
            }
            Button { if let selected { book.removeSnippetOrFolder(selected); self.selected = nil } } label: { Image(systemName: "minus") }
                .disabled(selected == nil)
                .help(tr("Delete the folder or snippet; a folder goes with everything in it"))
            Button { if let selected { book.move(selected, by: -1) } } label: { Image(systemName: "arrow.up") }.disabled(selected == nil)
            Button { if let selected { book.move(selected, by: 1) } } label: { Image(systemName: "arrow.down") }.disabled(selected == nil)
            Spacer()
            Menu(tr("File")) {
                Button(tr("Import Clipy Snippets…"), action: importClipy)
                Button(tr("Export as Clipy XML…"), action: exportClipy)
            }
            .fixedSize()
        }
    }

    @ViewBuilder private var editor: some View {
        if let id = selected, let folder = book.snippets.folders.first(where: { $0.id == id }) {
            Form {
                TextField(tr("Folder name"), text: Binding(get: { folder.title }, set: { book.renameFolder(id, to: $0) }))
                Text(trCount(folder.snippets.count, "snippet", "snippets")).foregroundStyle(.secondary)
            }
        } else if let id = selected, let snippet = book.snippets.snippet(id) {
            SnippetEditor(settings: settings, book: book, snippet: snippet).id(id)
        } else {
            VStack(alignment: .leading, spacing: 10) {
                Text(tr("Choose a snippet, or add one with + Snippet.")).foregroundStyle(.secondary)
                Text(tr("Paste them from any app with %@: type to search, ⏎ to paste.", GlobalShortcut.label(settings.clipSnippetsShortcut)))
                    .foregroundStyle(.secondary)
                if !problem.isEmpty { Text(problem).foregroundStyle(.red) }
            }
        }
    }

    private func importClipy() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.xml]
        panel.message = tr("Choose the XML file Clipy's Snippets editor exported.")
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do { problem = tr("%d snippets imported.", try book.importClipy(from: url)) }
        catch { problem = tr("That file is not Clipy's snippets XML.") }
        selected = nil
    }

    private func exportClipy() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.xml]
        panel.nameFieldStringValue = "snippets.xml"
        panel.message = tr("Protected snippets are exported with their titles only.")
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do { try book.exportClipy(to: url); problem = tr("Exported.") } catch { problem = error.localizedDescription }
        selected = nil
    }
}

/// One snippet: its title, its words (or its secret), protected or not, its own shortcut.
struct SnippetEditor: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject var book: ClipBook
    let snippet: Clipboard.Snippet
    @State private var title = ""
    @State private var text = ""
    /// A protected snippet's words, shown after Show.
    @State private var revealed = false
    @State private var saving: Task<Void, Never>?

    var body: some View {
        Form {
            TextField(tr("Title"), text: $title)
                .onChange(of: title) { _, _ in save() }
            Toggle(tr("Protected: kept in the Keychain, shown as dots, asks before pasting"), isOn: Binding(
                get: { book.snippets.snippet(snippet.id)?.protected ?? false },
                set: { on in
                    saveNow()
                    book.setProtected(snippet.id, on)
                    revealed = false
                    if !on { text = book.snippets.snippet(snippet.id)?.text ?? "" }
                }))
            LabeledContent(tr("Shortcut")) {
                HStack {
                    ShortcutRecorder(settings: settings, optional: Binding(
                        get: { book.snippets.snippet(snippet.id)?.shortcut },
                        set: { change { $0.shortcut = $1 }($0) }))
                    if book.snippets.snippet(snippet.id)?.shortcut != nil {
                        Button(tr("Clear")) { change { $0.shortcut = $1 }(nil) }
                    }
                }
            }
            if current.protected && !revealed {
                LabeledContent(tr("Words")) {
                    HStack {
                        Text(Clipboard.mask).monospaced()
                        Button(tr("Show…"), action: reveal)
                    }
                }
            } else {
                TextEditor(text: $text)
                    .font(.body.monospaced())
                    .frame(minHeight: 240)
                    .onChange(of: text) { _, _ in save() }
            }
        }
        .onAppear {
            title = snippet.title
            text = snippet.protected ? "" : snippet.text
        }
        .onDisappear(perform: saveNow)
    }

    private var current: Clipboard.Snippet { book.snippets.snippet(snippet.id) ?? snippet }

    private func change(_ edit: @escaping (inout Clipboard.Snippet, Shortcut?) -> Void) -> (Shortcut?) -> Void {
        { value in
            var s = current
            edit(&s, value)
            book.update(s)
        }
    }

    private func reveal() {
        Task { @MainActor in
            if settings.clipProtectedNeedsAuth, !(await OwnerCheck.confirm(tr("show the protected snippet “%@”", current.title))) { return }
            text = book.words(of: current)
            revealed = true
        }
    }

    /// A moment after the last keystroke, so the keychain is not written on every letter.
    private func save() {
        saving?.cancel()
        saving = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }
            saveNow()
        }
    }

    private func saveNow() {
        saving?.cancel()
        var s = current
        s.title = title
        if s.protected {
            guard s.title != current.title || revealed else { return }
            book.update(s, secret: revealed ? text : nil)
        } else {
            s.text = text
            if s != current { book.update(s) }
        }
    }
}
