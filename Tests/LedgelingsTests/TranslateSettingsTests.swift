import AppKit
import Foundation
import LedgelingsCore
import Testing
@testable import Ledgelings

/// Tools › Translate: its settings, its buttons, the sheet as you type (with a
/// stand-in model), and the clipboard picker's translate button.
@MainActor
@Suite(.serialized) struct TranslateSettingsTests {
    let name = "ledgelings-translate-settings-tests"

    final class Secrets: SecretStore, @unchecked Sendable {
        func get(_ account: String) -> String? { nil }
        func set(_ value: String?, for account: String) {}
    }

    func fresh() -> (UserDefaults, AppSettings) {
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return (defaults, AppSettings(defaults: defaults, keychain: Secrets()))
    }

    @Test func theDefaultsAndAChangeSurviveARelaunch() {
        let (defaults, s) = fresh()
        defer { defaults.removePersistentDomain(forName: name) }
        #expect(s.translateEnabled && s.translateShortcutEnabled && s.translateClipShortcutEnabled)
        #expect(s.translateShortcut == .translate && s.translateClipShortcut == .translateClip)
        #expect(Shortcut.translate == Shortcut(keyCode: 17, modifiers: [.control, .option]), "⌃⌥T")
        #expect(Shortcut.translateClip == Shortcut(keyCode: 17, modifiers: [.control, .option, .shift]), "⌃⌥⇧T")
        #expect(s.translateClipMode == .sheet)
        #expect(s.translateLanguages == ["en", "ru", "he"] && s.translateTargets == ["he": "en", "ru": "en", "en": "ru"])
        #expect(s.translateModel == "google/gemini-2.5-flash-lite" && s.translateAutocomplete && s.translateAutocompleteModel.isEmpty)
        #expect(s.translateDelayMs == 400 && s.translateLiveLimit == 5_000)
        #expect(s.translatePickerButton && s.translateKeepInHistory && s.translateHelperEnabled && s.translateHelper.isEmpty)
        #expect(s.translateSavedEnabled && s.translateSavedLimit == 500 && !s.translateSavedOpenDrawer)

        s.translateEnabled = false; s.translateShortcutEnabled = false; s.translateClipShortcutEnabled = false
        s.translateShortcut = Shortcut(keyCode: 17, modifiers: [.command, .option])
        s.translateClipMode = .quietly
        s.translateLanguages = ["en", "he"]; s.translateTargets["en"] = "he"
        s.translateModel = "openai/gpt-4.1-nano"; s.translateAutocomplete = false; s.translateAutocompleteModel = "x/y"
        s.translateDelayMs = 800; s.translateLiveLimit = 9_000
        s.translatePickerButton = false; s.translateKeepInHistory = false; s.translateHelperEnabled = false; s.translateHelper = "Zed"
        s.translateSavedEnabled = false; s.translateSavedLimit = 1_200; s.translateSavedOpenDrawer = true
        let again = AppSettings(defaults: defaults, keychain: Secrets())
        #expect(!again.translateEnabled && !again.translateShortcutEnabled && !again.translateClipShortcutEnabled)
        #expect(again.translateShortcut == Shortcut(keyCode: 17, modifiers: [.command, .option]) && again.translateClipMode == .quietly)
        #expect(again.translateLanguages == ["en", "he"] && again.translateTargets["en"] == "he")
        #expect(again.translateModel == "openai/gpt-4.1-nano" && !again.translateAutocomplete && again.translateAutocompleteModel == "x/y")
        #expect(again.translateDelayMs == 800 && again.translateLiveLimit == 9_000)
        #expect(!again.translatePickerButton && !again.translateKeepInHistory && !again.translateHelperEnabled && again.translateHelper == "Zed")
        #expect(!again.translateSavedEnabled && again.translateSavedLimit == 1_200 && again.translateSavedOpenDrawer)
    }

