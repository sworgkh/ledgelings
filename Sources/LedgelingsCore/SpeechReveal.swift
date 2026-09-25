import Foundation

/// How much of a bubble is on show while its line is being said out loud.
///
/// With voice on, a line's bubble first shows dots while the sound is fetched,
/// then types itself out as the voice speaks: in step with the words the Mac's
/// voices report, or evenly over the clip's length for a downloaded one.
/// The bubble is always sized for the whole line; the letters not yet said are
/// drawn invisible, so it does not grow and jump as the text comes in.
public enum SpeechReveal: Equatable, Sendable {
    /// Everything at once: voice off, or the line could not be said.
    case all
    /// The sound is on its way: `...`, one dot more every third of a second.
    case waiting(since: Double)
    /// A clip of `duration` seconds started playing at `start`.
    case timed(start: Double, duration: Double)
    /// A voice that reports its progress, now this far through the line.
    case spoken(Double)

    public static let dots = "..."
    /// Dots a second, while waiting.
    static let dotRate = 3.0

    /// The text to draw for `line` at time `now`, and the share of it to show (0...1).
    public func shown(_ line: String, at now: Double) -> (text: String, share: Double) {
        switch self {
        case .all:
            return (line, 1)
        case .waiting(let since):
            let step = Int(max(0, now - since) * Self.dotRate) % 3
            return (Self.dots, Double(step + 1) / 3)
        case .timed(let start, let duration):
            guard duration > 0 else { return (line, 1) }
            return (line, min(max((now - start) / duration, 0), 1))
        case .spoken(let share):
            return (line, min(max(share, 0), 1))
        }
    }

    /// How many of `count` characters a `share` shows. Never half a letter; the
    /// last one only once the share is whole.
    public static func visible(_ share: Double, of count: Int) -> Int {
        share >= 1 ? count : min(count, max(0, Int((share * Double(count)).rounded(.down))))
    }
}
