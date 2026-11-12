import Foundation
import Testing
@testable import LedgelingsCore

/// Chat with the creatures: who answers Everyone and in what order, the prompt
/// each one gets, what it remembers of the owner, the cost, the keys and the controls.
@Suite struct OwnerChatTests {
    struct Seeded: RandomNumberGenerator {
        var state: UInt64
        mutating func next() -> UInt64 { state = state &* 6364136223846793005 &+ 1442695040888963407; return state }
    }

    // MARK: Cost

    @Test func aChatCallLandsUnderItsOwnPurpose() {
        let now = Date()
        let records = [Spend.Record(time: now, provider: "OpenRouter", model: "m", usage: .init(promptTokens: 300, completionTokens: 40, cost: 0.002), purpose: .chat),
                       Spend.Record(time: now, provider: "OpenRouter", model: "m", usage: .init(promptTokens: 200, completionTokens: 0, cost: 0.001), purpose: .chat),
                       Spend.Record(time: now, provider: "OpenRouter", model: "m", usage: .init(promptTokens: 10, completionTokens: 5, cost: 0.0001), purpose: .talk)]
        let chat = Spend.summarise(records, now: now).byPurpose.first { $0.purpose == "Chat with you" }
        #expect(chat?.total.calls == 2, "an empty answer is a call too")
        #expect(abs((chat?.total.cost ?? 0) - 0.003) < 1e-9)
        #expect(Spend.Purpose.chat.title == "Chat with you")
    }

    // MARK: The prompt

