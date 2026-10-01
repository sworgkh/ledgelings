import CoreGraphics
import Testing
@testable import LedgelingsCore

/// Where and when each character plants its flower, and the flowers in the ground.
@Suite struct GardenTests {
    func temper(_ name: String) -> Garden.Temper {
        let c = Banter.defaultCharacters.first { $0.name == name }!
        return Garden.temper(persona: c.persona, kind: Banter.defaultKind)
    }

    func around(floor: Bool = true, corner: CGFloat = 500, creature: CGFloat = 200, flower: CGFloat = .infinity,
                night: Bool = false) -> Garden.Surroundings {
        Garden.Surroundings(inward: floor ? CGVector(dx: 0, dy: 1) : CGVector(dx: 0, dy: -1),
                            toCorner: corner, toCreature: creature, toFlower: flower, isNight: night)
    }

    @Test func theBuiltInCastEachHaveTheirOwnWay() {
        #expect(temper("Blocky").likes == [.floor, .alone], "the bottom edge is the only respectable edge; grumpy")
        #expect(temper("Pip").likes == [.ceiling, .company], "loves the ceiling; cheerful")
        #expect(temper("Ruth").likes.first == .row, "keeps count")
        #expect(temper("Zed").likes.first == .night, "would rather be napping")
        #expect(temper("Dot").keep < 0.1, "fast: plants at once")
        #expect(temper("Dot").likes.isEmpty, "and anywhere")
        #expect(temper("Mortimer").keep > temper("Pip").keep, "old and slow: wears it a while")
        #expect(temper("Blocky").keep > temper("Mortimer").keep, "proud: shows it off longest")
    }

    @Test func everyShippedCharacterLikesSomewhere() {
        let shipped = ["Whiskers": "Aloof. Pretends not to care, then asks what you are doing.",
                       "Morel": "Quiet and earthy. Speaks slowly about damp places and patience.",
                       "Puddle": "Anxious. Worried about drying out, evaporating, or being stepped on.",
                       "Unit 7": "Literal and precise. Reports its own status in numbers.",
                       "Sprocket": "Enthusiastic about maintenance. Offers to tighten everyone's bolts."]
        #expect(Garden.temper(persona: shipped["Whiskers"]!, kind: "a cat").likes.first == .alone)
        #expect(Garden.temper(persona: shipped["Morel"]!, kind: "a mushroom").likes.sorted { $0.rawValue < $1.rawValue } == [.alone, .floor])
        #expect(Garden.temper(persona: shipped["Puddle"]!, kind: "a slime").likes.first == .corner)
        #expect(Garden.temper(persona: shipped["Unit 7"]!, kind: "a robot").likes.first == .corner)
        let sprocket = Garden.temper(persona: shipped["Sprocket"]!, kind: "a robot")
        #expect(sprocket.likes.first == .row && sprocket.keep < 0.1)
    }

    @Test func speciesPlantByTheirKindWhenThePersonaSaysNothing() {
        let ghost = Garden.temper(persona: "Says boo a lot.", kind: "a little round ghost, hovering just above the edge")
        #expect(ghost.likes == [.ceiling])
        let nobody = Garden.temper(persona: "Curious and new here.", kind: "a small pixel creature")
        #expect(nobody.likes.isEmpty)
        #expect(nobody.keep == 0.25)
    }

    @Test func thePersonaOutranksTheKind() {
        let t = Garden.temper(persona: "Loves the ceiling.", kind: "a frog that sits in the pond")
        #expect(t.likes == [.ceiling, .floor])
    }

    @Test func itWearsTheFlowerBeforeItPlantsIt() {
        let blocky = temper("Blocky")
        #expect(!Garden.wantsToPlant(blocky, share: blocky.keep - 0.01, around: around()))
        #expect(Garden.wantsToPlant(blocky, share: blocky.keep, around: around()))
    }

    @Test func itWaitsForAPlaceItLikesThenMakesDo() {
        let blocky = temper("Blocky")
        let ceilingNearSomeone = around(floor: false, creature: 50)
        #expect(!Garden.wantsToPlant(blocky, share: blocky.keep, around: ceilingNearSomeone))
        #expect(!Garden.wantsToPlant(blocky, share: 0.89, around: ceilingNearSomeone))
        #expect(Garden.wantsToPlant(blocky, share: Garden.lastChance, around: ceilingNearSomeone), "rather than let it wilt")
    }

