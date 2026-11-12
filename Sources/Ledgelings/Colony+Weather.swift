import AppKit
import LedgelingsCore

/// What the weather keeps between frames (`Colony+Weather`).
@MainActor
final class WeatherState {
    var switches = Weather.Switches()
    var spell: Weather.Spell?
    var wind: Weather.Wind?
    /// The sky of each home monitor, its frame and its last picture, in the order of `homeDisplays`.
    var skies: [(display: CGRect, sky: Weather.Sky, frame: FXFrame, image: CGImage?)] = []
    var nextDraw = 0.0
    /// The cursor's path, for "the cursor barely moved".
    var trail = Weather.CursorTrail()
    var nextSample = 0.0
    var nextCheck = 0.0
    /// When the last spell ended: the next comes a quiet while later, not at once.
    var endedAt = -1e9
    var windows: [WeatherWatch.Window] = []
    var nextWindows = 0.0
    var fullScreen = false
    /// The windows were just read again: the ledges follow.
    var windowsFresh = false
    var microphone = false
    var nextMicrophone = 0.0
    /// Each creature's own walking pace, kept while the weather slows or speeds it.
    var pace: [Int: CGFloat] = [:]
    /// Where each walker last left a footprint, by creature.
    var printedAt: [Int: CGFloat] = [:]
    /// The umbrellas: who shares with whom, and each holder's colour.
    var groups: [[Int]] = []
    var nextGroups = 0.0
    var said: Set<String> = []
    /// The umbrellas of creatures hanging from the top edge, filling with rain.
    var bowls: [Int: Weather.Bowl] = [:]
    /// Umbrellas falling or fallen: where, how fast, its turn, and its picture.
    var dropped: [(at: CGPoint, vy: CGFloat, rotation: Double, spin: Double, image: CGImage?, scale: CGFloat, landed: Bool)] = []
    /// Creatures dripping wet until then.
    var wetUntil: [Int: Double] = [:]
    /// Umbrellas blown inside out until then.
    var insideOutUntil: [Int: Double] = [:]
    var snowmen: [(at: CGPoint, sky: Int, column: Int)] = []
    var snowballs: [(from: CGPoint, by: Int, to: Int, age: Double)] = []
    var nextDeed = 0.0
    var lastLine = -1e9
    var time = 0.0
    var umbrellaImages: [String: CGImage] = [:]
    lazy var snowmanImage: CGImage? = WeatherState.image(Weather.snowman())
    lazy var snowballImage: CGImage? = WeatherState.image(Weather.snowball())
    lazy var dripImage: CGImage? = WeatherState.image(Weather.drip())
    /// `--weather-film` and `--weather`: every step, as it happens.
    var trace: ((String) -> Void)?
    /// The film says where the windows are rather than the Mac.
    var fakeWindows: [WeatherWatch.Window]?

    static func image(_ art: Weather.Art) -> CGImage? { picture(art.rgba, art.w, art.h) }

    /// RGBA bytes as a picture, premultiplied: pixel art's alpha is all or nothing, so the bytes are the same, and
    /// Core Animation's Metal renderer draws a whole monitor's worth of it (straight alpha that size, it drops the
    /// layer and every layer after it).
    static func picture(_ rgba: [UInt8], _ w: Int, _ h: Int) -> CGImage? {
        guard let provider = CGDataProvider(data: Data(rgba) as CFData) else { return nil }
        return CGImage(width: w, height: h, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: w * 4,
                       space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                       provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)
    }
}

/// Weather on a quiet screen (SPEC §7.20): it comes when nobody has typed or moved the cursor for a while,
/// falls over the creatures' monitors, piles up, and eases off when the owner comes back. The creatures wade,
/// shiver, build snowmen, throw snowballs, open umbrellas, get soaked on the menu bar and are pushed by the wind.
/// Everything is drawn on the click-through overlay.
extension Colony {
    /// Screen points per art pixel of the sky.
    static let skyScale: CGFloat = 2
    /// Seconds between two weather lines from anyone.
    static let weatherLineGap = 9.0

    var weatherShowing: Bool { weather.spell != nil }

    // MARK: Starting and stopping

