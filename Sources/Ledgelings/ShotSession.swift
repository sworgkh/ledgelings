import AppKit
import Carbon.HIToolbox
import LedgelingsCore
import SwiftUI

/// One screenshot being taken with the toolbar (§7.12): every monitor frozen as it
/// was, dimmed, a crosshair, and the pixel toolbar at the top of the screen under the
/// cursor. First an area (R rectangle, L lasso, W the screen, A all monitors), then
/// marks on it (B box, → arrow, H highlight, X blur, F freehand blur; 1–6 colours,
/// ⌘Z undo). ⏎ takes it as the settings say, ⌘C copies it, ⌘S saves it; ⎋ lets go.
@MainActor
final class ShotSession {
    /// How it was finished.
    enum Action { case enter, copy, save }
    enum Outcome {
        case cancelled
        /// The picture, the area it was, how it was finished, and where the toolbar stood (global points).
        case taken(CGImage, ShotRenderer.Area, Action, spot: CGPoint)
    }

    let model: ShotModel
    let frames: [ShotFrame]
    private var panels: [(panel: ShotPanel, canvas: ShotCanvas)] = []
    private var toolbar: NSHostingView<ShotToolbar>?
    private var monitor: Any?
    private let done: (Outcome) -> Void
    /// The screen the toolbar is on, and where it stands there.
    private(set) var spot = CGPoint.zero
    /// Every step, for `--shot-demo`.
    var trace: ((String) -> Void)?

    init(frames: [ShotFrame], settings: AppSettings, done: @escaping (Outcome) -> Void) {
        self.frames = frames
        self.done = done
        model = ShotModel(colour: settings.shotColour, thickness: settings.shotThickness)
        model.pickColour = { [weak settings] in settings?.shotColour = $0 }
        model.entersCopy = settings.shotCopy || !settings.shotSave
        model.entersSave = settings.shotSave
        model.changed = { [weak self] in self?.panels.forEach { $0.canvas.needsDisplay = true } }
        model.act = { [weak self] in self?.act($0) }
    }

    /// On screen, or being filmed.
    private(set) var isUp = false

    /// Driven by `--shot-film` with no windows at all: the toolbar, `size` points, stands where it would.
    func startOffscreen(cursor: CGPoint, toolbar size: CGSize) {
        model.cursor = cursor
        isUp = true
        let here = Shot.monitor(at: cursor, in: frames.map(\.monitor)) ?? 0
        let origin = Shot.toolbarOrigin(cursorX: cursor.x, screen: frames[here].monitor.frame, size: size)
        spot = CGPoint(x: origin.x + size.width / 2, y: origin.y)
    }

