import Foundation

/// Snippets in and out as Clipy's XML, the file Clipy's Snippets editor exports:
/// `<folders><folder><title/><snippets><snippet><title/><content/></snippet>…`.
/// Someone moving over from Clipy brings their snippets in one go, and an export
/// from here opens in Clipy too.
///
/// A protected snippet is exported with its title and no words: a file on disk is
/// exactly where a password must not end up. It comes back in as an empty snippet.
extension Clipboard {
    public enum ClipyError: Error, Equatable { case notClipyXML }

    public static func importClipy(_ data: Data) throws -> SnippetBook {
        let reader = ClipyReader()
        let parser = XMLParser(data: data)
        parser.delegate = reader
        guard parser.parse(), reader.sawRoot else { throw ClipyError.notClipyXML }
        return SnippetBook(folders: reader.folders)
    }

    public static func exportClipy(_ book: SnippetBook) -> Data {
        var xml = "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n<folders>\n"
        for folder in book.folders {
            xml += "  <folder>\n    <title>\(escape(folder.title))</title>\n    <snippets>\n"
            for snippet in folder.snippets {
                xml += "      <snippet>\n        <title>\(escape(snippet.title))</title>\n"
                xml += "        <content>\(snippet.protected ? "" : escape(snippet.text))</content>\n      </snippet>\n"
            }
            xml += "    </snippets>\n  </folder>\n"
        }
        return Data((xml + "</folders>\n").utf8)
    }

    static func escape(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;").replacingOccurrences(of: "\"", with: "&quot;")
    }
}

private final class ClipyReader: NSObject, XMLParserDelegate {
    var folders: [Clipboard.Folder] = []
    var sawRoot = false
    private var path: [String] = []
    private var text = ""
    private var folder: Clipboard.Folder?
    private var snippet: Clipboard.Snippet?

    func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?, qualifiedName: String?, attributes: [String: String] = [:]) {
        if path.isEmpty, name == "folders" { sawRoot = true }
        path.append(name)
        text = ""
        switch name {
        case "folder": folder = Clipboard.Folder(title: "")
        case "snippet": snippet = Clipboard.Snippet(title: "")
        default: break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) { text += string }

    func parser(_ parser: XMLParser, foundCDATA block: Data) { text += String(decoding: block, as: UTF8.self) }

    func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName: String?) {
        let parent = path.dropLast().last
        switch (name, parent) {
        case ("title", "folder"): folder?.title = text.trimmingCharacters(in: .whitespacesAndNewlines)
        case ("title", "snippet"): snippet?.title = text.trimmingCharacters(in: .whitespacesAndNewlines)
        case ("content", "snippet"): snippet?.text = text
        case ("snippet", _):
            if let snippet { folder?.snippets.append(snippet) }
            snippet = nil
        case ("folder", _):
            if let folder { folders.append(folder) }
            folder = nil
        default: break
        }
        path.removeLast()
        text = ""
    }
}