    /// Weather starts now: from the menu, Play now, the film, or the quiet screen. False when it is off.
    @discardableResult
    func startWeather(_ kind: Weather.Kind, byHand: Bool = true) -> Bool {
        refreshWeatherSwitches()
        guard byHand || weather.switches.allows(kind) else { return false }
        weather.spell = Weather.Spell(kind: kind, lasts: weather.switches.lastsMinutes * 60, byHand: byHand)
        weather.wind = kind.blows ? Weather.Wind(fromLeft: Bool.random(using: &rng), strength: weather.switches.windStrength) : nil
        weather.time = 0
        weather.said = []
        weather.groups = []
        weather.bowls = [:]
        weather.insideOutUntil = [:]
        weather.nextDeed = elapsed + 12
        layOutSkies()
        weather.trace?("weather \(kind.name) starts")
        // The light season particles give way to the heavier weather.
        if let a = fx.ambient, a.tiles.first?.byHand != true { a.tiles.forEach { $0.instance.stop() } }
        if kind.snows { weatherLine("snow", by: weatherSpeaker()) }
        if kind.rains { weatherLine("rain", by: weatherSpeaker()) }
        if kind == .wind { weatherLine("wind", by: weatherSpeaker()) }
        return true
    }

    /// Clear: whatever falls eases off; the snow on the ground melts slowly.
    func clearWeather() {
        guard weather.spell != nil else { return }
        weather.spell?.ease()
        weather.trace?("weather eases off")
    }

    /// Everything gone at once (the film between kinds, a test).
    func resetWeather() {
        weather.spell = nil
        weather.wind = nil
        restorePaces()
        weather.skies = []
        weather.dropped = []
        weather.snowmen = []
        weather.snowballs = []
        weather.bowls = [:]
        weather.wetUntil = [:]
        weather.groups = []
    }

    func refreshWeatherSwitches() {
        let s = settings.weatherSwitches(systemReduceMotion: reduceMotionFromSystem)
        if s != weather.switches {
            if s.snowDepth != weather.switches.snowDepth { weather.skies.forEach { $0.sky.setDepth(s.snowDepth) } }
            weather.switches = s
        }
    }

    /// One sky per home monitor, made afresh when the monitors change (the snow lying there goes with them).
    private func layOutSkies() {
        let frames = homeFrames
        if weather.skies.map(\.display) == frames { return }
        weather.skies = frames.enumerated().map { k, f in
            let w = Int(f.width / Self.skyScale), h = Int(f.height / Self.skyScale)
            let sky = Weather.Sky(width: w, height: h, depth: weather.switches.snowDepth, seed: 7 + Double(k) * 13)
            sky.onShower = { [weak self] x, n in self?.weather.trace?("snow falls off a window at \(x): \(n) flakes") }
            return (f, sky, FXFrame(w, h), nil)
        }
    }

    // MARK: Every frame

    func updateWeather(dt: Double) {
        refreshWeatherSwitches()
        let s = weather.switches
        if !s.enabled, weather.spell?.byHand == false { weather.spell?.ease() }
        watchTheScreen()
        if var spell = weather.spell {
            weather.time += dt
            if !spell.byHand, Weather.isBack(keyIdle: WeatherWatch.keyIdle, recentTravel: weather.trail.travel(since: elapsed - 2)), !spell.isEasing {
                spell.ease()
                weather.trace?("weather eases off: someone is back")
            }
            let was = spell.isEasing
            spell.update(dt)
            if spell.isEasing && !was { weather.trace?("weather eases off") }
            weather.spell = spell
            if spell.isOver {
                weather.spell = nil
                weather.wind = nil
                weather.endedAt = elapsed
                restorePaces()
                weather.trace?("weather \(spell.kind.name) over")
            }
        }
        guard !weather.skies.isEmpty || weather.spell != nil else { return }
        layOutSkies()
        updateSkies(dt: dt)
        updateWeatherCreatures(dt: dt)
        if weather.spell == nil, weather.skies.allSatisfy({ $0.sky.isEmpty }), weather.dropped.isEmpty {
            weather.skies = []
            weather.snowmen = []
            weather.wetUntil = [:]
            weather.trace?("weather all melted")
        }
    }