    func start(cursor: CGPoint = NSEvent.mouseLocation) {
        model.cursor = cursor
        isUp = true
        for (i, frame) in frames.enumerated() {
            let panel = ShotPanel(frame: frame.monitor.frame)
            // The frozen picture sits in a layer of its own, under the canvas, so a mouse move redraws only the marks.
            let bounds = CGRect(origin: .zero, size: frame.monitor.frame.size)
            let picture = NSView(frame: bounds)
            picture.wantsLayer = true
            picture.layer?.contents = frame.image
            picture.layer?.contentsGravity = .resize
            picture.layer?.magnificationFilter = .nearest
            let canvas = ShotCanvas(frame: bounds, session: self, index: i)
            canvas.autoresizingMask = [.width, .height]
            picture.addSubview(canvas)
            panel.contentView = picture
            panels.append((panel, canvas))
            panel.orderFrontRegardless()
        }
        let here = Shot.monitor(at: cursor, in: frames.map(\.monitor)) ?? 0
        let hosting = NSHostingView(rootView: ShotToolbar(model: model))
        let size = hosting.fittingSize
        let screen = frames[here].monitor.frame
        let origin = Shot.toolbarOrigin(cursorX: cursor.x, screen: screen, size: size)
        hosting.frame = CGRect(origin: CGPoint(x: origin.x - screen.minX, y: origin.y - screen.minY), size: size)
        panels[here].canvas.addSubview(hosting)
        toolbar = hosting
        spot = CGPoint(x: origin.x + size.width / 2, y: origin.y)
        panels[here].panel.makeKeyAndOrderFront(nil)
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            let code = Int(event.keyCode), flags = event.modifierFlags
            let handled = MainActor.assumeIsolated { self?.key(code, flags) ?? false }
            return handled ? nil : event
        }
        trace?("toolbar on \(frames[here].name.isEmpty ? "screen \(here + 1)" : frames[here].name) at (\(Int(origin.x)), \(Int(origin.y)))")
    }

    // MARK: Keys

    private static let colourKeys = [kVK_ANSI_1, kVK_ANSI_2, kVK_ANSI_3, kVK_ANSI_4, kVK_ANSI_5, kVK_ANSI_6]

    /// A key pressed while the screens are frozen; false lets it through.
    func key(_ code: Int, _ flags: NSEvent.ModifierFlags) -> Bool {
        let command = flags.contains(.command)
        switch code {
        case kVK_Escape: act(.cancel)
        case kVK_Return, kVK_ANSI_KeypadEnter: act(.finish(.enter))
        case kVK_ANSI_C where command: act(.finish(.copy))
        case kVK_ANSI_S where command: act(.finish(.save))
        case kVK_ANSI_Z where command: act(.undo)
        case kVK_ANSI_R: act(.mode(.rectangle))
        case kVK_ANSI_L: act(.mode(.lasso))
        case kVK_ANSI_W: act(.mode(.screen))
        case kVK_ANSI_A: act(.mode(.all))
        case kVK_ANSI_B: act(.tool(.box))
        case kVK_RightArrow: act(.tool(.arrow))
        case kVK_ANSI_H: act(.tool(.highlight))
        case kVK_ANSI_X: act(.tool(.blur))
        case kVK_ANSI_F: act(.tool(.brush))
        default:
            if let n = Self.colourKeys.firstIndex(of: code) { act(.colour(n)); return true }
            return command ? false : true
        }
        return true
    }

    /// Everything the toolbar and the keys can ask for.
    enum Request: Equatable {
        case mode(Shot.Mode), tool(Shot.Tool), colour(Int), undo, finish(Action), cancel
    }

    func act(_ request: Request) {
        guard isUp else { return }
        switch request {
        case .mode(let mode):
            model.mode = mode
            model.marks = []
            model.drag = nil
            switch mode {
            case .rectangle, .lasso:
                model.area = nil
                model.stage = .choosing
            case .screen:
                let m = Shot.monitor(at: model.cursor, in: frames.map(\.monitor)) ?? 0
                choose(.rect(frames[m].monitor.frame, monitor: m))
            case .all:
                choose(.all)
            }
            trace?("mode \(mode.rawValue)")
        case .tool(let tool):
            guard model.stage == .marking else { NSSound.beep(); return }
            model.tool = tool
            trace?("tool \(tool.rawValue)")
        case .colour(let n):
            model.colour = n
            model.pickColour(n)
            trace?("colour \(n + 1)")
        case .undo:
            guard !model.marks.isEmpty else { NSSound.beep(); return }
            model.marks.removeLast()
            trace?("undo, \(model.marks.count) marks left")
        case .finish(let action):
            finish(action)
        case .cancel:
            trace?("cancelled")
            close()
            done(.cancelled)
        }
        model.changed()
    }

    private func choose(_ area: ShotRenderer.Area) {
        model.area = area
        model.stage = .marking
        let b = area.bounds(frames)
        trace?("area \(Int(b.minX)),\(Int(b.minY)) \(Int(b.width))×\(Int(b.height)) pt")
    }

    // MARK: The mouse, in global points

    func moved(_ p: CGPoint) {
        model.cursor = p
        if model.stage == .choosing || model.drag != nil { model.changed() }
    }

    func down(_ p: CGPoint) {
        model.cursor = p
        model.drag = ShotModel.Drag(start: p, now: p, lasso: Shot.Lasso(points: [p]), stroke: [p])
        model.changed()
    }

    func dragged(_ p: CGPoint) {
        model.cursor = p
        guard var drag = model.drag else { return }
        drag.now = p
        drag.lasso.add(p)
        if let last = drag.stroke.last, hypot(p.x - last.x, p.y - last.y) >= 2 { drag.stroke.append(p) }
        model.drag = drag
        model.changed()
    }

    func up(_ p: CGPoint) {
        dragged(p)
        guard let drag = model.drag else { return }
        model.drag = nil
        let monitors = frames.map(\.monitor)
        switch model.stage {
        case .choosing:
            let m = Shot.monitor(at: drag.start, in: monitors) ?? 0
            switch model.mode {
            case .lasso where drag.lasso.isUsable:
                choose(.lasso(drag.lasso, monitor: m))
            case .rectangle:
                let rect = Shot.area(drag.start, drag.now).intersection(monitors[m].frame)
                if !rect.isNull, Shot.isArea(rect) { choose(.rect(rect, monitor: m)) }
            default: break
            }
        case .marking:
            if let mark = model.pending(drag), !mark.isTiny {
                model.marks.append(mark)
                trace?("mark \(model.tool.rawValue), \(model.marks.count) in all")
            }
        }
        model.changed()
    }

    // MARK: Finishing

    /// The picture as it is now: the chosen area, else the screen under the cursor.
    func picture() -> (CGImage, ShotRenderer.Area)? {
        let area = model.area ?? {
            let m = Shot.monitor(at: model.cursor, in: frames.map(\.monitor)) ?? 0
            return .rect(frames[m].monitor.frame, monitor: m)
        }()
        return ShotRenderer.render(frames, area: area, marks: model.marks).map { ($0, area) }
    }

    private func finish(_ action: Action) {
        guard let (image, area) = picture() else { NSSound.beep(); return }
        trace?("taken \(image.width)×\(image.height) px, \(model.marks.count) marks")
        close()
        done(.taken(image, area, action, spot: spot))
    }

    /// The middle of a toolbar item on the screen, in global points; nil while the toolbar is not up.
    func spot(of item: ShotToolbar.Item) -> CGPoint? {
        guard let toolbar, let canvas = toolbar.superview, let window = canvas.window, let place = model.places[item] else { return nil }
        let inWindow = canvas.convert(CGPoint(x: toolbar.frame.minX + place.midX, y: toolbar.frame.maxY - place.midY), to: nil)
        return window.convertPoint(toScreen: inWindow)
    }

    func close() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        toolbar?.removeFromSuperview()
        toolbar = nil
        for (panel, _) in panels { panel.orderOut(nil); panel.close() }
        panels = []
        isUp = false
    }
}

