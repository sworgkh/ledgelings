import CoreGraphics
import Testing
@testable import LedgelingsCore

/// The wind, a plane's flight and trail, the quiet spell, and the letters.
@Suite struct PaperPlanesTests {
    struct Seeded: RandomNumberGenerator {
        var state: UInt64
        mutating func next() -> UInt64 {
            state = state &* 6364136223846793005 &+ 1442695040888963407
            return state
        }
    }

    @Test func theWindIsSmoothBoundedAndTheSameForTheSamePlaceAndTime() {
        let wind = Wind(strength: 100)
        #expect(wind.at(CGPoint(x: 300, y: 200), time: 5) == wind.at(CGPoint(x: 300, y: 200), time: 5))
        var biggest: CGFloat = 0
        for x in stride(from: 0, to: 3000, by: 97) {
            for t in stride(from: 0.0, to: 60, by: 1.3) {
                let v = wind.at(CGPoint(x: x, y: x / 2), time: t)
                biggest = max(biggest, hypot(v.dx, v.dy))
            }
        }
        #expect(biggest <= 100 * 1.8, "never much past its strength")
        let here = wind.at(CGPoint(x: 500, y: 500), time: 10), near = wind.at(CGPoint(x: 502, y: 500), time: 10.01)
        #expect(hypot(here.dx - near.dx, here.dy - near.dy) < 5, "no sudden jolts")
    }

    @Test func aPlaneAlwaysReachesItsCatcherEvenInAStrongWind() {
        var rng = Seeded(state: 7)
        for _ in 0..<40 {
            let start = CGPoint(x: .random(in: 0...2500, using: &rng), y: 20)
            var target = CGPoint(x: .random(in: 0...2500, using: &rng), y: .random(in: 20...1400, using: &rng))
            var plane = PaperPlane(from: 0, to: 1, start: start, inward: CGVector(dx: 0, dy: 1), target: target)
            plane.wind = Wind(strength: 400)
            var time = Double.random(in: 0...100, using: &rng)
            while plane.distance(to: target) > 40, plane.age < 30 {
                target.x += 50 * 0.02                           // the catcher keeps walking
                plane.fly(dt: 0.02, toward: target, time: time)
                time += 0.02
            }
            #expect(plane.age < 25, "arrived in \(plane.age) s from \(start) to \(target)")
        }
    }

    @Test func itDoesNotFlyStraightTheWindBendsItsPath() {
        var plane = PaperPlane(from: 0, to: 1, start: CGPoint(x: 0, y: 0), inward: CGVector(dx: 0, dy: 1), target: CGPoint(x: 2000, y: 0))
        var furthestOffLine: CGFloat = 0
        for k in 0..<200 {
            plane.fly(dt: 0.02, toward: CGPoint(x: 2000, y: 0), time: Double(k) * 0.02)
            furthestOffLine = max(furthestOffLine, abs(plane.position.y))
        }
        #expect(furthestOffLine > 20)
    }

    @Test func theTrailIsDottedAndFadesAway() {
        var plane = PaperPlane(from: 0, to: 1, start: .zero, inward: CGVector(dx: 0, dy: 1), target: CGPoint(x: 3000, y: 0))
        for k in 0..<100 { plane.fly(dt: 0.02, toward: CGPoint(x: 3000, y: 0), time: Double(k) * 0.02) }
        #expect(plane.trail.count > 10)
        let gaps = zip(plane.trail, plane.trail.dropFirst()).map { hypot($1.position.x - $0.position.x, $1.position.y - $0.position.y) }
        #expect(gaps.allSatisfy { $0 >= plane.puffSpacing * 0.9 }, "puffs, not a solid line")
        #expect(plane.trail.allSatisfy { $0.age < plane.puffLife })
        for _ in 0..<60 { plane.fadeTrail(dt: 0.02) }
        #expect(plane.trail.isEmpty, "gone a second after the plane is")
    }

    @Test func everyThrownPlaneFliesInItsOwnWeatherAndMostAreQuick() {
        var rng = Seeded(state: 21)
        let planes = (0..<200).map { _ in
            PaperPlane.thrown(from: 0, to: 1, start: .zero, inward: CGVector(dx: 0, dy: 1), target: CGPoint(x: 900, y: 400), using: &rng)
        }
        #expect(Set(planes.map { $0.wind.phases[0] }).count == 200, "no two share a wind")
        let quick = planes.filter { $0.cruise >= 380 }.count
        #expect(quick > 130 && quick < 190, "about four in five are quick: \(quick)")
        #expect(planes.allSatisfy { $0.swirl > 0 && $0.cruise > 240 * 0.9 })
    }

    @Test func aSwirlingQuickPlaneStillAlwaysReachesItsCatcherAtTheAppsFrameRate() {
        var rng = Seeded(state: 5)
        for _ in 0..<60 {
            let start = CGPoint(x: .random(in: 0...2500, using: &rng), y: 20)
            var target = CGPoint(x: .random(in: 0...2500, using: &rng), y: .random(in: 20...1400, using: &rng))
            var plane = PaperPlane.thrown(from: 0, to: 1, start: start, inward: CGVector(dx: 0, dy: 1), target: target, using: &rng)
            var time = 0.0, caught = false
            while !caught, plane.age < 30 {
                target.y += 40 / 30.0
                plane.fly(dt: 1 / 30.0, toward: target, time: time)
                time += 1 / 30.0
                caught = plane.passed(within: 30, of: target)
            }
            #expect(caught && plane.age < 25, "caught after \(plane.age) s, cruise \(plane.cruise), swirl \(plane.swirl)")
        }
    }

