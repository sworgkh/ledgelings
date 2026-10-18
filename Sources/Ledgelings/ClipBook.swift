import AppKit
import Combine
import LedgelingsCore
import LocalAuthentication

/// The clipboard history and the snippets, kept in `clipboard.json` and
/// `snippets.json` beside the chats and saved on every change. A protected
/// snippet's words are kept in the login keychain, one item per snippet under
/// the "Ledgelings Snippets" service, and read only when it is pasted or shown.
@MainActor
final class ClipBook: ObservableObject {
    let store: Clipboard.Store
    private let secrets: any SecretStore
    @Published private(set) var history: Clipboard.History
    @Published private(set) var snippets: Clipboard.SnippetBook

    static let secretService = "Ledgelings Snippets"

    init(directory: URL = SpendLedger.defaultDirectory, secrets: any SecretStore = Keychain(service: ClipBook.secretService)) {
        store = Clipboard.Store(directory: directory)
        self.secrets = secrets
        history = store.loadHistory()
        snippets = store.loadSnippets()
    }

    // MARK: History

    func changeHistory(_ edit: (inout Clipboard.History) -> Void) {
        edit(&history)
        do { try store.save(history) } catch { Self.complain(error) }
    }

    /// A new copy, then the limits applied.
    func add(_ clip: Clipboard.Clip, limit: Int, days: Int) {
        changeHistory {
            $0.add(clip)
            $0.prune(limit: limit, days: days, now: clip.copiedAt)
        }
    }

    /// A clip pasted from the picker goes back to the top, as copying it again would.
    func bump(_ id: UUID, at now: Date = Date()) {
        guard var clip = history.clips.first(where: { $0.id == id }) else { return }
        clip.copiedAt = now
        changeHistory { $0.add(clip) }
    }

    func togglePin(_ id: UUID) { changeHistory { $0.togglePin(id) } }
    func remove(_ id: UUID) { changeHistory { $0.remove(id) } }
    func clearHistory(pinnedToo: Bool = false) { changeHistory { $0.clear(pinnedToo: pinnedToo) } }

    // MARK: Snippets

    func changeSnippets(_ edit: (inout Clipboard.SnippetBook) -> Void) {
        edit(&snippets)
        do { try store.save(snippets) } catch { Self.complain(error) }
    }

    @discardableResult
    func addFolder(_ title: String) -> UUID {
        var id = UUID()
        changeSnippets { id = $0.addFolder(title) }
        return id
    }

    /// A snippet; a protected one's words go to the keychain, never into the book.
    @discardableResult
    func addSnippet(title: String, text: String, protected: Bool = false, to folder: UUID? = nil) -> UUID {
        let snippet = Clipboard.Snippet(title: title, text: text, protected: protected)
        if protected { secrets.set(text, for: snippet.secretAccount) }
        changeSnippets { $0.add(snippet, to: folder) }
        return snippet.id
    }

    /// Saves an edit of the snippet's title, shortcut or words. Its words, for a
    /// protected one, are written to the keychain; nil leaves them as they were.
    func update(_ snippet: Clipboard.Snippet, secret: String? = nil) {
        if snippet.protected, let secret { secrets.set(secret, for: snippet.secretAccount) }
        changeSnippets { $0.update(snippet) }
    }

    /// Protected on: the words move into the keychain. Off: they come back into the book.
    func setProtected(_ id: UUID, _ protected: Bool) {
        guard var snippet = snippets.snippet(id), snippet.protected != protected else { return }
        if protected {
            secrets.set(snippet.text, for: snippet.secretAccount)
            snippet.protected = true
            snippet.text = ""
        } else {
            snippet.text = secrets.get(snippet.secretAccount) ?? ""
            secrets.set(nil, for: snippet.secretAccount)
            snippet.protected = false
        }
        changeSnippets { $0.update(snippet) }
    }

    func renameFolder(_ id: UUID, to title: String) { changeSnippets { $0.renameFolder(id, to: title) } }
    func move(_ id: UUID, by step: Int) { changeSnippets { $0.move(id, by: step) } }

    /// A folder or a snippet goes, and with it the keychain items of every protected snippet in it.
    func removeSnippetOrFolder(_ id: UUID) {
        var gone: [Clipboard.Snippet] = []
        changeSnippets { gone = $0.remove(id) }
        for snippet in gone where snippet.protected { secrets.set(nil, for: snippet.secretAccount) }
    }

    /// The words to paste: the book's, or the keychain's for a protected snippet.
    func words(of snippet: Clipboard.Snippet) -> String {
        snippet.protected ? secrets.get(snippet.secretAccount) ?? "" : snippet.text
    }

    // MARK: Files

    /// Clipy's XML from Clipy's Snippets editor, its folders added after ours.
    func importClipy(from url: URL) throws -> Int {
        let read = try Clipboard.importClipy(Data(contentsOf: url))
        changeSnippets { $0.merge(read) }
        return read.all.count
    }

    /// The snippets as Clipy's XML; protected ones with their titles only.
    func exportClipy(to url: URL) throws {
        try Clipboard.exportClipy(snippets).write(to: url, options: .atomic)
    }

    private static func complain(_ error: Error) {
        FileHandle.standardError.write(Data("Ledgelings clipboard: \(error)\n".utf8))
    }
}

/// A fingerprint before a protected snippet is pasted or shown, every time, with no
/// way round it: Touch ID only (`.deviceOwnerAuthenticationWithBiometrics`), never
/// the login password instead. No Touch ID to ask (no sensor, the lid closed, no
/// finger enrolled, locked after too many tries): it is refused, saying why.
///
/// The keychain item itself cannot be bound to Touch ID (`.biometryCurrentSet`) yet:
/// an ad-hoc signed app gets errSecMissingEntitlement (-34018) for any item with an
/// access control, so that waits for a Developer ID and its entitlements.
enum OwnerCheck {
    enum Answer: Equatable {
        case yes
        /// Cancelled, or the wrong finger.
        case no
        /// Touch ID cannot be asked now; the words say why, for the user.
        case unavailable(String)
    }

    static func fingerprint(_ reason: String) async -> Answer {
        let context = LAContext()
        var problem: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &problem) else {
            return .unavailable(why(problem?.code))
        }
        do {
            return try await context.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, localizedReason: reason) ? .yes : .no
        } catch let error as LAError where error.code == .biometryLockout {
            return .unavailable(why(error.code.rawValue))
        } catch {
            return .no
        }
    }

    /// Why Touch ID cannot be asked, in plain words.
    static func why(_ code: Int?) -> String {
        switch code.flatMap(LAError.Code.init(rawValue:)) {
        case .biometryNotEnrolled: tr("No fingerprint is set up. Add one in System Settings › Touch ID & Password to paste protected snippets.")
        case .biometryLockout: tr("Touch ID is locked after too many tries. Lock the Mac and unlock it with your password, then try again.")
        default: tr("Touch ID is not available (no sensor, or the lid is closed), so protected snippets cannot be pasted.")
        }
    }
}
