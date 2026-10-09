import CoreGraphics
import Foundation
import Testing
@testable import LedgelingsCore

/// Who sleeps in which bed, how the favourite place is learned, and the file it is kept in.
@Suite struct BedsTests {
    static let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

    /// Every character of every shipped species, and Blocky's built-in cast.
    static var shipped: [String] {
        let sprites = root.appendingPathComponent("Sources/Ledgelings/Resources/sprites")
        let names = ((try? FileManager.default.contentsOfDirectory(atPath: sprites.path)) ?? []).filter { $0.hasSuffix(".json") }
        let casts = names.flatMap { file -> [String] in
            guard let data = try? Data(contentsOf: sprites.appendingPathComponent(file)),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let cast = json["cast"] as? [[String: Any]] else { return [] }
            return cast.compactMap { $0["name"] as? String }
        }
        return Banter.defaultCharacters.map(\.name) + casts
    }

    @Test func everyShippedCharacterHasABedOfItsOwn() {
        let names = Self.shipped
        #expect(names.count == 27)
        for name in names { #expect(Beds.builtIn[name] != nil, "\(name) has no bed") }
        let beds = names.compactMap { Beds.builtIn[$0] }
        #expect(Set(beds).count == names.count, "no two characters share a bed")
        #expect(Set(beds) == Set(Beds.Kind.allCases), "and every picture is somebody's")
    }

    @Test func aNewCharacterGetsABedFromItsWords() {
        #expect(Beds.kind(name: "Tom", persona: "Purrs a lot.", kind: "a small pixel creature") == .catbed)
        #expect(Beds.kind(name: "Bolt", persona: "Curious and new here.", kind: "a tall robot with a lamp") == .dock)
        #expect(Beds.kind(name: "Nobody", persona: "Curious and new here.", kind: "a small pixel creature") == .matchbox, "small")
        #expect(Beds.kind(name: "X", persona: "", kind: "") == .grass, "a tuft of grass when nothing fits")
        #expect(Beds.kind(name: "Blocky", persona: "Purrs.", kind: "a cat") == .crate, "a built-in name keeps its own bed")
    }

    /// The app lifts a sleeper by `Kind.lift`; the painter draws the mattress at `LIFT`.
    @Test func theLiftMatchesThePainter() throws {
        let painter = try String(contentsOf: Self.root.appendingPathComponent("spritetool/painters/beds.py"), encoding: .utf8)
        let table = try #require(painter.range(of: "LIFT = {").map { painter[$0.upperBound...] }?.prefix { $0 != "}" })
        var lifts: [String: Int] = [:]
        for pair in table.split(separator: ",") {
            let parts = pair.split(separator: ":").map { $0.trimmingCharacters(in: .whitespacesAndNewlines.union(.init(charactersIn: "\""))) }
            if parts.count == 2, let n = Int(parts[1]) { lifts[parts[0]] = n }
        }
        for kind in Beds.Kind.allCases { #expect(lifts[kind.rawValue] == kind.lift, "\(kind)") }
    }

    @Test func thePullGrowsWithEveryNight() {
        #expect(Beds.pull(nights: 0, strength: 1) == 0)
        #expect(Beds.pull(nights: 1, strength: 1) == 0.5)
        #expect(Beds.pull(nights: 3, strength: 1) == 0.875)
        #expect(abs(Beds.pull(nights: 3, strength: 0.8) - 0.7) < 1e-9)
        #expect(Beds.pull(nights: 12, strength: 0) == 0, "no pull at all: they sleep where night finds them")
    }

    @Test func theFavouriteSettlesWhereItSleepsMostAndMovesWhenTheHabitWearsOff() {
        var book = Beds.Book()
        let a = CGPoint(x: 100, y: 22), b = CGPoint(x: 900, y: 22)
        book.slept("Zed", at: a)
        #expect(book.spots["Zed"] == Beds.Spot(a, nights: 1), "the first night anywhere")
        for _ in 0..<20 { book.slept("Zed", at: CGPoint(x: 110, y: 22)) }
        #expect(book.spots["Zed"]?.nights == Beds.mostNights, "the habit grows, up to a point")
        #expect(book.spots["Zed"]?.x == 110, "close enough is the same place, as it is now")
        for _ in 0..<(Beds.mostNights - 1) { book.slept("Zed", at: b) }
        #expect(book.spots["Zed"]?.x == 110 && book.spots["Zed"]?.nights == 1, "a night elsewhere wears it down")
        book.slept("Zed", at: b)
        #expect(book.spots["Zed"] == Beds.Spot(b, nights: 1), "until it moves")
    }

    @Test func aBedMovedByTheUserIsTheFavouriteAtOnce() {
        var book = Beds.Book()
        book.moved("Pip", to: CGPoint(x: 5, y: 590))
        #expect(book.spots["Pip"] == Beds.Spot(x: 5, y: 590, nights: Beds.movedNights))
        for _ in 0..<5 { book.slept("Pip", at: CGPoint(x: 5, y: 590)) }
        book.moved("Pip", to: CGPoint(x: 700, y: 590))
        #expect(book.spots["Pip"]?.nights == Beds.movedNights + 5, "moving it keeps the habit it had")
        book.forget("Pip")
        #expect(book.spots.isEmpty)
    }

    @Test func theBookSurvivesARelaunch() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("ledgelings-beds-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = Beds.Store(directory: dir)
        var book = Beds.Book()
        book.slept("Blocky", at: CGPoint(x: 320, y: 22))
        try store.save(book)
        #expect(Beds.Store(directory: dir).load() == book)
        #expect(Beds.Store(directory: dir.appendingPathComponent("nothing")).load() == Beds.Book())
    }

    @Test func everyCharacterHasItsOwnBedtimeLinesInEveryLanguage() {
        for language in Language.allCases {
            for name in Self.shipped {
                #expect(Beds.settleSets(language)[name]?.count == 2, "\(name) \(language)")
                #expect(Beds.movedSets(language)[name]?.isEmpty == false, "\(name) \(language)")
            }
        }
        var rng = SystemRandomNumberGenerator()
        let anyone = Language.$override.withValue(.english) { Beds.settleLine(by: "Stranger", bed: .grass, using: &rng) }
        #expect(anyone.contains("a tuft of grass") || !anyone.contains("{bed}"))
        #expect(!anyone.contains("{"))
    }

    @Test func wordsForWhereItSleeps() {
        let screen = CGRect(x: 0, y: 0, width: 800, height: 600)
        Language.$override.withValue(.english) {
            #expect(Beds.place(of: CGPoint(x: 400, y: 2), screens: [screen]) == "on the bottom edge")
            #expect(Beds.place(of: CGPoint(x: 400, y: 598), screens: [screen]) == "on the ceiling")
            #expect(Beds.place(of: CGPoint(x: 1, y: 300), screens: [screen]) == "on the left edge")
            #expect(Beds.place(of: CGPoint(x: 1000, y: 299), screens: [screen, CGRect(x: 800, y: 0, width: 400, height: 300)])
                    == "on the ceiling of screen 2")
        }
    }
}
