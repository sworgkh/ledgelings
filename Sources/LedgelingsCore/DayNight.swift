import Foundation

/// The colony's shared clock: a day, then a night, forever.
public struct DayNight: Equatable, Sendable {
    public var day: Double      // seconds
    public var night: Double    // seconds

    public init(day: Double, night: Double) {
        self.day = max(1, day)
        self.night = max(0, night)
    }

    public var cycle: Double { day + night }

    public func isNight(at elapsed: Double) -> Bool {
        night > 0 && elapsed.truncatingRemainder(dividingBy: cycle) >= day
    }

    /// Seconds until the current day or night ends.
    public func remaining(at elapsed: Double) -> Double {
        let phase = elapsed.truncatingRemainder(dividingBy: cycle)
        return phase >= day ? cycle - phase : day - phase
    }

    /// The smallest elapsed time after `elapsed` that falls in the other half.
    public func skippingToNextPhase(from elapsed: Double) -> Double {
        elapsed + remaining(at: elapsed)
    }
}
