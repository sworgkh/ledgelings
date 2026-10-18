import Foundation
import Testing
@testable import LedgelingsCore

@Suite struct ShotTests {
    /// A 2× laptop on the left, a 1× monitor to its right, their tops level.
    static let laptop = Shot.Monitor(frame: CGRect(x: 0, y: 0, width: 1440, height: 900), scale: 2)
    static let monitor = Shot.Monitor(frame: CGRect(x: 1440, y: -180, width: 1920, height: 1080), scale: 1)

    @Test func anAreaIsTheSameWhicheverWayItIsDragged() {
        let r = CGRect(x: 10, y: 20, width: 100, height: 50)
        #expect(Shot.area(CGPoint(x: 10, y: 20), CGPoint(x: 110, y: 70)) == r)
        #expect(Shot.area(CGPoint(x: 110, y: 70), CGPoint(x: 10, y: 20)) == r)
        #expect(Shot.area(CGPoint(x: 110, y: 20), CGPoint(x: 10, y: 70)) == r)
        #expect(!Shot.isArea(CGRect(x: 0, y: 0, width: 3, height: 100)))
        #expect(Shot.isArea(CGRect(x: 0, y: 0, width: 4, height: 4)))
    }

    @Test func pixelRectsCountFromTheTopAtTheMonitorsScale() {
        // 100 pt from the laptop's left, 50 pt below its top, 200×100 pt: twice that in pixels.
        let r = CGRect(x: 100, y: 900 - 50 - 100, width: 200, height: 100)
        #expect(Shot.pixelRect(r, on: Self.laptop) == CGRect(x: 200, y: 100, width: 400, height: 200))
        // Cut to the monitor: half of it hangs off the laptop's right edge.
        let across = CGRect(x: 1340, y: 800, width: 200, height: 100)
        #expect(Shot.pixelRect(across, on: Self.laptop) == CGRect(x: 2680, y: 0, width: 200, height: 200))
        #expect(Shot.pixelRect(across, on: Self.monitor) == CGRect(x: 0, y: 0, width: 100, height: 100))
        #expect(Shot.pixelRect(CGRect(x: 5000, y: 0, width: 10, height: 10), on: Self.laptop) == .zero)
    }

    @Test func theMonitorUnderAPointOrTheNearest() {
        let all = [Self.laptop, Self.monitor]
        #expect(Shot.monitor(at: CGPoint(x: 10, y: 10), in: all) == 0)
        #expect(Shot.monitor(at: CGPoint(x: 2000, y: 0), in: all) == 1)
        #expect(Shot.monitor(at: CGPoint(x: 9000, y: 0), in: all) == 1)
        #expect(Shot.monitor(at: .zero, in: []) == nil)
    }

    @Test func stitchingKeepsEachMonitorsOwnPixels() {
        let (size, places) = Shot.stitch([Self.laptop, Self.monitor])
        // The laptop's 2880×1800 pixels first, the monitor's 1920×1080 after them, nothing resized.
        #expect(places[0] == CGRect(x: 0, y: 0, width: 2880, height: 1800))
        #expect(places[1].origin.x == 2880)
        #expect(places[1].size == CGSize(width: 1920, height: 1080))
        // Their tops are level, so both start at the top.
        #expect(places[1].origin.y == 0)
        // A laptop whose top is 100 pt lower starts 200 of its pixels down.
        let lower = Shot.stitch([Shot.Monitor(frame: CGRect(x: 0, y: -100, width: 1440, height: 900), scale: 2), Self.monitor]).places
        #expect(lower[0].origin.y == 200)
        #expect(size == CGSize(width: 4800, height: 1800))
    }

