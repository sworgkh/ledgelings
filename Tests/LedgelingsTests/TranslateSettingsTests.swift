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

        s.translateEnabled = false; s.translateShortcutEnabled = false; s.translateClipShortcutEnabled = false
        s.translateShortcut = Shortcut(keyCode: 17, modifiers: [.command, .option])
        s.translateClipMode = .quietly
        s.translateLanguages = ["en", "he"]; s.translateTargets["en"] = "he"
        s.translateModel = "openai/gpt-4.1-nano"; s.translateAutocomplete = false; s.translateAutocompleteModel = "x/y"
        s.translateDelayMs = 800; s.translateLiveLimit = 9_000
        s.translatePickerButton = false; s.translateKeepInHistory = false; s.translateHelperEnabled = false; s.translateHelper = "Zed"
        let again = AppSettings(defaults: defaults, keychain: Secrets())
        #expect(!again.translateEnabled && !again.translateShortcutEnabled && !again.translateClipShortcutEnabled)
        #expect(again.translateShortcut == Shortcut(keyCode: 17, modifiers: [.command, .option]) && again.translateClipMode == .quietly)
        #expect(again.translateLanguages == ["en", "he"] && again.translateTargets["en"] == "he")
        #expect(again.translateModel == "openai/gpt-4.1-nano" && !again.translateAutocomplete && again.translateAutocompleteModel == "x/y")
        #expect(again.translateDelayMs == 800 && again.translateLiveLimit == 9_000)
        #expect(!again.translatePickerButton && !again.translateKeepInHistory && !again.translateHelperEnabled && again.translateHelper == "Zed")
    }

    @Test func nonsenseIsClampedOnLoad() {
        let (defaults, _) = fresh()
        defer { defaults.removePersistentDomain(forName: name) }
        defaults.set(10, forKey: "translateDelayMs"); defaults.set(900_000, forKey: "translateLiveLimit")
        defaults.set(["en"], forKey: "translateLanguages"); defaults.set(["en": "en", "xx": "ru", "ru": "he"], forKey: "translateTargets")
        defaults.set("loudly", forKey: "translateClipMode"); defaults.set("  ", forKey: "translateModel")
        let s = AppSettings(defaults: defaults, keychain: Secrets())
        #expect(s.translateDelayMs == 200 && s.translateLiveLimit == 20_000)
        #expect(s.translateLanguages == ["en", "ru", "he"], "at least two languages")
        #expect(s.translateTargets == ["he": "en", "ru": "he", "en": "ru"], "into itself and unknown languages are dropped")
        #expect(s.translateClipMode == .sheet && s.translateModel == Translate.defaultModel)
    }

    @Test func translateIsTheFifthTool() {
        #expect(SettingsGroup.tools.pages == [.reminders, .clipboard, .screenshots, .dictation, .translate])
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

    // MARK: The sheet, with a stand-in model

    func sheet(_ s: AppSettings, answer: @escaping (String, String) -> String = { _, user in "[ru] \(user)" }) -> (TranslateSheetController, ClipBook) {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("\(name)-\(UUID().uuidString)")
        let clips = ClipBook(directory: dir, secrets: Secrets())
        let translator = Translator(settings: s, spend: SpendLedger(directory: dir))
        translator.fake = { system, user in ChatClient.Answer(text: answer(system, user), usage: nil) }
        let sheet = TranslateSheetController(settings: s, translator: translator, clips: clips, watcher: { nil })
        sheet.model.hasModel = true
        sheet.model.languages = s.translateLanguagesOn
        return (sheet, clips)
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
