import Foundation
import Testing
@testable import LedgelingsCore

/// The effects' rules (SPEC §7.19): which moment plays which effect, cooldowns, the switches, Reduce motion,
/// the seasons; and the drawing: whole pixels only, the creature left where it stands.
struct EffectsTests {
    static func date(_ y: Int, _ m: Int, _ d: Int) -> Date {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c.date(from: DateComponents(year: y, month: m, day: d, hour: 12))!
    }
    static var utc: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }

    // MARK: Which moment fires which effect

    @Test func everyStyleAndMomentHasItsEffect() {
        for s in Effects.Style.allCases { #expect(FXCatalog.all[s.effect] != nil, "\(s)") }
        // The printed steps name a style in English whatever the app's language.
        #expect(Effects.Style.allCases.map(\.name) == ["Frost", "Smitten", "Charged", "Fired up", "Haunted"])
        for m in Effects.Moment.allCases { #expect(FXCatalog.all[m.effect] != nil, "\(m)") }
        #expect(FXCatalog.all.count == 25)
    }

    @Test func theMomentsPlayWhatTheOwnerPicked() {
        #expect(Effects.Moment.goal.effect == "ui/confetti")
        #expect(Effects.Moment.leaveScreen.effect == "arcane/blink-out")
        #expect(Effects.Moment.arriveScreen.effect == "arcane/blink-in")
        #expect(Effects.Moment.asleep.effect == "status/sleep")
        #expect(Effects.Moment.clockTicking.effect == "status/slowed")
        #expect(Effects.Moment.translating.effect == "arcane/magic-circle-cast")
        #expect(Effects.Moment.moneySpent.effect == "spawn/coin-drop")
        #expect(Effects.Moment.winter.effect == "weather/snow")
        #expect(Effects.Style.smitten.effect == "status/charmed")
        #expect(Effects.Style.haunted.effect == "status/cursed")
        // Every feature has at least one moment, every moment its feature.
        #expect(Set(Effects.Moment.allCases.map(\.feature)) == Set(Effects.Feature.allCases))
        #expect(Set(Effects.Moment.allCases.map(\.effect)).count == 20)
    }

    @Test func eachTriggerPutsOnItsStyle() {
        #expect(Effects.Trigger.friendsMeet.style == .smitten)
        #expect(Effects.Trigger.invitationAccepted.style == .smitten)
        #expect(Effects.Trigger.cursorGrab.style == .charged)
        #expect(Effects.Trigger.fastTyping.style == .charged)
        #expect(Effects.Trigger.grumpy.style == .firedUp)
        #expect(Effects.Trigger.lostGame.style == .firedUp)
        #expect(Effects.Trigger.winter.style == .frost)
        #expect(Effects.Trigger.leftAlone.style == .frost)
        #expect(Effects.Trigger.halloween.style == .haunted)
        #expect(Effects.Trigger.booSpooks.style == .haunted)
        #expect(Set(Effects.Trigger.allCases.map(\.style)) == Set(Effects.Style.allCases))
    }

    // MARK: Cooldowns

    @Test func aMomentWaitsOutItsCooldownPerCreature() {
        var rules = Effects.Rules()
        do { let ok = rules.moment(.dizzy, creature: 0, now: 100); #expect(ok) }
        do { let ok = !rules.moment(.dizzy, creature: 0, now: 100 + Effects.Moment.dizzy.cooldown - 1); #expect(ok) }
        do { let ok = rules.moment(.dizzy, creature: 1, now: 101); #expect(ok) }
        do { let ok = rules.moment(.dizzy, creature: 0, now: 100 + Effects.Moment.dizzy.cooldown); #expect(ok) }
        // Each moment has its own clock.
        do { let ok = rules.moment(.goal, creature: 0, now: 101); #expect(ok) }
        #expect(Effects.Moment.allCases.filter { !$0.held && !$0.ambient && $0.cooldown > 0 }.count >= 8)
    }

    @Test func aStyleComesByChanceAndThenWaits() {
        var rules = Effects.Rules()
        rules.switches.frequency = .sometimes
        #expect(rules.style(for: .friendsMeet, creature: 0, now: 0, roll: 0.9) == nil)      // unlucky
        do { let ok = rules.style(for: .friendsMeet, creature: 0, now: 0, roll: 0.1) == .smitten; #expect(ok) }
        #expect(rules.style(for: .invitationAccepted, creature: 0, now: 60, roll: 0) == nil)   // the same style, too soon
        #expect(rules.style(for: .cursorGrab, creature: 0, now: 60, roll: 0) == .charged)      // another style may
        do { let ok = rules.style(for: .friendsMeet, creature: 0, now: 10 * 60, roll: 0) == .smitten; #expect(ok) }
        // Often never rolls against it; a now-and-then style always takes.
        rules.switches.frequency = .often
        do { let ok = rules.style(for: .grumpy, creature: 2, now: 0, roll: 0.99) == .firedUp; #expect(ok) }
        rules.switches.frequency = .rarely
        do { let ok = rules.style(for: .winter, creature: 3, now: 0, roll: 0.99) == .frost; #expect(ok) }
        #expect(Effects.Frequency.rarely.cooldownMinutes > Effects.Frequency.often.cooldownMinutes)
        #expect(rules.nowAndThenChance(step: 30) < Effects.Rules(switches: { var s = Effects.Switches(); s.frequency = .often; return s }()).nowAndThenChance(step: 30))
    }

    // MARK: Switches

    @Test func eachSwitchTurnsItsEffectOff() {
        for m in Effects.Moment.allCases {
            var rules = Effects.Rules()
            rules.switches.moments.remove(m)
            do { let ok = !rules.moment(m, creature: 0, now: 1e6); #expect(ok, "\(m)") }
            #expect(!rules.switches.allows(m))
            for other in Effects.Moment.allCases where other != m { #expect(rules.switches.allows(other)) }
        }
        for s in Effects.Style.allCases {
            var rules = Effects.Rules()
            rules.switches.styles.remove(s)
            for t in Effects.Trigger.allCases where t.style == s {
                let got = rules.style(for: t, creature: 0, now: 0, roll: 0)
                #expect(got == nil)
            }
            #expect(Effects.Style.allCases.filter(rules.switches.allows).count == 4)
        }
    }

    @Test func theMasterSwitchTurnsEverythingOff() {
        var rules = Effects.Rules()
        rules.switches.enabled = false
        for m in Effects.Moment.allCases { do { let ok = !rules.moment(m, creature: 0, now: 0); #expect(ok) } }
        for t in Effects.Trigger.allCases { do { let ok = rules.style(for: t, creature: 0, now: 0, roll: 0) == nil; #expect(ok) } }
        #expect(Effects.ambient(at: Self.date(2026, 1, 5), isNight: true, switches: rules.switches, calendar: Self.utc) == nil)
    }

    @Test func reduceMotionTurnsOnlyTheBusyOnesOff() {
        var s = Effects.Switches()
        s.reduceMotion = true
        #expect(!s.allows(Effects.Style.charged) && !s.allows(Effects.Style.firedUp))
        #expect(s.allows(Effects.Style.frost) && s.allows(Effects.Style.smitten) && s.allows(Effects.Style.haunted))
        #expect(!s.allows(Effects.Moment.goal) && !s.allows(Effects.Moment.winter) && !s.allows(Effects.Moment.night))
        #expect(s.allows(Effects.Moment.asleep) && s.allows(Effects.Moment.heyLook) && s.allows(Effects.Moment.clockTicking))
        // The setting follows the system unless chosen.
        #expect(Effects.ReduceMotion.system.isOn(system: true))
        #expect(!Effects.ReduceMotion.system.isOn(system: false))
        #expect(Effects.ReduceMotion.on.isOn(system: false))
        #expect(!Effects.ReduceMotion.off.isOn(system: true))
    }

    // MARK: Seasons

    @Test func winterIsDecemberToFebruaryAcrossTheNewYear() {
        let c = Self.utc
        #expect(Effects.Season.of(Self.date(2026, 11, 30), calendar: c) == .autumn)
        #expect(Effects.Season.of(Self.date(2026, 12, 1), calendar: c) == .winter)
        #expect(Effects.Season.of(Self.date(2026, 12, 31), calendar: c) == .winter)
        #expect(Effects.Season.of(Self.date(2027, 1, 1), calendar: c) == .winter)
        #expect(Effects.Season.of(Self.date(2028, 2, 29), calendar: c) == .winter)
        #expect(Effects.Season.of(Self.date(2027, 3, 1), calendar: c) == .spring)
        #expect(Effects.Season.of(Self.date(2027, 5, 31), calendar: c) == .spring)
        #expect(Effects.Season.of(Self.date(2027, 7, 15), calendar: c) == .summer)
        #expect(Effects.Season.of(Self.date(2027, 9, 1), calendar: c) == .autumn)
        #expect(Effects.Season.summer.moment == nil)
        #expect(Effects.aroundHalloween(Self.date(2026, 10, 31), calendar: c))
        #expect(Effects.aroundHalloween(Self.date(2026, 11, 1), calendar: c))
        #expect(!Effects.aroundHalloween(Self.date(2026, 11, 2), calendar: c))
        #expect(!Effects.aroundHalloween(Self.date(2026, 10, 24), calendar: c))
    }

    @Test func theAmbientParticlesFollowTheSeasonAndTheNight() {
        let s = Effects.Switches(), c = Self.utc
        #expect(Effects.ambient(at: Self.date(2027, 1, 10), isNight: false, switches: s, calendar: c) == .winter)
        #expect(Effects.ambient(at: Self.date(2027, 1, 10), isNight: true, switches: s, calendar: c) == .night)
        #expect(Effects.ambient(at: Self.date(2027, 4, 10), isNight: false, switches: s, calendar: c) == .spring)
        #expect(Effects.ambient(at: Self.date(2027, 10, 10), isNight: false, switches: s, calendar: c) == .autumn)
        #expect(Effects.ambient(at: Self.date(2027, 7, 10), isNight: false, switches: s, calendar: c) == nil)
        var off = s
        off.moments.remove(.night)
        #expect(Effects.ambient(at: Self.date(2027, 1, 10), isNight: true, switches: off, calendar: c) == .winter)
        // A minute out of every ten, the first ten minutes after launch.
        #expect(!Effects.ambientShowing(at: 30, seconds: 60, everyMinutes: 10))
        #expect(Effects.ambientShowing(at: 630, seconds: 60, everyMinutes: 10))
        #expect(!Effects.ambientShowing(at: 661, seconds: 60, everyMinutes: 10))
        #expect(Effects.ambientShowing(at: 1205, seconds: 60, everyMinutes: 10))
    }

    // MARK: Friendship and typing

    @Test func aFriendshipGrowsInStages() {
        var bond = Bonds.Bond(names: ["A", "B"])
        #expect(Effects.friendshipStage(nil) == 0)
        #expect(Effects.friendshipStage(bond) == 0)
        bond.talks = Plays.friendsAt
        #expect(Effects.friendshipStage(bond) == 1)
        bond.talks = 20
        #expect(Effects.friendshipStage(bond) == 4)
    }

    @Test func aFastHourNeedsAWholeHourOfKeys() {
        var w = Effects.TypingWatch()
        for minute in 0...60 { w.add(count: Double(minute * 100), at: Double(minute) * 60) }
        #expect(w.keysInLastHour == 6000)
        #expect(w.fast(threshold: 5000))
        #expect(!w.fast(threshold: 7000))
        var short = Effects.TypingWatch()
        for minute in 0...20 { short.add(count: Double(minute * 1000), at: Double(minute) * 60) }
        #expect(!short.fast(threshold: 5000))   // not an hour yet
    }

    // MARK: The pixels

    static let blocky: FXActor = {
        // A 10×10 square body with an outline and two black eyes, like a tiny Blocky.
        var px = [FXColor](repeating: FX.hex("#ff8a3d"), count: 100)
        for i in 0..<10 { px[i] = FX.hex("#3b1f0f"); px[90 + i] = FX.hex("#3b1f0f"); px[i * 10] = FX.hex("#3b1f0f"); px[i * 10 + 9] = FX.hex("#3b1f0f") }
        px[3 * 10 + 5] = FX.black; px[3 * 10 + 7] = FX.black; px[4 * 10 + 5] = FX.black; px[4 * 10 + 7] = FX.black
        return FXActor(w: 10, h: 10, pixels: px)
    }()

    @Test func anEffectFrameIsWholePixelsAndLeavesTheCreatureInPlace() {
        for (id, type) in FXCatalog.all.sorted(by: { $0.key < $1.key }) {
            var o = FXOptions(meta: type.meta, actor: Self.blocky, seed: 5)
            o.x = Double(type.meta.origin.x); o.y = Double(type.meta.origin.y)
            let fx = FXInstance(type, options: o)
            let whole = FXFrame(type.meta.size.w, type.meta.size.h), behind = FXFrame(type.meta.size.w, type.meta.size.h)
            let a = o.actor, ax = Int(o.x) + a.x, ay = Int(o.y) + a.y
            var t = 0.0
            for step in [0.2, 0.5, 0.7, 0.6] {
                fx.update(step); t += step
                let shown = fx.render(into: whole)
                let rgba = FXComposite.rgba(whole)
                #expect(stride(from: 3, to: rgba.count, by: 4).allSatisfy { rgba[$0] == 0 || rgba[$0] == 255 }, "\(id) at \(t) s")
                // What is behind it never paints over it: back and creature alone, the creature is all there.
                guard shown else { continue }
                behind.clear()
                fx.draw(behind, .back)
                for yy in 0..<a.h { for xx in 0..<a.w where a.pixels[yy * a.w + xx] != 0 {
                    behind.color[(ay + yy) * behind.w + ax + xx] = a.pixels[yy * a.w + xx]
                } }
                // Where the front left the creature alone, the picture is the creature's own colour, exactly.
                var kept = 0
                for yy in 0..<a.h { for xx in 0..<a.w where a.pixels[yy * a.w + xx] != 0 {
                    let i = (ay + yy) * whole.w + ax + xx
                    guard whole.color[i] == behind.color[i], whole.light[i] == 0 else { continue }
                    kept += 1
                    let c = a.pixels[yy * a.w + xx]
                    #expect(rgba[i * 4] == UInt8(c & 255) && rgba[i * 4 + 1] == UInt8((c >> 8) & 255) && rgba[i * 4 + 2] == UInt8((c >> 16) & 255) && rgba[i * 4 + 3] == 255,
                            "\(id): the creature's pixel at \(xx),\(yy) moved or changed")
                } }
                _ = kept
            }
        }
    }

    @Test func theNativePortStepsLikePixelfx() {
        // pixelfx's mulberry32 and hash, number for number.
        let r = Rng(3)
        #expect(String(format: "%.12f", r.next()) == "0.720226783771")
        #expect(FX.hash(1, 2, 3) == 2_901_138_804)
        #expect(FX.round(-2.5) == -2 && FX.round(2.5) == 3)
        #expect(FX.i32(-1.5) == -1 && FX.byte(-1.5) == 255 && FX.i32(4_294_967_297) == 1)
    }
}
