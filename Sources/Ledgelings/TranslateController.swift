import AppKit
import Combine
import LedgelingsCore

/// The translator from the outside (§7.14): ⌃⌥T opens the sheet to type into,
/// ⌃⌥⇧T translates the newest copy (in the sheet, or quietly onto the
/// clipboard), and the clipboard picker's rows ask it for theirs.
@MainActor
final class TranslateController {
    private let settings: AppSettings
    private let clips: ClipBook
    private let watcher: () -> ClipWatcher?
    let translator: Translator
    let sheet: TranslateSheetController
    private var typeShortcut: GlobalShortcut?
    private var clipShortcut: GlobalShortcut?
    private var problems = ["type": "", "clip": ""]
    var trace: ((String) -> Void)? {
        didSet { translator.trace = trace; sheet.trace = trace }
    }

    init(settings: AppSettings, spend: SpendLedger, clips: ClipBook, watcher: @escaping () -> ClipWatcher?, helper: @escaping () -> ClipHelping?) {
        self.settings = settings
        self.clips = clips
        self.watcher = watcher
        translator = Translator(settings: settings, spend: spend)
        sheet = TranslateSheetController(settings: settings, translator: translator, clips: clips, watcher: watcher, helper: helper)
    }

    /// Takes both shortcuts from every app, following the settings.
    func takeShortcuts(pressed: @escaping (String) -> Void = { _ in }) {
        let on = settings.$translateEnabled
        typeShortcut = GlobalShortcut(settings: settings, enabled: on.combineLatest(settings.$translateShortcutEnabled).map { $0 && $1 },
                                      shortcut: settings.$translateShortcut, problem: { [weak self] in self?.report("type", $0) },
                                      pressed: { [weak self] in pressed("type"); self?.sheet.toggle() })
        clipShortcut = GlobalShortcut(settings: settings, enabled: on.combineLatest(settings.$translateClipShortcutEnabled).map { $0 && $1 },
                                      shortcut: settings.$translateClipShortcut, problem: { [weak self] in self?.report("clip", $0) },
                                      pressed: { [weak self] in pressed("clip"); self?.translateLastCopy() })
    }

    private func report(_ which: String, _ problem: String) {
        problems[which] = problem
        let all = ["type", "clip"].compactMap { problems[$0] }.filter { !$0.isEmpty }.joined(separator: " ")
        if settings.translateShortcutProblem != all { settings.translateShortcutProblem = all }
    }

    // MARK: The last copy

    /// The newest text copy: into the sheet, already translated, or quietly onto the clipboard.
    func translateLastCopy() {
        guard let clip = Translate.newest(in: clips.history, snippets: clips.snippets) else {
            trace?("last copy: nothing to translate")
            ClipToast.show(Translate.Refusal.notText.line, near: ClipPaster.caret())
            return
        }
        switch settings.translateClipMode {
        case .sheet: sheet.show(text: clip.text)
        case .quietly: Task { @MainActor in await quietly(clip.text) }
        }
    }

    /// No sheet: the translation replaces the clipboard, a note by the text cursor says so.
    func quietly(_ text: String) async {
        let caret = ClipPaster.caret()
        let on = settings.translateLanguagesOn
        guard let source = Translate.detect(Translate.protect(text).text, among: on) else {
            ClipToast.show(Translate.Refusal.nothingToTranslate.line, near: caret)
            return
        }
        let target = Translate.target(for: source, targets: settings.translateTargets, on: on)
        translator.refresh()
        trace?("quietly \(source.code)→\(target.code), \(text.count) characters")
        switch await translator.translate(text, from: source, to: target) {
        case .success(let done):
            let board = NSPasteboard.general
            board.clearContents()
            board.setString(done.text, forType: .string)
            watcher()?.ownWrite()
            keepInHistory(done.text, clips: clips, settings: settings)
            ClipToast.show(tr("In %@ on the clipboard: ⌘V pastes it", target.title), near: caret)
            trace?("quietly copied: \(done.text.prefix(80))")
        case .failure(.cancelled):
            return
        case .failure(let trouble):
            ClipToast.show(trouble.line, near: caret)
            trace?("quietly trouble: \(trouble.line)")
        }
    }

    // MARK: For the clipboard picker

    /// A row's translation into its "goes into" language, or the next one after
    /// `after` (⌥⇥); the target with it, or the reason there is none.
    func translateRow(_ text: String, after: Translate.Language? = nil) async -> (target: Translate.Language?, result: Result<String, Translator.Trouble>) {
        let on = settings.translateLanguagesOn
        guard let source = Translate.detect(Translate.protect(text).text, among: on) else { return (nil, .failure(.empty)) }
        var target = Translate.target(for: source, targets: settings.translateTargets, on: on)
        if let after, let at = on.firstIndex(of: after) {
            let others = on.filter { $0 != source }
            let next = on[(at + 1)...].first { $0 != source } ?? others.first
            target = next ?? target
        }
        translator.refresh()
        return (target, await translator.translate(text, from: source, to: target).map(\.text))
    }
}
