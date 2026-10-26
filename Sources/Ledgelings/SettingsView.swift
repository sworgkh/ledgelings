import Combine
import AppKit
import LedgelingsCore
import SwiftUI

/// Which page the window shows, what the search box holds, and which section
/// a search just landed on; the menu and the scripts point it at a page.
@MainActor
final class SettingsNavigation: ObservableObject {
    @Published var page: SettingsPage = .creatures
    @Published var query = ""
    /// The heading of the section to scroll to and light up, for a moment.
    @Published var flash: String?
    private var unflash: Task<Void, Never>?

    /// Opens a search's hit: its page, scrolled to its section, which flashes gold.
    func open(_ hit: SettingsIndex.Hit) {
        page = hit.page
        unflash?.cancel()
        flash = nil
        guard !hit.section.isEmpty else { return }
        // A turn later, once the page is drawn and its headings can be found.
        unflash = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(50))
            self?.flash = hit.section
            try? await Task.sleep(for: .seconds(SettingsHeader.flashSeconds))
            if !Task.isCancelled { self?.flash = nil }
        }
    }
}

struct SettingsView: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject var history: ChatHistory
    @ObservedObject var library: SpriteLibrary
    @ObservedObject var spend: SpendLedger
    @ObservedObject var bonds: BondBook
    @ObservedObject var reminders: ReminderBook
    @ObservedObject var hunts: HuntBook
    @ObservedObject var beds: BedBook
    @ObservedObject var voice: Voice
    @ObservedObject var navigation: SettingsNavigation
    @ObservedObject var clips: ClipBook
    /// Deliver a reminder now.
    let send: (Reminders.Reminder) -> Void
    /// Opens Edit Snippets….
    var editSnippets: () -> Void = {}
    /// Pull up every planted flower; returns how many there were.
    var clearGarden: () -> Int = { 0 }
    /// Opens the Relationships window.
    var openRelationships: () -> Void = {}
    /// Reads the chat log into the pairs' memory; returns what it did.
    var seedMemory: (Bool) async -> String = { _ in "" }

    var body: some View {
        HStack(spacing: 0) {
            SettingsSidebar(navigation: navigation)
                .frame(width: SettingsSidebar.width)
            Divider()
            VStack(alignment: .leading, spacing: 0) {
                // One line, so the page keeps the room the tabs used to take.
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(navigation.page.title).font(.title3.weight(.bold))
                    Text(navigation.page.group.title.uppercased())
                        .font(.caption2.weight(.bold)).foregroundStyle(.tertiary)
                }
                .padding(.horizontal, 20)
                .padding(.top, 10)
                page(navigation.page)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            // Drawn, not left to the window, so a snapshot shows it too.
            .background(Color(nsColor: .windowBackgroundColor))
            .environment(\.settingsFlash, navigation.flash)
        }
        .frame(width: SettingsWindowController.size.width, height: SettingsWindowController.size.height)
        // Every title is looked up as it is drawn: a new language draws the window anew.
        .id(settings.language)
        // Dates and numbers too, whatever the system speaks.
        .environment(\.locale, Locale(identifier: settings.language.code))
    }

    /// One page's own view; a new page is a `SettingsPage` case and a line here.
    @ViewBuilder private func page(_ page: SettingsPage) -> some View {
        switch page {
        case .creatures: creaturesTab
        case .actions: ActionsSettingsView(settings: settings)
        case .sprites: SpritesSettingsView(settings: settings, library: library, spend: spend)
        case .beds: BedsSettingsView(settings: settings, library: library, beds: beds)
        case .flowers: FlowersSettingsView(settings: settings, library: library, clearGarden: clearGarden)
        case .calendar: CalendarSettingsView(settings: settings)
        case .chases: ChasesSettingsView(settings: settings, library: library, hunts: hunts)
        case .play: PlaySettingsView(settings: settings)
        case .ballGames: BallGamesSettingsView(settings: settings)
        case .talk: TalkSettingsView(settings: settings, library: library, voice: voice)
        case .voice: VoiceSettingsView(settings: settings, voice: voice)
        case .bonds: BondsSettingsView(settings: settings, bonds: bonds)
        case .relationships: RelationshipsSettingsView(settings: settings, bonds: bonds, open: openRelationships, seed: seedMemory)
        case .reminders: RemindersSettingsView(settings: settings, reminders: reminders, send: send)
        case .clipboard: ClipboardSettingsView(settings: settings, clips: clips, library: library, editSnippets: editSnippets)
        case .screenshots: ScreenshotSettingsView(settings: settings)
        case .dictation: DictationSettingsView(settings: settings, library: library)
        case .translate: TranslateSettingsView(settings: settings, library: library)
        case .costs: CostsSettingsView(spend: spend)
        case .chats: ChatHistoryView(history: history)
        }
    }

    private var creaturesTab: some View {
        TwoColumns {
            Section {
                Stepper(value: $settings.creatureCount, in: AppSettings.countRange) {
                    LabeledContent(tr("How many"), value: "\(settings.creatureCount)")
                }
                SliderRow(tr("Smallest"), value: $settings.minSize, in: AppSettings.sizeRange, step: AppSettings.sizeStep, unit: "×")
                SliderRow(tr("Largest"), value: $settings.maxSize, in: AppSettings.sizeRange, step: AppSettings.sizeStep, unit: "×")
                Picker(tr("Live on"), selection: screenBinding) {
                    Text(tr("All screens")).tag(HomeScreen.all)
                    ForEach(ScreenChoice.attached, id: \.id) { Text(verbatim: $0.name).tag($0.id) }
                    if ScreenChoice.isAway(settings) { Text(tr("%@ (unplugged)", settings.homeScreenName)).tag(settings.homeScreen) }
                }
            } header: {
                SettingsHeader("Creatures")
            } footer: {
                Text(tr("Every creature gets its own size between the two. Set them equal and they all match. Live on: keep them all on one monitor; choose another and they parachute over. While it is unplugged they use every screen, and go back when it returns."))
            }

            Section {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 44), spacing: 10)], alignment: .leading, spacing: 10) {
                    ForEach(settings.colors.indices, id: \.self) { index in
                        ColorPicker(tr("Colour %d", index + 1), selection: colorBinding(index), supportsOpacity: false)
                            .labelsHidden()
                    }
                }
                HStack {
                    Button(tr("Add Colour")) { settings.colors.append(AppSettings.defaultColors[settings.colors.count % AppSettings.defaultColors.count]) }
                        .disabled(settings.colors.count >= 12)
                    Button(tr("Remove Last")) { settings.colors.removeLast() }
                        .disabled(settings.colors.count <= 1)
                    Spacer()
                    Button(tr("Reset")) { settings.colors = AppSettings.defaultColors }
                }
            } header: {
                SettingsHeader("Colours")
            } footer: {
                Text(tr("Creature 1 wears the first colour, creature 2 the second, and so on, starting over when the colours run out."))
            }

            Section {
                Toggle(tr("Sit down to tea now and then"), isOn: $settings.teaPartiesEnabled)
                SliderRow(tr("Share of bumps"), value: $settings.teaPartyChance, in: AppSettings.teaChanceRange, step: 1, unit: "%")
                    .disabled(!settings.teaPartiesEnabled)
                SliderRow(tr("Lasts"), value: $settings.teaPartyMinutes, in: AppSettings.teaMinutesRange, step: 0.5, unit: tr(" min"))
                    .disabled(!settings.teaPartiesEnabled)
                SliderRow(tr("Sip between stories"), value: $settings.teaSipSeconds, in: AppSettings.teaSipRange, step: 1, unit: tr(" s"))
                    .disabled(!settings.teaPartiesEnabled)
            } header: {
                SettingsHeader("Tea parties")
            } footer: {
                Text(tr("Now and then two creatures who bump into each other put a little table out between them and sit down to tea, taking turns to tell each other stories from their lives. One party at a time. With talk off they just sip."))
            }
        } right: {
            Section {
                SliderRow(tr("Day lasts"), value: $settings.dayMinutes, in: 0.5...60, step: 0.5, unit: tr(" min"))
                SliderRow(tr("Night lasts"), value: $settings.nightMinutes, in: 0...60, step: 0.5, unit: tr(" min"), zero: tr("never"))
            } header: {
                SettingsHeader("Day and night")
            } footer: {
                Text(tr("They walk by day and sleep by night. Set the night to 0 and they never sleep. A cursor still startles a sleeper awake."))
            }

            Section {
                Picker(tr("The cursor is"), selection: $settings.cursorMood) {
                    ForEach(CursorMood.allCases, id: \.self) { Text(verbatim: $0.title).tag($0) }
                }
                Toggle(tr("Complain when pushed around"), isOn: $settings.complainEnabled)
                Stepper(value: $settings.complainAfter, in: AppSettings.complainAfterRange) {
                    LabeledContent(tr("Puts up with"), value: tr("%d in a row", settings.complainAfter))
                }
                .disabled(!settings.complainEnabled)
                SliderRow(tr("Calms down after"), value: $settings.complainCalmSeconds, in: AppSettings.complainCalmRange, step: 5, unit: tr(" s"))
                    .disabled(!settings.complainEnabled)
            } header: {
                SettingsHeader("The cursor")
            } footer: {
                Text(tr("A playmate: a chase is a game of tag. Just there: they hop aside. A menace: a grudge. Chase one too often in a row and it says so in its own voice."))
            }

            Section {
                Picker(tr("Language"), selection: $settings.language) {
                    ForEach(Language.allCases, id: \.self) { Text(verbatim: $0.title).tag($0) }
                }
                Toggle(tr("Start Ledgelings when you log in"), isOn: $startsAtLogin)
                    .onChange(of: startsAtLogin) { _, wanted in
                        guard wanted != LaunchAtLogin.isOn else { return }
                        do { try LaunchAtLogin.set(wanted) } catch { loginStatus = "\(error.localizedDescription)" ; return }
                        loginStatus = LaunchAtLogin.status
                        startsAtLogin = LaunchAtLogin.isOn
                    }
                LabeledContent(tr("Status")) { Text(loginStatus).foregroundStyle(.secondary) }
            } header: {
                SettingsHeader("Language and startup")
            } footer: {
                Text(tr("Menus, settings and what the creatures say. Prompts you edited stay as written. Login uses the system's Login Items."))
            }
        }
        .onAppear { startsAtLogin = LaunchAtLogin.isOn; loginStatus = LaunchAtLogin.status }
    }

    @State private var startsAtLogin = false
    @State private var loginStatus = tr("not checked")

    /// The chosen monitor by id; picking one saves its name with it.
    private var screenBinding: Binding<String> {
        Binding(get: { settings.homeScreen }, set: { id in
            guard id != settings.homeScreen else { return }
            settings.liveOn(ScreenChoice.attached.first { $0.id == id })
        })
    }

    private func colorBinding(_ index: Int) -> Binding<Color> {
        Binding(
            get: {
                let rgb = settings.colors.indices.contains(index) ? RGB(hex: settings.colors[index]) : nil
                let c = rgb ?? .white
                return Color(.sRGB, red: Double(c.r) / 255, green: Double(c.g) / 255, blue: Double(c.b) / 255)
            },
            set: { new in
                guard settings.colors.indices.contains(index),
                      let c = NSColor(new).usingColorSpace(.sRGB) else { return }
                func byte(_ v: CGFloat) -> UInt8 { UInt8((min(max(v, 0), 1) * 255).rounded()) }
                settings.colors[index] = RGB(r: byte(c.redComponent), g: byte(c.greenComponent), b: byte(c.blueComponent)).hex
            }
        )
    }
}

