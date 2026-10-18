import AppKit
import Foundation
import LedgelingsCore
import Testing
@testable import Ledgelings

/// Productivity tools › Screenshots: its settings, the picture put together from
/// frozen monitors, and where a finished shot goes.
@MainActor
@Suite(.serialized) struct ScreenshotSettingsTests {
    let name = "ledgelings-screenshot-settings-tests"

    final class Secrets: SecretStore, @unchecked Sendable {
        func get(_ account: String) -> String? { nil }
        func set(_ value: String?, for account: String) {}
    }

    @Test func theDefaultsAndAChangeSurviveARelaunch() {
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        defer { defaults.removePersistentDomain(forName: name) }
        let s = AppSettings(defaults: defaults, keychain: Secrets())
        #expect(s.shotEnabled && s.shotCopy && !s.shotSave && s.shotHideCreatures && s.shotCreatureBrings)
        #expect(s.shotCaptureShortcutEnabled && s.shotCaptureShortcut == .shotCapture)
        #expect(s.shotFullShortcutEnabled && s.shotFullShortcut == .shotFull && s.shotFullScope == .allScreens)
        #expect(s.shotLastShortcutEnabled && s.shotLastShortcut == .shotLast)
        #expect(s.shotFolder == "~/Desktop/Screenshots" && s.shotThickness == 3 && s.shotColour == 0 && s.shotLastRect.isEmpty)
        #expect(Shortcut.shotCapture == Shortcut(keyCode: 1, modifiers: [.control, .option]), "⌃⌥S")
        #expect(Shortcut.shotFull == Shortcut(keyCode: 28, modifiers: [.command, .shift]), "⌘⇧8, the * key")
        #expect(Shortcut.shotLast == Shortcut(keyCode: 42, modifiers: [.command, .shift]), "⌘⇧\\")

        s.shotEnabled = false; s.shotCopy = false; s.shotSave = true; s.shotHideCreatures = false; s.shotCreatureBrings = false
        s.shotCaptureShortcutEnabled = false; s.shotFullShortcutEnabled = false; s.shotLastShortcutEnabled = false
        s.shotCaptureShortcut = Shortcut(keyCode: 1, modifiers: [.command, .option])
        s.shotFullShortcut = Shortcut(keyCode: 20, modifiers: [.command, .shift])
        s.shotLastShortcut = Shortcut(keyCode: 21, modifiers: [.command, .shift])
        s.shotFullScope = .screenUnderCursor
        s.shotFolder = "~/Pictures/Shots"; s.shotThickness = 6; s.shotColour = 3; s.shotLastRect = "10,20,300,200"
        let again = AppSettings(defaults: defaults, keychain: Secrets())
        #expect(!again.shotEnabled && !again.shotCopy && again.shotSave && !again.shotHideCreatures && !again.shotCreatureBrings)
        #expect(!again.shotCaptureShortcutEnabled && !again.shotFullShortcutEnabled && !again.shotLastShortcutEnabled)
        #expect(again.shotCaptureShortcut == Shortcut(keyCode: 1, modifiers: [.command, .option]))
        #expect(again.shotFullShortcut == Shortcut(keyCode: 20, modifiers: [.command, .shift]))
        #expect(again.shotLastShortcut == Shortcut(keyCode: 21, modifiers: [.command, .shift]))
        #expect(again.shotFullScope == .screenUnderCursor)
        #expect(again.shotFolder == "~/Pictures/Shots" && again.shotThickness == 6 && again.shotColour == 3 && again.shotLastRect == "10,20,300,200")

        defaults.set(40, forKey: "shotThickness"); defaults.set(9, forKey: "shotColour"); defaults.set("  ", forKey: "shotFolder")
        defaults.set("sideways", forKey: "shotFullScope")
        defaults.set(Shortcut.Modifiers.shift.rawValue, forKey: "shotFullShortcutModifiers")
        let clamped = AppSettings(defaults: defaults, keychain: Secrets())
        #expect(clamped.shotThickness == 8 && clamped.shotColour == 0, "clamped on load")
        #expect(clamped.shotFolder == "~/Desktop/Screenshots", "an empty folder is the default one")
        #expect(clamped.shotFullScope == .allScreens)
        #expect(clamped.shotFullShortcut == .shotFull, "a shortcut with no Command, Control or Option is the standard one")
    }

    @Test func screenshotsIsTheThirdTool() {
        #expect(ProductivityTool.allCases == [.reminders, .clipboard, .screenshots])
    }

    /// A flat picture of one colour, `w`×`h` pixels.
    func flat(_ w: Int, _ h: Int, _ grey: CGFloat) -> CGImage {
        let c = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        c.setFillColor(CGColor(gray: grey, alpha: 1))
        c.fill(CGRect(x: 0, y: 0, width: w, height: h))
        return c.makeImage()!
    }

    /// The bytes of pixel (x, y), counted from the top-left, as the picture holds them.
    func pixel(_ image: CGImage, _ x: Int, _ y: Int) -> [UInt8] {
        guard let data = image.dataProvider?.data, let bytes = CFDataGetBytePtr(data) else { return [] }
        let at = y * image.bytesPerRow + x * 4
        return (0..<4).map { bytes[at + $0] }
    }

