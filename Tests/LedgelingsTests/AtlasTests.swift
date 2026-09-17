import CoreGraphics
import Foundation
import Testing
import LedgelingsCore
@testable import Ledgelings

/// Every distinct opaque colour in an image.
private func colours(in image: CGImage) -> Set<RGB> {
    let w = image.width, h = image.height
    let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                        space: CGColorSpace(name: CGColorSpace.sRGB)!,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
    let px = ctx.data!.bindMemory(to: UInt8.self, capacity: w * h * 4)
    var found: Set<RGB> = []
    for i in stride(from: 0, to: w * h * 4, by: 4) where px[i + 3] == 255 {
        found.insert(RGB(r: px[i], g: px[i + 1], b: px[i + 2]))
    }
    return found
}

@Suite struct AtlasTests {
    @Test func hexRoundTrips() {
        #expect(RGB(hex: "#3dc7b5")?.hex == "#3dc7b5")
        #expect(RGB(hex: "nope") == nil)
    }

    @Test func everyAnimationTheBrainAsksForHasFramesForEveryEyeState() throws {
        let frames = try SpriteAtlas(named: "blocky").frames()
        for animation in ["walk", "idle", "jump", "land", "sleep"] {
            for eyes in [Eyes.open, .half, .closed] {
                #expect(frames.frame(animation: animation, time: 0.7, eyes: eyes) != nil, "\(animation) \(eyes)")
            }
        }
        #expect(try SpriteAtlas(named: "zzz").frames().frame(animation: "float", time: 0) != nil)
    }

    @Test func recolouringSwapsTheBodyAndLeavesTheEyesBlack() throws {
        let atlas = try SpriteAtlas(named: "blocky")
        let orange = RGB(hex: "#ff8a3d")!, teal = RGB(hex: "#3dc7b5")!

        let plain = colours(in: atlas.frames().frame(animation: "idle", time: 0)!)
        #expect(plain.contains(orange))

        let tinted = colours(in: atlas.frames(body: teal).frame(animation: "idle", time: 0)!)
        #expect(tinted.contains(teal))
        #expect(!tinted.contains(orange))
        #expect(tinted.contains(.black))
        #expect(tinted.count == plain.count)      // body, light, shade, outline, eyes -- nothing smeared
    }
}
