import AppKit
import Carbon.HIToolbox
import Combine
import LedgelingsCore
import SwiftUI

/// The Tools screen (§7.15): every tool the creatures run for you on one sheet of
/// the letter's pixel paper, a tile each. ⌃⌥K from any app, or the Creature Actions
/// sheet's Tools picture. A click, its number, or the arrows and ⏎ start one; ⎋
/// closes. The panel never makes Ledgelings the active app, so a tool that pastes
/// (the picker, the translator) still pastes into the app you were in.
@MainActor
final class ToolsScreenController {
    static let columns = 4
    static let tile = CGSize(width: 124, height: 128)
    static let gap: CGFloat = 10

    private let settings: AppSettings
    let model = ToolsScreenModel()
    private var panel: ClipPanel?
    private var monitor: Any?
    private var shortcut: GlobalShortcut?
    /// Starts a tool, once the screen is gone.
    var start: (Tools.Tool) -> Void = { _ in }
    /// Whether a tool is switched on, and its shortcut from any app as drawn.
    var isOn: (Tools.Tool) -> Bool = { _ in true }
    var shortcutLabel: (Tools.Tool) -> String? = { _ in nil }
    /// A greyed tile opens the settings page that switches it on.
    var openSettings: (SettingsPage) -> Void = { _ in }
    var trace: ((String) -> Void)?

    init(settings: AppSettings) {
        self.settings = settings
        model.choose = { [weak self] in self?.choose($0) }
        model.close = { [weak self] in self?.close() }
    }

    var isUp: Bool { panel != nil }

    static func size(tiles: Int) -> CGSize {
        let rows = max(1, (tiles + columns - 1) / columns)
        return CGSize(width: CGFloat(columns) * tile.width + CGFloat(columns - 1) * gap + 2 * 33,
                      height: CGFloat(rows) * tile.height + CGFloat(rows - 1) * gap + 24 + 34 + 40 + 20)
    }

    /// Takes its shortcut from every app, following the settings.
    func takeShortcut(pressed: @escaping () -> Void = {}) {
        let enabled = settings.$toolsScreenEnabled.combineLatest(settings.$toolsScreenShortcutEnabled).map { $0 && $1 }
        shortcut = GlobalShortcut(settings: settings, enabled: enabled, shortcut: settings.$toolsScreenShortcut,
                                  problem: { [weak settings] in if settings?.toolsScreenShortcutProblem != $0 { settings?.toolsScreenShortcutProblem = $0 } },
                                  pressed: { [weak self] in pressed(); self?.toggle() })
    }

    func toggle() { if isUp { close() } else { show() } }

    func show() {
        guard !isUp else { return }
        let tools = Tools.shown(settings.toolsScreenTools)
        model.tiles = tools.enumerated().map { i, tool in
            ToolsScreenModel.Tile(tool: tool, number: i + 1, on: isOn(tool), shortcut: shortcutLabel(tool))
        }
        model.chosen = model.tiles.firstIndex { $0.on } ?? 0
        let screen = ClipPickerController.screen(caret: ClipPaster.caret())
        let size = Self.size(tiles: tools.count)
        let made = ClipPanel(frame: screen.visibleFrame)
        model.paper = CGRect(x: (screen.visibleFrame.width - size.width) / 2, y: (screen.visibleFrame.height - size.height) / 2,
                             width: size.width, height: size.height).integral
        let hosting = NSHostingView(rootView: ToolsScreenView(model: model))
        hosting.frame = CGRect(origin: .zero, size: screen.visibleFrame.size)
        made.contentView = hosting
        panel = made
        made.makeKeyAndOrderFront(nil)
        trace?("tools open: \(tools.map(\.rawValue).joined(separator: ", "))")
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            let code = Int(event.keyCode), flags = event.modifierFlags
            let handled = MainActor.assumeIsolated { self?.key(code, flags) ?? false }
            return handled ? nil : event
        }
    }

    func close() {
        guard let panel else { return }
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        panel.orderOut(nil)
        self.panel = nil
    }

    /// A key on the screen: its number, an arrow, ⏎, ⎋.
    func key(_ code: Int, _ flags: NSEvent.ModifierFlags) -> Bool {
        guard flags.intersection([.command, .option, .control]).isEmpty else { return false }
        let count = model.tiles.count
        switch code {
        case kVK_Escape: close()
        case kVK_Return, kVK_ANSI_KeypadEnter: if model.tiles.indices.contains(model.chosen) { choose(model.chosen) }
        case kVK_LeftArrow: model.chosen = Tools.step(from: model.chosen, by: .left, count: count, columns: Self.columns)
        case kVK_RightArrow: model.chosen = Tools.step(from: model.chosen, by: .right, count: count, columns: Self.columns)
        case kVK_UpArrow: model.chosen = Tools.step(from: model.chosen, by: .up, count: count, columns: Self.columns)
        case kVK_DownArrow: model.chosen = Tools.step(from: model.chosen, by: .down, count: count, columns: Self.columns)
        default:
            guard let n = Self.digits.firstIndex(of: code), model.tiles.indices.contains(n) else { return false }
            choose(n)
        }
        return true
    }

    private static let digits = [kVK_ANSI_1, kVK_ANSI_2, kVK_ANSI_3, kVK_ANSI_4, kVK_ANSI_5, kVK_ANSI_6, kVK_ANSI_7, kVK_ANSI_8, kVK_ANSI_9]

    /// Tile `index`: the screen goes, then the tool starts; a greyed one opens where to switch it on.
    func choose(_ index: Int) {
        guard model.tiles.indices.contains(index) else { return }
        let tile = model.tiles[index]
        close()
        guard tile.on else {
            trace?("tools: \(tile.tool.rawValue) is off, opening its settings")
            openSettings(tile.tool.page)
            return
        }
        trace?("tools: start \(tile.tool.rawValue)")
        // A beat for the panel to go, so a screenshot does not catch it and a picker finds the app in front.
        Task { @MainActor [start] in
            try? await Task.sleep(for: .milliseconds(150))
            start(tile.tool)
        }
    }

    /// The paper as a PNG: `--tools --snapshot out.png`.
    func snapshot(to url: URL) throws {
        guard let view = panel?.contentView, let rep = view.bitmapImageRepForCachingDisplay(in: model.paper) else { return }
        view.cacheDisplay(in: model.paper, to: rep)
        try rep.representation(using: .png, properties: [:])?.write(to: url)
    }
}

