import CoreGraphics

/// The Stop button: while a surf, a dive or a game runs, a plate in the top-right
/// corner of the monitor it runs on, a stop sign and the words "Stop · Control +
/// Option + Q". It is the only part of the overlay a click lands on; the click
/// stops the activity, as the shortcut and the menu do. What it says and where it
/// sits, worked out here; the colony draws it.
public enum StopButton {
    /// The words on it: the key written out, so nobody has to know the symbols. Only "Stop"
    /// while the shortcut is off.
    public static func label(spokenShortcut: String?) -> String {
        guard let key = spokenShortcut, !key.isEmpty else { return tr("Stop") }
        return tr("Stop · %@", key)
    }

    /// The tag hovering shows under it.
    public static func tag(spokenShortcut: String?) -> String {
        guard let key = spokenShortcut, !key.isEmpty else { return tr("Stop the activity") }
        return tr("Stop the activity (%@)", key)
    }

    /// Points from the screen's right edge and from under the menu bar.
    public static let margin: CGFloat = 12

    /// Where a button of `size` sits on a monitor whose frame is `screen` (global points, y up):
    /// its top-right corner, `topInset` below the top (the menu bar, the notch's band), and
    /// below anything in `avoiding` it would cover there (the surfing score board).
    public static func frame(size: CGSize, on screen: CGRect, topInset: CGFloat, avoiding: [CGRect] = []) -> CGRect {
        var place = CGRect(x: screen.maxX - margin - size.width, y: screen.maxY - topInset - margin - size.height,
                           width: size.width, height: size.height)
        // Each in the way pushes it down below itself; checked again, as moving down may meet another.
        for _ in 0..<avoiding.count {
            guard let hit = avoiding.first(where: { $0.intersects(place) }) else { break }
            place.origin.y = hit.minY - margin - size.height
        }
        return place
    }

    /// The stop sign, in the game's style: an eight-sided red plate made of steps (no curves), a
    /// 1-pixel dark outline, a light line top-left, a shade line bottom-right, a white bar across.
    /// `o` outline, `l` light, `r` red, `s` shade, `w` white, `.` nothing.
    public static let icon: [String] = [
        "...oooooo...",
        "..olllllro..",
        ".olrrrrrrso.",
        "olrrrrrrrrso",
        "olrrrrrrrrso",
        "olwwwwwwwwso",
        "olwwwwwwwwso",
        "olrrrrrrrrso",
        "olrrrrrrrrso",
        ".orrrrrrrso.",
        "..osssssso..",
        "...oooooo...",
    ]
}
