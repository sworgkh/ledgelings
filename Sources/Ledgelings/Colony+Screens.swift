import AppKit
import LedgelingsCore

/// Which monitors the creatures live on (`homeScreen`), and moving house.
///
/// Every overlay stays up on every monitor, so a creature is drawn wherever it
/// is; only the edges they walk, the sky a plane flies in, the house, the
/// garden and the cursor they grab are limited to the home monitors. Choosing
/// another monitor live, each creature not on it springs up out of the top of
/// its screen and comes down on the new one by parachute, one after another.
extension Colony {

    /// A creature on its way to the monitors the colony lives on now.
    struct Move {
        enum Stage {
            /// Springing up and out of its old screen.
            case leaving(HomeScreen.Hop)
            /// Out of sight, until its turn to come down.
            case waiting(until: Double)
            /// Under its parachute, over the new monitor.
            case arriving(Plays.Chute)
        }
        var stage: Stage
        /// When it comes down, on the colony's clock: arrivals are spaced out.
        var turn: Double
    }

    /// The monitors as `HomeScreen` sees them.
    var monitors: [HomeScreen.Monitor] {
        displays.map { HomeScreen.Monitor(id: $0.id, name: $0.name, frame: $0.frame) }
    }

    /// The monitors the creatures live on: the chosen one while attached, else all.
    var homeDisplays: [Display] {
        let home = Set(HomeScreen.home(settings.homeScreen, among: monitors).map(\.id))
        let picked = displays.filter { home.contains($0.id) }
        return picked.isEmpty ? displays : picked
    }

    var homeFrames: [CGRect] { homeDisplays.map(\.frame) }

    /// Whether `point` is on a monitor they live on.
    func isHome(_ point: CGPoint, slack: CGFloat = 0) -> Bool {
        HomeScreen.isHome(point, in: homeFrames, slack: slack)
    }

    /// Whether creature `i` is moving house.
    func isMoving(_ i: Int) -> Bool { moves[i] != nil }

    // MARK: When the home changes

    /// The setting or the monitors changed: if the home monitors are not what
    /// they were, the edges are traced afresh and whoever is not on them moves over.
    func homeMayHaveChanged() {
        let home = homeFrames
        guard home != homeWas else { return }
        homeWas = home
        trace?("screens home " + homeDisplays.map { $0.name.isEmpty ? "\($0.frame)" : $0.name }.joined(separator: ", "))
        moveHome()
    }

    /// Rebuild the edges on the home monitors and send everyone not there over.
    func moveHome() {
        // Whatever they were up to across the old edges is off.
        letGo()
        letGoOfCursor(.escape)
        endPlay(completed: false)
        // Movers still on the way finish where they are, then everyone is judged afresh.
        for i in Array(moves.keys) { landNow(i) }
        worlds.removeAll()
        replantAfterScreensChanged()
        var leaving: [Int] = []
        for i in creatures.indices {
            // Its centre is always inside the screen it walks; outside every home one, it moves.
            if hideout.isInside(i) || isHome(creatures[i].position, slack: 1) {
                creatures[i].rehome(to: world(forSize: sizes[i]))
            } else {
                leaving.append(i)
            }
        }
        if leaving.contains(where: { teaParty?.involves($0) == true }) { breakUpTea() }
        if !leaving.isEmpty { releaseChat() }
        var turn = elapsed
        for i in leaving.shuffled(using: &rng) {
            guard creatures[i].takeOff(waking: true) else { creatures[i].rehome(to: world(forSize: sizes[i])); continue }
            bedTrips.removeValue(forKey: i)
            gardeners.remove(i)
            busy.insert(i)
            let half = atlas.bodyHalfSize * CGFloat(sizes[i])
            let p = creatures[i].position
            if let screen = displays.first(where: { $0.frame.contains(p) }) {
                let hop = HomeScreen.Hop(from: p, rotation: creatures[i].rotation, gone: screen.frame.maxY + half * 3,
                                         way: creatures[i].isMirrored ? -1 : 1)
                turn = max(turn, elapsed + HomeScreen.Hop.crouch + hop.flightTime)
                moves[i] = Move(stage: .leaving(hop), turn: turn)
                trace?("move \(character(forCreature: i).name) hops off \(screen.name.isEmpty ? "\(screen.frame)" : screen.name)")
            } else {
                // On a monitor that is gone: nothing to see leave, it just comes down.
                moves[i] = Move(stage: .waiting(until: turn), turn: turn)
            }
            turn += HomeScreen.arrivalGap
        }
        render()
    }

    // MARK: Every frame