    /// The cursor, the keys, full-screen apps and the microphone: whether the screen is quiet, and weather may come.
    private func watchTheScreen() {
        if elapsed >= weather.nextSample {
            weather.nextSample = elapsed + 0.5
            weather.trail.add(NSEvent.mouseLocation, at: elapsed, keep: max(60, weather.switches.quietMinutes * 60))
        }
        if elapsed >= weather.nextWindows {
            weather.nextWindows = elapsed + 0.5
            weather.windows = weather.fakeWindows ?? (stage == nil ? WeatherWatch.windows() : [])
            weather.fullScreen = WeatherWatch.fullScreen(weather.windows, screens: displays.map(\.frame))
            weather.windowsFresh = true
        }
        guard weather.spell == nil, elapsed >= weather.nextCheck else { return }
        let step = 10.0
        weather.nextCheck = elapsed + step
        let s = weather.switches
        guard s.enabled, stage == nil else { return }
        if elapsed >= weather.nextMicrophone {
            weather.nextMicrophone = elapsed + 30
            weather.microphone = WeatherWatch.microphoneInUse
        }
        let meeting = weather.microphone || (settings.effectsCalendar && fx.meetings.inMeetingNow(at: now()))
        let screen = Weather.Screen(keyIdle: WeatherWatch.keyIdle, cursorTravel: weather.trail.travel(since: elapsed - s.quietMinutes * 60),
                                    fullScreen: weather.fullScreen, activity: Activities.shared.isRunning, meeting: meeting)
        // A whole quiet stretch watched, and one since the last spell ended.
        guard weather.trail.span >= min(s.quietMinutes * 60, 60) - 1, elapsed - weather.endedAt >= s.quietMinutes * 60,
              Weather.isQuiet(screen, minutes: s.quietMinutes) else { return }
        guard Double.random(in: 0..<1, using: &rng) < Weather.chance(step: step, frequency: s.frequency),
              let kind = Weather.pick(Effects.Season.of(now()), switches: s, roll: Double.random(in: 0..<1, using: &rng)) else { return }
        startWeather(kind, byHand: false)
    }

    private func updateSkies(dt: Double) {
        let s = weather.switches, spell = weather.spell
        let drift = spell.flatMap { sp in weather.wind?.drift(at: weather.time, intensity: sp.intensity) } ?? 0
        let leafy = Effects.Season.of(now()) == .autumn
        for k in weather.skies.indices {
            let entry = weather.skies[k]
            entry.sky.leafy = leafy
            if s.windowTops && weather.windowsFresh {
                entry.sky.setLedges(WeatherWatch.ledges(weather.windows, on: entry.display, scale: Self.skyScale, topInset: topInset(of: entry.display)),
                                    depth: s.snowDepth)
            }
            entry.sky.update(dt, kind: spell?.kind, intensity: spell?.intensity ?? 0, drift: drift, heaviness: s.rainHeaviness,
                             depth: s.snowDepth, windowTops: s.windowTops, reduced: s.reduceMotion)
        }
        weather.windowsFresh = false
    }

    private func topInset(of frame: CGRect) -> CGFloat { displays.first { $0.frame == frame }?.topInset ?? 0 }

    /// The sky under `point`, and the column there.
    func sky(at point: CGPoint) -> (index: Int, column: Int)? {
        guard let k = weather.skies.firstIndex(where: { $0.display.insetBy(dx: -1, dy: -1).contains(point) }) else { return nil }
        return (k, Int((point.x - weather.skies[k].display.minX) / Self.skyScale))
    }

    // MARK: The creatures in it

    /// On the floor (the bottom edge), or hanging from the top edge, or neither (a wall).
    private func side(of i: Int) -> (floor: Bool, ceiling: Bool) {
        let c = creatures[i]
        guard !c.isPlaying, !c.isHeld, !c.isJumping else { return (false, false) }
        let up = c.loop.inward(ofSegment: c.segment).dy
        return (up > 0.9, up < -0.9)
    }

    private func outside(_ i: Int) -> Bool { !hideout.isInside(i) && !isMoving(i) }