    @Test func aRectangleIsCutAtTheMonitorsScaleWithItsMarks() throws {
        let laptop = ShotFrame(monitor: Shot.Monitor(frame: CGRect(x: 0, y: 0, width: 200, height: 100), scale: 2), image: flat(400, 200, 1))
        let area = CGRect(x: 20, y: 20, width: 100, height: 50)
        let image = try #require(ShotRenderer.render([laptop], area: .rect(area, monitor: 0),
                                                     marks: [.box(CGRect(x: 30, y: 30, width: 40, height: 30), colour: 0, thickness: 2)]))
        #expect(image.width == 200 && image.height == 100)
        // The box's left side, 10 pt in (20 px), is red; the middle stays white.
        #expect(pixel(image, 21, 50) == [232, 59, 59, 255])
        #expect(pixel(image, 100, 50) == [255, 255, 255, 255])
    }

    @Test func aBlurIsBakedInAsBlocks() throws {
        // Black and white stripes one pixel wide: blurred, each block is one even grey.
        let w = 96, h = 48
        let c = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        c.setFillColor(CGColor(gray: 1, alpha: 1)); c.fill(CGRect(x: 0, y: 0, width: w, height: h))
        c.setFillColor(CGColor(gray: 0, alpha: 1))
        for x in stride(from: 0, to: w, by: 2) { c.fill(CGRect(x: x, y: 0, width: 1, height: h)) }
        let frame = ShotFrame(monitor: Shot.Monitor(frame: CGRect(x: 0, y: 0, width: 96, height: 48), scale: 1), image: c.makeImage()!)
        let image = try #require(ShotRenderer.render([frame], area: .rect(frame.monitor.frame, monitor: 0), marks: [.blur(CGRect(x: 0, y: 0, width: 48, height: 48))]))
        let a = pixel(image, 0, 0), b = pixel(image, 1, 0), far = pixel(image, 11, 11)
        #expect(a == b && a == far, "one colour across the block: \(a) \(b) \(far)")
        #expect((120...135).contains(Int(a.first ?? 0)), "half black, half white: \(a)")
        #expect(pixel(image, 60, 10) != pixel(image, 61, 10), "outside the blur the stripes are still there")
    }

    @Test func aLassosOutsideIsSeeThrough() throws {
        let frame = ShotFrame(monitor: Shot.Monitor(frame: CGRect(x: 0, y: 0, width: 100, height: 100), scale: 1), image: flat(100, 100, 0.5))
        let lasso = Shot.Lasso(points: [CGPoint(x: 10, y: 10), CGPoint(x: 90, y: 10), CGPoint(x: 10, y: 90)])
        let image = try #require(ShotRenderer.render([frame], area: .lasso(lasso, monitor: 0), marks: []))
        #expect(image.width == 80 && image.height == 80)
        #expect(pixel(image, 5, 75)[3] == 255, "inside the triangle, near its corner")
        #expect(pixel(image, 75, 5)[3] == 0, "outside it")
    }

    @Test func allMonitorsAreStitchedAtTheirOwnScale() throws {
        let laptop = ShotFrame(monitor: Shot.Monitor(frame: CGRect(x: 0, y: 0, width: 100, height: 50), scale: 2), image: flat(200, 100, 1))
        let monitor = ShotFrame(monitor: Shot.Monitor(frame: CGRect(x: 100, y: 0, width: 80, height: 50), scale: 1), image: flat(80, 50, 0))
        let image = try #require(ShotRenderer.render([laptop, monitor], area: .all, marks: []))
        #expect(image.width == 280 && image.height == 100)
        #expect(pixel(image, 199, 10) == [255, 255, 255, 255])
        #expect(pixel(image, 200, 10) == [0, 0, 0, 255])
        #expect(pixel(image, 200, 60)[3] == 0, "under the shorter 1× monitor, nothing")
    }

    @Test func aShotIsSavedUnderAFreeNameInAFolderMadeForIt() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("shots-\(UUID().uuidString)/Screenshots")
        defer { try? FileManager.default.removeItem(at: folder.deletingLastPathComponent()) }
        let date = Date(timeIntervalSince1970: 1_792_321_402)
        let first = ShotController.output(flat(10, 10, 1), copy: false, save: true, folder: folder.path, at: date)
        let second = ShotController.output(flat(10, 10, 1), copy: false, save: true, folder: folder.path, at: date)
        #expect(first.problem == nil && !first.copied)
        #expect(first.saved?.lastPathComponent == Shot.fileName(at: date))
        #expect(second.saved?.lastPathComponent == Shot.freeName(Shot.fileName(at: date)) { $0 == Shot.fileName(at: date) })
        #expect(FileManager.default.fileExists(atPath: second.saved?.path ?? ""))
    }

    @Test func aTinyPictureForTheCreatureHasADarkRim() throws {
        let thumb = try #require(ShotRenderer.thumbnail(flat(400, 300, 1), size: CGSize(width: 18, height: 14)))
        #expect(thumb.width == 18 && thumb.height == 14)
        #expect(pixel(thumb, 0, 0) == pixel(thumb, 17, 13))
        #expect(pixel(thumb, 9, 7) == [255, 255, 255, 255])
    }
}
