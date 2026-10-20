import CoreGraphics
import Foundation

/// Who plays the ball games, and on which side. Soccer and baseball are for
/// however many are free: one plays alone, two play each other, three play
/// one goal (soccer), and from four (soccer) or six (baseball) the crowd splits
/// into two teams, best friends on the same side.
extension Plays {

    /// How a crowd lines up, by how many there are.
    public enum Lineup: Equatable, Sendable {
        /// One: keepy-uppy and shots at an empty goal; practice swings.
        case solo
        /// Two: a goal each; a pitcher and a batter who swap.
        case duel
        /// Three at soccer: one goal, a keeper and two attackers, the keeper changing after each goal.
        case keeper
        /// Every one for itself at baseball, three to five: the rest field while one bats.
        case rotation
        /// Two teams split by friendship.
        case teams

        public static func soccer(_ count: Int) -> Lineup {
            switch count {
            case ...1: .solo
            case 2: .duel
            case 3: .keeper
            default: .teams
            }
        }

        public static func baseball(_ count: Int) -> Lineup {
            switch count {
            case ...1: .solo
            case 2: .duel
            case 3...5: .rotation
            default: .teams
            }
        }
    }

    /// Players a team game takes at most, and at the least.
    public static let teamPlayersRange = 1...10

    /// The chance a game that is due is a team game, when one is on: more
    /// likely the more of them are free to join.
    public static func teamChance(crowd: Int) -> Double {
        min(0.75, 0.3 + 0.1 * Double(max(0, crowd)))
    }

    /// A team game for `initiator` and whoever else is free (`crowd`, with how
    /// close each is to it), or nil: none is on (`enabled` holds only those whose
    /// turn it may be), or the dice say a smaller game. Its closest friends join
    /// first, then the rest, up to `maxPlayers` of that game.
    public static func chooseTeamGame(initiator: Int, crowd: [(index: Int, closeness: Double)], enabled: Set<Kind>,
                                      maxPlayers: [Kind: Int], using rng: inout some RandomNumberGenerator) -> (kind: Kind, players: [Int])? {
        let games = Kind.allCases.filter { enabled.contains($0) && $0.isTeamGame }
        guard !games.isEmpty, Double.random(in: 0..<1, using: &rng) < teamChance(crowd: crowd.count) else { return nil }
        let kind = games.randomElement(using: &rng)!
        return (kind, joining(initiator: initiator, crowd: crowd, max: maxPlayers[kind] ?? 6))
    }

    /// The initiator, then the crowd closest first (in their order when equally close), `max` in all.
    public static func joining(initiator: Int, crowd: [(index: Int, closeness: Double)], max: Int) -> [Int] {
        let ranked = crowd.enumerated().sorted { ($0.element.closeness, -$0.offset) > ($1.element.closeness, -$1.offset) }
        return [initiator] + ranked.prefix(Swift.max(0, max - 1)).map(\.element.index)
    }

    /// Two sides out of `players`, the closest friends together: of every way
    /// to split them into halves (the first player's side the bigger when odd),
    /// the one with the most closeness inside the sides. Each side keeps the
    /// players' order.
    public static func split(_ players: [Int], closeness: (Int, Int) -> Double) -> [[Int]] {
        let n = players.count
        guard n >= 2 else { return [players, []] }
        func within(_ side: [Int]) -> Double {
            var sum = 0.0
            for a in side.indices { for b in side.indices where b > a { sum += closeness(side[a], side[b]) } }
            return sum
        }
        let size = (n + 1) / 2
        var best: (score: Double, mask: Int)?
        // Every side of `size` that holds the first player.
        for mask in 0..<(1 << n) where mask & 1 == 1 && mask.nonzeroBitCount == size {
            let a = players.indices.filter { mask & (1 << $0) != 0 }.map { players[$0] }
            let b = players.indices.filter { mask & (1 << $0) == 0 }.map { players[$0] }
            let score = within(a) + within(b)
            if best == nil || score > best!.score + 1e-9 { best = (score, mask) }
        }
        let mask = best!.mask
        return [players.indices.filter { mask & (1 << $0) != 0 }.map { players[$0] },
                players.indices.filter { mask & (1 << $0) == 0 }.map { players[$0] }]
    }

    /// From six players a soccer side has a keeper: the one with the fewest
    /// friends on its side (the last of them when tied), who stays in goal.
    public static func keeper(of side: [Int], closeness: (Int, Int) -> Double) -> Int? {
        guard side.count >= 3 else { return nil }
        func ties(_ p: Int) -> Double { side.filter { $0 != p }.reduce(0) { $0 + closeness(p, $1) } }
        return side.reversed().min { ties($0) < ties($1) }
    }
}