    private func updateWeatherCreatures(dt: Double) {
        let spell = weather.spell, s = weather.switches
        let intensity = spell?.intensity ?? 0
        let kind = spell?.kind
        let force = weather.wind?.force(at: weather.time) ?? 0
        for i in creatures.indices where outside(i) {
            let c = creatures[i]
            let (floor, ceiling) = side(of: i)
            // Wading and the wind: a slower or a faster pace.
            if c.isAtLeisure {
                let base = weather.pace[i] ?? c.config.walkSpeed
                weather.pace[i] = base
                var pace = 1.0
                if floor, let at = sky(at: c.position) {
                    let d = weather.skies[at.index].sky.depth(at: at.column)
                    pace *= Weather.wading(depth: d.depth, cap: d.cap)
                }
                if let wind = weather.wind, floor || ceiling, intensity > 0 {
                    let rightwards = Double(c.loop.direction(ofSegment: c.segment).dx) * (c.isMirrored ? -1 : 1)
                    pace *= Weather.windPace(walking: rightwards, wind: wind, force: force * intensity)
                }
                creatures[i].config.walkSpeed = base * CGFloat(pace)
            }
            // Footprints in the snow along the bottom.
            if floor, c.animation == "walk", let at = sky(at: c.position) {
                let last = weather.printedAt[i] ?? c.position.x
                if abs(c.position.x - last) >= 6 * Self.skyScale {
                    weather.printedAt[i] = c.position.x
                    if weather.skies[at.index].sky.depth(at: at.column).depth >= 2 { weather.skies[at.index].sky.footprint(at: at.column) }
                } else if weather.printedAt[i] == nil { weather.printedAt[i] = c.position.x }
            }
        }
        if let kind, kind.rains { updateUmbrellas(dt: dt, intensity: intensity) } else if !weather.groups.isEmpty { weather.groups = [] }
        if kind?.rains != true, !weather.bowls.isEmpty, spell == nil { weather.bowls = [:] }
        if let wind = weather.wind, let spell, !s.reduceMotion, wind.peaks(at: weather.time, dt: dt) { gust(wind, intensity: spell.intensity) }
        updateDropped(dt: dt)
        updateSnowballs(dt: dt)
        if kind == .snow, intensity > 0.6, elapsed >= weather.nextDeed { snowDeed() }
        // Snowmen melt with the snow they stand in.
        weather.snowmen.removeAll { m in
            guard weather.skies.indices.contains(m.sky) else { return true }
            return weather.skies[m.sky].sky.depth(at: m.column).depth < 1
        }
    }

    /// Everyone walks at their own pace again.
    func restorePaces() {
        for (i, pace) in weather.pace where creatures.indices.contains(i) { creatures[i].config.walkSpeed = pace }
        weather.pace = [:]
    }

    // MARK: Umbrellas

    /// Who is out in the rain on the floor or the top edge, grouped by the sharing distance, every second.
    private func updateUmbrellas(dt: Double, intensity: Double) {
        if elapsed >= weather.nextGroups {
            weather.nextGroups = elapsed + 1
            var standing: [Weather.Standing] = []
            for i in creatures.indices where outside(i) {
                let (floor, ceiling) = side(of: i)
                guard floor || ceiling else { continue }
                let c = creatures[i]
                // The same edge: the same loop's segment.
                standing.append(Weather.Standing(index: i, edge: c.spot.loop * 1000 + c.segment, along: Double(c.position.x)))
            }
            let groups = Weather.umbrellaGroups(standing, distance: weather.switches.shareDistance)
            if groups != weather.groups {
                for g in groups where g.count > 1 && !weather.groups.contains(g) {
                    let names = g.map { character(forCreature: $0).name }
                    weather.trace?("rain " + names.joined(separator: " & ") + " share an umbrella")
                    let holder = Weather.holder(of: g)
                    if let guest = g.first(where: { $0 != holder }), !weather.said.contains("share\(g)") {
                        weather.said.insert("share\(g)")
                        weatherLine("share", by: guest, friend: holder)
                    }
                }
                weather.groups = groups
            }
        }
        // Those sharing keep close to whoever holds it.
        for g in weather.groups where g.count > 1 {
            let holder = Weather.holder(of: g)
            for i in g where i != holder && creatures[i].isAtLeisure {
                creatures[i].head(toward: creatures[holder].t, near: atlas.bodyHalfSize * CGFloat(sizes[i]) * 1.6)
            }
        }
        // The top edge: the umbrella is a bowl, and it fills.
        for g in weather.groups {
            let holder = Weather.holder(of: g)
            guard side(of: holder).ceiling else { weather.bowls.removeValue(forKey: holder); continue }
            var bowl = weather.bowls[holder] ?? Weather.Bowl()
            if bowl.state == .fallen { continue }
            let event = bowl.update(dt, intensity: intensity, heaviness: weather.switches.rainHeaviness)
            weather.bowls[holder] = bowl
            let name = character(forCreature: holder).name
            switch event {
            case .full: weather.trace?("rain \(name) umbrella full, tips")
            case .spills:
                weather.trace?("rain \(name) umbrella full, falls")
                spillBowl(of: holder, group: g)
            case nil: break
            }
        }
    }

