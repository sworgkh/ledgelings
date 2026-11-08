import AppKit
import Carbon.HIToolbox
import LedgelingsCore

/// The screenshot tool on the real screen, from a script.
///
/// `--shot-check` says whether this build may see the screen (Screen Recording) and
/// whether a capture really shows it. Started from a terminal it borrows the
/// terminal's permission; `open build/Ledgelings.app --stderr /dev/stdout --args --shot-check`
/// asks for the app's own.
///
/// `--shot-demo` freezes the real screens with the toolbar, drags a rectangle in the
/// middle of the main screen, draws a box, an arrow, a blur and a freehand blur,
/// undoes one, types a text over the blur and turns it 30°, copies, checks the
/// clipboard holds that PNG with the text's pixels where it was put, then takes the last
/// rectangle again with its shortcut's action; the clipboard and the settings it
/// touched are put back. Each step is printed with its time; exit 1 if anything is wrong.
@MainActor
enum ShotDemo {
    static func check() async -> Bool {
        func log(_ line: String) { FileHandle.standardError.write(Data("shot \(line)\n".utf8)) }
        log("screen recording \(ShotCapture.allowed ? "granted" : "NOT granted to this build")")
        do {
            let frames = try await ShotCapture.capture()
            for f in frames {
                let colours = distinctColours(f.image)
                log("\(f.name): \(f.image.width)×\(f.image.height) px at \(Int(f.monitor.scale))×, \(colours) colours in a sample\(colours < 4 ? ": blank, no permission?" : "")")
            }
            let ok = ShotCapture.allowed && frames.allSatisfy { distinctColours($0.image) >= 4 }
            log(ok ? "capture works" : "capture does NOT show the screen")
            return ok
        } catch {
            log("capture refused: \(error)")
            return false
        }
    }

