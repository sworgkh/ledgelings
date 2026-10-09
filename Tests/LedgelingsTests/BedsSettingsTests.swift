import AppKit
import Foundation
import LedgelingsCore
import Testing
@testable import Ledgelings

/// The Beds tab's settings, the favourites on disk, and the colony putting beds
/// down, walking to them, and letting the user move them.
@MainActor
@Suite(.serialized) struct BedsSettingsTests {
    let name = "ledgelings-beds-settings-tests"

    @Test func theDefaultsAndAChangeSurviveARelaunch() {
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        defer { defaults.removePersistentDomain(forName: name) }
        let s = AppSettings(defaults: defaults, keychain: Keychain(service: name))
        #expect(s.bedsEnabled && s.bedTalk)
        #expect(s.bedPull == 80 && s.bedWalkDistance == 2000)
        s.bedsEnabled = false; s.bedTalk = false; s.bedPull = 35; s.bedWalkDistance = 600
        let again = AppSettings(defaults: defaults, keychain: Keychain(service: name))
        #expect(!again.bedsEnabled && !again.bedTalk && again.bedPull == 35 && again.bedWalkDistance == 600)
        defaults.set(500.0, forKey: "bedPull"); defaults.set(1.0, forKey: "bedWalkDistance")
        let clamped = AppSettings(defaults: defaults, keychain: Keychain(service: name))
        #expect(clamped.bedPull == 100 && clamped.bedWalkDistance == 100, "clamped on load")
    }

