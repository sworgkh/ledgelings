import AppKit
import LedgelingsCore

/// `--clip-demo`: the clipboard manager end to end on the real pasteboard, every
/// step printed with its time. A picture is copied (PNG and TIFF) and kept as
/// files beside the history. Two copies are made as if in another app and the
/// watcher keeps them; one is copied again in a password manager's way and must
/// not be kept; the history picker opens, a search narrows it, one is chosen; the
/// snippets picker opens and a protected snippet is chosen, which must go on the
/// pasteboard concealed, stay out of the history and leave again. Last, a search for
/// "image" finds the picture and choosing it puts the same PNG and TIFF back. Then the
/// Wi-Fi password is copied the ordinary way, as from a note: it is kept, but shown
/// and found only as `PWD:Wi-Fi password: [16] chars`, and choosing it pastes the words.
///
/// It keeps its own history and snippets in a folder of its own, its secret under
/// a keychain service of its own that it empties at the end, and puts back what
/// was on the pasteboard. It never presses ⌘V. `--snapshot out.png` writes the
/// history picker as it looks after the search, and `out.masked.png` with the masked copy.
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
        let (png, tiff) = picture()
        pasteboard.clearContents()
        let shot = NSPasteboardItem()
        shot.setData(png, forType: .png)
        shot.setData(tiff, forType: .tiff)
        pasteboard.writeObjects([shot])
        log("copy a picture: \(png.count) bytes of PNG, \(tiff.count) of TIFF")
        watcher.look()
        try? await Task.sleep(for: .milliseconds(100))
        let image = book.history.clips.first { $0.kind == .image }
        let files = image.map { clip in clip.picture?.types.filter { FileManager.default.fileExists(atPath: book.store.imageFile(clip.id, $0).path) } ?? [] } ?? []
        log("history: \(image.map { "\"\($0.text)\", files \(files.joined(separator: " + "))" } ?? "NO PICTURE ✗")")
        var ok = image?.text == "Image 48×30" && files == ["public.png", "public.tiff"]

        await copy("Meeting notes: ship the clipboard on Friday")
        await copy("invoice #4821 for the café")
        await copy("hunter2", concealed: true)
        await copy("invoice #4821 for the café")
        ok = ok && book.history.clips.filter { $0.kind != .image }.map(\.text) == ["invoice #4821 for the café", "Meeting notes: ship the clipboard on Friday"]
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
        log("protected snippets always ask for a fingerprint; a script has no finger, so the demo pastes without")
        _ = picker.key(36, [])
        try? await Task.sleep(for: .milliseconds(200))
        let types = pasteboard.types?.map(\.rawValue) ?? []
        log("pasteboard now \"\(pasteboard.string(forType: .string) ?? "-")\", concealed \(types.contains(ClipPaster.concealed.rawValue))")
        ok = ok && pasteboard.string(forType: .string) == "pixel-perfect-42" && types.contains(ClipPaster.concealed.rawValue)
        try? await Task.sleep(for: .milliseconds(1400))
        watcher.look()
        let restored = pasteboard.string(forType: .string)
        log("a second later: pasteboard \"\(restored ?? "-")\", secret in history \(book.history.clips.contains { $0.text == "pixel-perfect-42" })")
        ok = ok && restored == "Meeting notes: ship the clipboard on Friday" && !book.history.clips.contains { $0.text == "pixel-perfect-42" }

        picker.show(.recent)
        try? await Task.sleep(for: .milliseconds(300))
        picker.model.query = "image"
        log("search \"image\": \(picker.model.rows.map { "\"\($0.text)\" \($0.thumbnail.map { "thumbnail \(Int($0.size.width))×\(Int($0.size.height))" } ?? "no thumbnail")" }.joined(separator: ", "))")
        ok = ok && picker.model.rows.count == 1 && picker.model.rows.first?.thumbnail != nil
        _ = picker.key(36, [])
        try? await Task.sleep(for: .milliseconds(300))
        let back = (pasteboard.types ?? []).map(\.rawValue).filter { $0.hasPrefix("public.") }
        let same = pasteboard.data(forType: .png) == png && pasteboard.data(forType: .tiff) == tiff
        log("pasteboard now \(back.joined(separator: " + ")), the same bytes \(same), words \(pasteboard.string(forType: .string) == nil ? "none" : "SOME ✗")")
        ok = ok && same && pasteboard.string(forType: .string) == nil

        pasteboard.clearContents()
        pasteboard.setString("pixel-perfect-42", forType: .string)
        log("copy the Wi-Fi password, unmarked, as from a note")
        watcher.look()
        picker.show(.recent)
        try? await Task.sleep(for: .milliseconds(300))
        picker.model.query = "pixel"
        let byWords = picker.model.rows.filter { $0.group == .recent }.count
        picker.model.query = "pwd wi-fi"
        let masked = picker.model.rows.first { $0.group == .recent }
        log("search \"pixel\": \(byWords) copies; \"pwd wi-fi\": \(masked.map { "\"\($0.text)\"\($0.masked ? ", tinted" : "")" } ?? "nothing")")
        ok = ok && byWords == 0 && masked?.text == "PWD:Wi-Fi password: [16] chars" && masked?.masked == true
        if let snapshot {
            picker.model.query = ""
            try? await Task.sleep(for: .milliseconds(300))
            let masked = snapshot.deletingPathExtension().appendingPathExtension("masked.png")
            do { try picker.snapshot(to: masked); log("snapshot \(masked.path)") } catch { log("snapshot failed: \(error)") }
        }
        if let masked { picker.choose(masked) }
        try? await Task.sleep(for: .milliseconds(300))
        let words = pasteboard.string(forType: .string) == "pixel-perfect-42"
        log("pasteboard now the real words \(words), concealed \(pasteboard.types?.contains(ClipPaster.concealed) == true)")
        ok = ok && words
        log(ok ? "all well" : "SOMETHING IS WRONG")
        return ok
    }

    /// A small picture in the creatures' palette: 48×30, as PNG and as TIFF.
    static func picture() -> (png: Data, tiff: Data) {
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 48, pixelsHigh: 30, bitsPerSample: 8, samplesPerPixel: 4,
                                   hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        NSColor(red: 0.96, green: 0.95, blue: 0.9, alpha: 1).setFill()
        CGRect(x: 0, y: 0, width: 48, height: 30).fill()
        NSColor(red: 0.95, green: 0.6, blue: 0.2, alpha: 1).setFill()
        CGRect(x: 8, y: 6, width: 16, height: 16).fill()
        NSColor(red: 0.3, green: 0.55, blue: 0.85, alpha: 1).setFill()
        CGRect(x: 28, y: 10, width: 12, height: 12).fill()
        NSGraphicsContext.restoreGraphicsState()
        return (rep.representation(using: .png, properties: [:])!, rep.tiffRepresentation!)
    }
}