    /// How many pixels of `a` and `b` (the same size) differ clearly, where `inBox` says and elsewhere.
    static func differences(_ a: CGImage, _ b: CGImage, inBox: (CGPoint) -> Bool) -> (Int, Int) {
        func bytes(_ image: CGImage) -> [UInt8] {
            let w = image.width, h = image.height
            var data = [UInt8](repeating: 0, count: w * h * 4)
            data.withUnsafeMutableBytes { raw in
                let c = CGContext(data: raw.baseAddress, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
                c?.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
            }
            return data
        }
        guard a.width == b.width, a.height == b.height else { return (0, -1) }
        let x = bytes(a), y = bytes(b)
        var inside = 0, outside = 0
        for row in 0..<a.height {
            for col in 0..<a.width {
                let at = (row * a.width + col) * 4
                let d = (0..<3).reduce(0) { $0 + abs(Int(x[at + $1]) - Int(y[at + $1])) }
                guard d > 30 else { continue }
                if inBox(CGPoint(x: CGFloat(col) + 0.5, y: CGFloat(row) + 0.5)) { inside += 1 } else { outside += 1 }
            }
        }
        return (inside, outside)
    }

    /// How many colours a 24×24 sample of the picture has: a refused capture is one flat colour.
    static func distinctColours(_ image: CGImage) -> Int {
        let n = 24
        guard let context = CGContext(data: nil, width: n, height: n, bitsPerComponent: 8, bytesPerRow: n * 4,
                                      space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
              let data = context.data else { return 0 }
        context.interpolationQuality = .none
        context.draw(image, in: CGRect(x: 0, y: 0, width: n, height: n))
        let bytes = UnsafeBufferPointer(start: data.assumingMemoryBound(to: UInt32.self), count: n * n)
        return Set(bytes).count
    }

    /// The settings the demo changes: put back after, and a key that was not saved before is removed again.
    static let touched = ["shotCopy", "shotSave", "shotLastRect", "shotCreatureBrings", "shotColour", "shotTextFont", "shotTextSize"]

    static func run(settings: AppSettings, controller: ShotController, snapshot: URL?, defaults: UserDefaults = .standard) async -> Bool {
        let start = Date()
        func log(_ line: String) { FileHandle.standardError.write(Data(String(format: "shot %5.2f  %@\n", Date().timeIntervalSince(start), line).utf8)) }
        let board = ClipPaster.saved()
        let kept = (copy: settings.shotCopy, save: settings.shotSave, last: settings.shotLastRect, brings: settings.shotCreatureBrings,
                    colour: settings.shotColour, font: settings.shotTextFont, size: settings.shotTextSize)
        let unsaved = touched.filter { defaults.object(forKey: $0) == nil }
        defer {
            ClipPaster.restore(board)
            settings.shotCopy = kept.copy; settings.shotSave = kept.save; settings.shotLastRect = kept.last
            settings.shotCreatureBrings = kept.brings; settings.shotColour = kept.colour
            settings.shotTextFont = kept.font; settings.shotTextSize = kept.size
            // Putting a value back saves it; one that was never saved goes again, so the default still decides.
            unsaved.forEach(defaults.removeObject(forKey:))
            log("clipboard and settings put back")
        }
        settings.shotCopy = true; settings.shotSave = false
        var ok = true
        func expect(_ good: Bool, _ what: String) {
            log((good ? "ok: " : "WRONG: ") + what)
            ok = ok && good
        }
        var results: [(CGImage, ShotController.Delivery)] = []
        controller.trace = log
        controller.finished = { results.append(($0, $1)) }
        defer { controller.trace = nil; controller.finished = nil }

        controller.withToolbar()
        var session: ShotSession?
        for _ in 0..<50 {
            session = controller.session
            if session?.isUp == true { break }
            try? await Task.sleep(for: .milliseconds(100))
        }
        guard let session, session.isUp else { expect(false, "the toolbar came up"); return false }
        guard let main = NSScreen.screens.first?.frame else { return false }
        func drag(_ a: CGPoint, _ b: CGPoint, through: [CGPoint] = []) async {
            session.down(a)
            for p in through { session.dragged(p) }
            session.up(b)
            try? await Task.sleep(for: .milliseconds(250))
        }
        let c = CGPoint(x: main.midX, y: main.midY)
        try? await Task.sleep(for: .milliseconds(600))
        await drag(CGPoint(x: c.x - 300, y: c.y + 180), CGPoint(x: c.x + 300, y: c.y - 180))
        expect(session.model.stage == .marking, "a 600×360 pt rectangle is the area")
        session.act(.tool(.box)); session.act(.colour(0))
        await drag(CGPoint(x: c.x - 250, y: c.y + 120), CGPoint(x: c.x - 50, y: c.y + 20))
        session.act(.tool(.arrow)); session.act(.colour(1))
        await drag(CGPoint(x: c.x + 200, y: c.y - 120), CGPoint(x: c.x - 40, y: c.y + 10))
        session.act(.tool(.blur))
        await drag(CGPoint(x: c.x + 40, y: c.y + 140), CGPoint(x: c.x + 260, y: c.y + 60))
        session.act(.tool(.brush))
        await drag(CGPoint(x: c.x - 260, y: c.y - 140), CGPoint(x: c.x - 40, y: c.y - 120), through: [CGPoint(x: c.x - 150, y: c.y - 150)])
        session.act(.tool(.highlight))
        await drag(CGPoint(x: c.x, y: c.y), CGPoint(x: c.x + 100, y: c.y - 60))
        expect(session.model.marks.count == 5, "five marks drawn (\(session.model.marks.count))")
        session.act(.undo)
        expect(session.model.marks.count == 4, "⌘Z took the highlight back")
        // A text over the blur, typed, then turned two steps left while still typed.
        session.act(.tool(.text)); session.act(.colour(4))
        let at = CGPoint(x: c.x + 60, y: c.y + 100)
        session.down(at); session.up(at)
        for ch in "Moss 42" { _ = session.key(0, [], characters: String(ch)) }
        _ = session.key(kVK_ANSI_LeftBracket, .command); _ = session.key(kVK_ANSI_LeftBracket, .command)
        // Then real keys, through the keyboard: "!" typed, ⏎ ending it. Only while the frozen screen
        // holds the keyboard, or they would land in whatever app is in front.
        if NSApp.keyWindow is ShotPanel {
            func press(_ code: Int, _ typed: String? = nil) {
                for down in [true, false] {
                    let event = CGEvent(keyboardEventSource: nil, virtualKey: CGKeyCode(code), keyDown: down)
                    if let typed { event?.keyboardSetUnicodeString(stringLength: typed.utf16.count, unicodeString: Array(typed.utf16)) }
                    event?.post(tap: .cghidEventTap)
                }
            }
            press(kVK_ANSI_1, "!")
            try? await Task.sleep(for: .milliseconds(300))
            press(kVK_Return)
            try? await Task.sleep(for: .milliseconds(300))
        } else {
            expect(false, "the frozen screen holds the keyboard")
            _ = session.key(kVK_Return, [])
        }
        let text = session.model.marks.last?.text
        expect(text?.string == "Moss 42!" && text?.angle == 30 && !session.model.editing,
               "a text typed (the ! from the keyboard), turned 30° and ended by ⏎ (\(text.map { "\($0.string), \(Int($0.angle))°" } ?? "none"))")
        expect(session.model.marks.count == 5, "five marks with the text")
        // The font menu opens as a row under the toolbar, which grows down for it, and shuts again.
        let closed = session.spot(of: .button(.font))
        session.act(.fontMenu)
        try? await Task.sleep(for: .milliseconds(500))
        let serif = session.spot(of: .font(.serif))
        expect(serif != nil && closed != nil && serif!.y < closed!.y - 20 && session.spot(of: .button(.font)) == closed,
               "the font menu opens under the font button, the toolbar's top where it was")
        session.act(.fontMenu)
        try? await Task.sleep(for: .milliseconds(300))
        let marks = session.model.marks, area = session.picture()?.1
        // The real pointer rests on the blur button: its tag says its name and key.
        if let spot = session.spot(of: .button(.blur)), let top = NSScreen.screens.first?.frame.maxY {
            let back = NSEvent.mouseLocation
            func move(_ p: CGPoint) {
                CGEvent(mouseEventSource: nil, mouseType: .mouseMoved, mouseCursorPosition: CGPoint(x: p.x, y: top - p.y), mouseButton: .left)?.post(tap: .cghidEventTap)
            }
            move(spot)
            try? await Task.sleep(for: .milliseconds(500))
            expect(session.model.hovered == .button(.blur),
                   "the pointer on the blur button shows \"\(ShotToolbar.tooltip(.button(.blur), session.model))\" (\(session.model.hovered.map { "\($0)" } ?? "nothing"))")
            move(back)
            try? await Task.sleep(for: .milliseconds(300))
            expect(session.model.hovered == nil, "the tag goes when the pointer leaves")
        } else {
            expect(false, "the blur button is on the screen")
        }
        if let snapshot, let (image, _) = session.picture(), let png = ShotRenderer.png(image) { try? png.write(to: snapshot); log("snapshot \(snapshot.path)") }
        session.act(.finish(.copy))
        try? await Task.sleep(for: .milliseconds(400))
        let scale = NSScreen.screens.first?.backingScaleFactor ?? 1
        let want = (Int(600 * scale), Int(360 * scale))
        guard let first = results.first else { expect(false, "a shot was taken"); return false }
        expect((first.0.width, first.0.height) == want, "the picture is \(first.0.width)×\(first.0.height) px (want \(want.0)×\(want.1))")
        expect(first.1.copied && first.1.saved == nil, "⌘C copied and saved nothing")
        let png = NSPasteboard.general.data(forType: .png)
        let onBoard = png.flatMap { NSBitmapImageRep(data: $0) }
        expect(onBoard?.pixelsWide == want.0 && onBoard?.pixelsHigh == want.1, "the clipboard holds that PNG (\(onBoard.map { "\($0.pixelsWide)×\($0.pixelsHigh)" } ?? "none"))")
        // The text is in that PNG: against the same shot without it, pixels differ inside its turned box and nowhere else.
        if let copied = onBoard?.cgImage, let area, let text, let bare = ShotRenderer.render(session.frames, area: area, marks: marks.filter { $0.text == nil }) {
            let mapped = ShotRenderer.mapping(area, frames: session.frames).pixels(.text(text)).text!
            let box = ShotText.measure(mapped)
            let (inside, outside) = differences(copied, bare) { p in
                let l = mapped.local(p, yDown: true)
                return abs(l.x) <= box.width / 2 + 2 && abs(l.y) <= box.height / 2 + 2
            }
            expect(inside > 300 && outside == 0, "the copied PNG has the text where it was put: \(inside) pixels in its box, \(outside) outside")
        } else {
            expect(false, "the copied PNG could be checked for the text")
        }
        expect(!settings.shotLastRect.isEmpty, "the rectangle is remembered (\(settings.shotLastRect))")

        // The last rectangle again: straight to the output, the same size.
        settings.shotCreatureBrings = false
        controller.lastRectangle()
        for _ in 0..<50 where results.count < 2 { try? await Task.sleep(for: .milliseconds(100)) }
        if results.count >= 2 {
            let again = results[1].0
            expect((again.width, again.height) == want, "the last rectangle again is \(again.width)×\(again.height) px")
        } else {
            expect(false, "the last rectangle was taken again")
        }
        try? await Task.sleep(for: .seconds(1))
        log(ok ? "all well" : "something was wrong")
        return ok
    }
}
