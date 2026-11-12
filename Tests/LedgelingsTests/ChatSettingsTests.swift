import Foundation
import LedgelingsCore
import Testing
@testable import Ledgelings

/// Talk › Chat with you: its settings, and the chat through a real colony with
/// stand-in answers: one to one, Everyone in turn, the memory, the cost and the log.
@MainActor
@Suite(.serialized) struct ChatSettingsTests {
    let name = "ledgelings-chat-settings-tests"

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
        #expect(s.chatEnabled && s.chatShortcutEnabled && s.chatShortcut == .chat)
        #expect(GlobalShortcut.spoken(s.chatShortcut) == "Control + Option + C" && GlobalShortcut.label(s.chatShortcut) == "⌃⌥C")
        #expect(s.chatEveryone == 3 && s.chatLength == .short && s.chatSpeak && s.chatBubbles)
        #expect(s.chatRemember && s.chatMemoryExchanges == 10)

        s.chatEnabled = false; s.chatShortcutEnabled = false
        s.chatShortcut = Shortcut(keyCode: 8, modifiers: [.command, .option])
        s.chatEveryone = 6; s.chatLength = .long; s.chatSpeak = false; s.chatBubbles = false
        s.chatRemember = false; s.chatMemoryExchanges = 25
        let again = AppSettings(defaults: defaults, keychain: Secrets())
        #expect(!again.chatEnabled && !again.chatShortcutEnabled && again.chatShortcut == Shortcut(keyCode: 8, modifiers: [.command, .option]))
        #expect(again.chatEveryone == 6 && again.chatLength == .long && !again.chatSpeak && !again.chatBubbles)
        #expect(!again.chatRemember && again.chatMemoryExchanges == 25)
    }

    @Test func nonsenseIsClampedOnLoad() {
        let (defaults, _) = fresh()
        defer { defaults.removePersistentDomain(forName: name) }
        defaults.set(40, forKey: "chatEveryone"); defaults.set(-3, forKey: "chatMemoryExchanges"); defaults.set("epic", forKey: "chatLength")
        defaults.set(200, forKey: "chatShortcutKeyCode"); defaults.set(0, forKey: "chatShortcutModifiers")
        var s = AppSettings(defaults: defaults, keychain: Secrets())
        #expect(s.chatEveryone == 8 && s.chatMemoryExchanges == 0 && s.chatLength == .short && s.chatShortcut == .chat)
        defaults.set(0, forKey: "chatEveryone"); defaults.set(500, forKey: "chatMemoryExchanges")
        s = AppSettings(defaults: defaults, keychain: Secrets())
        #expect(s.chatEveryone == 1 && s.chatMemoryExchanges == 50)
    }

    @Test func everySavedChatKeyIsFoundBySearch() {
        for key in ["chatEnabled", "chatShortcutEnabled", "chatShortcutKeyCode", "chatShortcutModifiers", "chatEveryone", "chatLength",
                    "chatSpeak", "chatBubbles", "chatRemember", "chatMemoryExchanges"] {
            #expect(SettingsIndex.sections.contains { $0.page == .chatWithYou && $0.keys.contains(key) }, "\(key)")
        }
    }

    // MARK: Through a colony

    func colony(_ s: AppSettings, _ dir: URL, count: Int = 5) throws -> Colony {
        s.creatureCount = count
        s.species = ["blocky"]
        s.brain = .script
        s.talkEnabled = false; s.planesEnabled = false; s.playEnabled = false; s.teaPartiesEnabled = false
        s.chatBubbles = false; s.chatSpeak = false
        let colony = try Colony(settings: s, history: ChatHistory(directory: dir.appendingPathComponent("chats")),
                                library: SpriteLibrary(directory: dir.appendingPathComponent("sprites")), spend: SpendLedger(directory: dir),
                                stage: Display(frame: CGRect(x: 0, y: 0, width: 1024, height: 576), scale: 1))
        colony.ownerChats = OwnerChatBook(directory: dir)
        return colony
    }

    @Test func everyoneIsAskedAtMostNInTurnAndRemembered() async throws {
        let (defaults, s) = fresh()
        defer { defaults.removePersistentDomain(forName: name) }
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("ledgelings-chat-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let colony = try colony(s, dir)
        s.chatEveryone = 3
        var heard: [(String, [String])] = []
        var answers: [String] = []
        await colony.answerOwner("Hello all", to: nil, window: .zero, fake: { who, _, earlier in
            heard.append((who, earlier.map(\.name)))
            return "\(who) says hi"
        }) { e in if case .answer(let who, _, _) = e { answers.append(who) } }
        #expect(answers.count == 3 && Set(answers).count == 3, "at most three, each once")
        #expect(heard.map(\.1) == [[], [answers[0]], [answers[0], answers[1]]], "each hears the ones before: in turn")
        #expect(colony.busy.isEmpty && colony.chatThinking.isEmpty, "everyone let go")
        for who in answers { #expect(colony.ownerChats?.memory(of: who)?.exchanges.first?.everyone == true) }
        let logged = colony.history.exchanges(on: ChatLog.day(of: Date()))
        #expect(logged.count == 1 && logged[0].lines.count == 4, "the talk is on the Chats tab: you and three answers")

        // One to one, remembered and capped, and back after a relaunch of the book.
        s.chatMemoryExchanges = 2
        let one = answers[0]
        for k in 0..<3 { await colony.answerOwner("note \(k)", to: one, window: .zero, fake: { _, m, _ in "ok \(m)" }) { _ in } }
        #expect(colony.ownerChats?.memory(of: one)?.exchanges.map(\.said) == ["note 1", "note 2"])
        #expect(OwnerChatBook(directory: dir).memory(of: one)?.exchanges.count == 2, "it survives a relaunch")
        s.chatRemember = false
        await colony.answerOwner("secret", to: one, window: .zero, fake: { _, _, _ in "shh" }) { _ in }
        #expect(colony.ownerChats?.memory(of: one)?.exchanges.map(\.said) == ["note 1", "note 2"], "off: nothing new kept")
        colony.ownerChats?.forget(one)
        #expect(colony.ownerChats?.memory(of: one) == nil && OwnerChatBook(directory: dir).memory(of: one) == nil)
    }

    @Test func noModelSaysSoInOneLine() async throws {
        let (defaults, s) = fresh()
        defer { defaults.removePersistentDomain(forName: name) }
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("ledgelings-chat-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let colony = try colony(s, dir, count: 2)
        var trouble: String?
        await colony.answerOwner("Hi", to: nil, window: .zero) { e in if case .trouble(let why) = e { trouble = why } }
        #expect(trouble == OwnerChat.noModel)
        let chat = ChatController(settings: s, colony: { colony })
        chat.refresh()
        #expect(!chat.model.hasModel && chat.model.targets.count == 2 && chat.model.targets[0].number == 1)
    }
}