    @Test func nonsenseIsClampedOnLoad() {
        let (defaults, _) = fresh()
        defer { defaults.removePersistentDomain(forName: name) }
        defaults.set(10, forKey: "translateDelayMs"); defaults.set(900_000, forKey: "translateLiveLimit")
        defaults.set(["en"], forKey: "translateLanguages"); defaults.set(["en": "en", "xx": "ru", "ru": "he"], forKey: "translateTargets")
        defaults.set("loudly", forKey: "translateClipMode"); defaults.set("  ", forKey: "translateModel")
        defaults.set(3, forKey: "translateSavedLimit")
        let s = AppSettings(defaults: defaults, keychain: Secrets())
        #expect(s.translateDelayMs == 200 && s.translateLiveLimit == 20_000)
        #expect(s.translateSavedLimit == 50)
        #expect(s.translateLanguages == ["en", "ru", "he"], "at least two languages")
        #expect(s.translateTargets == ["he": "en", "ru": "he", "en": "ru"], "into itself and unknown languages are dropped")
        #expect(s.translateClipMode == .sheet && s.translateModel == Translate.defaultModel)
    }

    @Test func translateIsTheFifthTool() {
        #expect(SettingsGroup.tools.pages == [.tools, .reminders, .clipboard, .screenshots, .dictation, .translate, .savedTranslations, .readAloud])
        #expect(SettingsPage.named("savedtranslations") == .savedTranslations)
        #expect(SettingsPage.named("translate") == .translate)
    }

    /// AGENTS rule 4: every button is a picture, and its tag names its key.
    @Test func everyButtonHasItsPictureAndATooltipNamingItsKey() {
        for button in Translate.Button.allCases {
            #expect(button.icon.count == 11 && button.icon.allSatisfy { $0.count == 11 && $0.allSatisfy { ".#".contains($0) } }, "\(button)")
            #expect(button.icon.joined().contains("#"))
            #expect(button.tooltip().contains(button.key), "\(button): \(button.tooltip())")
            Language.$override.withValue(.russian) {
                #expect(button.tooltip().contains(button.key) && button.tooltip() != Language.$override.withValue(.english) { button.tooltip() })
            }
        }
        #expect(Set(Translate.Button.allCases.map(\.icon)).count == Translate.Button.allCases.count, "each its own picture")
        #expect(Translate.Button.paste.tooltip(app: "Notes") == "Paste into Notes (⌘⏎)")
    }