/// Two grouped forms side by side, each scrolling on its own, so a whole tab
/// fits on one screen.
struct TwoColumns<Left: View, Right: View>: View {
    @ViewBuilder let left: () -> Left
    @ViewBuilder let right: () -> Right

    init(@ViewBuilder left: @escaping () -> Left, @ViewBuilder right: @escaping () -> Right) {
        self.left = left; self.right = right
    }

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            SettingsColumn { left() }
            SettingsColumn { right() }
        }
    }
}

/// One grouped form that shows when it scrolls: a shadow along the bottom
/// while there is more below, and room under the last control so nothing sits
/// in the shadow once scrolled to the end. (The scroll bar itself stays visible
/// app-wide; see main.swift.)
struct SettingsColumn<Content: View>: View {
    @ViewBuilder let content: () -> Content
    @State private var moreBelow = false

    @Environment(\.settingsFlash) private var flash

    var body: some View {
        ScrollViewReader { proxy in
            form.onChange(of: flash) { _, heading in
                guard let heading else { return }
                withAnimation(.easeInOut(duration: 0.25)) { proxy.scrollTo(heading, anchor: .top) }
            }
        }
    }

    private var form: some View {
        Form { content() }
            .formStyle(.grouped)
            .contentMargins(.bottom, 56, for: .scrollContent)
            .onScrollGeometryChange(for: Bool.self) { g in
                g.contentSize.height + g.contentInsets.bottom - g.contentOffset.y - g.containerSize.height > 2
            } action: { _, more in moreBelow = more }
            .overlay(alignment: .bottom) {
                LinearGradient(colors: [.clear, .black.opacity(0.3)], startPoint: .top, endPoint: .bottom)
                    .frame(height: 44)
                    .padding(.trailing, 16)          // leave the scroll bar crisp
                    .allowsHitTesting(false)
                    .opacity(moreBelow ? 1 : 0)
                    .animation(.easeInOut(duration: 0.15), value: moreBelow)
            }
            .frame(maxWidth: .infinity)
    }
}

