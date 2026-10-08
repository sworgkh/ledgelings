import AppKit
import Foundation
import LedgelingsCore
import Testing
@testable import Ledgelings

/// Revenge's settings, and the colony grabbing the cursor, holding it and letting go.
@MainActor
@Suite(.serialized) struct RevengeSettingsTests {
    let name = "ledgelings-revenge-settings-tests"

    /// Records what the colony does to the pointer, instead of moving the real one.
    @MainActor final class FakePointer: PointerHold {
        var onMove: ((CGPoint) -> Void)?
        var onEscape: (() -> Void)?
        var canMove = true
        var pinnedAt: CGPoint?
        var heldAgain = 0
        var released = 0
        var following = 0
        func pin(at point: CGPoint) -> Bool { pinnedAt = canMove ? point : nil; return canMove }
        func follow() { following += 1 }
        func hold(at point: CGPoint) { heldAgain += 1 }
        func release() { released += 1; pinnedAt = nil }
    }

    @Test func theDefaultsAndAChangeSurviveARelaunch() {
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        defer { defaults.removePersistentDomain(forName: name) }
        let s = AppSettings(defaults: defaults, keychain: Keychain(service: name))
        #expect(s.revengeEnabled)
        #expect(s.revengeAfter == 10 && s.revengeWindowSeconds == 120 && s.revengeHoldSeconds == 0, "until shaken off")
        #expect(s.revengeShakes == 4 && s.revengeShakeStroke == 20 && s.revengeShakeWindowSeconds == 2, "a wiggle, not a fight")
        #expect(!s.revengePinsCursor, "it rides along")
        #expect(s.revengeTauntSeconds == 15 && s.revengeCooldownMinutes == 10)
        s.revengeEnabled = false; s.revengeAfter = 15; s.revengeWindowSeconds = 300; s.revengeHoldSeconds = 20
        s.revengeShakes = 9; s.revengeCooldownMinutes = 45; s.revengeShakeStroke = 40; s.revengeShakeWindowSeconds = 1.5
        s.revengePinsCursor = true; s.revengeTauntSeconds = 30
        let again = AppSettings(defaults: defaults, keychain: Keychain(service: name))
        #expect(!again.revengeEnabled && again.revengeAfter == 15 && again.revengeWindowSeconds == 300)
        #expect(again.revengeHoldSeconds == 20 && again.revengeShakes == 9 && again.revengeCooldownMinutes == 45)
        #expect(again.revengeShakeStroke == 40 && again.revengeShakeWindowSeconds == 1.5)
        #expect(again.revengePinsCursor && again.revengeTauntSeconds == 30)
        defaults.set(1, forKey: "revengeAfter"); defaults.set(999.0, forKey: "revengeHoldSeconds")
        defaults.set(0, forKey: "revengeShakes"); defaults.set(0.0, forKey: "revengeCooldownMinutes"); defaults.set(1.0, forKey: "revengeWindowSeconds")
        defaults.set(500.0, forKey: "revengeShakeStroke"); defaults.set(0.1, forKey: "revengeShakeWindowSeconds"); defaults.set(-5.0, forKey: "revengeTauntSeconds")
        let clamped = AppSettings(defaults: defaults, keychain: Keychain(service: name))
        #expect(clamped.revengeAfter == 3 && clamped.revengeHoldSeconds == 30 && clamped.revengeShakes == 2, "clamped on load")
        #expect(clamped.revengeCooldownMinutes == 1 && clamped.revengeWindowSeconds == 30)
        #expect(clamped.revengeShakeStroke == 60 && clamped.revengeShakeWindowSeconds == 1 && clamped.revengeTauntSeconds == 0)
    }

    /// A colony whose creature 0 has been hunted one short of revenge, with a fake pointer.
    func world() throws -> (ColonyTalkTests.World, FakePointer) {
        let w = try ColonyTalkTests.World()
        let pointer = FakePointer()
        w.settings.complainEnabled = false
        w.settings.huntTalkEnabled = false
        w.settings.revengeAfter = 4
        w.colony.applySettings()
        w.colony.pointer = pointer
        w.colony.mouseIsDown = { false }
        w.colony.pointerLocation = { CGPoint(x: 400, y: 300) }
        for _ in 0..<3 { w.colony.bothered(0) }
        #expect(w.colony.grab == nil, "not yet")
        return (w, pointer)
    }