    /// The bowl tips: water everywhere, the creatures under it soaked, and the umbrella falls to the floor.
    private func spillBowl(of holder: Int, group: [Int]) {
        let p = umbrellaPlace(holder, group: group)
        if let at = sky(at: p.position), weather.skies.indices.contains(at.index) {
            let d = weather.skies[at.index].display
            weather.skies[at.index].sky.spill(Double((p.position.x - d.minX) / Self.skyScale), Double((d.maxY - p.position.y) / Self.skyScale))
        }
        weather.dropped.append((p.position, 0, p.rotation, Double.random(in: -5...5, using: &rng), p.image, p.scale, false))
        for i in group {
            weather.wetUntil[i] = elapsed + 25
            styleTrigger(.winter, on: i)
        }
        weatherLine("soaked", by: holder)
    }

    /// Umbrellas falling down the screen, and lying on the floor once down; gone when the weather is.
    private func updateDropped(dt: Double) {
        for k in weather.dropped.indices.reversed() {
            var d = weather.dropped[k]
            if !d.landed {
                d.vy -= 900 * CGFloat(dt)
                d.at.y += d.vy * CGFloat(dt)
                d.rotation += d.spin * dt
                let floorY = (homeFrames.first { $0.minX <= d.at.x && d.at.x <= $0.maxX }?.minY ?? 0) + 6 * d.scale
                if d.at.y <= floorY {
                    d.at.y = floorY
                    d.landed = true
                    d.rotation = .pi / 2 * (d.spin > 0 ? 1 : -1)
                    if let at = sky(at: CGPoint(x: d.at.x, y: floorY)) {
                        let disp = weather.skies[at.index].display
                        weather.skies[at.index].sky.spill(Double((d.at.x - disp.minX) / Self.skyScale), Double((disp.maxY - floorY) / Self.skyScale) + Double(6 * d.scale / Self.skyScale))
                    }
                    weather.trace?("rain umbrella lands on the floor with a splash")
                }
            }
            weather.dropped[k] = d
        }
        if weather.spell == nil { weather.dropped.removeAll() }
    }

    /// Where `holder`'s umbrella goes: over its head along its edge's inward line, a little bigger when shared.
    private func umbrellaPlace(_ holder: Int, group: [Int]) -> PropSnapshot {
        let width = Weather.umbrellaWidth(for: group.count)
        let c = creatures[holder], scale = CGFloat(sizes[holder])
        // Over the middle of everyone under it, along their edge.
        var p = drawnPosition(of: holder)
        let mates = group.filter { creatures.indices.contains($0) }
        if mates.count > 1 { p.x = mates.map { drawnPosition(of: $0).x }.reduce(0, +) / CGFloat(mates.count) }
        let colour = Weather.umbrellaColour(for: character(forCreature: holder).name)
        let insideOut = (weather.insideOutUntil[holder] ?? 0) > elapsed
        let water = weather.bowls[holder]?.water ?? 0
        let key = "\(width) \(colour) \(insideOut) \(Int(water * 5))"
        let image = weather.umbrellaImages[key] ?? {
            var art = Weather.umbrella(width: width, colour: colour, insideOut: insideOut)
            Self.fill(&art, water: water)
            let made = WeatherState.image(art)
            if weather.umbrellaImages.count > 64 { weather.umbrellaImages.removeAll() }
            weather.umbrellaImages[key] = made
            return made
        }()
        let inward = c.loop.inward(ofSegment: c.segment)
        let height = CGFloat(Weather.umbrellaDome(width: max(12, width | 1)) + 10)
        let up = (height / 2 - 2) * scale + atlas.bodyHalfSize * scale * 0.2
        let tip = weather.bowls[holder]?.tip ?? 0
        let lean = weatherLean(of: holder)
        return PropSnapshot(image: image, position: CGPoint(x: p.x + inward.dx * up, y: p.y + inward.dy * up),
                            rotation: c.rotation + lean + tip * .pi / 2, scale: scale,
                            size: CGSize(width: CGFloat(max(12, width | 1)), height: height))
    }