/// Shown above whatever a tab greys out for want of a model, so nothing is
/// silently dead: the reason, and where to choose one.
struct NeedsModelNote: View {
    var body: some View {
        Label(AppSettings.needsModel, systemImage: "info.circle")
            .font(.callout)
            .foregroundStyle(.secondary)
    }
}

/// A labelled slider with its value printed beside it: "3×", "5 min", "14 s".
struct SliderRow: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double
    let unit: String
    /// What to print instead of "0" when zero means off.
    var zero: String? = nil

    init(_ title: String, value: Binding<Double>, in range: ClosedRange<Double>, step: Double, unit: String, zero: String? = nil) {
        self.title = title
        _value = value
        self.range = range
        self.step = step
        self.unit = unit
        self.zero = zero
    }

    var body: some View {
        LabeledContent(title) {
            HStack {
                Slider(value: $value, in: range, step: step)
                Text(value == 0 && zero != nil ? zero! : String(format: "%g", value) + unit)
                    .monospacedDigit()
                    .frame(width: 70, alignment: .trailing)
            }
        }
    }
}

@MainActor
final class SettingsWindowController {
    /// The sidebar and two columns of about 530 each; tall enough that a page needs no
    /// scrolling, and both fit a 1280×800 laptop screen.
    static let size = CGSize(width: 1280, height: 760)
    private var window: NSWindow?
    private let settings: AppSettings
    private let history: ChatHistory
    private let library: SpriteLibrary
    private let spend: SpendLedger
    private let bonds: BondBook
    private let reminders: ReminderBook
    private let hunts: HuntBook
    private let beds: BedBook
    private let voice: Voice
    private let send: (Reminders.Reminder) -> Void
    private let clearGarden: () -> Int
    private let clips: ClipBook
    private let editSnippets: () -> Void
    private let openRelationships: () -> Void
    private let seedMemory: (Bool) async -> String
    private let navigation = SettingsNavigation()
    private var retitle: AnyCancellable?