// MARK: The model

@MainActor
final class ShotModel: ObservableObject {
    enum Stage { case choosing, marking }
    struct Drag {
        var start: CGPoint
        var now: CGPoint
        var lasso: Shot.Lasso
        var stroke: [CGPoint]
    }

    @Published var mode = Shot.Mode.rectangle
    @Published var tool = Shot.Tool.box
    @Published var colour: Int
    @Published var thickness: Int
    @Published var stage = Stage.choosing
    @Published var marks: [Shot.Mark] = []
    /// The toolbar item the pointer rests on, whose name and key show under it.
    @Published var hovered: ShotToolbar.Item?
    /// Where each toolbar item stands, in the toolbar's points from its top-left.
    var places: [ShotToolbar.Item: CGRect] = [:]
    /// What ⏎ does, as Productivity tools › Screenshots says.
    var entersCopy = true
    var entersSave = false
    var area: ShotRenderer.Area?
    var drag: Drag?
    var cursor = CGPoint.zero
    var changed: () -> Void = {}
    var pickColour: (Int) -> Void = { _ in }
    var act: (ShotSession.Request) -> Void = { _ in }

    init(colour: Int, thickness: Int) {
        self.colour = colour
        self.thickness = thickness
    }

    /// The mark the drag would leave, in global points.
    func pending(_ drag: Drag) -> Shot.Mark? {
        let t = CGFloat(thickness), rect = Shot.area(drag.start, drag.now)
        switch tool {
        case .box: return .box(rect, colour: colour, thickness: t)
        case .arrow: return .arrow(from: drag.start, to: drag.now, colour: colour, thickness: t)
        case .highlight: return .highlight(rect, colour: colour)
        case .blur: return .blur(rect)
        case .brush: return .brush(drag.stroke, width: Shot.brushWidth(thickness: thickness))
        }
    }
}

