import AppKit
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
/// undoes one, copies, checks the clipboard holds that PNG, then takes the last
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

    static func run(settings: AppSettings, controller: ShotController, snapshot: URL?) async -> Bool {
        let start = Date()
        func log(_ line: String) { FileHandle.standardError.write(Data(String(format: "shot %5.2f  %@\n", Date().timeIntervalSince(start), line).utf8)) }
        let board = ClipPaster.saved()
        let kept = (copy: settings.shotCopy, save: settings.shotSave, last: settings.shotLastRect, brings: settings.shotCreatureBrings)
        defer {
            ClipPaster.restore(board)
            settings.shotCopy = kept.copy; settings.shotSave = kept.save; settings.shotLastRect = kept.last
            settings.shotCreatureBrings = kept.brings
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