    /// The rain collected in an upside-down umbrella: its top rows, which hang lowest, turn to water.
    static func fill(_ art: inout Weather.Art, water: Double) {
        guard water > 0.05 else { return }
        let rows = Int((water * 4).rounded(.up))
        let blue = FX.hex("#4f82d6"), light = FX.hex("#b4d4ff")
        for y in 1...rows {
            for x in 1..<(art.w - 1) where art.at(x, y) != 0 && art.at(x - 1, y) != 0 && art.at(x + 1, y) != 0 {
                art.pixels[y * art.w + x] = y == rows ? light : blue
            }
        }
    }

    // MARK: Wind

    /// How far a creature on the floor or the top edge leans into the wind, in radians.
    func weatherLean(of i: Int) -> Double {
        guard let wind = weather.wind, let spell = weather.spell, creatures.indices.contains(i), outside(i) else { return 0 }
        let (floor, ceiling) = side(of: i)
        guard floor || ceiling else { return 0 }
        return wind.lean(at: weather.time, intensity: spell.intensity) * (ceiling ? -1 : 1)
    }

    /// A gust at its height: the light ones pushed, one on the top edge maybe blown off, umbrellas inside out.
    private func gust(_ wind: Weather.Wind, intensity: Double) {
        let force = wind.force(at: weather.time) * intensity
        weather.trace?(String(format: "wind gust %.2f from the %@", force, wind.from > 0 ? "left" : "right"))
        var blown = false
        for i in creatures.indices where outside(i) && creatures[i].isAtLeisure {
            let (floor, ceiling) = side(of: i)
            guard floor || ceiling else { continue }
            let size = sizes[i] / max(0.5, settings.minSize)        // the smallest on screen counts as 1
            let c = creatures[i], name = character(forCreature: i).name
            if ceiling, !blown, Weather.blowsOff(size: size, force: force, strength: wind.strength) {
                blown = true
                let below = homeFrames.first { $0.minX <= c.position.x && c.position.x <= $0.maxX }?.minY ?? 0
                creatures[i].leap(to: c.world.nearest(to: CGPoint(x: c.position.x + CGFloat(wind.from) * 80, y: below)))
                weather.trace?("wind blows \(name) off the top edge")
                weatherLine("blown", by: i, force: true)
                continue
            }
            let push = Weather.push(size: size, force: force, strength: wind.strength)
            guard push > 0 else { continue }
            let along = c.loop.direction(ofSegment: c.segment).dx
            creatures[i].shove(by: CGFloat(push * wind.from) * along)
            weather.trace?("wind gust pushes \(name) \(Int(push)) px")
        }
        if weather.spell?.kind.rains == true {
            for g in weather.groups {
                let holder = Weather.holder(of: g)
                guard Weather.turnsInsideOut(force: force, strength: wind.strength, roll: Double.random(in: 0..<1, using: &rng)) else { continue }
                weather.insideOutUntil[holder] = elapsed + 4
                weather.trace?("storm \(character(forCreature: holder).name) umbrella inside out")
                weatherLine("insideOut", by: holder)
            }
        } else if !weather.said.contains("gust\(Int(weather.time / 30))"), let i = weatherSpeaker() {
            weather.said.insert("gust\(Int(weather.time / 30))")
            weatherLine("wind", by: i)
        }
    }

    // MARK: Snow

