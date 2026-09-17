import Combine
import Foundation

/// Everything the user can change, saved to UserDefaults as it changes.
@MainActor
final class AppSettings: ObservableObject {
    static let countRange = 1...24
    /// Screen points per sprite pixel. Half steps stay crisp on a Retina display.
    static let sizeRange = 1.0...5.0
    static let sizeStep = 0.5
    static let defaultColors = ["#ff8a3d", "#3dc7b5", "#ff6fa3", "#ffd23d", "#9b7bff", "#7bd65a"]

    @Published var creatureCount: Int { didSet { save(creatureCount, "creatureCount") } }
    /// Creature number i wears colour i, wrapping round when there are more creatures than colours.
    @Published var colors: [String] { didSet { save(colors, "colors") } }
    /// Each creature gets its own size somewhere from `minSize` to `maxSize`.
    /// Setting one past the other drags the other along, so min <= max always holds.
    @Published var minSize: Double {
        didSet { save(minSize, "minSize"); if maxSize < minSize { maxSize = minSize } }
    }
    @Published var maxSize: Double {
        didSet { save(maxSize, "maxSize"); if minSize > maxSize { minSize = maxSize } }
    }
    @Published var dayMinutes: Double { didSet { save(dayMinutes, "dayMinutes") } }
    /// Zero means they never sleep.
    @Published var nightMinutes: Double { didSet { save(nightMinutes, "nightMinutes") } }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let count = defaults.object(forKey: "creatureCount") as? Int ?? 3
        creatureCount = min(max(count, Self.countRange.lowerBound), Self.countRange.upperBound)
        let saved = (defaults.stringArray(forKey: "colors") ?? []).filter { RGB(hex: $0) != nil }
        colors = saved.isEmpty ? Self.defaultColors : saved
        func size(_ key: String, _ fallback: Double) -> Double {
            let value = defaults.object(forKey: key) as? Double ?? fallback
            return min(max(value, Self.sizeRange.lowerBound), Self.sizeRange.upperBound)
        }
        let low = size("minSize", 1.5), high = size("maxSize", 3)
        minSize = min(low, high)
        maxSize = max(low, high)
        dayMinutes = max(0.5, defaults.object(forKey: "dayMinutes") as? Double ?? 3)
        nightMinutes = max(0, defaults.object(forKey: "nightMinutes") as? Double ?? 5)
    }

    /// The size for a creature whose place in the range is `share` (0 = smallest,
    /// 1 = largest), snapped to the step.
    func size(forShare share: Double) -> Double {
        let raw = minSize + (maxSize - minSize) * min(max(share, 0), 1)
        return (raw / Self.sizeStep).rounded() * Self.sizeStep
    }

    func color(forCreature index: Int) -> RGB {
        RGB(hex: colors[index % max(colors.count, 1)]) ?? RGB(hex: Self.defaultColors[0])!
    }

    private func save(_ value: Any, _ key: String) { defaults.set(value, forKey: key) }
}