/// A borderless panel over one monitor, above the creatures, that takes the keyboard
/// without making Ledgelings the active app.
final class ShotPanel: NSPanel {
    init(frame: CGRect) {
        super.init(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isOpaque = true
        backgroundColor = .black
        hasShadow = false
        isReleasedWhenClosed = false
        level = NSWindow.Level(rawValue: NSWindow.Level.screenSaver.rawValue + 1)
        hidesOnDeactivate = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

// MARK: One frozen monitor

/// One monitor's frozen picture, dimmed outside the area, with the marks drawn on it,
/// the size in pixels beside the area and a pixel crosshair for a cursor.
final class ShotCanvas: NSView {
    private weak var session: ShotSession?
    private let index: Int
    private lazy var blocks: CGImage? = session.flatMap { s in
        ShotRenderer.blocky(s.frames[index].image, block: Shot.blurBlock * s.frames[index].monitor.scale)
    }

    init(frame: CGRect, session: ShotSession, index: Int) {
        self.session = session
        self.index = index
        super.init(frame: frame)
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseMoved, .cursorUpdate, .activeAlways, .inVisibleRect], owner: self))
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func cursorUpdate(with event: NSEvent) { ShotCanvas.crosshair.set() }

    private func global(_ event: NSEvent) -> CGPoint {
        let p = event.locationInWindow, o = window?.frame.origin ?? .zero
        return CGPoint(x: p.x + o.x, y: p.y + o.y)
    }

    override func mouseMoved(with event: NSEvent) { ShotCanvas.crosshair.set(); MainActor.assumeIsolated { session?.moved(global(event)) } }
    override func mouseDown(with event: NSEvent) { MainActor.assumeIsolated { session?.down(global(event)) } }
    override func mouseDragged(with event: NSEvent) { MainActor.assumeIsolated { session?.dragged(global(event)) } }
    override func mouseUp(with event: NSEvent) { MainActor.assumeIsolated { session?.up(global(event)) } }

    override func draw(_ dirtyRect: NSRect) {
        guard let session, let context = NSGraphicsContext.current?.cgContext else { return }
        MainActor.assumeIsolated {
            ShotCanvas.paint(context, frame: session.frames[index], model: session.model, frames: session.frames, blocks: blocks, picture: false)
        }
    }

    /// Everything one monitor shows, in its own points (y up): the frozen picture, the
    /// dimming, the area's rim, the marks and the size label. Also how `--shot-film` draws.
    /// `picture`: draw the frozen picture too; on screen it is a layer underneath.
    @MainActor
    static func paint(_ context: CGContext, frame: ShotFrame, model: ShotModel, frames: [ShotFrame], blocks: CGImage?, picture: Bool = true) {
        let origin = frame.monitor.frame.origin
        let bounds = CGRect(origin: .zero, size: frame.monitor.frame.size)
        func local(_ p: CGPoint) -> CGPoint { CGPoint(x: p.x - origin.x, y: p.y - origin.y) }
        context.interpolationQuality = .none
        if picture { context.draw(frame.image, in: bounds) }

        // The area, chosen or being dragged, as a path in this monitor's points.
        var outline: CGPath?
        var sized: CGRect?
        if let area = model.area {
            switch area {
            case .rect(let r, _): outline = CGPath(rect: r.offsetBy(dx: -origin.x, dy: -origin.y), transform: nil); sized = r
            case .lasso(let l, _): outline = polygon(l.points.map(local)); sized = l.bounds
            case .all: outline = nil
            }
        } else if let drag = model.drag, model.stage == .choosing {
            switch model.mode {
            case .lasso: outline = polygon(drag.lasso.points.map(local), closed: false)
            default:
                let r = Shot.area(drag.start, drag.now)
                outline = CGPath(rect: r.offsetBy(dx: -origin.x, dy: -origin.y), transform: nil); sized = r
            }
        }
        // Dim all but the area; everything while nothing is chosen.
        if case .all = model.area {} else {
            context.saveGState()
            context.addRect(bounds)
            if let outline { context.addPath(outline) }
            context.setFillColor(CGColor(gray: 0, alpha: 0.42))
            context.fillPath(using: .evenOdd)
            context.restoreGState()
        }
        if let outline { rim(outline, context) }

        var marks = model.marks
        if let drag = model.drag, model.stage == .marking, let mark = model.pending(drag) { marks.append(mark) }
        for mark in marks {
            let shown = mark.mapped(local, scale: 1)
            switch shown {
            case .blur(let r):
                block(blocks, bounds: bounds, context) { $0.addRect(r) }
            case .brush(let points, let width):
                block(blocks, bounds: bounds, context) { c in
                    c.addLines(between: points.count == 1 ? [points[0], points[0]] : points)
                    c.setLineWidth(width)
                    c.setLineCap(.square)
                    c.setLineJoin(.miter)
                    c.replacePathWithStrokedPath()
                }
            default:
                ShotRenderer.draw(shown, in: context)
            }
        }

        // The size in the picture's pixels, under the area's bottom-right corner.
        if let r = sized, frame.monitor.frame.intersects(r) {
            let px = CGSize(width: (r.width * frame.monitor.scale).rounded(), height: (r.height * frame.monitor.scale).rounded())
            let corner = local(CGPoint(x: r.maxX, y: r.minY))
            label(Shot.sizeLabel(px), at: CGPoint(x: min(max(corner.x, 70), bounds.width - 4), y: max(corner.y - 6, 30)), context)
        }
    }

    private static func polygon(_ points: [CGPoint], closed: Bool = true) -> CGPath? {
        guard points.count >= 2 else { return nil }
        let path = CGMutablePath()
        path.addLines(between: points)
        if closed { path.closeSubpath() }
        return path
    }

    /// The area's rim in blocky's rule: a dark line, a white one inside it.
    private static func rim(_ path: CGPath, _ context: CGContext) {
        context.saveGState()
        context.setLineJoin(.miter)
        context.setLineCap(.square)
        context.addPath(path)
        context.setStrokeColor(ScreenOverlay.ink)
        context.setLineWidth(3)
        context.strokePath()
        context.addPath(path)
        context.setStrokeColor(CGColor(gray: 1, alpha: 1))
        context.setLineWidth(1)
        context.strokePath()
        context.restoreGState()
    }

    /// The blocky picture, inside the path `shape` adds.
    private static func block(_ blocks: CGImage?, bounds: CGRect, _ context: CGContext, shape: (CGContext) -> Void) {
        guard let blocks else { return }
        context.saveGState()
        shape(context)
        context.clip()
        context.interpolationQuality = .none
        // Each block is one blur square of the monitor's pixels: `blurBlock` points, from the top-left corner.
        let size = CGSize(width: CGFloat(blocks.width) * Shot.blurBlock, height: CGFloat(blocks.height) * Shot.blurBlock)
        context.draw(blocks, in: CGRect(x: 0, y: bounds.height - size.height, width: size.width, height: size.height))
        context.restoreGState()
    }

    /// "1280×720" on a little pixel plate, its right edge at `at`.
    static func label(_ text: String, at: CGPoint, _ context: CGContext) {
        let font = NSFont.monospacedSystemFont(ofSize: 11, weight: .heavy)
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: [
            .font: font, .foregroundColor: NSColor(cgColor: ScreenOverlay.ink) ?? .black,
        ]))
        let width = CTLineGetTypographicBounds(line, nil, nil, nil)
        let plate = CGRect(x: at.x - CGFloat(width) - 14, y: at.y - 20, width: CGFloat(width) + 14, height: 20).integral
        pixelPlate(plate, context)
        context.textPosition = CGPoint(x: plate.minX + 7, y: plate.minY + 6)
        CTLineDraw(line, context)
    }

    /// A plate in blocky's rules: a dark rim with its corners cut, a light fill, a light line top-left, a shade line bottom-right.
    static func pixelPlate(_ r: CGRect, _ context: CGContext) {
        context.setFillColor(ScreenOverlay.ink)
        context.fill([CGRect(x: r.minX + 1, y: r.minY, width: r.width - 2, height: r.height),
                      CGRect(x: r.minX, y: r.minY + 1, width: r.width, height: r.height - 2)])
        context.setFillColor(CGColor(srgbRed: 250 / 255, green: 248 / 255, blue: 240 / 255, alpha: 1))
        context.fill(r.insetBy(dx: 1, dy: 1))
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill([CGRect(x: r.minX + 1, y: r.maxY - 2, width: r.width - 2, height: 1), CGRect(x: r.minX + 1, y: r.minY + 1, width: 1, height: r.height - 2)])
        context.setFillColor(CGColor(srgbRed: 196 / 255, green: 192 / 255, blue: 206 / 255, alpha: 1))
        context.fill([CGRect(x: r.minX + 1, y: r.minY + 1, width: r.width - 2, height: 1), CGRect(x: r.maxX - 2, y: r.minY + 1, width: 1, height: r.height - 2)])
    }

    /// A pixel crosshair: a dark plus with a white rim, square ends, a gap in the middle.
    static let crosshair: NSCursor = {
        let size = 23, mid = 11
        let image = NSImage(size: NSSize(width: size, height: size), flipped: false) { _ in
            guard let c = NSGraphicsContext.current?.cgContext else { return false }
            let arms = [CGRect(x: 0, y: mid - 1, width: mid - 2, height: 3), CGRect(x: mid + 3, y: mid - 1, width: mid - 2, height: 3),
                        CGRect(x: mid - 1, y: 0, width: 3, height: mid - 2), CGRect(x: mid - 1, y: mid + 3, width: 3, height: mid - 2)]
            c.setFillColor(CGColor(gray: 1, alpha: 1))
            c.fill(arms)
            c.setFillColor(ScreenOverlay.ink)
            c.fill(arms.map { $0.insetBy(dx: 1, dy: 1) })
            c.fill(CGRect(x: mid, y: mid, width: 1, height: 1))
            return true
        }
        return NSCursor(image: image, hotSpot: NSPoint(x: mid, y: mid))
    }()
}

