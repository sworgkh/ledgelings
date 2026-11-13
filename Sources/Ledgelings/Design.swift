import AppKit
import SwiftUI

// The shared look, so that a new screen cannot drift from the others.
// docs/DESIGN.md says what each part is for; this file is the only place
// sizes, fonts and the pixel boxes are defined. Two families:
//
// - The settings window and the other ordinary windows (Relationships, Snippets):
//   native macOS controls, laid out by the rules under `Look`.
// - The pixel paper (Creature Actions, the reminder note, the clipboard picker,
//   Tools, Translate, Read aloud, Chat): drawn in Blocky's style, by `Pixel`.

// MARK: - Ordinary windows

/// Sizes of the ordinary windows and the settings rows.
enum Look {
    /// The spacing scale: every gap and margin is one of these.
    enum Space {
        static let xs: CGFloat = 4
        static let s: CGFloat = 8
        static let m: CGFloat = 12
        static let l: CGFloat = 16
        static let xl: CGFloat = 24
    }

    /// The settings window's content: the sidebar and two columns of about 570. Tall
    /// enough that every page and the whole sidebar fit without scrolling; with its title
    /// bar it fits under the menu bar of a 1470×956 screen, the smallest a current Mac
    /// laptop shows by default (a 13-inch MacBook Air).
    static let settingsSize = CGSize(width: 1360, height: 880)
    /// The smallest screen every window must fit, title bar and menu bar included.
    static let smallestScreen = CGSize(width: 1470, height: 956)
    static let titleBar: CGFloat = 28
    static let menuBar: CGFloat = 37
    static let sidebarWidth: CGFloat = 220
    /// The value printed beside a slider: "5 min", "20 MB", "no limit".
    static let valueWidth: CGFloat = 76
}

extension View {
    /// A button inside a list row (Forget, Reset, Send Now): small and bordered, the
    /// same everywhere, its words on one line.
    func rowAction() -> some View {
        buttonStyle(.bordered).controlSize(.small).lineLimit(1).fixedSize()
    }

    /// A button in a settings section: its words on one line, the button as wide as
    /// they are. Wording too long for its place is shortened, never wrapped.
    func settingsButton() -> some View {
        lineLimit(1).fixedSize()
    }
}

/// A row of buttons under a section's controls: the first ones on the left, a last
/// one (a reset, a clear) pushed to the right.
struct ButtonRow<Leading: View, Trailing: View>: View {
    @ViewBuilder var leading: () -> Leading
    @ViewBuilder var trailing: () -> Trailing

    init(@ViewBuilder leading: @escaping () -> Leading, @ViewBuilder trailing: @escaping () -> Trailing = { EmptyView() }) {
        self.leading = leading; self.trailing = trailing
    }

    var body: some View {
        HStack(spacing: Look.Space.s) {
            leading().settingsButton()
            Spacer(minLength: Look.Space.s)
            trailing().settingsButton()
        }
    }
}

/// What a list says while it is empty, in the list's own place.
struct EmptyNote: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text).font(.callout).foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - The pixel paper

/// The pixel paper's rules: Blocky's style at three screen points a pixel.
@MainActor
enum Pixel {
    /// One paper pixel, in points.
    static let px: CGFloat = 3

    static let ink = Color(cgColor: ScreenOverlay.ink)
    static let softInk = Color(cgColor: ScreenOverlay.softInk)
    static let faintInk = Color(cgColor: ScreenOverlay.faintInk)

    /// Where the words start inside a sheet: clear of the rim, and on the right of
    /// the folded-down corner (`cornerRoom`) for the bottom row.
    static let margin = EdgeInsets(top: 22, leading: 27, bottom: 18, trailing: 27)
    static let cornerRoom: CGFloat = 48