    @Test func atFirstOnlyTheFavouriteWillDoThenAnySecondChoice() {
        let blocky = temper("Blocky")
        let ceilingAlone = around(floor: false, creature: 1_000)
        #expect(!Garden.wantsToPlant(blocky, share: blocky.keep, around: ceilingAlone), "only the floor, at first")
        #expect(Garden.wantsToPlant(blocky, share: 0.8, around: ceilingAlone), "later, alone will do")
    }

    @Test func placesFit() {
        #expect(Garden.fits(.floor, around()))
        #expect(Garden.fits(.ceiling, around(floor: false)))
        #expect(Garden.fits(.wall, Garden.Surroundings(inward: CGVector(dx: -1, dy: 0), toCorner: 500, toCreature: 500,
                                                       toFlower: .infinity, isNight: false)))
        #expect(Garden.fits(.corner, around(corner: 30)) && !Garden.fits(.corner, around(corner: 300)))
        #expect(Garden.fits(.alone, around(creature: .infinity)) && !Garden.fits(.alone, around(creature: 100)))
        #expect(Garden.fits(.company, around(creature: 100)))
        #expect(Garden.fits(.row, around(flower: 40)) && !Garden.fits(.row, around()), "a row needs a first flower")
        #expect(Garden.fits(.night, around(night: true)) && Garden.fits(.day, around()))
    }

    @Test func flowersStayTheirTimeAndTheOldestMakesRoom() {
        var garden = Garden()
        for (i, flower) in ["poppy", "tulip", "daisy"].enumerated() {
            garden.plant(flower, at: CGPoint(x: Double(i) * 100, y: 0), rotation: 0, scale: 2, by: "Blocky",
                         at: Double(i), lasts: 60, most: 2)
        }
        #expect(garden.beds.map(\.flower) == ["tulip", "daisy"])
        garden.update(at: 61.5, most: 2)
        #expect(garden.beds.map(\.flower) == ["daisy"])
        garden.update(at: 62, most: 2)
        #expect(garden.beds.isEmpty)
    }

    @Test func fewerAllowedWiltsTheOldest() {
        var garden = Garden()
        for i in 0..<4 { garden.plant("rose", at: CGPoint(x: Double(i) * 100, y: 0), rotation: 0, scale: 2, by: "Ruth",
                                      at: Double(i), lasts: 600, most: 10) }
        garden.update(at: 5, most: 1)
        #expect(garden.beds.map(\.planted) == [3])
    }

    @Test func aFlowerNeedsRoom() {
        var garden = Garden()
        garden.plant("rose", at: .zero, rotation: 0, scale: 2, by: "Ruth", at: 0, lasts: 60, most: 10)
        #expect(!garden.hasRoom(at: CGPoint(x: 20, y: 0), scale: 2))
        #expect(garden.hasRoom(at: CGPoint(x: 30, y: 0), scale: 2))
        #expect(garden.distance(to: CGPoint(x: 30, y: 40)) == 50)
    }

    @Test func itComesUpOutOfTheGround() {
        var garden = Garden()
        garden.plant("lily", at: .zero, rotation: 0, scale: 2, by: "Zed", at: 10, lasts: 60, most: 10)
        #expect(Garden.grown(garden.beds[0], at: 10) == 0)
        #expect(Garden.grown(garden.beds[0], at: 10 + Garden.growTime / 2) == 0.5)
        #expect(Garden.grown(garden.beds[0], at: 20) == 1)
    }

    @Test func aHatCanBeTakenOffToPlant() {
        var gifts = Gifts(flightTime: 0.5)
        gifts.give("daisy", from: 0, to: 1, at: 0)
        gifts.update(at: 0.5, wearFor: 100)
        #expect(gifts.worn(1, at: 50.5) == 0.5)
        #expect(gifts.takeOff(1)?.flower == "daisy")
        #expect(gifts.hat(of: 1) == nil && gifts.worn(1, at: 51) == nil)
    }

    @Test func aTemperReadsAsASentence() {
        #expect(Garden.describe(temper("Blocky")) == "After showing it off for most of its time, on the bottom edge or where nobody is.")
        #expect(Garden.describe(temper("Dot")) == "At once, wherever it is.")
        #expect(Garden.describe(Garden.Temper(keep: 0.25, likes: [.row, .corner, .night]))
                == "After a little while, beside the flowers already planted, in a corner or after dark.")
    }
}