    @Test func huntedOnceTooOftenItGrabsTheCursorAndSaysSo() throws {
        let (w, pointer) = try world()
        defer { w.forget() }
        w.colony.bothered(0)
        #expect(w.colony.grab?.index == 0 && w.colony.creatures[0].isHeld)
        #expect(pointer.pinnedAt == nil && pointer.following == 1, "it rides along: the pointer stays free, its moves are heard")
        #expect(w.colony.grab?.pinned == false)
        #expect(w.colony.bubbles[0] != nil, "it tells the user off")
        let me = w.colony.character(forCreature: 0).name
        let saved = w.history.days().flatMap(w.history.exchanges(on:))
        #expect(saved.last?.lines.first?.speaker == me, "into the Chats tab")
    }

    @Test func shakingHardThrowsItOffWithALastWord() throws {
        let (w, pointer) = try world()
        defer { w.forget() }
        w.settings.revengePinsCursor = true
        w.settings.revengeShakes = 6
        w.colony.bothered(0)
        #expect(pointer.pinnedAt == CGPoint(x: 400, y: 300), "held still, the real pointer is held where it was")
        w.colony.bubbles.removeAll()
        // Fine, even strokes of 60 points, back and forth, a frame each.
        for k in 0..<12 where w.colony.grab != nil {
            w.colony.advance(dt: 1.0 / 30, cursor: CGPoint(x: 400 + (k.isMultiple(of: 2) ? 60 : -60), y: 300), shift: false)
        }
        #expect(w.colony.grab == nil, "shaken off")
        #expect(pointer.heldAgain > 0, "held the pointer back while it struggled")
        #expect(pointer.released == 1)
        #expect(w.colony.creatures[0].isJumping, "tumbling down")
        #expect(w.colony.bubbles[0] != nil, "a last word")
    }

    @Test func gentleMovesDoNotShakeItOff() throws {
        let (w, _) = try world()
        defer { w.forget() }
        w.colony.bothered(0)
        for k in 0..<60 { w.colony.advance(dt: 1.0 / 30, cursor: CGPoint(x: 400 + (k.isMultiple(of: 2) ? 5 : -5), y: 300), shift: false) }
        #expect(w.colony.grab != nil)
    }

    @Test func itLetsGoByItselfAfterTheLongestHold() throws {
        let (w, pointer) = try world()
        defer { w.forget() }
        w.settings.revengeHoldSeconds = 3
        w.colony.bothered(0)
        for _ in 0..<80 { w.colony.advance(dt: 0.05, cursor: CGPoint(x: 400, y: 300), shift: false) }
        #expect(w.colony.grab == nil && pointer.released == 1, "3 s and it lets go")
        #expect(!w.colony.creatures[0].isHeld)
    }

    @Test func escapeLetsGoAtOnce() throws {
        let (w, pointer) = try world()
        defer { w.forget() }
        w.colony.bothered(0)
        pointer.onEscape?()
        #expect(w.colony.grab == nil && pointer.released == 1 && !w.colony.creatures[0].isHeld)
        #expect(pointer.onMove == nil, "it stops listening")
    }

    @Test func afterAGrabTheCooldownKeepsTheCursorFree() throws {
        let (w, pointer) = try world()
        defer { w.forget() }
        w.colony.bothered(0)
        pointer.onEscape?()
        for _ in 0..<10 { w.colony.bothered(1) }
        #expect(w.colony.grab == nil, "nobody grabs again for ten minutes")
        w.step(601)
        for _ in 0..<4 { w.colony.bothered(1) }
        #expect(w.colony.grab?.index == 1)
    }

    @Test func offItNeverGrabs() throws {
        let (w, pointer) = try world()
        defer { w.forget() }
        w.settings.revengeEnabled = false
        w.colony.applySettings()
        for _ in 0..<20 { w.colony.bothered(0) }
        #expect(w.colony.grab == nil && pointer.pinnedAt == nil)
    }

    @Test func turningItOffMidGrabLetsGo() throws {
        let (w, pointer) = try world()
        defer { w.forget() }
        w.colony.bothered(0)
        w.settings.revengeEnabled = false
        w.colony.applySettings()
        #expect(w.colony.grab == nil && pointer.released == 1)
    }

    @Test func notWhileTheUserHoldsTheMouseButton() throws {
        let (w, pointer) = try world()
        defer { w.forget() }
        w.colony.mouseIsDown = { true }
        w.colony.bothered(0)
        #expect(w.colony.grab == nil && pointer.pinnedAt == nil, "mid-drag")
        w.colony.mouseIsDown = { false }
        w.colony.bothered(0)
        #expect(w.colony.grab != nil, "the next chase, once the button is up")
    }