    /// The font sizes, all monospaced and heavy as the creatures' lines are. Nothing
    /// on the paper is smaller than `hint`, and nothing is shrunk to fit.
    enum Font {
        /// The sheet's name, top left, in capitals: CLIPBOARD, TOOLS.
        static let title = SwiftUI.Font.system(size: 11, weight: .bold, design: .monospaced)
        /// A label beside controls, or a group's heading in a list: TO:, RECENT.
        static let label = SwiftUI.Font.system(size: 11, weight: .heavy, design: .monospaced)
        /// What is read: a row, a line, a message.
        static let body = SwiftUI.Font.system(size: 12, weight: .semibold, design: .monospaced)
        /// The big field at the top of a picker.
        static let field = SwiftUI.Font.system(size: 18, weight: .heavy, design: .monospaced)
        static let button = SwiftUI.Font.system(size: 13, weight: .heavy, design: .monospaced)
        static let smallButton = SwiftUI.Font.system(size: 11, weight: .heavy, design: .monospaced)
        /// The keys line at the bottom, a row's detail, a hover tag.
        static let hint = SwiftUI.Font.system(size: 10, weight: .heavy, design: .monospaced)
        /// The same sizes for measuring words (`fits`).
        static func ns(_ size: CGFloat) -> NSFont { NSFont.monospacedSystemFont(ofSize: size, weight: .heavy) }
    }

    /// Button heights: every pixel button is one of these.
    static let buttonHeight: CGFloat = 38
    static let smallButtonHeight: CGFloat = 30
    static let pictureButton: CGFloat = 34

    /// Whether words fit a width in a pixel font: the tests measure every label with it.
    static func fits(_ words: String, size: CGFloat, width: CGFloat) -> Bool {
        width >= textWidth(words, size: size)
    }

    static func textWidth(_ words: String, size: CGFloat) -> CGFloat {
        ceil((words as NSString).size(withAttributes: [.font: Font.ns(size)]).width)
    }
}

/// The sheet's name, top left, with whatever belongs on its right (a count, the
/// close button) pushed to the other side.
struct PaperTitle<Trailing: View>: View {
    let text: String
    @ViewBuilder var trailing: () -> Trailing

    init(_ text: String, @ViewBuilder trailing: @escaping () -> Trailing = { EmptyView() }) {
        self.text = text; self.trailing = trailing
    }

    var body: some View {
        HStack(spacing: 6) {
            Text(text).font(Pixel.Font.title).foregroundStyle(Pixel.faintInk).lineLimit(1)
            Spacer(minLength: Look.Space.s)
            trailing()
        }
    }
}

/// The keys line at the bottom of a sheet. It wraps to a second line rather than
/// shrinking past reading, and keeps clear of the folded corner.
struct PaperHints: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text).font(Pixel.Font.hint).foregroundStyle(Pixel.faintInk)
            .lineLimit(2).fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.trailing, Pixel.cornerRoom)
    }
}

/// What a paper list says while it is empty.
struct PaperEmpty: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text).font(Pixel.Font.body).foregroundStyle(Pixel.softInk)
            .multilineTextAlignment(.center)
            .padding(.top, 20).frame(maxWidth: .infinity)
    }
}

/// A box in blocky's rules at the paper's pixel size: a flat fill, a dark rim,
/// a light line top-left and a shade line bottom-right. A well (a field) is lit
/// the other way round, so it reads as pressed into the paper.
struct PixelBox: View {
    enum Style { case raised, pressed, chosen, well }
    var style: Style

    private static let px = Pixel.px
    private static func rgb(_ r: Double, _ g: Double, _ b: Double) -> Color { Color(red: r / 255, green: g / 255, blue: b / 255) }
    static let rim = Color(cgColor: ScreenOverlay.ink)

    private var colours: (fill: Color, topLeft: Color, bottomRight: Color) {
        switch style {
        case .raised: (Self.rgb(250, 248, 240), .white, Self.rgb(196, 192, 206))
        case .pressed: (Self.rgb(226, 222, 212), Self.rgb(196, 192, 206), .white)
        // Blocky's own orange, for the choice made and the button that does it.
        case .chosen: (Self.rgb(255, 138, 61), Self.rgb(255, 178, 122), Self.rgb(214, 98, 32))
        case .well: (Self.rgb(234, 230, 218), Self.rgb(196, 192, 206), Self.rgb(250, 248, 240))
        }
    }