@MainActor
final class ToolsScreenModel: ObservableObject {
    struct Tile: Equatable {
        let tool: Tools.Tool
        let number: Int
        let on: Bool
        let shortcut: String?

        var tooltip: String { tool.tooltip(number: number, shortcut: shortcut, on: on) }
    }

    @Published var tiles: [Tile] = []
    @Published var chosen = 0
    @Published var paper = CGRect.zero
    var choose: (Int) -> Void = { _ in }
    var close: () -> Void = {}
}

struct ToolsScreenView: View {
    @ObservedObject var model: ToolsScreenModel
    private static let softInk = Color(cgColor: ScreenOverlay.softInk)
    private static let faintInk = Color(cgColor: ScreenOverlay.faintInk)

    var body: some View {
        let paper = model.paper
        ZStack(alignment: .topLeading) {
            Color.black.opacity(0.001).onTapGesture { model.close() }
            sheet.frame(width: paper.width, height: paper.height).offset(x: paper.minX, y: paper.minY)
        }
    }

    private var sheet: some View {
        let size = model.paper.size
        let rows = stride(from: 0, to: model.tiles.count, by: ToolsScreenController.columns).map {
            Array(model.tiles.indices[$0..<min($0 + ToolsScreenController.columns, model.tiles.count)])
        }
        return ZStack(alignment: .topLeading) {
            NotePaper(width: size.width, height: size.height)
            VStack(alignment: .leading, spacing: 0) {
                Text(tr("TOOLS")).font(.system(size: 11, weight: .bold, design: .monospaced)).foregroundStyle(Self.faintInk)
                    .frame(height: 24, alignment: .topLeading)
                VStack(alignment: .leading, spacing: ToolsScreenController.gap) {
                    ForEach(rows.indices, id: \.self) { r in
                        HStack(spacing: ToolsScreenController.gap) {
                            ForEach(rows[r], id: \.self) { tileView($0) }
                        }
                    }
                }
                Spacer(minLength: 0)
                Text(model.tiles.isEmpty ? tr("No tools chosen: Settings › Tools › Tools screen.")
                     : tr("1–%d START  ←→↑↓ CHOOSE  ⏎ START  ⎋ CLOSE", min(model.tiles.count, 9)))
                    .font(.system(size: 9, weight: .heavy, design: .monospaced)).foregroundStyle(Self.faintInk)
                    .padding(.trailing, 60)
            }
            .padding(.horizontal, 33)
            .padding(.top, 24)
            .padding(.bottom, 20)
            .frame(width: size.width, height: size.height, alignment: .topLeading)
        }
        .contentShape(Rectangle())
        .onTapGesture {}
    }

    private func tileView(_ index: Int) -> some View {
        let tile = model.tiles[index]
        return Button { model.choose(index) } label: {
            VStack(spacing: 6) {
                PixelIcon(rows: tile.tool.icon).scaleEffect(2, anchor: .center).frame(width: 44, height: 44)
                Text(tile.tool.title).font(.system(size: 10, weight: .heavy, design: .monospaced))
                    .foregroundStyle(PixelBox.rim)
                    .multilineTextAlignment(.center).lineLimit(2).fixedSize(horizontal: false, vertical: true)
                    .frame(width: ToolsScreenController.tile.width - 16)
                Text(tile.on ? tile.shortcut ?? " " : tr("off")).font(.system(size: 9, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Self.softInk).lineLimit(1)
            }
            .frame(width: ToolsScreenController.tile.width, height: ToolsScreenController.tile.height)
            .overlay(alignment: .topTrailing) {
                Text(tile.number <= 9 ? "\(tile.number)" : " ").font(.system(size: 9, weight: .heavy, design: .monospaced))
                    .foregroundStyle(Self.faintInk).padding(.top, 8).padding(.trailing, 9)
            }
        }
        .buttonStyle(PixelTileStyle(chosen: index == model.chosen))
        .opacity(tile.on ? 1 : 0.45)
        .onHover { if $0 { model.chosen = index } }
        .modifier(PixelTag(text: tile.tooltip))
        .accessibilityLabel(tile.tooltip)
    }
}