    /// The star and the drawer: their keys, their tags in both states, the star filled once saved.
    @Test func theStarAndTheDrawerSayWhatTheyDo() {
        Language.$override.withValue(.english) {
            #expect(Translate.Button.save.key == "⌘D" && Translate.Button.savedList.key == "⌘L")
            #expect(Translate.Button.save.tooltip() == "Save this translation (⌘D)")
            #expect(Translate.Button.save.tooltip(on: true) == "Remove from saved (⌘D)")
            #expect(Translate.Button.savedList.tooltip() == "Show saved translations (⌘L)")
            #expect(Translate.Button.savedList.tooltip(on: true).contains("⌘L"))
            #expect(Translate.Button.copySaved.tooltip() == "Copy this translation (⌘C)")
            #expect(Translate.Button.deleteSaved.tooltip() == "Delete from saved (⌫)")
        }
        let filled = Translate.Button.save.icon(on: true)
        #expect(filled != Translate.Button.save.icon && filled.count == 11 && filled.allSatisfy { $0.count == 11 })
        #expect(filled.joined().filter { $0 == "#" }.count > Translate.Button.save.icon.joined().filter { $0 == "#" }.count)
        #expect(Translate.Button.copy.icon(on: true) == Translate.Button.copy.icon, "only the star changes")
        for button in Translate.Button.allCases {
            Language.$override.withValue(.russian) { #expect(button.tooltip(on: true).contains(button.key)) }
        }
    }

    @Test func theKeysAreFreeInTheSheet() {
        let (defaults, s) = fresh()
        defer { defaults.removePersistentDomain(forName: name) }
        let (sheet, _, _) = sheetWithBook(s)
        // ⌘D and ⌘L were not taken before: the text box only ever saw them.
        #expect(sheet.key(2, .command), "⌘D is the sheet's")
        #expect(sheet.key(37, .command), "⌘L is the sheet's")
        #expect(!sheet.key(2, []), "a plain d is typed")
    }

    // MARK: The sheet, with a stand-in model

    func sheet(_ s: AppSettings, answer: @escaping (String, String) -> String = { _, user in "[ru] \(user)" }) -> (TranslateSheetController, ClipBook) {
        let (sheet, clips, _) = sheetWithBook(s, answer: answer)
        return (sheet, clips)
    }

    func sheetWithBook(_ s: AppSettings, directory: URL? = nil, answer: @escaping (String, String) -> String = { _, user in "[ru] \(user)" },
                       calls: ((String) -> Void)? = nil) -> (TranslateSheetController, ClipBook, SavedTranslations) {
        let dir = directory ?? FileManager.default.temporaryDirectory.appendingPathComponent("\(name)-\(UUID().uuidString)")
        let clips = ClipBook(directory: dir, secrets: Secrets())
        let saved = SavedTranslations(directory: dir)
        let translator = Translator(settings: s, spend: SpendLedger(directory: dir))
        translator.fake = { system, user in calls?(user); return ChatClient.Answer(text: answer(system, user), usage: nil) }
        let sheet = TranslateSheetController(settings: s, translator: translator, clips: clips, saved: saved, watcher: { nil })
        sheet.model.hasModel = true
        sheet.model.languages = s.translateLanguagesOn
        return (sheet, clips, saved)
    }

    // MARK: Saved translations

    @Test func theStarSavesTheTranslationOnShowAndTheDrawerLoadsItBackForFree() async {
        let (defaults, s) = fresh()
        defer { defaults.removePersistentDomain(forName: name) }
        s.translateDelayMs = 200
        s.translateAutocomplete = false
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("\(name)-\(UUID().uuidString)")
        var sent: [String] = []
        let (sheet, _, saved) = sheetWithBook(s, directory: dir, calls: { sent.append($0) })
        let m = sheet.model
        m.appName = "Notes"
        sheet.act(.save)
        #expect(saved.book.isEmpty, "nothing translated yet: only a beep")
        m.typed("Good morning", cursorAtEnd: true)
        await waitFor { m.state == .done }
        #expect(!m.isSaved)
        #expect(sheet.key(2, .command), "⌘D")
        #expect(m.isSaved && saved.book.count == 1)
        let first = saved.book.entries[0]
        #expect(first.text == "Good morning" && first.from == "en" && first.translation == "[ru] Good morning" && first.to == "ru" && first.app == "Notes")
        m.typed("Good night", cursorAtEnd: true)
        #expect(!m.isSaved, "a new text is not saved")
        await waitFor { m.state == .done && m.result == "[ru] Good night" }
        sheet.act(.save)
        #expect(saved.book.entries.map(\.text) == ["Good night", "Good morning"], "newest first")
        sheet.act(.save)
        #expect(!m.isSaved && saved.book.count == 1, "pressed again: removed")
        sheet.act(.save)

        // The drawer: ⌘L, a search, ⏎ loads, ⌫ deletes, ⎋ closes it, a second ⎋ the sheet.
        #expect(sheet.key(37, .command))
        #expect(m.drawerOpen && m.selectedSaved == saved.book.entries[0].id)
        m.query = "morning"
        #expect(m.shownSaved.map(\.text) == ["Good morning"] && m.selectedSaved == first.id)
        let calls = sent.count
        #expect(sheet.key(36, []), "⏎ loads it")
        #expect(m.text == "Good morning" && m.result == "[ru] Good morning" && m.state == .done && m.isSaved)
        #expect(m.target == Translate.russian && m.source == Translate.english)
        try? await Task.sleep(for: .milliseconds(400))
        #expect(sent.count == calls, "loaded from the saved copy: no call")
        m.query = ""
        sheet.key(125, [])  // ↓
        #expect(m.selectedSaved == first.id)
        #expect(sheet.key(51, []), "⌫ deletes the chosen row")
        #expect(saved.book.entries.map(\.text) == ["Good night"] && m.selectedSaved == saved.book.entries.first?.id)
        #expect(sheet.key(53, []), "⎋")
        #expect(!m.drawerOpen)
        #expect(SavedTranslations(directory: dir).book.entries.map(\.text) == ["Good night"], "kept on disk")
    }

    @Test func offMeansNoStarAndNoDrawer() {
        let (defaults, s) = fresh()
        defer { defaults.removePersistentDomain(forName: name) }
        s.translateSavedEnabled = false
        let (sheet, _, saved) = sheetWithBook(s)
        sheet.model.savedOn = false
        sheet.model.text = "Good morning"; sheet.model.result = "Доброе утро"; sheet.model.state = .done; sheet.model.detected = Translate.english
        sheet.act(.save)
        sheet.act(.savedList)
        #expect(saved.book.isEmpty && !sheet.model.drawerOpen)
    }

    func waitFor(_ ok: () -> Bool) async {
        for _ in 0..<200 where !ok() { try? await Task.sleep(for: .milliseconds(20)) }
    }

    @Test func typingDetectsTranslatesAfterTheWaitAndShowsTheDirection() async {
        let (defaults, s) = fresh()
        defer { defaults.removePersistentDomain(forName: name) }
        s.translateDelayMs = 200
        let (sheet, _) = sheet(s)
        let m = sheet.model
        m.typed("Good morning", cursorAtEnd: true)
        #expect(m.detected == Translate.english)
        #expect(m.state == .idle || m.state == .waiting, "nothing yet: it waits after typing")
        await waitFor { m.state == .done }
        #expect(m.result == "[ru] Good morning")
        #expect(m.status.hasPrefix(Language.$override.withValue(.english) { "ENGLISH → RUSSIAN" }) || m.status.contains("→"))
    }

    @Test func aNewerKeystrokeWinsAndOnlyItsAnswerIsShown() async {
        let (defaults, s) = fresh()
        defer { defaults.removePersistentDomain(forName: name) }
        s.translateDelayMs = 200
        let (sheet, _) = sheet(s)
        let m = sheet.model
        m.typed("Good", cursorAtEnd: true)
        m.typed("Good night", cursorAtEnd: true)
        await waitFor { m.state == .done }
        #expect(m.result == "[ru] Good night")
    }

    @Test func aProtectedSnippetTypedIntoTheSheetIsNeverSent() async {
        let (defaults, s) = fresh()
        defer { defaults.removePersistentDomain(forName: name) }
        var sent: [String] = []
        let (sheet, clips) = sheet(s) { _, user in sent.append(user); return "x" }
        clips.addSnippet(title: "Wi-Fi", text: "correct horse battery", protected: true, to: clips.addFolder("Secrets"))
        sheet.model.typed("correct horse battery", cursorAtEnd: true)
        try? await Task.sleep(for: .milliseconds(700))
        #expect(sheet.model.state == .refused)
        #expect(sheet.model.status == Translate.Refusal.protected.line)
        #expect(sent.isEmpty)
    }

    @Test func aLongTextWaitsForEnterAndSaysItsParts() async {
        let (defaults, s) = fresh()
        defer { defaults.removePersistentDomain(forName: name) }
        s.translateLiveLimit = 1_000
        let (sheet, _) = sheet(s)
        let text = String(repeating: "A long paragraph of words. ", count: 120)
        sheet.model.typed(text, cursorAtEnd: true)
        #expect(sheet.model.state == .waitingForEnter)
        #expect(sheet.model.status.contains("⏎"))
        sheet.act(.copy)  // ⏎ translates it
        await waitFor { sheet.model.state == .done }
        #expect(sheet.model.result.hasPrefix("[ru] "))
    }

    @Test func aGuessIsKeptWhileItsLettersAreTypedAndTabTakesIt() async {
        let (defaults, s) = fresh()
        defer { defaults.removePersistentDomain(forName: name) }
        s.translateDelayMs = 200
        let (sheet, _) = sheet(s) { system, user in system.hasPrefix("You complete") ? " tomorrow at ten" : "[ru] \(user)" }
        let m = sheet.model
        m.typed("See you", cursorAtEnd: true)
        await waitFor { !m.guess.isEmpty }
        #expect(m.guess == " tomorrow at ten")
        m.typed("See you t", cursorAtEnd: true)
        #expect(m.guess == "omorrow at ten", "its own next letters keep it")
        m.typed("See you to", cursorAtEnd: true)
        #expect(m.guess == "morrow at ten")
        sheet.takeGuess()
        #expect(m.text == "See you tomorrow at ten" && m.guess.isEmpty)
        m.typed(m.text + "x", cursorAtEnd: true)
        #expect(m.guess.isEmpty)
    }

    @Test func anyOtherKeyThrowsTheGuessAway() {
        let m = TranslateSheetModel()
        m.text = "See you"
        m.guess = " tomorrow"
        m.typed("See you!", cursorAtEnd: true)
        #expect(m.guess.isEmpty)
        m.guess = " tomorrow"
        m.typed("See yo", cursorAtEnd: true)
        #expect(m.guess.isEmpty, "a backspace too")
    }

    @Test func swapTurnsTheTranslationIntoTheText() async {
        let (defaults, s) = fresh()
        defer { defaults.removePersistentDomain(forName: name) }
        let (sheet, _) = sheet(s) { system, user in system.contains("from English into Russian") ? "Доброе утро" : "Good morning" }
        let m = sheet.model
        m.typed("Good morning", cursorAtEnd: true)
        await waitFor { m.state == .done }
        sheet.swap()
        #expect(m.text == "Доброе утро" && m.sourceChoice == Translate.russian && m.targetChoice == Translate.english)
        await waitFor { m.state == .done }
        #expect(m.result == "Good morning")
    }

    @Test func choosingLanguagesByKey() {
        let (defaults, s) = fresh()
        defer { defaults.removePersistentDomain(forName: name) }
        let (sheet, _) = sheet(s)
        sheet.model.text = "hello"
        sheet.chooseTarget(2)
        #expect(sheet.model.targetChoice == Translate.hebrew, "⌥3")
        sheet.chooseSource(2)
        #expect(sheet.model.sourceChoice == Translate.russian, "⌘3")
        sheet.chooseSource(0)
        #expect(sheet.model.sourceChoice == nil, "⌘1 is Detect")
    }

    @Test func aTranslationIsKeptInTheHistoryFromTranslateWhenAsked() {
        let (defaults, s) = fresh()
        defer { defaults.removePersistentDomain(forName: name) }
        let clips = ClipBook(directory: FileManager.default.temporaryDirectory.appendingPathComponent("\(name)-\(UUID().uuidString)"), secrets: Secrets())
        keepInHistory("Доброе утро", clips: clips, settings: s)
        #expect(clips.history.clips.first?.text == "Доброе утро" && clips.history.clips.first?.app == tr("Translate"))
        s.translateKeepInHistory = false
        keepInHistory("Добрый вечер", clips: clips, settings: s)
        #expect(clips.history.clips.count == 1)
    }

    // MARK: The clipboard picker

    @Test func onlyRowsWithWordsAModelMaySeeGetTheButton() {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("\(name)-\(UUID().uuidString)")
        let clips = ClipBook(directory: dir, secrets: Secrets())
        let now = Date()
        clips.add(Clipboard.Clip(text: "Good morning to you", copiedAt: now), limit: 100, days: 0)
        clips.add(Clipboard.Clip(text: "https://example.com/x", copiedAt: now.addingTimeInterval(1)), limit: 100, days: 0)
        clips.add(Clipboard.Clip(text: "correct horse battery", copiedAt: now.addingTimeInterval(2)), limit: 100, days: 0)
        let folder = clips.addFolder("Secrets")
        clips.addSnippet(title: "Wi-Fi", text: "correct horse battery", protected: true, to: folder)
        clips.addSnippet(title: "Hello", text: "Hello there, friend", to: folder)
        let model = ClipPickerModel()
        model.source = { (clips.history, clips.snippets) }
        model.translateOn = true
        model.refresh(selectFirst: true)
        func button(_ text: String) -> Bool? { model.rows.first { $0.text.contains(text) || $0.title == text }?.translatable }
        #expect(button("Good morning") == true)
        #expect(button("example.com") == false, "only a link")
        #expect(model.rows.first { $0.masked }?.translatable == false, "a copy of a protected snippet's words")
        #expect(button("Wi-Fi") == false, "a protected snippet")
        #expect(button("Hello") == true, "an ordinary snippet")
        model.translateOn = false
        model.refresh()
        #expect(model.rows.allSatisfy { !$0.translatable }, "off: no buttons at all")
    }
}
