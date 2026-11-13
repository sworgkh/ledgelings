import AppKit
import Combine
import LedgelingsCore
import SwiftUI

/// The Weather & Sky window: every aspect of the weather and the sky in one place, in three columns. The whole
/// thing (on, Reduce motion, Stop now, Pause for today) and when weather comes; snow, and the wind with the storm;
/// rain, and the season's light particles with the fireflies. Each kind has its Play button, which shows it at
/// once, quiet screen or not. Too much for a settings page, so it has a window of its own; the page
/// (`WeatherPageView`) opens it.
struct WeatherSettingsView: View {
    @ObservedObject var settings: AppSettings
    /// Starts one now by name (a weather, a season's moment, `night`, or `stop`, `pause`, `resume`); nil in a snapshot.
    var play: ((String) -> Void)?

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            // Three equal columns: each would otherwise take the width its widest row asks for.
            SettingsColumn { general; when; skyTimes }.frame(width: WeatherWindowController.size.width / 3)
            SettingsColumn { snow; wind }.frame(width: WeatherWindowController.size.width / 3)
            SettingsColumn { rain; sky }.frame(width: WeatherWindowController.size.width / 3)
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .frame(width: WeatherWindowController.size.width, height: WeatherWindowController.size.height)
        .id(settings.language)
        .environment(\.locale, Locale(identifier: settings.language.code))
    }

    @ViewBuilder private var general: some View {
            Section {
                Toggle(tr("Weather on"), isOn: $settings.weatherEnabled)
                Picker(tr("Reduce motion"), selection: $settings.weatherReduceMotion) {
                    ForEach(Effects.ReduceMotion.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                Toggle(tr("The creatures talk about it"), isOn: $settings.weatherTalk)
                HStack(spacing: 8) {
                    Button(tr("Stop now")) { play?("stop") }
                        .help(tr("The weather, the falling leaves and the fireflies fade out now, and the snow lying goes"))
                    let paused = settings.weatherPaused()
                    Button(paused ? tr("Resume today") : tr("Pause for today")) { play?(paused ? "resume" : "pause") }
                        .help(tr("No weather, falling leaves, petals or fireflies until tomorrow; what is out now stops"))
                    Spacer(minLength: 0)
                }
                .disabled(play == nil)
            } header: {
                SettingsHeader("Weather & Sky")
            } footer: {
                Text(tr("Everything falls from above the top edge, the whole height, a sparse few at a time. Stop activity (⌃⌥Q), the Stop button and Stop Weather in the menu fade it all out in a second; nothing is switched off."))
            }
    }

    @ViewBuilder private var snow: some View {
            Section {
                kindRow(.snow, $settings.weatherSnow)
                countRow(tr("How many at once"), $settings.weatherSnowCount, Weather.snowCountRange)
                Picker(tr("Flake size"), selection: $settings.weatherFlakeSize) {
                    ForEach(Weather.FlakeSize.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                SliderRow(tr("Speed"), value: $settings.weatherSnowSpeed, in: Weather.speedRange, step: 0.1, unit: "×")
                Toggle(tr("Piles up"), isOn: $settings.weatherSnowPiles)
                levelPicker(tr("How deep"), $settings.weatherSnowDepth).disabled(!settings.weatherSnowPiles)
                Toggle(tr("On window tops too"), isOn: $settings.weatherWindowTops).disabled(!settings.weatherSnowPiles)
            } header: {
                SettingsHeader("Snow")
            } footer: {
                Text(tr("Flakes on a whole monitor at once. Piled up, they wade in it and build snowmen."))
            }
    }

    @ViewBuilder private var wind: some View {
            Section {
                kindRow(.wind, $settings.weatherWind)
                levelPicker(tr("How strong"), $settings.weatherWindStrength)
                SliderRow(tr("A gust every"), value: $settings.weatherGustSeconds, in: Weather.gustRange, step: 1, unit: tr(" s"))
                Toggle(tr("Gusts push the light ones"), isOn: $settings.weatherWindPushes)
                kindRow(.storm, $settings.weatherStorm, title: tr("Storm: rain and wind together"))
            } header: {
                SettingsHeader("Wind and storm")
            } footer: {
                Text(tr("Leaves or dust blow from one side; a strong gust can blow a light one off the top edge."))
            }
    }

    @ViewBuilder private var when: some View {
            Section {
                SliderRow(tr("How quiet the screen must be"), value: $settings.weatherQuietMinutes, in: AppSettings.weatherQuietRange, step: 1, unit: tr(" min"))
                Picker(tr("How often"), selection: $settings.weatherFrequency) {
                    ForEach(Weather.Frequency.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                SliderRow(tr("How long it lasts"), value: $settings.weatherMinutes, in: AppSettings.weatherMinutesRange, step: 1, unit: tr(" min"))
                Toggle(tr("Follow the season"), isOn: $settings.weatherFollowSeason)
            } header: {
                SettingsHeader("When weather comes")
            } footer: {
                Text(tr("Quiet: no typing, the cursor barely moving, nothing full screen, no game and no meeting. When you come back it eases off."))
            }
    }

    /// When the season's particles and the fireflies come out: beside when weather comes, where there is room.
    @ViewBuilder private var skyTimes: some View {
            Section {
                Picker(tr("Fireflies come out"), selection: $settings.skyFirefliesFrom) {
                    ForEach(AppSettings.skyFirefliesHours, id: \.self) { hour in
                        Text(hour == AppSettings.skyNightFollowsColony ? tr("with the creatures' night") : tr("from %d:00", hour)).tag(hour)
                    }
                }
                SliderRow(tr("Out for"), value: $settings.effectsAmbientSeconds, in: AppSettings.effectsAmbientSecondsRange, step: 10, unit: tr(" s"))
                SliderRow(tr("Once every"), value: $settings.effectsAmbientEveryMinutes, in: AppSettings.effectsAmbientEveryRange, step: 1, unit: tr(" min"))
            } header: {
                SettingsHeader("When leaves and fireflies come")
            }
    }

    @ViewBuilder private var rain: some View {
            Section {
                kindRow(.rain, $settings.weatherRain)
                countRow(tr("How many at once"), $settings.weatherRainCount, Weather.rainCountRange)
                SliderRow(tr("Speed"), value: $settings.weatherRainSpeed, in: Weather.speedRange, step: 0.1, unit: "×")
                Toggle(tr("Puddles"), isOn: $settings.weatherPuddles)
                Toggle(tr("Umbrellas"), isOn: $settings.weatherUmbrellas)
                SliderRow(tr("Umbrella sharing distance"), value: $settings.weatherShareDistance, in: AppSettings.weatherShareRange, step: 5, unit: tr(" pt"),
                          zero: tr("each their own"))
                    .disabled(!settings.weatherUmbrellas)
                Toggle(tr("On the menu bar an umbrella fills and falls"), isOn: $settings.weatherMenuBarUmbrella).disabled(!settings.weatherUmbrellas)
            } header: {
                SettingsHeader("Rain")
            } footer: {
                Text(tr("Creatures closer than the distance share a bigger umbrella. Hanging from the top edge, an umbrella fills like a bowl, tips over and falls."))
            }
    }

    @ViewBuilder private var sky: some View {
            Section {
                lightRow(tr("Autumn leaves"), $settings.skyAutumnLeaves, $settings.skyAutumnCount, play: "autumn")
                lightRow(tr("Spring petals"), $settings.skySpringPetals, $settings.skySpringCount, play: "spring")
                lightRow(tr("Winter snow"), $settings.skyWinterSnow, $settings.skyWinterCount, play: "winter")
                lightRow(tr("Fireflies"), $settings.skyFireflies, Binding(get: { Double(settings.skyFirefliesCount) }, set: { settings.skyFirefliesCount = Int($0.rounded()) }),
                         range: Double(AppSettings.skyFirefliesRange.lowerBound)...Double(AppSettings.skyFirefliesRange.upperBound), play: "night")
            } header: {
                SettingsHeader("Seasons and night")
            } footer: {
                Text(tr("Apart from the weather, falling from the top: leaves in autumn, petals in spring, snow in winter. Fireflies stay low, after dark."))
            }
    }

    /// A weather's switch and its Play button.
    @ViewBuilder private func kindRow(_ kind: Weather.Kind, _ on: Binding<Bool>, title: String? = nil) -> some View {
        HStack(spacing: 8) {
            Toggle(title ?? kind.title, isOn: on).help(kind.detail)
            Spacer(minLength: 4)
            if let play {
                Button(tr("Play now"), action: { play(kind.rawValue) })
                    .controlSize(.small)
                    .help(tr("Start %@ now", kind.title.lowercased()))
            }
        }
    }

    /// How many on a monitor at once: a slider with the number.
    private func countRow(_ title: String, _ value: Binding<Double>, _ range: ClosedRange<Double>) -> some View {
        SliderRow(title, value: value, in: range, step: 1, unit: "")
    }

    /// A season's light particles (or the fireflies): the switch, how many at once, and Play.
    @ViewBuilder private func lightRow(_ title: String, _ on: Binding<Bool>, _ count: Binding<Double>,
                                       range: ClosedRange<Double> = AppSettings.skyCountRange, play name: String) -> some View {
        LabeledContent(title) {
            HStack(spacing: 8) {
                Slider(value: count, in: range, step: 1).disabled(!on.wrappedValue)
                    .frame(minWidth: 50)
                    .help(tr("How many on a monitor at once"))
                Text(String(format: "%g", count.wrappedValue)).monospacedDigit().frame(width: 24, alignment: .trailing)
                Toggle(title, isOn: on).labelsHidden().toggleStyle(.switch)
                if let play {
                    Button(tr("Play now"), action: { play(name) })
                        .controlSize(.small)
                        .fixedSize()
                        .help(tr("Show %@ now", title.lowercased()))
                }
            }
        }
    }

    private func levelPicker(_ title: String, _ value: Binding<Weather.Level>) -> some View {
        Picker(title, selection: value) {
            ForEach(Weather.Level.allCases, id: \.self) { Text($0.title).tag($0) }
        }
        .pickerStyle(.segmented)
    }
}

/// Settings › Weather & Sky: the main switch, Stop now and Pause for today, and the button that opens the
/// Weather & Sky window with every aspect in it. Coming to this page (from the sidebar or a search) opens it too.
struct WeatherPageView: View {
    @ObservedObject var settings: AppSettings
    var play: ((String) -> Void)?
    /// Opens the Weather & Sky window; nil in a snapshot.
    var open: (() -> Void)?

    var body: some View {
        TwoColumns {
            Section {
                Toggle(tr("Weather on"), isOn: $settings.weatherEnabled)
                HStack(spacing: 8) {
                    Button(tr("Open Weather & Sky…")) { open?() }
                        .keyboardShortcut(.defaultAction)
                        .help(tr("Every aspect of the weather and the sky, in a window of its own"))
                    Button(tr("Stop now")) { play?("stop") }
                        .help(tr("The weather, the falling leaves and the fireflies fade out now, and the snow lying goes"))
                    let paused = settings.weatherPaused()
                    Button(paused ? tr("Resume today") : tr("Pause for today")) { play?(paused ? "resume" : "pause") }
                        .help(tr("No weather, falling leaves, petals or fireflies until tomorrow; what is out now stops"))
                    Spacer(minLength: 0)
                }
            } header: {
                SettingsHeader("Weather & Sky")
            } footer: {
                Text(tr("Snow, rain, wind and storms, the season's leaves, petals and snow, and the fireflies: each with its own switches in the Weather & Sky window, which also opens from the menu's Weather submenu."))
            }
        } right: {
            EmptyView()
        }
        .onAppear { open?() }
    }
}

/// The Weather & Sky window (`WeatherSettingsView`), opened from its settings page, the menu and a search.
@MainActor
final class WeatherWindowController {
    /// Three columns of about 425 points: every aspect fits without scrolling on a 1280×800 laptop screen.
    static let size = CGSize(width: 1280, height: 760)
    private let settings: AppSettings
    private var window: NSWindow?
    private var retitle: AnyCancellable?
    var play: ((String) -> Void)?

    init(settings: AppSettings) { self.settings = settings }

    func show() {
        if window == nil {
            let made = NSWindow(contentViewController: NSHostingController(rootView: WeatherSettingsView(settings: settings, play: { [weak self] in self?.play?($0) })))
            made.title = tr("Weather & Sky")
            retitle = settings.$language.dropFirst().receive(on: RunLoop.main).sink { [weak made] _ in made?.title = tr("Weather & Sky") }
            made.styleMask = [.titled, .closable]
            made.isReleasedWhenClosed = false
            made.setContentSize(Self.size)
            WindowPlacer.place(made, as: .weather, settings: settings) { made.center() }
            window = made
        }
        if let window { WindowPlacer.watch(window, as: .weather, settings: settings) }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    func close() { window?.close() }

    func snapshot(to url: URL) throws {
        guard let view = window?.contentView, let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
        view.cacheDisplay(in: view.bounds, to: rep)
        try rep.representation(using: .png, properties: [:])?.write(to: url)
    }
}