    var body: some View {
        Canvas { context, size in
            let p = Self.px, w = size.width, h = size.height
            let (fill, light, shade) = colours
            context.fill(Path(CGRect(x: 0, y: 0, width: w, height: h)), with: .color(Self.rim))
            context.fill(Path(CGRect(x: p, y: p, width: w - 2 * p, height: h - 2 * p)), with: .color(fill))
            context.fill(Path(CGRect(x: p, y: p, width: w - 2 * p, height: p)), with: .color(light))
            context.fill(Path(CGRect(x: p, y: p, width: p, height: h - 2 * p)), with: .color(light))
            context.fill(Path(CGRect(x: p, y: h - 2 * p, width: w - 2 * p, height: p)), with: .color(shade))
            context.fill(Path(CGRect(x: w - 2 * p, y: p, width: p, height: h - 2 * p)), with: .color(shade))
            // Stepped corners: the rim's corner pixels are cut away, never rounded.
            for (x, y) in [(0, 0), (w - p, 0), (0, h - p), (w - p, h - p)] {
                context.blendMode = .clear
                context.fill(Path(CGRect(x: x, y: y, width: p, height: p)), with: .color(.black))
            }
        }
    }
}

/// A button drawn as a `PixelBox` that sinks a pixel while pressed.
struct PixelButton: View {
    var title: String
    var small = false
    var chosen = false
    var action: () -> Void

    var body: some View {
        Button(action: action) { Text(title) }
            .buttonStyle(PixelButtonStyle(small: small, chosen: chosen))
    }
}

/// Every pixel button: words (`small` or not), or a square picture (`square`); the
/// choice made, or the button that does the main thing, is `chosen` (orange).
/// Words stay on one line: a label that does not fit is reworded, never wrapped.
struct PixelButtonStyle: ButtonStyle {
    var small: Bool
    var chosen: Bool
    /// A square button for a pixel picture rather than words.
    var square = false

    /// The room either side of the words.
    static func inset(small: Bool) -> CGFloat { small ? 9 : 14 }

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(small ? Pixel.Font.smallButton : Pixel.Font.button)
            .foregroundStyle(PixelBox.rim)
            .lineLimit(1)
            .padding(.horizontal, square ? 0 : Self.inset(small: small))
            .frame(minWidth: square ? Pixel.pictureButton : small ? Pixel.smallButtonHeight : 0,
                   minHeight: square ? Pixel.pictureButton : small ? Pixel.smallButtonHeight : Pixel.buttonHeight)
            .background(PixelBox(style: configuration.isPressed ? .pressed : chosen ? .chosen : .raised))
            .offset(y: configuration.isPressed ? Pixel.px : 0)
            .contentShape(Rectangle())
    }
}

/// A tile drawn as a `PixelBox` that sinks a pixel while pressed.
struct PixelTileStyle: ButtonStyle {
    var chosen: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(PixelBox(style: configuration.isPressed ? .pressed : chosen ? .chosen : .raised))
            .offset(y: configuration.isPressed ? Pixel.px : 0)
            .contentShape(Rectangle())
    }
}

/// A pixel button smaller than the switches', for a title line: the screen choice.
struct TinyPixelButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Pixel.Font.hint)
            .foregroundStyle(PixelBox.rim)
            .lineLimit(1)
            .padding(.horizontal, 7)
            .frame(minHeight: 22)
            .background(PixelBox(style: configuration.isPressed ? .pressed : .raised))
            .offset(y: configuration.isPressed ? Pixel.px : 0)
            .contentShape(Rectangle())
    }
}

/// A tag drawn in the sheet itself on hover: the paper sits above where the
/// system's tooltips open, so `.help` would show underneath.
struct PixelTag: ViewModifier {
    let text: String
    @State private var hovering = false

    func body(content: Content) -> some View {
        content
            .onHover { hovering = $0 }
            .overlay(alignment: .bottom) {
                if hovering {
                    Text(text)
                        .font(Pixel.Font.hint)
                        .foregroundStyle(PixelBox.rim)
                        .padding(.horizontal, 7).padding(.vertical, 4)
                        .background(PixelBox(style: .raised))
                        .fixedSize()
                        .offset(y: 30)
                        .allowsHitTesting(false)
                        .zIndex(10)
                }
            }
            .zIndex(hovering ? 10 : 0)
    }
}
