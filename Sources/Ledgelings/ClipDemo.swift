import AppKit
import LedgelingsCore

/// `--clip-demo`: the clipboard manager end to end on the real pasteboard, every
/// step printed with its time. Two copies are made as if in another app and the
/// watcher keeps them; one is copied again in a password manager's way and must
/// not be kept; the history picker opens, a search narrows it, one is chosen; the
/// snippets picker opens and a protected snippet is chosen, which must go on the
/// pasteboard concealed, stay out of the history and leave again.
///
/// It keeps its own history and snippets in a folder of its own, its secret under
/// a keychain service of its own that it empties at the end, and puts back what
/// was on the pasteboard. It never presses ⌘V. `--snapshot out.png` writes the
/// history picker as it looks after the search.
@MainActor
enum ClipDemo {
    static func run(settings: AppSettings, snapshot: URL?) async -> Bool {
        let start = Date()
        func log(_ line: String) { FileHandle.standardError.write(Data(String(format: "clip %6.2f  %@\n", Date().timeIntervalSince(start), line).utf8)) }
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("ledgelings-clip-demo-\(UUID().uuidString)")
        let secrets = Keychain(service: "Ledgelings Snippets demo")
        let book = ClipBook(directory: folder, secrets: secrets)
        let before = ClipPaster.saved()
        defer {
            for (_, s) in book.snippets.all where s.protected { secrets.set(nil, for: s.secretAccount) }
            try? FileManager.default.removeItem(at: folder)
            ClipPaster.restore(before)
            log("pasteboard and keychain put back")
        }
        let watcher = ClipWatcher(settings: settings, book: book)
        watcher.trace = { log("watch: \($0)") }
        let picker = ClipPickerController(settings: settings, book: book, watcher: { watcher }, editSnippets: {})
        picker.trace = { log("picker: \($0)") }
        picker.pressKeys = false
        picker.askOwner = false
        let pasteboard = NSPasteboard.general

        func copy(_ text: String, concealed: Bool = false) async {
            pasteboard.clearContents()
            let item = NSPasteboardItem()
            item.setString(text, forType: .string)
            if concealed { item.setString("", forType: ClipPaster.concealed) }
            pasteboard.writeObjects([item])
            log("copy \"\(text)\"\(concealed ? " (concealed)" : "")")
            watcher.look()
            try? await Task.sleep(for: .milliseconds(100))
        }
        await copy("Meeting notes: ship the clipboard on Friday")
        await copy("invoice #4821 for the café")
        await copy("hunter2", concealed: true)
        await copy("invoice #4821 for the café")
        var ok = book.history.clips.map(\.text) == ["invoice #4821 for the café", "Meeting notes: ship the clipboard on Friday"]
        log("history: \(book.history.clips.count) clips, newest \"\(book.history.clips.first?.preview(30) ?? "-")\"\(ok ? "" : "  ✗ expected 2, deduped, no concealed")")

        let work = book.addFolder("Work")
        book.addSnippet(title: "Signature", text: "Best regards,\nThe Ledgelings", to: work)
        let secretID = book.addSnippet(title: "Wi-Fi password", text: "pixel-perfect-42", protected: true, to: work)
        log("snippets: \(book.snippets.all.count), protected one kept \(book.snippets.snippet(secretID)?.text.isEmpty == true ? "only in the keychain" : "IN THE FILE ✗")")

        picker.show(.recent)
        try? await Task.sleep(for: .milliseconds(300))
        picker.model.query = "cafe invoice"
        log("search \"cafe invoice\": \(picker.model.rows.map { "\($0.group == .recent ? "recent" : "snippet") \"\($0.title ?? $0.text)\"" }.joined(separator: ", "))")
        ok = ok && picker.model.rows.count == 1
        picker.model.query = ""
        log("all: \(picker.model.counts.recent) recent, \(picker.model.counts.snippets) snippets")
        _ = picker.key(48, [])           // ⇥
        log("⇥ to \(picker.model.selectedRow?.title ?? picker.model.selectedRow?.text ?? "-")")
        _ = picker.key(48, [])
        _ = picker.key(125, [])          // ↓
        log("↓ to \"\(picker.model.selectedRow?.text ?? "-")\"")
        if let snapshot {
            try? await Task.sleep(for: .milliseconds(300))
            do { try picker.snapshot(to: snapshot); log("snapshot \(snapshot.path)") } catch { log("snapshot failed: \(error)") }
        }
        _ = picker.key(36, [])           // ⏎
        try? await Task.sleep(for: .milliseconds(300))
        let pasted = pasteboard.string(forType: .string)
        log("pasteboard now \"\(pasted ?? "-")\"")
        ok = ok && pasted == "Meeting notes: ship the clipboard on Friday" && !picker.isUp
        ok = ok && book.history.clips.first?.text == pasted

        picker.show(.snippets)
        try? await Task.sleep(for: .milliseconds(300))
        picker.model.query = "wifi"
        picker.model.query = "wi-fi"
        log("search \"wi-fi\": \(picker.model.rows.map { "\($0.title ?? "") \($0.text)" }.joined(separator: ", "))")
        if settings.clipProtectedNeedsAuth {
            log("protected snippets ask for Touch ID here; a script cannot press it, so the demo pastes without")
        }
        _ = picker.key(36, [])
        try? await Task.sleep(for: .milliseconds(200))
        let types = pasteboard.types?.map(\.rawValue) ?? []
        log("pasteboard now \"\(pasteboard.string(forType: .string) ?? "-")\", concealed \(types.contains(ClipPaster.concealed.rawValue))")
        ok = ok && pasteboard.string(forType: .string) == "pixel-perfect-42" && types.contains(ClipPaster.concealed.rawValue)
        try? await Task.sleep(for: .milliseconds(1400))
        watcher.look()
        let back = pasteboard.string(forType: .string)
        log("a second later: pasteboard \"\(back ?? "-")\", secret in history \(book.history.clips.contains { $0.text == "pixel-perfect-42" })")
        ok = ok && back == "Meeting notes: ship the clipboard on Friday" && !book.history.clips.contains { $0.text == "pixel-perfect-42" }
        log(ok ? "all well" : "SOMETHING IS WRONG")
        return ok
    }
}