    /// Now and then in deep enough snow: someone shivers, builds a snowman, or throws a snowball at a friend.
    private func snowDeed() {
        weather.nextDeed = elapsed + Double.random(in: 14...26, using: &rng)
        let onFloor = creatures.indices.filter { outside($0) && side(of: $0).floor && creatures[$0].isAtLeisure && !creatures[$0].looksAsleep }
        guard let i = onFloor.randomElement(using: &rng), let at = sky(at: creatures[i].position) else { return }
        let name = character(forCreature: i).name
        let roll = Double.random(in: 0..<1, using: &rng)
        let friends = onFloor.filter { j in
            j != i && bonds.bond(name, character(forCreature: j).name) != nil && abs(creatures[j].position.x - creatures[i].position.x) < 500
        }
        if roll < 0.35, let j = friends.randomElement(using: &rng) {
            throwSnowball(from: i, at: j)
        } else if roll < 0.7, weather.snowmen.count < 3, weather.skies[at.index].sky.canBuildSnowman(at: at.column) {
            creatures[i].pause(for: 3)
            let x = creatures[i].position.x + (creatures[i].isMirrored ? -1 : 1) * atlas.bodyHalfSize * CGFloat(sizes[i]) * 2.2
            let d = weather.skies[at.index].display
            let column = Int((x - d.minX) / Self.skyScale)
            weather.snowmen.append((CGPoint(x: x, y: d.minY), at.index, column))
            weather.trace?("snow \(name) builds a snowman")
            weatherLine("snowman", by: i, force: true)
        } else {
            styleTrigger(.winter, on: i)
            if fx.on[i] == nil { wear(.frost, on: i) }
            weather.trace?("snow \(name) shivers")
            weatherLine("cold", by: i)
        }
    }

    func throwSnowball(from i: Int, at j: Int) {
        creatures[i].face(creatures[j].position.x > creatures[i].position.x ? creatures[i].loop.direction(ofSegment: creatures[i].segment).dx : -creatures[i].loop.direction(ofSegment: creatures[i].segment).dx)
        creatures[i].pause(for: 1.5)
        let p = drawnPosition(of: i)
        weather.snowballs.append((CGPoint(x: p.x, y: p.y + atlas.bodyHalfSize * CGFloat(sizes[i])), i, j, 0))
        weather.trace?("snow \(character(forCreature: i).name) throws a snowball at \(character(forCreature: j).name)")
        weatherLine("throw", by: i, friend: j, force: true)
    }

    /// Snowballs fly in an arc for most of a second; the one hit gets a puff of snow and says so.
    private func updateSnowballs(dt: Double) {
        for k in weather.snowballs.indices.reversed() {
            weather.snowballs[k].age += dt
            let b = weather.snowballs[k]
            guard b.age >= Self.snowballFlight else { continue }
            weather.snowballs.remove(at: k)
            guard creatures.indices.contains(b.to) else { continue }
            let p = drawnPosition(of: b.to)
            if let at = sky(at: p) {
                let d = weather.skies[at.index].display
                weather.skies[at.index].sky.puff(Double((p.x - d.minX) / Self.skyScale), Double((d.maxY - p.y) / Self.skyScale))
            }
            weather.trace?("snow \(character(forCreature: b.to).name) is hit")
            lastWeatherLineAt(elapsed - Self.weatherLineGap)
            weatherLine("hit", by: b.to, friend: b.by, force: true)
        }
    }

    static let snowballFlight = 0.8

    private func lastWeatherLineAt(_ t: Double) { weather.lastLine = t }

    // MARK: Words

    /// Someone awake and outside to say the weather's first line.
    private func weatherSpeaker() -> Int? {
        creatures.indices.filter { outside($0) && !creatures[$0].looksAsleep && bubbles[$0] == nil }.randomElement(using: &rng)
    }

    /// `i` says its line for `kind` (`friend` fills `{friend}`), unless someone said one just now.
    func weatherLine(_ kind: String, by i: Int?, friend: Int? = nil, force: Bool = false) {
        guard let i, settings.weatherTalk, settings.talkEnabled, !voiceIsTaken, creatures.indices.contains(i), outside(i) else { return }
        guard force || elapsed - weather.lastLine >= Self.weatherLineGap else { return }
        weather.lastLine = elapsed
        let name = character(forCreature: i).name
        let text = Weather.line(by: name, kind, friend: friend.map { character(forCreature: $0).name } ?? "", using: &rng)
        guard !text.isEmpty else { return }
        say(text, from: i, builtIn: true)
        weather.trace?("say \(name): \(text)")
        history.record(ChatLog.Exchange(time: Date(), situation: tr("The weather: %@.", weather.spell?.kind.title.lowercased() ?? "") + " " + describe(i) + ".",
                                        provider: AppSettings.Brain.script.title, model: "",
                                        lines: [ChatLog.Line(speaker: name, text: text)], cost: nil, tokens: nil))
    }

