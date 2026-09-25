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

    @Test func aBubbleBeingSaidKeepsItsSizeAndHidesWhatIsNotSaidYet() {
        let whole = ScreenOverlay.bubbleText("Hello there")
        let half = ScreenOverlay.visibleLength(of: whole, share: 0.5)
        #expect(half == 5)
        let partly = ScreenOverlay.partly(whole, visible: half)
        #expect(partly.string == whole.string, "the whole line is laid out, so the bubble does not grow")
        let hidden = partly.attribute(.foregroundColor, at: 7, effectiveRange: nil) as? NSColor
        let shown = partly.attribute(.foregroundColor, at: 2, effectiveRange: nil) as? NSColor
        #expect(hidden == .clear && shown == .white)
        #expect(ScreenOverlay.partly(whole, visible: whole.length) == whole)
    }

    @Test func aLetterIsNeverCutInHalf() {
        let whole = ScreenOverlay.bubbleText("ab👍cd")        // the emoji is two UTF-16 units, at 2 and 3
        #expect(ScreenOverlay.visibleLength(of: whole, share: 3.0 / 6) == 2)
    }
}