    @Test func stitchingStacksMonitorsAboveEachOther() {
        let top = Shot.Monitor(frame: CGRect(x: 0, y: 900, width: 1920, height: 1080), scale: 1)
        let (size, places) = Shot.stitch([Self.laptop, top])
        #expect(places[1] == CGRect(x: 0, y: 0, width: 1920, height: 1080))
        #expect(places[0] == CGRect(x: 0, y: 1080, width: 2880, height: 1800))
        #expect(size == CGSize(width: 2880, height: 2880))
        for (i, a) in places.enumerated() { for b in places.dropFirst(i + 1) { #expect(!a.intersects(b)) } }
    }

    @Test func stitchingNeverOverlapsMixedScales() {
        // Three in a row with the 1× one in the middle and a 2× one either side.
        let ms = [Shot.Monitor(frame: CGRect(x: 0, y: 0, width: 1000, height: 600), scale: 2),
                  Shot.Monitor(frame: CGRect(x: 1000, y: 0, width: 1000, height: 600), scale: 1),
                  Shot.Monitor(frame: CGRect(x: 2000, y: 0, width: 1000, height: 600), scale: 2)]
        let places = Shot.stitch(ms).places
        #expect(places.map(\.minX) == [0, 2000, 3000])
        for (i, a) in places.enumerated() { for b in places.dropFirst(i + 1) { #expect(!a.intersects(b)) } }
    }

    @Test func aMarkLandsInTheAreasPixels() {
        let area = CGRect(x: 100, y: 100, width: 400, height: 300)
        let map = Shot.Mapping.area(area, scale: 2)
        // The area's top-left corner is pixel (0, 0); y counts down.
        #expect(map.pixel(CGPoint(x: 100, y: 400)) == .zero)
        #expect(map.pixel(CGPoint(x: 150, y: 350)) == CGPoint(x: 100, y: 100))
        let box = map.pixels(.box(CGRect(x: 150, y: 300, width: 100, height: 50), colour: 0, thickness: 3))
        #expect(box == .box(CGRect(x: 100, y: 100, width: 200, height: 100), colour: 0, thickness: 6))
    }

    @Test func aMarkOnAllMonitorsUsesTheMonitorItStartsOn() {
        let map = Shot.Mapping.all([Self.laptop, Self.monitor])
        // On the 1× monitor, 10 pt in from its top-left: pixel 2880 + 10 across, 10 down.
        #expect(map.pixel(CGPoint(x: 1450, y: 890)) == CGPoint(x: 2890, y: 10))
        #expect(map.scale(at: CGPoint(x: 1450, y: 890)) == 1)
        let arrow = map.pixels(.arrow(from: CGPoint(x: 10, y: 890), to: CGPoint(x: 20, y: 880), colour: 1, thickness: 2))
        #expect(arrow == .arrow(from: CGPoint(x: 20, y: 20), to: CGPoint(x: 40, y: 40), colour: 1, thickness: 4))
    }

    @Test func aLassoIsALoopWithAnArea() {
        var lasso = Shot.Lasso()
        for p in [CGPoint(x: 0, y: 0), CGPoint(x: 1, y: 0), CGPoint(x: 100, y: 0), CGPoint(x: 100, y: 100), CGPoint(x: 0, y: 100)] { lasso.add(p) }
        #expect(lasso.points.count == 4)             // (1, 0) was too near (0, 0)
        #expect(lasso.area == 10_000)
        #expect(lasso.bounds == CGRect(x: 0, y: 0, width: 100, height: 100))
        #expect(lasso.isUsable)
        #expect(!Shot.Lasso(points: [.zero, CGPoint(x: 50, y: 0), CGPoint(x: 100, y: 0)]).isUsable)   // a line, no area
        #expect(Shot.Lasso().bounds.isNull)
    }

    @Test func theArrowHeadPointsAlongTheArrow() {
        let head = Shot.arrowHead(from: .zero, to: CGPoint(x: 100, y: 0), thickness: 3)
        #expect(head[0] == CGPoint(x: 100, y: 0))
        #expect(head[1].x == 88 && head[2].x == 88)                  // 4 × 3 = 12 back
        #expect(abs(head[1].y + head[2].y) < 0.001 && abs(head[1].y) > 7)
        #expect(Shot.arrowHead(from: .zero, to: .zero, thickness: 3).allSatisfy { $0 == .zero })
    }

    @Test func blurCellsFollowOneGridAndStayInside() {
        let cells = Shot.blurCells(CGRect(x: 5, y: 5, width: 20, height: 10), block: 10, size: CGSize(width: 100, height: 100))
        #expect(cells == [CGRect(x: 5, y: 5, width: 5, height: 5), CGRect(x: 10, y: 5, width: 10, height: 5), CGRect(x: 20, y: 5, width: 5, height: 5),
                          CGRect(x: 5, y: 10, width: 5, height: 5), CGRect(x: 10, y: 10, width: 10, height: 5), CGRect(x: 20, y: 10, width: 5, height: 5)])
        #expect(Shot.blurCells(CGRect(x: 95, y: 95, width: 20, height: 20), block: 10, size: CGSize(width: 100, height: 100))
            == [CGRect(x: 95, y: 95, width: 5, height: 5)])
        #expect(Shot.blurCells(CGRect(x: 200, y: 200, width: 20, height: 20), block: 10, size: CGSize(width: 100, height: 100)).isEmpty)
    }

    @Test func brushCellsCoverTheStroke() {
        let cells = Shot.brushCells([CGPoint(x: 5, y: 15), CGPoint(x: 55, y: 15)], width: 4, block: 10, size: CGSize(width: 100, height: 100))
        // The row the stroke runs along, square by square, and nothing far off it.
        for x in stride(from: 0, through: 50, by: 10) { #expect(cells.contains(CGRect(x: CGFloat(x), y: 10, width: 10, height: 10))) }
        #expect(!cells.contains { $0.minY >= 30 || $0.minX >= 70 })
        #expect(Shot.brushCells([], width: 4, block: 10, size: CGSize(width: 100, height: 100)).isEmpty)
    }

    @Test func pixelatingMakesEachCellOneColour() {
        // A 4×2 picture: the left 2×2 square half black, half white.
        var bytes: [UInt8] = [0, 0, 0, 255, 255, 255, 255, 255, 9, 9, 9, 255, 9, 9, 9, 255,
                              0, 0, 0, 255, 255, 255, 255, 255, 9, 9, 9, 255, 9, 9, 9, 255]
        Shot.pixelate(&bytes, width: 4, height: 2, bytesPerRow: 16, cells: [CGRect(x: 0, y: 0, width: 2, height: 2)])
        #expect(Array(bytes[0..<4]) == [128, 128, 128, 255])
        #expect(Array(bytes[4..<8]) == [128, 128, 128, 255])
        #expect(Array(bytes[16..<20]) == [128, 128, 128, 255])
        #expect(Array(bytes[8..<12]) == [9, 9, 9, 255])         // outside the cell, untouched
    }

    @Test func fileNamesSayWhenAndNeverClash() {
        let date = Date(timeIntervalSince1970: 1_792_321_402)   // 2026-10-18 11:03:22 UTC
        #expect(Shot.fileName(at: date, timeZone: TimeZone(identifier: "UTC")!) == "Screenshot 2026-10-18 11.03.22.png")
        #expect(Shot.fileName(at: date, timeZone: TimeZone(identifier: "Asia/Jerusalem")!) == "Screenshot 2026-10-18 14.03.22.png")
        let taken: Set = ["a.png", "a (2).png"]
        #expect(Shot.freeName("a.png") { taken.contains($0) } == "a (3).png")
        #expect(Shot.freeName("b.png") { taken.contains($0) } == "b.png")
    }

    @Test func theFolderPathMakesTheHomeFolder() {
        #expect(Shot.folderPath("~/Desktop/Screenshots", home: "/Users/me") == "/Users/me/Desktop/Screenshots")
        #expect(Shot.folderPath("", home: "/Users/me") == "/Users/me/Desktop/Screenshots")
        #expect(Shot.folderPath("/Volumes/Shots", home: "/Users/me") == "/Volumes/Shots")
    }

    @Test func theLastRectangleComesBackOnTheMonitorItWasOn() {
        let all = [Self.laptop, Self.monitor]
        let r = CGRect(x: 100, y: 200, width: 300, height: 150)
        #expect(Shot.lastArea(Shot.save(r), on: all) == r)
        // Half off the laptop's right edge onto the monitor: cut to where most of it is.
        #expect(Shot.lastArea(Shot.save(CGRect(x: 1340, y: 100, width: 400, height: 100)), on: all) == CGRect(x: 1440, y: 100, width: 300, height: 100))
        #expect(Shot.lastArea(Shot.save(CGRect(x: 9000, y: 0, width: 100, height: 100)), on: all) == nil)   // that monitor is gone
        #expect(Shot.lastArea("", on: all) == nil)
        #expect(Shot.lastArea("1,2,three,4", on: all) == nil)
    }

    @Test func theToolbarSitsAtTheTopUnderTheCursor() {
        let screen = CGRect(x: 0, y: 0, width: 1440, height: 900), size = CGSize(width: 400, height: 40)
        #expect(Shot.toolbarOrigin(cursorX: 700, screen: screen, size: size) == CGPoint(x: 500, y: 828))
        #expect(Shot.toolbarOrigin(cursorX: 10, screen: screen, size: size).x == 8)
        #expect(Shot.toolbarOrigin(cursorX: 1430, screen: screen, size: size).x == 1032)
    }

    @Test func theToastSaysWhatHappened() {
        Language.$override.withValue(.english) {
            let size = CGSize(width: 1280, height: 720)
            #expect(Shot.toast(size: size, copied: true, saved: nil) == "Copied 1280×720")
            #expect(Shot.toast(size: size, copied: false, saved: "x.png") == "Saved x.png")
            #expect(Shot.toast(size: size, copied: true, saved: "x.png") == "Copied 1280×720 and saved x.png")
        }
    }

    @Test func tinyMarksAreClicks() {
        #expect(Shot.Mark.box(CGRect(x: 0, y: 0, width: 2, height: 2), colour: 0, thickness: 3).isTiny)
        #expect(!Shot.Mark.box(CGRect(x: 0, y: 0, width: 20, height: 20), colour: 0, thickness: 3).isTiny)
        #expect(Shot.Mark.arrow(from: .zero, to: CGPoint(x: 3, y: 0), colour: 0, thickness: 3).isTiny)
        #expect(!Shot.Mark.brush([.zero], width: 12).isTiny)
    }
}