    @Test func theSwirlCurlsThePathFarMoreThanStillAir() {
        var rng = Seeded(state: 9)
        func wander(_ plane: inout PaperPlane) -> CGFloat {
            var furthest: CGFloat = 0
            for k in 0..<90 {
                plane.fly(dt: 1 / 30.0, toward: CGPoint(x: 3000, y: 0), time: Double(k) / 30)
                furthest = max(furthest, abs(plane.position.y))
            }
            return furthest
        }
        var still = PaperPlane(from: 0, to: 1, start: .zero, inward: CGVector(dx: 1, dy: 0), target: CGPoint(x: 3000, y: 0))
        still.wind = Wind(strength: 0)
        var swirly = still
        swirly.swirl = 1000
        swirly.swirlRate = 2
        let a = wander(&still), b = wander(&swirly)
        #expect(b > a + 40, "swirl \(b) vs still \(a)")
        _ = rng.next()
    }

    @Test func aFastPlaneCannotSkipPastItsCatcherBetweenFrames() {
        var plane = PaperPlane(from: 0, to: 1, start: CGPoint(x: 0, y: 0), inward: CGVector(dx: 1, dy: 0), target: CGPoint(x: 1000, y: 0))
        plane.wind = Wind(strength: 0)
        plane.cruise = 700
        for k in 0..<40 { plane.fly(dt: 0.1, toward: CGPoint(x: 1000, y: 0), time: Double(k) * 0.1); if plane.position.x > 300 { break } }
        let between = CGPoint(x: (plane.previous.x + plane.position.x) / 2, y: 0)
        #expect(plane.distance(to: between) > 20, "the step is long")
        #expect(plane.passed(within: 5, of: between))
    }

    @Test func aPlaneIsDueEveryIntervalFromTheLastOne() {
        var post = Post(quietFor: 120)
        #expect(!post.isDue(at: 119))
        #expect(post.isDue(at: 120))
        post.stir(at: 100)
        #expect(!post.isDue(at: 200))
        #expect(post.isDue(at: 220))
        post.retry(at: 220, in: 10)
        #expect(!post.isDue(at: 229) && post.isDue(at: 230), "nobody free: ask again in ten seconds")
        #expect(!Post(quietFor: 0).isDue(at: 1e9), "zero means never")
    }

    @Test func theCatcherIsOneOfTheFartherHalfFromTheSender() {
        var rng = Seeded(state: 3)
        let free: [Int: CGPoint] = [0: CGPoint(x: 0, y: 0), 1: CGPoint(x: 10, y: 0), 2: CGPoint(x: 900, y: 0),
                                    3: CGPoint(x: 1000, y: 0), 4: CGPoint(x: 20, y: 0)]
        for _ in 0..<50 {
            let pair = Post.pickPair(free, using: &rng)!
            #expect(pair.from != pair.to)
            let d = hypot(free[pair.to]!.x - free[pair.from]!.x, 0)
            let others = free.filter { $0.key != pair.from }.map { hypot($0.value.x - free[pair.from]!.x, 0) }.sorted(by: >)
            #expect(others.prefix(2).contains(d))
        }
        #expect(Post.pickPair([0: .zero], using: &rng) == nil, "one creature cannot write to itself")
    }

    @Test func everyDefaultCharacterHasItsOwnVoiceAndEveryLineFillsIn() {
        var rng = Seeded(state: 11)
        for c in Banter.defaultCharacters {
            #expect(Letters.voices[c.name] != nil, "\(c.name) has a voice")
        }
        for (name, voice) in Letters.voices.merging(["someone new": Letters.anyone], uniquingKeysWith: { a, _ in a }) {
            #expect(voice.notes.count >= 3 && voice.musings.count >= 3 && voice.replies.count >= 3 && !voice.topics.isEmpty, "\(name)")
            for line in voice.notes + voice.musings + voice.replies {
                let filled = Letters.fill(line, sender: "Ann", reader: "Bob")
                #expect(!filled.contains("{") && !filled.contains("}"), "\(name): \(line)")
                #expect(filled.split(separator: " ").count <= 22, "\(name) is too wordy: \(line)")
            }
        }
        #expect(Letters.voice(of: "Nobody we know") == Letters.anyone)
        #expect(!Letters.note(by: "Blocky", to: "Pip", using: &rng).isEmpty)
        #expect(Letters.musing(by: "Zed", from: "Dot", using: &rng).count > 5)
        #expect(Letters.reading("Hi.", from: "Dot") == "*reads* \"Hi.\" — Dot")
    }

    @Test func theModelPromptsUseOnlyBantersPlaceholders() {
        for prompt in [Letters.notePrompt, Letters.musingPrompt, Letters.replyPrompt] {
            var rest = prompt
            for key in Banter.placeholders { rest = rest.replacingOccurrences(of: "{\(key)}", with: "") }
            #expect(!rest.contains("{"), "unknown placeholder in \(prompt)")
        }
    }
}
