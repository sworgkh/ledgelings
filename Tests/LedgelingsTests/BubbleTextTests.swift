import AppKit
import LedgelingsCore
import Testing
@testable import Ledgelings

/// The bubble shows the model's marks as faces, not as asterisks.
@MainActor
@Suite struct BubbleTextTests {
    @Test func italicAndBoldRunsGetTheirOwnFaces() {
        let text = ScreenOverlay.bubbleText("Ah, *sighs* ... the **good** edge.")
        #expect(text.string == "Ah, sighs ... the good edge.")
        var faces: [String] = []
        text.enumerateAttribute(.font, in: NSRange(location: 0, length: text.length)) { value, _, _ in
            faces.append((value as? NSFont)?.fontName ?? "?")
        }
        #expect(faces.count == 5)
        #expect(faces[1] != faces[0], "the italic run has a different face from plain text")
        #expect(faces[3] != faces[0], "so does the bold one")
        #expect(faces[4] == faces[0])
    }

    @Test func aChatLineKeepsTheSpeakerBoldAndStylesTheText() {
        let line = ChatHistoryView.spoken(ChatLog.Line(speaker: "Pip", text: "I *am* here."))
        #expect(String(line.characters) == "Pip: I am here.")
    }
}
