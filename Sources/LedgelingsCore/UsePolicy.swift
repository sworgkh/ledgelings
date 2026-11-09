import Foundation

/// When "Stop when I use the computer" stops a running activity: a key press or
/// a click that came after it started (and after a short grace, so the click
/// or key that started it does not stop it), unless the click was on a
/// creature. Moving the mouse alone never counts.
public enum UsePolicy {
    /// Seconds after an activity starts in which nothing stops it: the click on
    /// the menu, the shortcut's own key coming up.
    public static let grace = 0.6
    /// A click this close to one the creatures took is that same click.
    public static let sameClick = 0.25

    /// `runningFor`: seconds since the activity started; the others are seconds
    /// since the last key press, the last click anywhere, the last click on a creature.
    public static func stops(runningFor: Double, sinceKey: Double, sinceClick: Double, sinceOwnClick: Double) -> Bool {
        guard runningFor > grace else { return false }
        let window = runningFor - grace
        if sinceKey < window { return true }
        if sinceClick < window, abs(sinceClick - sinceOwnClick) > sameClick { return true }
        return false
    }
}
