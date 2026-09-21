import Testing
@testable import LedgelingsCore

/// Flowers in flight and flowers on heads.
@Suite struct GiftsTests {
    @Test func aGiftFliesThenSitsOnTheHeadThenWilts() {
        var gifts = Gifts(flightTime: 0.5)
        let given = gifts.give("poppy", from: 0, to: 1, at: 10)
        #expect(given)
        #expect(gifts.hat(of: 1) == nil)
        #expect(gifts.flightProgress(at: 10.25) == 0.5)
        gifts.update(at: 10.4, wearFor: 60)
        #expect(gifts.flight != nil && gifts.hat(of: 1) == nil)
        gifts.update(at: 10.5, wearFor: 60)
        #expect(gifts.flight == nil)
        #expect(gifts.hat(of: 1) == "poppy")
        gifts.update(at: 70.4, wearFor: 60)
        #expect(gifts.hat(of: 1) == "poppy")
        gifts.update(at: 70.5, wearFor: 60)
        #expect(gifts.hat(of: 1) == nil)
    }

    @Test func aHatRemembersWhoGaveIt() {
        var gifts = Gifts(flightTime: 0.5)
        gifts.give("tulip", from: 3, to: 1, at: 0)
        gifts.update(at: 0.5, wearFor: 60)
        #expect(gifts.giver(of: 1) == 3)
        #expect(gifts.giver(of: 3) == nil)
        gifts.update(at: 61, wearFor: 60)
        #expect(gifts.giver(of: 1) == nil, "gone with the flower")
    }

    @Test func onlyOneFlowerFliesAtATime() {
        var gifts = Gifts()
        let first = gifts.give("rose", from: 0, to: 1, at: 0)
        let second = gifts.give("lily", from: 2, to: 3, at: 0.1)
        #expect(first && !second)
        #expect(gifts.flight?.flower == "rose")
    }

    @Test func creaturesThatNoLongerExistLoseTheirFlowers() {
        var gifts = Gifts(flightTime: 0)
        gifts.give("daisy", from: 0, to: 4, at: 0)
        gifts.update(at: 0, wearFor: 60)
        gifts.give("tulip", from: 1, to: 5, at: 1)
        gifts.forget(creaturesFrom: 3)
        #expect(gifts.hat(of: 4) == nil)
        #expect(gifts.flight == nil)
    }

    @Test func everyFlowerHasAName() {
        #expect(Gifts.flowers.count == 10)
        #expect(Set(Gifts.flowers).count == 10)
    }
}
