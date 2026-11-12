import AppKit
import LedgelingsCore

/// The chat from a terminal (§7.18): `--chat "text" [--to Blocky|all]` sends one
/// message through the real calls and prints each answer, voice cue, price and
/// time; `--chat-window` opens the window on the real screen and writes it to a
/// PNG. `LEDGELINGS_FAKE_CHAT=1`: hand-written answers, no key, no network.
@MainActor
enum ChatDemo {

    /// Stand-in answers, each in its character's voice, reacting to the one before when there is one.
    static let fake: Colony.ChatFake = { name, message, earlier in
        let topic = message.split(separator: " ").prefix(4).joined(separator: " ")
        let before = earlier.last?.name
        switch name {
        case "Blocky": return before.map { "\($0) is wrong, as usual. \"\(topic)\"? I'd rather glare at the cursor." } ?? "\"\(topic)\"? Fine. As long as the cursor stays off my edge."
        case "Pip": return before.map { "Ha! \($0) said it! Oh, I love this, tell me more!" } ?? "Ooh, \"\(topic)\"! That's the best thing anyone's said to me today!"
        case "Mortimer": return "Ahh. \"\(topic)\"… As my grandmother never said: the edge is long, but the evening is longer."
        case "Zed": return "Mm… \(topic)… sounds nice… can we talk about it after a nap…"
        case "Dot": return before.map { "Faster than \($0), as always. Yes. Next question." } ?? "Answered before you finished typing. Next!"
        case "Ruth": return "Noted. That is the third message today. I am keeping count."
        case "Unit 7": return "Message received: \(message.count) characters. Joy level: 7 of 10. Processing… done."
        case "Boo": return "Boo? Oh! A message! For me? I'll float around with it for a while."
        default: return before.map { "Like \($0) said, more or less. But mostly: hello!" } ?? "Hello! \"\(topic)\": I'll think about that on my edge."
        }
    }

    /// One message, the answers on stderr; true when anyone answered.
    static func once(_ text: String, to: String?, controller: ChatController, colony: Colony, settings: AppSettings, spend: SpendLedger) async -> Bool {
        let start = Date()
        func log(_ line: String) { FileHandle.standardError.write(Data(String(format: "chat %6.2f  %@\n", Date().timeIntervalSince(start), line).utf8)) }
        colony.trace = { line in if line.hasPrefix("chat") || line.hasPrefix("say") || line.hasPrefix("cue") { log(line) } }
        controller.trace = { log($0) }
        controller.refresh()
        let names = controller.model.targets.map(\.name)
        log("on screen: \(names.joined(separator: ", ")); brain \(settings.brain.title)\(controller.fake != nil ? " (stand-in answers)" : ""), voice \(settings.voiceEnabled && settings.chatSpeak ? "on" : "off"), bubbles \(settings.chatBubbles ? "on" : "off"), length \(settings.chatLength.rawValue)")
        if let to, to.lowercased() != "all" {
            guard let name = names.first(where: { $0.lowercased() == to.lowercased() }) else { log("nobody called \(to) on screen"); return false }
            controller.choose(name)
        } else {
            controller.choose(nil)
        }
        guard controller.model.hasModel else { log(OwnerChat.noModel); return false }
        let before = chatSpend(spend)
        controller.send(text)
        await controller.finished()
        try? await Task.sleep(for: .seconds(1))
        let answers = controller.model.lines.filter { !$0.isOwner }
        for line in answers { log("answer \(line.speaker): \(line.text)\(line.cost.map { " (" + Spend.label($0) + ")" } ?? "")") }
        let after = chatSpend(spend)
        log(String(format: "%d answered in %.1f s; Chat with you: %d calls, %@", answers.count, Date().timeIntervalSince(start),
                   after.calls - before.calls, Spend.label(after.cost - before.cost)))
        // Let the voice finish what it is saying before quitting.
        for _ in 0..<300 where !colony.voicedLines.isEmpty { try? await Task.sleep(for: .seconds(0.1)) }
        for line in colony.ownerChatDump() { log(line) }
        return !answers.isEmpty
    }

    /// The window on the real screen, a message sent when given, written to a PNG.
    static func window(to: String?, send: String?, snapshot: URL?, controller: ChatController, colony: Colony) async -> Bool {
        controller.trace = { FileHandle.standardError.write(Data("\($0)\n".utf8)) }
        colony.trace = { line in if line.hasPrefix("chat") { FileHandle.standardError.write(Data("\(line)\n".utf8)) } }
        controller.show(to: to.flatMap { $0.lowercased() == "all" ? nil : $0 })
        try? await Task.sleep(for: .seconds(1))
        if let send {
            controller.send(send)
            await controller.finished()
            try? await Task.sleep(for: .seconds(0.5))
        }
        if let snapshot { try? controller.snapshot(to: snapshot) }
        controller.close()
        return true
    }

    private static func chatSpend(_ spend: SpendLedger) -> Spend.Total {
        spend.summary.byPurpose.first { $0.purpose == Spend.Purpose.chat.title }?.total ?? Spend.Total()
    }
}
