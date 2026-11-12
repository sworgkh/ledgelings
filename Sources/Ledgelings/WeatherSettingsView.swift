import LedgelingsCore
import SwiftUI

/// Settings › Weather: the switches and when it comes on the left; how deep, how heavy, how strong, and the
/// umbrellas on the right. Each weather has Play now, which starts it at once, quiet screen or not.
struct WeatherSettingsView: View {
    @ObservedObject var settings: AppSettings
    /// Starts one now (`clear` for Clear); nil in a snapshot.
    var play: ((String) -> Void)?

    var body: some View {
        TwoColumns {
            Section {
                Toggle(tr("Weather on"), isOn: $settings.weatherEnabled)
                row(.snow, $settings.weatherSnow)
                row(.rain, $settings.weatherRain)
                row(.wind, $settings.weatherWind)
                HStack {
                    Text(tr("Storm: rain and wind together")).foregroundStyle(.secondary)
                    Spacer(minLength: 4)
                    if let play {
                        Button(tr("Play now"), action: { play(Weather.Kind.storm.rawValue) }).controlSize(.small)
                            .help(tr("Start %@ now", Weather.Kind.storm.title.lowercased()))
                        Button(tr("Clear sky"), action: { play("clear") }).controlSize(.small)
                            .help(tr("Let the weather ease off now"))
                    }
                }
                Toggle(tr("Follow the season"), isOn: $settings.weatherFollowSeason)
                Picker(tr("Reduce motion"), selection: $settings.weatherReduceMotion) {
                    ForEach(Effects.ReduceMotion.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                Toggle(tr("The creatures talk about it"), isOn: $settings.weatherTalk)
            } header: {
                SettingsHeader("Weather")
            } footer: {
                Text(tr("Snow, rain or wind over the creatures' monitors when the screen is quiet. Following the season, snow comes mostly in winter, wind in autumn, rain any time. While it falls, the season's light particles along the bottom pause. Reduce motion halves the particles and keeps the wind from pushing anyone. It is only drawn: clicks go through it."))
            }

            Section {
                SliderRow(tr("How quiet the screen must be"), value: $settings.weatherQuietMinutes, in: AppSettings.weatherQuietRange, step: 1, unit: tr(" min"))
                Picker(tr("How often"), selection: $settings.weatherFrequency) {
                    ForEach(Weather.Frequency.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                SliderRow(tr("How long it lasts"), value: $settings.weatherMinutes, in: AppSettings.weatherMinutesRange, step: 1, unit: tr(" min"))
            } header: {
                SettingsHeader("When it comes")
            } footer: {
                Text(tr("Quiet: no typing and the cursor barely moving for that long, nothing full screen, no game, surf or dive, and no meeting (the calendar, when allowed, or a microphone in use). When you come back it eases off over a few seconds, and the snow left lying melts slowly."))
            }
        } right: {
            Section {
                levelPicker(tr("How deep snow piles"), $settings.weatherSnowDepth)
                Toggle(tr("Snow on window tops"), isOn: $settings.weatherWindowTops)
            } header: {
                SettingsHeader("Snow")
            } footer: {
                Text(tr("It piles up along the bottom edge and on the tops of windows, and grows until it is that deep. A window that moves or closes drops its snow. The creatures wade slower in deep snow and leave footprints; now and then one shivers, builds a snowman or throws a snowball at a friend."))
            }

            Section {
                levelPicker(tr("How heavy the rain is"), $settings.weatherRainHeaviness)
                SliderRow(tr("Umbrella sharing distance"), value: $settings.weatherShareDistance, in: AppSettings.weatherShareRange, step: 5, unit: tr(" pt"),
                          zero: tr("each their own"))
            } header: {
                SettingsHeader("Rain")
            } footer: {
                Text(tr("Everyone out in it opens an umbrella; creatures closer than this share a bigger one, up to three under it. Hanging from the top edge, an umbrella fills with rain like a bowl, tips over and falls. Puddles dry up afterwards."))
            }

            Section {
                levelPicker(tr("How strong the wind is"), $settings.weatherWindStrength)
            } header: {
                SettingsHeader("Wind")
            } footer: {
                Text(tr("Gusts come from one side with leaves or dust. The creatures lean into it, walk slower into it and faster with it; a strong gust pushes the light ones and can blow one off the top edge. In a storm, umbrellas turn inside out."))
            }
        }
    }

    @ViewBuilder private func row(_ kind: Weather.Kind, _ on: Binding<Bool>) -> some View {
        HStack(spacing: 8) {
            Toggle(kind.title, isOn: on).help(kind.detail)
            Spacer(minLength: 4)
            if let play {
                Button(tr("Play now"), action: { play(kind.rawValue) })
                    .controlSize(.small)
                    .help(tr("Start %@ now", kind.title.lowercased()))
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