    @Test func withoutControlOfThePointerItClingsAndRidesAlong() throws {
        let (w, pointer) = try world()
        defer { w.forget() }
        w.settings.revengePinsCursor = true
        pointer.canMove = false
        w.colony.bothered(0)
        #expect(w.colony.grab?.pinned == false)
        w.colony.advance(dt: 1.0 / 30, cursor: CGPoint(x: 200, y: 200), shift: false)
        let p = w.colony.creatures[0].position
        #expect(abs(p.x - 200) < 40 && abs(p.y - 200) < 40, "it hangs from the cursor wherever it goes: \(p)")
        #expect(pointer.heldAgain == 0, "never moves the pointer")
    }

    @Test func ridingAlongItFollowsTheCursorAndNeverMovesIt() throws {
        let (w, pointer) = try world()
        defer { w.forget() }
        w.colony.bothered(0)
        for (k, x) in [300.0, 200, 150, 120].enumerated() {
            w.colony.advance(dt: 0.5, cursor: CGPoint(x: x, y: 300 - Double(k) * 40), shift: false)
        }
        let p = w.colony.creatures[0].position
        #expect(abs(p.x - 120) < 40 && abs(p.y - 180) < 40, "it hangs from the cursor wherever it goes: \(p)")
        #expect(pointer.heldAgain == 0 && pointer.pinnedAt == nil, "never moves the pointer")
        #expect(w.colony.grab != nil, "slow moves are not a shake")
    }

    @Test func withNoLimitItHoldsOnUntilShakenOff() throws {
        let (w, pointer) = try world()
        defer { w.forget() }
        w.colony.bothered(0)
        for _ in 0..<1200 { w.colony.advance(dt: 0.1, cursor: CGPoint(x: 400, y: 300), shift: false) }
        #expect(w.colony.grab != nil && pointer.released == 0, "two minutes on, still there")
    }

    @Test func aGentleWiggleShakesItOff() throws {
        let (w, _) = try world()
        defer { w.forget() }
        w.colony.bothered(0)
        // Strokes of 25 points, a tenth of a second each: four turns back in half a second.
        for k in 0..<8 where w.colony.grab != nil {
            w.colony.advance(dt: 0.1, cursor: CGPoint(x: 400 + (k.isMultiple(of: 2) ? 25 : 0), y: 300), shift: false)
        }
        #expect(w.colony.grab == nil, "shaken off with the default four")
    }

    @Test func holdingThePointerStillItNeverHoldsOnPastTenSeconds() throws {
        let (w, pointer) = try world()
        defer { w.forget() }
        w.settings.revengePinsCursor = true
        w.colony.bothered(0)
        for _ in 0..<95 { w.colony.advance(dt: 0.1, cursor: CGPoint(x: 400, y: 300), shift: false) }
        #expect(w.colony.grab != nil)
        for _ in 0..<10 { w.colony.advance(dt: 0.1, cursor: CGPoint(x: 400, y: 300), shift: false) }
        #expect(w.colony.grab == nil && pointer.released == 1, "the safety limit, even with no limit set")
    }

    @Test func itTellsYouOffAgainNowAndThen() throws {
        let (w, _) = try world()
        defer { w.forget() }
        w.settings.revengeTauntSeconds = 5
        w.colony.bothered(0)
        var lines = 0, last = w.colony.bubbles[0]?.serial
        for _ in 0..<900 {
            w.colony.advance(dt: 0.1, cursor: CGPoint(x: 400, y: 300), shift: false)
            if let s = w.colony.bubbles[0]?.serial, s != last { lines += 1; last = s }
        }
        #expect(lines >= 3, "again five seconds after the last bubble is gone: \(lines) in 90 s")
        w.settings.revengeTauntSeconds = 0
        let quiet = w.colony.bubbles[0]?.serial
        for _ in 0..<300 { w.colony.advance(dt: 0.1, cursor: CGPoint(x: 400, y: 300), shift: false) }
        #expect(w.colony.bubbles[0] == nil || w.colony.bubbles[0]?.serial == quiet, "never again with it off")
    }

    @Test func hidingInTheHouseLetsGo() throws {
        let (w, pointer) = try world()
        defer { w.forget() }
        w.colony.bothered(0)
        w.colony.hide(for: 30)
        #expect(w.colony.grab == nil && pointer.released == 1)
    }
}
