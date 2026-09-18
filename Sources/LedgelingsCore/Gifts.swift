import Foundation

/// Flowers: the one in the air between two creatures, and the ones on heads.
public struct Gifts: Sendable {
    public struct Flight: Equatable, Sendable {
        public var flower: String
        public var from: Int
        public var to: Int
        public var started: Double
    }

    public struct Worn: Equatable, Sendable {
        public var flower: String
        public var until: Double
    }

    /// Everything a creature can give. Each is an animation in the flowers sheet.
    public static let flowers = ["poppy", "tulip", "daisy", "sunflower", "rose", "bluebell",
                                 "dandelion", "lavender", "lily", "forget-me-not"]

    public var flightTime: Double
    public private(set) var flight: Flight?
    public private(set) var worn: [Int: Worn] = [:]

    public init(flightTime: Double = 0.6) { self.flightTime = flightTime }

    /// Start a flower on its way. Refused while another is still in the air.
    @discardableResult
    public mutating func give(_ flower: String, from: Int, to: Int, at time: Double) -> Bool {
        guard flight == nil else { return false }
        flight = Flight(flower: flower, from: from, to: to, started: time)
        return true
    }

    /// 0...1 along the flight, or nil when nothing is flying.
    public func flightProgress(at time: Double) -> Double? {
        flight.map { min(1, max(0, (time - $0.started) / max(flightTime, 1e-9))) }
    }

    public func hat(of creature: Int) -> String? { worn[creature]?.flower }

    /// Land the flight when its time is up, and drop every hat past its time.
    public mutating func update(at time: Double, wearFor: Double) {
        if let flight, time - flight.started >= flightTime {
            worn[flight.to] = Worn(flower: flight.flower, until: time + wearFor)
            self.flight = nil
        }
        worn = worn.filter { $0.value.until > time }
    }

    /// The colony shrank: creatures at `count` and beyond are gone.
    public mutating func forget(creaturesFrom count: Int) {
        worn = worn.filter { $0.key < count }
        if let flight, max(flight.from, flight.to) >= count { self.flight = nil }
    }
}
