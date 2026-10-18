import AppKit
import Combine
import LedgelingsCore

/// The clipboard's shortcuts from any app: one for the history picker, one for
/// the snippets picker, and one for each snippet given its own. They follow the
/// settings and the snippets: changed, switched off, or let go while a shortcut
/// is being recorded. What the system refused is said in `clipShortcutProblem`.
@MainActor
final class ClipShortcuts {
    private let settings: AppSettings
    private let book: ClipBook
    private var history: GlobalShortcut?
    private var snippets: GlobalShortcut?
    /// Each snippet's own, by snippet.
    private var own: [UUID: (id: UInt32, shortcut: Shortcut)] = [:]
    private var problems: [String: String] = [:]
    private var following: AnyCancellable?

    init(settings: AppSettings, book: ClipBook, open: @escaping (ClipPickerModel.Group) -> Void,
         paste: @escaping (Clipboard.Snippet) -> Void) {
        self.settings = settings
        self.book = book
        let on = settings.$clipboardEnabled
        history = GlobalShortcut(settings: settings, enabled: on.combineLatest(settings.$clipHistoryShortcutEnabled).map { $0 && $1 },
                                 shortcut: settings.$clipHistoryShortcut, problem: { [weak self] in self?.report("history", $0) },
                                 pressed: { open(.recent) })
        snippets = GlobalShortcut(settings: settings, enabled: on.combineLatest(settings.$clipSnippetsShortcutEnabled).map { $0 && $1 },
                                  shortcut: settings.$clipSnippetsShortcut, problem: { [weak self] in self?.report("snippets", $0) },
                                  pressed: { open(.snippets) })
        following = Publishers.CombineLatest4(on, settings.$clipSnippetShortcutsEnabled, settings.$recordingShortcut, book.$snippets)
            .sink { [weak self] on, each, recording, book in
                self?.holdEach(on && each && !recording ? book : .init(), paste: paste)
            }
    }

    /// The snippets' own shortcuts now: new ones taken, changed ones moved, gone ones let go.
    private func holdEach(_ book: Clipboard.SnippetBook, paste: @escaping (Clipboard.Snippet) -> Void) {
        let wanted = Dictionary(book.all.compactMap { _, s in s.shortcut.map { (s.id, $0) } }, uniquingKeysWith: { a, _ in a })
        for (snippet, held) in own where wanted[snippet] != held.shortcut {
            HotKeys.shared.release(held.id)
            own[snippet] = nil
        }
        var refused: [String] = []
        for (snippet, shortcut) in wanted where own[snippet] == nil {
            let id = HotKeys.shared.newID()
            let taken = HotKeys.shared.hold(id, shortcut) { [weak self] in
                if let s = self?.book.snippets.snippet(snippet) { paste(s) }
            }
            if taken { own[snippet] = (id, shortcut) } else {
                HotKeys.shared.release(id)
                refused.append(GlobalShortcut.label(shortcut))
            }
        }
        report("own", refused.isEmpty ? "" : tr("macOS would not take %@: it is already taken. Record another.", refused.sorted().joined(separator: ", ")))
    }

    private func report(_ which: String, _ problem: String) {
        problems[which] = problem
        let all = ["history", "snippets", "own"].compactMap { problems[$0] }.filter { !$0.isEmpty }.joined(separator: " ")
        if settings.clipShortcutProblem != all { settings.clipShortcutProblem = all }
    }
}