    @Test func theFavouritesSurviveARelaunch() {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("ledgelings-bedbook-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let book = BedBook(directory: dir)
        book.slept("Blocky", at: CGPoint(x: 300, y: 22)); book.moved("Zed", to: CGPoint(x: 10, y: 400))
        let relaunched = BedBook(directory: dir)
        #expect(relaunched.spot(of: "Blocky") == Beds.Spot(x: 300, y: 22, nights: 1))
        #expect(relaunched.spot(of: "Zed")?.nights == Beds.movedNights)
        relaunched.forget("Zed")
        #expect(BedBook(directory: dir).spot(of: "Zed") == nil && BedBook(directory: dir).spot(of: "Blocky") != nil)
        relaunched.forget()
        #expect(BedBook(directory: dir).book == Beds.Book())
    }

    /// Creature 0, alone on screen (nobody overlaps it), asleep by hand, its bed out under it.
    func napping(_ w: ColonyTalkTests.World) {
        w.settings.creatureCount = 1
        w.colony.applySettings()
        w.colony.creatures[0].toggleNap(using: &w.colony.rng)
        w.step(0.5)
    }

    @Test func aSleeperLiesInItsBedAndFoldsItAwayOnWaking() throws {
        let w = try ColonyTalkTests.World()
        defer { w.forget() }
        napping(w)
        #expect(w.colony.bedSince[0] != nil && w.colony.bedSnapshots().count == 1)
        let shown = try #require(w.colony.bedSnapshots().first)
        #expect(shown.image != nil, "its own picture, from the beds sheet")
        let lift = w.colony.bedLift(of: 0)
        #expect(hypot(lift.dx, lift.dy) == CGFloat(w.colony.bedKind(of: 0).lift) * CGFloat(w.colony.sizes[0]), "raised onto the mattress")
        #expect(w.colony.describe(0).contains(w.colony.bedKind(of: 0).title), "the prompt knows")
        #expect(w.colony.beds.spot(of: w.colony.character(forCreature: 0).name) == nil, "a nap teaches it nothing")
        w.colony.creatures[0].toggleNap(using: &w.colony.rng)
        w.step(0.1)
        #expect(w.colony.bedSince[0] == nil && w.colony.bedSnapshots().count == 1, "fading")
        w.step(0.5)
        #expect(w.colony.bedSnapshots().isEmpty, "gone")
    }

    @Test func withBedsOffTheySleepOnTheBareEdge() throws {
        let w = try ColonyTalkTests.World()
        defer { w.forget() }
        w.settings.bedsEnabled = false
        napping(w)
        #expect(w.colony.creatures[0].isSleeping)
        #expect(w.colony.bedSince.isEmpty && w.colony.bedSnapshots().isEmpty)
        #expect(w.colony.bedLift(of: 0) == .zero)
    }

    @Test func atNightfallItWalksToItsFavouritePlaceAndTheHabitGrows() throws {
        let w = try ColonyTalkTests.World()
        defer { w.forget() }
        w.settings.creatureCount = 1
        w.settings.bedPull = 100
        w.colony.applySettings()
        let me = w.colony.character(forCreature: 0).name
        let c = w.colony.creatures[0]
        // A place 300 points along its own loop, slept in for many nights.
        let favourite = c.loop.point(at: c.loop.wrap(c.t + 300))
        for _ in 0..<Beds.mostNights { w.colony.beds.slept(me, at: favourite) }
        var lines: [String] = []
        w.colony.trace = { lines.append($0) }
        w.colony.skipPhase()
        var waited = 0.0
        while waited < 60, !(w.colony.creatures[0].isSleeping && w.colony.bedTrips.isEmpty) { w.step(0.5); waited += 0.5 }
        let at = w.colony.creatures[0].position
        #expect(hypot(at.x - favourite.x, at.y - favourite.y) <= Beds.near, "asleep at its favourite: \(lines)")
        // It walks there, unless night found it passing by already.
        #expect(lines.contains { $0.hasPrefix("bed \(me) walks to") } || lines.contains { $0.hasPrefix("bed \(me) sleeps") })
        #expect(w.colony.beds.spot(of: me)?.nights == Beds.mostNights, "kept at its strongest")
        #expect(w.colony.bedSince[0] != nil)
    }

    @Test func twoWithTheSameFavouriteSleepSideBySideNotOnTopOfEachOther() throws {
        let w = try ColonyTalkTests.World()
        defer { w.forget() }
        w.settings.bedPull = 100
        w.settings.minSize = 2; w.settings.maxSize = 2
        w.colony.applySettings()
        let c = w.colony.creatures[0]
        let shared = c.loop.point(at: c.loop.wrap(c.t + 200))
        for i in 0..<2 {
            let name = w.colony.character(forCreature: i).name
            for _ in 0..<Beds.mostNights { w.colony.beds.slept(name, at: shared) }
        }
        w.colony.skipPhase()
        var waited = 0.0
        while waited < 90, !(w.colony.creatures.allSatisfy(\.isSleeping) && w.colony.bedTrips.isEmpty) { w.step(0.5); waited += 0.5 }
        let loop = w.colony.creatures[0].loop, d = loop.wrap(w.colony.creatures[1].t - w.colony.creatures[0].t)
        #expect(w.colony.creatures.allSatisfy { $0.isSleeping })
        #expect(min(d, loop.length - d) >= w.colony.bedCell.width * 2, "a bed's width apart along the edge, at least")
    }

    @Test func tooFarAlongTheEdgeItSleepsWhereItIs() throws {
        let w = try ColonyTalkTests.World()
        defer { w.forget() }
        w.settings.creatureCount = 1
        w.settings.bedPull = 100
        w.settings.bedWalkDistance = 100
        w.colony.applySettings()
        let me = w.colony.character(forCreature: 0).name
        let c = w.colony.creatures[0]
        let favourite = c.loop.point(at: c.loop.wrap(c.t + c.loop.length / 2))
        for _ in 0..<3 { w.colony.beds.slept(me, at: favourite) }
        w.colony.skipPhase()
        w.step(12)
        #expect(w.colony.creatures[0].isSleeping && w.colony.bedTrips.isEmpty)
        #expect(w.colony.beds.spot(of: me)?.nights == 2, "a night elsewhere wears the habit down")
    }

    @Test func draggingABedMovesTheFavouriteAndIsNotAHunt() throws {
        let w = try ColonyTalkTests.World()
        defer { w.forget() }
        napping(w)
        let me = w.colony.character(forCreature: 0).name
        let bed = try #require(w.colony.bedSnapshots().first)
        // Just above the bed's foot, at its end: the bed, not the sleeper's body.
        let half = w.colony.bedCell.width * bed.scale / 2 - 2
        let up = CGVector(dx: -sin(bed.rotation), dy: cos(bed.rotation))
        let grip = CGPoint(x: bed.floor.x + up.dx * 2 + up.dy * half, y: bed.floor.y + up.dy * 2 - up.dx * half)
        #expect(w.colony.bed(at: grip) == 0 && !w.colony.onBody(0, grip))
        w.colony.hand(.down(grip, shift: false))
        #expect(w.colony.creatures[0].isHeld && w.colony.bedCarry == 0)
        let target = CGPoint(x: 400, y: 120)
        w.colony.hand(.dragged(target))
        #expect(!w.colony.bedSnapshots().isEmpty, "the bed goes with it")
        w.colony.hand(.up(target))
        w.step(1.5)
        #expect(w.colony.creatures[0].isSleeping && w.colony.bedCarry == nil, "landed, still asleep, in its bed")
        let spot = try #require(w.colony.beds.spot(of: me))
        let landed = w.colony.creatures[0].position
        #expect(hypot(spot.x - landed.x, spot.y - landed.y) < 1, "the new place is the favourite")
        #expect(spot.nights == Beds.movedNights)
        #expect(w.colony.hunts.numbers(of: me).all == 0, "not counted as a chase")
        #expect(BedBook(directory: w.colony.beds.store.directory).spot(of: me) == spot, "saved for the next launch")
    }

    @Test func aPlainPressOnTheSleeperStillPicksItUpAndThatIsAHunt() throws {
        let w = try ColonyTalkTests.World()
        defer { w.forget() }
        w.settings.complainEnabled = false
        napping(w)
        let me = w.colony.character(forCreature: 0).name
        w.colony.hand(.down(w.colony.drawnPosition(of: 0), shift: false))
        #expect(w.colony.creatures[0].isHeld && w.colony.bedCarry == nil)
        w.step(0.1)
        #expect(w.colony.bedSnapshots().allSatisfy { $0.opacity < 1 }, "carried off, its bed folds away")
        #expect(w.colony.hunts.numbers(of: me).all == 1)
        w.colony.hand(.up(CGPoint(x: 300, y: 300)))
        w.step(1.5)
        #expect(w.colony.beds.spot(of: me) == nil, "carrying the sleeper is not moving its bed")
        #expect(w.colony.bedSince[0] != nil, "but where it lands it sleeps in its bed")
    }
}