    @Test func thePromptCarriesThePersonaAndTheKind() {
        let values = OwnerChat.values(speaker: "Unit 7", kind: "a boxy little robot", persona: "Talks in numbers. Counts everything.",
                                      length: .medium, memory: "", situation: "On the edge it is day.", message: "How was your night?",
                                      everyone: false, earlier: [])
        let prompt = OwnerChat.prompt(values)
        #expect(prompt.system.contains("Unit 7") && prompt.system.contains("a boxy little robot"))
        #expect(prompt.system.contains("Talks in numbers. Counts everything."))
        #expect(prompt.system.contains("at most 60 words"))
        #expect(prompt.user.contains("How was your night?") && prompt.user.contains("to you"))
        #expect(!prompt.system.contains("{") && !prompt.user.contains("{"), "every placeholder filled")
        for p in ["speakerPersona", "speakerKind", "speaker"] { #expect(OwnerChat.englishSystemPrompt.contains("{\(p)}")) }
    }

    @Test func theRussianPromptAsksForRussian() {
        Language.$override.withValue(.russian) {
            let values = OwnerChat.values(speaker: "Blocky", kind: "", persona: "", length: .short, memory: "", situation: "",
                                          message: "привет", everyone: true, earlier: [])
            let prompt = OwnerChat.prompt(values)
            #expect(prompt.system.contains("по-русски") && prompt.system.contains("не больше 25 слов"))
            #expect(prompt.user.contains("всем вам") && prompt.user.contains("«привет»"))
        }
    }

    @Test func laterOnesHearTheEarlierAnswers() {
        let values = OwnerChat.values(speaker: "Pip", kind: "", persona: "", length: .short, memory: "", situation: "", message: "Hi all",
                                      everyone: true, earlier: [("Blocky", "Go away."), ("Zed", "Mm… sleep…")])
        let user = OwnerChat.prompt(values).user
        #expect(user.contains("Blocky: \"Go away.\"") && user.contains("Zed: \"Mm… sleep…\""))
        #expect(user.contains("never the same answer") && user.contains("to all of you"))
    }

    // MARK: Everyone

    @Test func everyoneIsAtMostNAndEachOnceAwakeFirst() {
        var rng = Seeded(state: 7)
        let six = ["Blocky", "Pip", "Zed", "Dot", "Ruth", "Mortimer"].map { OwnerChat.Candidate(name: $0, asleep: $0 == "Zed" || $0 == "Ruth") }
        for n in 1...8 {
            let who = OwnerChat.answerers(six + six, count: n, using: &rng)
            #expect(who.count == min(n, 6) && Set(who).count == who.count, "at most \(n), each once")
            if n <= 4 { #expect(!who.contains("Zed") && !who.contains("Ruth"), "the awake answer first") }
        }
        #expect(OwnerChat.answerers(six, count: 0, using: &rng).isEmpty)
    }

    // MARK: Memory

    @Test func memoryIsKeptCappedAndForgotten() {
        var book = OwnerChat.Book()
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        var dropped: [OwnerChat.Exchange] = []
        for k in 0..<5 {
            dropped += book.remember("Blocky", .init(time: start.addingTimeInterval(Double(k) * 60), said: "m\(k)", answer: "a\(k)"), keep: 3)
        }
        #expect(book.memory(of: "Blocky")?.exchanges.map(\.said) == ["m2", "m3", "m4"], "the newest three")
        #expect(dropped.map(\.said) == ["m0", "m1"], "the rest come back, oldest first, for the summary")
        book.summarised("Blocky", "The owner went to the dentist.", cost: 0.001)
        book.summarised("Blocky", nil, cost: 0.002)
        #expect(book.memory(of: "Blocky")?.summary == "The owner went to the dentist.", "an empty summary keeps the old one")
        #expect(abs((book.memory(of: "Blocky")?.summaryCost ?? 0) - 0.003) < 1e-9)
        let cut = book.keep(1)
        #expect(cut["Blocky"]?.map(\.said) == ["m2", "m3"] && book.memory(of: "Blocky")?.exchanges.count == 1)
        book.remember("Zed", .init(time: start, said: "hi", answer: "zz"), keep: 0)
        #expect(book.memory(of: "Zed")?.exchanges.isEmpty == true, "0 keeps nothing word for word")
        book.forget("Blocky")
        #expect(book.memory(of: "Blocky") == nil)
        book.remember("Pip", .init(time: start, said: "hi", answer: "yay"), keep: 3)
        book.forgetAll()
        #expect(book.names.isEmpty)
    }

    @Test func memorySurvivesARelaunch() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("owner-chat-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = OwnerChat.Store(directory: dir)
        #expect(store.load() == OwnerChat.Book(), "nothing saved yet")
        var book = OwnerChat.Book()
        book.remember("Blocky", .init(time: Date(timeIntervalSince1970: 1_800_000_000), said: "I have a cat", answer: "Keep it off my edge.", everyone: true), keep: 10)
        book.summarised("Blocky", "The owner has a cat.", at: Date(timeIntervalSince1970: 1_800_000_100), cost: nil)
        try store.save(book)
        #expect(OwnerChat.Store(directory: dir).load() == book)
        try Data("nonsense".utf8).write(to: store.file)
        #expect(store.load() == OwnerChat.Book(), "a damaged file reads as empty")
    }

    @Test func theMemoryBlockGoesIntoThePrompt() {
        var memory = OwnerChat.Memory()
        let now = Date()
        memory.summary = "The owner's name is Sam."
        memory.exchanges = [.init(time: Calendar.current.date(byAdding: .day, value: -1, to: now)!, said: "I'm off to the dentist", answer: "Bite them.")]
        let block = OwnerChat.memoryBlock(memory, now: now)
        #expect(block.contains("The owner's name is Sam.") && block.contains("yesterday") && block.contains("I'm off to the dentist"))
        let values = OwnerChat.values(speaker: "Blocky", kind: "", persona: "", length: .short, memory: block, situation: "", message: "Back!", everyone: false, earlier: [])
        #expect(OwnerChat.prompt(values).system.contains("I'm off to the dentist"))
        #expect(OwnerChat.memoryBlock(nil).isEmpty && OwnerChat.memoryBlock(OwnerChat.Memory()).isEmpty)
        let summary = OwnerChat.summaryPrompt(speaker: "Blocky", kind: "", summary: nil, dropped: memory.exchanges, now: now)
        #expect(summary.contains("I'm off to the dentist") && summary.contains("(nothing yet)") && !summary.contains("{"))
    }

    @Test func anAnswerIsCleanedToItsLength() {
        #expect(OwnerChat.clean("<think>hmm</think>\nBlocky: \"Fine.\nGo away.\"", speaker: "Blocky", length: .short) == "Fine. Go away.")
        #expect(OwnerChat.clean("<think>still going", speaker: "Blocky", length: .short).isEmpty)
        let long = String(repeating: "Word word word. ", count: 80)
        #expect(OwnerChat.clean(long, speaker: "Zed", length: .short).count <= OwnerChat.Length.short.maxCharacters)
        #expect(OwnerChat.clean(long, speaker: "Zed", length: .long).count > OwnerChat.Length.short.maxCharacters)
        #expect(OwnerChat.cleanSummary("\n\"Sam has a cat.\"\n") == "Sam has a cat." && OwnerChat.cleanSummary("  ") == nil)
    }

    // MARK: Keys and controls

    @Test func theShortcutIsControlOptionC() {
        #expect(Shortcut.chat == Shortcut(keyCode: 8, modifiers: [.control, .option]))
        #expect(Shortcut.chat.spoken(key: "C") == "Control + Option + C")
        #expect(Shortcut.chat.label(key: "C") == "⌃⌥C")
        let ours: [Shortcut] = [.standard, .clipHistory, .clipSnippets, .shotCapture, .shotFull, .shotLast, .dictation, .tools,
                                .translate, .translateClip, .readAloud, .stopActivity]
        #expect(!ours.contains(.chat), "none of the app's own keys")
    }

    @Test func everyControlHasAPictureAndATagNamingItsKey() {
        for button in OwnerChat.Button.allCases {
            #expect(button.icon.count == 11 && button.icon.allSatisfy { $0.count == 11 && $0.allSatisfy { ".#".contains($0) } }, "\(button)")
            #expect(button.icon.joined().contains("#"))
            #expect(!button.tooltip.isEmpty && button.tooltip.contains("("), "\(button): \(button.tooltip)")
        }
        #expect(Set(OwnerChat.Button.allCases.map(\.icon)).count == OwnerChat.Button.allCases.count, "each its own picture")
        #expect(OwnerChat.Button.send.tooltip == "Send (⏎)" && OwnerChat.Button.everyone.tooltip == "Write to everyone (⌘0)")
        #expect(OwnerChat.writeTo("Blocky", number: 1) == "Write to Blocky (⌘1)")
        #expect(OwnerChat.icon.count == 11 && OwnerChat.icon.allSatisfy { $0.count == 11 })
        #expect(Tools.Tool.chat.icon == OwnerChat.icon && Tools.Tool.chat.page == .chatWithYou)
        #expect(Tools.Tool.chat.tooltip(number: 11, shortcut: nil, on: false).contains("Talk & friends › Chat with you"))
        Language.$override.withValue(.russian) {
            #expect(OwnerChat.Button.send.tooltip == "Отправить (⏎)")
        }
    }

    @Test func thePageSitsUnderTalk() {
        #expect(SettingsPage.chatWithYou.group == .talkAndFriends && SettingsPage.chatWithYou.title == "Chat with you")
        #expect(SettingsPage.named("chatwithyou") == .chatWithYou)
        #expect(SettingsIndex.search("reply length").first?.page == .chatWithYou)
    }
}