// MARK: The toolbar

/// The toolbar in the game's style: pixel pictures for the areas, the marks, six
/// colour squares, undo, and the three ways out; under it a line saying what to do.
/// Hovering a button puts a tag with its name and key on that line instead: no
/// letters to remember, and the system's tooltips would open under the frozen screens.
struct ShotToolbar: View {
    @ObservedObject var model: ShotModel

    /// What the pointer can rest on.
    enum Item: Hashable {
        case button(Shot.Button), colour(Int)
    }

    private static let ink = Color(cgColor: ScreenOverlay.ink)
    private static let faintInk = Color(cgColor: ScreenOverlay.faintInk)
    /// Every item's place, in the toolbar's own points.
    @State private var places: [Item: CGRect] = [:]
    @State private var width: CGFloat = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) {
                ForEach(Shot.Mode.allCases, id: \.self) { mode in
                    button(Shot.Button(mode), chosen: model.mode == mode) { model.act(.mode(mode)) }
                }
                gap
                ForEach(Shot.Tool.allCases, id: \.self) { tool in
                    button(Shot.Button(tool), chosen: model.stage == .marking && model.tool == tool) { model.act(.tool(tool)) }
                        .opacity(model.stage == .marking ? 1 : 0.45)
                }
                gap
                HStack(spacing: 2) {
                    ForEach(Shot.palette.indices, id: \.self) { n in
                        let c = Shot.palette[n]
                        Button { model.act(.colour(n)) } label: {
                            Rectangle().fill(Color(red: Double(c.r) / 255, green: Double(c.g) / 255, blue: Double(c.b) / 255))
                                .frame(width: 14, height: 14)
                                .padding(2).background(PixelBox.rim)
                                .frame(width: 30, height: 34)
                                .background(PixelBox(style: model.colour == n ? .chosen : .raised))
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .tip(.colour(n), model)
                    }
                }
                gap
                button(.undo) { model.act(.undo) }
                    .opacity(model.marks.isEmpty ? 0.45 : 1)
                gap
                button(.done, chosen: true) { model.act(.finish(.enter)) }
                button(.save) { model.act(.finish(.save)) }
                button(.cancel) { model.act(.cancel) }
            }
            ZStack(alignment: .leading) {
                Text(hint)
                    .font(.system(size: 10, weight: .heavy, design: .monospaced)).foregroundStyle(Self.ink)
                    .padding(.leading, 2)
                    .opacity(model.hovered == nil ? 1 : 0)
                if let item = model.hovered, let place = places[item] {
                    tag(Self.tooltip(item, model), under: place)
                }
            }
            .frame(height: 22)
        }
        .padding(.horizontal, 12).padding(.vertical, 10)
        .background(PixelBox(style: .raised))
        .coordinateSpace(name: ShotTipPlaces.space)
        .onPreferenceChange(ShotTipPlaces.self) { places = $0; model.places = $0 }
        .background(GeometryReader { g in Color.clear.onAppear { width = g.size.width }.onChange(of: g.size.width) { _, w in width = w } })
        .fixedSize()
    }

    private func button(_ which: Shot.Button, chosen: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) { PixelIcon(rows: which.icon) }
            .buttonStyle(PixelButtonStyle(small: true, chosen: chosen, square: true))
            .tip(.button(which), model)
    }

    /// The hovered item's name and key on a little plate, under it, kept inside the toolbar.
    private func tag(_ text: String, under place: CGRect) -> some View {
        let label = Text(text)
            .font(.system(size: 11, weight: .heavy, design: .monospaced)).foregroundStyle(Self.ink)
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(PixelBox(style: .well))
            .fixedSize()
        // Left of the middle it starts under the item; right of it, it ends there.
        let inset: CGFloat = 12
        return HStack(spacing: 0) {
            if place.midX < width / 2 {
                Color.clear.frame(width: max(0, place.minX - inset))
                label
                Spacer(minLength: 0)
            } else {
                Spacer(minLength: 0)
                label
                Color.clear.frame(width: max(0, width - inset - place.maxX))
            }
        }
    }

    private var gap: some View { Rectangle().fill(Self.faintInk).frame(width: 2, height: 22).padding(.horizontal, 3) }

    private var hint: String {
        guard model.stage == .marking else {
            switch model.mode {
            case .lasso: return tr("DRAW A LOOP AROUND IT · ⏎ THE WHOLE SCREEN · ⎋ CANCEL")
            default: return tr("DRAG AN AREA · W SCREEN · A ALL SCREENS · ⏎ THE WHOLE SCREEN · ⎋ CANCEL")
            }
        }
        return tr("%@ · 1–6 COLOUR · ⌘Z UNDO · ⏎ COPY · ⌘S SAVE · ⎋ CANCEL", Self.title(model.tool).uppercased())
    }

    /// What resting on `item` says.
    static func tooltip(_ item: Item, _ model: ShotModel) -> String {
        switch item {
        case .button(let b): b.tooltip(copies: model.entersCopy, saves: model.entersSave)
        case .colour(let n): Shot.colourTooltip(n)
        }
    }

    /// Every item on the toolbar, in order.
    static let items: [Item] = Shot.Button.allCases.map(Item.button) + Shot.palette.indices.map(Item.colour)

    static func title(_ tool: Shot.Tool) -> String {
        switch tool {
        case .box: tr("Box")
        case .arrow: tr("Arrow")
        case .highlight: tr("Highlight")
        case .blur: tr("Blur")
        case .brush: tr("Freehand blur")
        }
    }
}