    // MARK: Drawing

    /// Each home monitor's sky as one picture, in global points: redrawn fifteen times a second.
    func weatherPictures() -> [WeatherPicture] {
        guard !weather.skies.isEmpty else { return [] }
        if elapsed >= weather.nextDraw {
            weather.nextDraw = elapsed + 1.0 / 15
            for k in weather.skies.indices {
                let e = weather.skies[k]
                e.sky.draw(into: e.frame)
                weather.skies[k].image = WeatherState.picture(FXComposite.rgba(e.frame), e.frame.w, e.frame.h)
            }
        }
        return weather.skies.map { e in
            WeatherPicture(image: e.image, frame: CGRect(x: e.display.minX, y: e.display.maxY - CGFloat(e.frame.h) * Self.skyScale,
                                                         width: CGFloat(e.frame.w) * Self.skyScale, height: CGFloat(e.frame.h) * Self.skyScale))
        }
    }

    /// The umbrellas, the falling ones, the snowmen, the snowballs in the air and the drips off the wet.
    func weatherProps() -> [PropSnapshot] {
        var props: [PropSnapshot] = []
        if weather.spell?.kind.rains == true, (weather.spell?.intensity ?? 0) > 0.15 {
            for g in weather.groups where creatures.indices.contains(Weather.holder(of: g)) {
                let holder = Weather.holder(of: g)
                if weather.bowls[holder]?.state == .fallen { continue }
                props.append(umbrellaPlace(holder, group: g))
            }
        }
        for d in weather.dropped {
            props.append(PropSnapshot(image: d.image, position: d.at, rotation: d.rotation, scale: d.scale, size: d.image.map { CGSize(width: $0.width, height: $0.height) }))
        }
        for m in weather.snowmen where weather.skies.indices.contains(m.sky) {
            let sky = weather.skies[m.sky]
            let ground = CGFloat(sky.sky.depth(at: m.column).depth) * Self.skyScale
            props.append(PropSnapshot(image: weather.snowmanImage, position: CGPoint(x: m.at.x, y: sky.display.minY + max(0, ground - Self.skyScale * 2) + 15 * Self.skyScale / 2),
                                      rotation: 0, scale: Self.skyScale, size: CGSize(width: 11, height: 15)))
        }
        for b in weather.snowballs where creatures.indices.contains(b.to) {
            let to = drawnPosition(of: b.to), k = CGFloat(b.age / Self.snowballFlight)
            let x = b.from.x + (to.x - b.from.x) * k, y = b.from.y + (to.y - b.from.y) * k + sin(.pi * k) * 70
            props.append(PropSnapshot(image: weather.snowballImage, position: CGPoint(x: x, y: y), rotation: 0, scale: Self.skyScale,
                                      inFront: true, size: CGSize(width: 4, height: 4)))
        }
        for (i, until) in weather.wetUntil where until > elapsed && creatures.indices.contains(i) {
            let p = drawnPosition(of: i), half = atlas.bodyHalfSize * CGFloat(sizes[i])
            let inward = creatures[i].loop.inward(ofSegment: creatures[i].segment)
            for k in 0..<3 {
                let phase = (elapsed * 1.3 + Double(k) / 3).truncatingRemainder(dividingBy: 1)
                let x = p.x + CGFloat(k - 1) * half * 0.7
                let y = p.y - inward.dy * half - CGFloat(phase) * 24 * (inward.dy >= 0 ? 1 : -1)
                props.append(PropSnapshot(image: weather.dripImage, position: CGPoint(x: x, y: y), rotation: 0, scale: Self.skyScale,
                                          opacity: Float(1 - phase), inFront: true, size: CGSize(width: 1, height: 2)))
            }
        }
        return props
    }
}

/// One monitor's weather as a picture, in global points.
struct WeatherPicture {
    var image: CGImage?
    var frame: CGRect
}