    init(settings: AppSettings, history: ChatHistory, library: SpriteLibrary, spend: SpendLedger, bonds: BondBook,
         reminders: ReminderBook, hunts: HuntBook, beds: BedBook, voice: Voice, clips: ClipBook, send: @escaping (Reminders.Reminder) -> Void,
         clearGarden: @escaping () -> Int = { 0 }, editSnippets: @escaping () -> Void = {},
         openRelationships: @escaping () -> Void = {}, seedMemory: @escaping (Bool) async -> String = { _ in "" }) {
        self.openRelationships = openRelationships
        self.seedMemory = seedMemory
        self.clips = clips
        self.editSnippets = editSnippets
        self.settings = settings
        self.history = history
        self.library = library
        self.spend = spend
        self.bonds = bonds
        self.reminders = reminders
        self.hunts = hunts
        self.beds = beds
        self.voice = voice
        self.send = send
        self.clearGarden = clearGarden
    }

    /// Opens the window, on `page` when one is named; with `search`, those words are in
    /// the search box and its first place is open, its section lit up.
    func show(_ page: SettingsPage? = nil, search: String? = nil) {
        if let page { navigation.page = page }
        if let search {
            navigation.query = search
            if let first = SettingsIndex.search(search).first { navigation.open(first) }
        }
        if window == nil {
            let hosting = NSHostingController(rootView: SettingsView(settings: settings, history: history, library: library, spend: spend, bonds: bonds, reminders: reminders, hunts: hunts, beds: beds, voice: voice, navigation: navigation, clips: clips, send: send, editSnippets: editSnippets, clearGarden: clearGarden, openRelationships: openRelationships, seedMemory: seedMemory))
            let made = NSWindow(contentViewController: hosting)
            made.title = tr("Ledgelings Settings")
            retitle = settings.$language.dropFirst().receive(on: RunLoop.main).sink { [weak made] _ in made?.title = tr("Ledgelings Settings") }
            made.styleMask = [.titled, .closable]
            made.isReleasedWhenClosed = false
            // Size it before centring: centring the small frame the controller starts
            // with, then growing, left half the window off the screen.
            made.setContentSize(Self.size)
            made.center()
            window = made
        }
        // A menu-bar-only app is never frontmost on its own.
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    /// The window's content as a PNG, drawn by the app itself: no screen-recording permission needed.
    func snapshot(to url: URL) throws {
        guard let view = window?.contentView, let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
        if ProcessInfo.processInfo.environment["LEDGELINGS_SCROLL_TRACE"] != nil {
            func walk(_ v: NSView) {
                if let s = v as? NSScrollView {
                    FileHandle.standardError.write(Data("scroll: \(type(of: s)) style=\(s.scrollerStyle == .legacy ? "legacy" : "overlay") doc=\(s.documentView?.frame.height ?? -1) clip=\(s.contentView.frame.size) bar=\(s.verticalScroller?.frame ?? .zero)\n".utf8))
                }
                v.subviews.forEach(walk)
            }
            walk(view)
        }
        view.cacheDisplay(in: view.bounds, to: rep)
        guard let png = rep.representation(using: .png, properties: [:]) else { return }
        try png.write(to: url)
    }
}
