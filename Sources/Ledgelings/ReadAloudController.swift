import AppKit
import Combine
import LedgelingsCore

/// Read aloud from the outside (§7.16): ⌃⌥R opens the sheet with the
/// clipboard's text and reads it, the clipboard picker's rows read theirs, the
/// menu stops a reading the sheet let go on.
@MainActor
final class ReadAloudController {
    private let settings: AppSettings
    private let library: SpriteLibrary
    let player: ReadAloudPlayer
    let sheet: ReadAloudSheetController
    private var shortcut: GlobalShortcut?
    var trace: ((String) -> Void)? {
        didSet { player.trace = trace; sheet.trace = trace }
    }

    init(settings: AppSettings, spend: SpendLedger, voice: Voice, library: SpriteLibrary, clips: ClipBook,
         watcher: @escaping () -> ClipWatcher?, helper: @escaping () -> ClipHelping?) {
        self.settings = settings
        self.library = library
        player = ReadAloudPlayer(settings: settings, spend: spend, voice: voice)
        sheet = ReadAloudSheetController(settings: settings, player: player, clips: clips, watcher: watcher, helper: helper)
        player.describe = { [weak self] in self?.describe($0) }
        sheet.readers = { [weak self] in self?.readers() ?? [] }
    }

    func takeShortcut(pressed: @escaping () -> Void = {}) {
        shortcut = GlobalShortcut(settings: settings, enabled: settings.$readAloudEnabled.combineLatest(settings.$readAloudShortcutEnabled).map { $0 && $1 },
                                  shortcut: settings.$readAloudShortcut,
                                  problem: { [weak self] problem in
                                      guard let self, self.settings.readAloudShortcutProblem != problem else { return }
                                      self.settings.readAloudShortcutProblem = problem
                                  },
                                  pressed: { [weak self] in pressed(); self?.sheet.toggle() })
    }

    /// A clipboard picker row: into the sheet, read at once.
    func read(_ text: String) {
        sheet.show(text: text, start: true)
    }

    /// Every character there is, species by species in the Sprites page's order, each name once.
    func readers() -> [String] {
        var names: [String] = []
        for species in library.species {
            for who in settings.cast(of: species.name, fallback: library.cast(of: species.name)) where !names.contains(who.name) {
                names.append(who.name)
            }
        }
        return names
    }

    /// Who a character is, from whichever species' cast has it: for casting its voice.
    func describe(_ name: String) -> (persona: String, kind: String)? {
        for species in library.species {
            if let who = settings.cast(of: species.name, fallback: library.cast(of: species.name)).first(where: { $0.name == name }) {
                return (who.persona, library.kind(of: species.name))
            }
        }
        return nil
    }
}