/// Where each toolbar item stands, so its tag can sit under it.
struct ShotTipPlaces: PreferenceKey {
    static let space = "shot-toolbar"
    static let defaultValue: [ShotToolbar.Item: CGRect] = [:]
    static func reduce(value: inout [ShotToolbar.Item: CGRect], nextValue: () -> [ShotToolbar.Item: CGRect]) {
        value.merge(nextValue()) { $1 }
    }
}

private extension View {
    /// Says where this item stands and, while the pointer rests on it, that it is the one hovered.
    func tip(_ item: ShotToolbar.Item, _ model: ShotModel) -> some View {
        background(GeometryReader { g in
            Color.clear.preference(key: ShotTipPlaces.self, value: [item: g.frame(in: .named(ShotTipPlaces.space))])
        })
        .onHover { inside in
            if inside { model.hovered = item } else if model.hovered == item { model.hovered = nil }
        }
        .accessibilityLabel(ShotToolbar.tooltip(item, model))
    }
}

/// A picture of square pixels, `#` ink and `+` faint ink, two points each: the
/// creatures' flat, outlined look at toolbar size, light or dark mode alike, since
/// it always sits on the toolbar's own cream.
struct PixelIcon: View {
    var rows: [String]
    static let pixel: CGFloat = 2

    var body: some View {
        let w = CGFloat(rows.map(\.count).max() ?? 0), h = CGFloat(rows.count), p = Self.pixel
        Canvas { context, _ in
            for (y, row) in rows.enumerated() {
                for (x, c) in row.enumerated() {
                    let colour: CGColor? = c == "#" ? ScreenOverlay.ink : c == "+" ? ScreenOverlay.faintInk : nil
                    guard let colour else { continue }
                    context.fill(Path(CGRect(x: CGFloat(x) * p, y: CGFloat(y) * p, width: p, height: p)), with: .color(Color(cgColor: colour)))
                }
            }
        }
        .frame(width: w * p, height: h * p)
    }
}