    func updateMoves(dt: Double) {
        for i in Array(moves.keys) {
            guard var move = moves[i], creatures.indices.contains(i) else { moves.removeValue(forKey: i); continue }
            switch move.stage {
            case .leaving(var hop):
                hop.update(dt: dt)
                creatures[i].carry(to: hop.position, rotation: hop.rotation, pose: hop.pose)
                move.stage = hop.isGone ? .waiting(until: move.turn) : .leaving(hop)
            case .waiting(let until):
                guard elapsed >= until else { break }
                guard let chute = chute(for: i) else { landNow(i); continue }
                creatures[i].carry(to: chute.position, rotation: chute.rotation, pose: chute.pose)
                move.stage = .arriving(chute)
                trace?(String(format: "move %@ comes down at %.0f", character(forCreature: i).name, chute.position.x))
            case .arriving(var chute):
                let events = chute.update(dt: dt)
                creatures[i].carry(to: chute.position, rotation: chute.rotation, pose: chute.pose)
                move.stage = .arriving(chute)
                if events.contains(.packed) {
                    moves[i] = move
                    landNow(i)
                    trace?(String(format: "move %@ lands at (%.0f, %.0f)", character(forCreature: i).name,
                                  creatures[i].position.x, creatures[i].position.y))
                    continue
                }
            }
            moves[i] = move
        }
    }

    /// A parachute over a random spot of the home floor, starting just above the
    /// top of that monitor, out of sight; nil if the home has no floor at all.
    private func chute(for i: Int) -> Plays.Chute? {
        let w = world(forSize: sizes[i]), half = atlas.bodyHalfSize * CGFloat(sizes[i])
        for frame in homeFrames.shuffled(using: &rng) {
            let margin = min(half * 3, frame.width / 2)
            let x = CGFloat.random(in: (frame.minX + margin)...(frame.maxX - margin), using: &rng)
            guard let floor = w.floor(under: CGPoint(x: x, y: frame.maxY)) else { continue }
            // Brisker than the game's float, and never more than about 4.5 s down a tall monitor.
            let speed = max(CGFloat(settings.parachuteFallSpeed) * 1.6, (frame.maxY - floor.y) / 4.5)
            return Plays.Chute(from: CGPoint(x: min(max(x, floor.span.lowerBound), floor.span.upperBound), y: frame.maxY + half * 1.5),
                               floorY: floor.y, floor: floor.span, fallSpeed: speed)
        }
        return nil
    }

    /// Done moving (or cut short): onto the nearest home edge, walking.
    func landNow(_ i: Int) {
        moves.removeValue(forKey: i)
        busy.remove(i)
        guard creatures.indices.contains(i) else { return }
        creatures[i].rehome(to: world(forSize: sizes[i]))
    }

    /// The open parachutes of everyone coming down, in global points.
    func moveProps() -> [PropSnapshot] {
        moves.compactMap { i, move -> PropSnapshot? in
            guard case .arriving(let chute) = move.stage, chute.canopy > 0, creatures.indices.contains(i) else { return nil }
            let c = creatures[i], scale = CGFloat(sizes[i]), open = CGFloat(chute.canopy)
            let half = atlas.bodyHalfSize * scale
            let up = CGVector(dx: -sin(c.rotation), dy: cos(c.rotation))
            let lift = half * 0.8 + playCell.height * scale * open / 2
            return PropSnapshot(image: playFrames.frame(animation: "chute", time: 0),
                                position: CGPoint(x: c.position.x + up.dx * lift, y: c.position.y + up.dy * lift),
                                rotation: c.rotation, scale: scale * open)
        }
    }

    // MARK: For the menu, the sheet and the settings

    /// Every attached monitor, by name, left to right; and which one is chosen.
    var screenChoices: [HomeScreen.Monitor] { monitors.sorted { ($0.frame.minX, -$0.frame.maxY) < ($1.frame.minX, -$1.frame.maxY) } }

    /// `--screens`: the monitors, the choice and the edges they walk, one line each.
    func describeScreens() -> [String] {
        var lines = displays.map { d in
            String(format: "screen %@ \"%@\" %.0f,%.0f %.0f×%.0f%@", d.id, d.name, d.frame.minX, d.frame.minY, d.frame.width, d.frame.height,
                   homeDisplays.contains(d) ? " home" : "")
        }
        let chosen = settings.homeScreen
        lines.append(chosen == HomeScreen.all ? "chosen: all screens"
                     : "chosen: \(chosen) \"\(settings.homeScreenName)\"\(HomeScreen.isAway(chosen, among: monitors) ? " (away: living on all)" : "")")
        let bounds = homeFrames.reduce(CGRect.null) { $0.union($1) }
        lines.append(String(format: "colony bounds %.0f,%.0f %.0f×%.0f", bounds.minX, bounds.minY, bounds.width, bounds.height))
        for i in creatures.indices {
            let p = creatures[i].position
            lines.append(String(format: "creature %@ at (%.0f, %.0f)%@", character(forCreature: i).name, p.x, p.y, isHome(p, slack: 1) ? "" : " OFF HOME"))
        }
        return lines
    }
}
