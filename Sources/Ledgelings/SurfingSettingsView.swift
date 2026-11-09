import LedgelingsCore
import SwiftUI

/// Settings › Surfing: on the left, the session (on or off, how often, how
/// long, how many waves, how many surf); on the right the waves' height and
/// the boards. It is switched on or off on the Play tab too, with the other games.
struct SurfingSettingsView: View {
    @ObservedObject var settings: AppSettings

    var body: some View {
        TwoColumns {
            Section {
                Toggle(tr("Surfing (anyone free, on the bottom edge)"), isOn: $settings.playSurfEnabled)
                SliderRow(tr("Surfing at most every"), value: $settings.surfEveryMinutes, in: AppSettings.ballGameEveryRange, step: 1, unit: tr(" min"))
                SliderRow(tr("A session lasts up to"), value: $settings.surfMinutes, in: AppSettings.surfMinutesRange, step: 0.5, unit: tr(" min"))
                Stepper(value: $settings.surfWaves, in: AppSettings.surfWavesRange) {
                    LabeledContent(tr("Waves in a session"), value: "\(settings.surfWaves)")
                }
                Stepper(value: $settings.surfPlayers, in: AppSettings.ballPlayersRange) {
                    LabeledContent(tr("Surfers at most"), value: "\(settings.surfPlayers)")
                }
            } header: {
                SettingsHeader("Surfing")
            } footer: {
                Text(tr(SurfingText.session))
            }
            .disabled(!settings.playEnabled)
        } right: {
            Section {
                SliderRow(tr("Wave height"), value: $settings.surfWaveHeight, in: AppSettings.surfWaveHeightRange, step: 0.5, unit: tr(" creatures"))
                SliderRow(tr("Water opacity"), value: $settings.surfWaterOpacity, in: AppSettings.surfWaterOpacityRange, step: 5, unit: "%")
            } header: {
                SettingsHeader("The waves")
            } footer: {
                Text(tr(SurfingText.waves))
            }
            .disabled(!settings.playEnabled)

            Section {
                LazyVGrid(columns: Array(repeating: GridItem(.fixed(30), spacing: 6), count: 9), spacing: 6) {
                    ForEach(0..<Plays.Surf.boardCount, id: \.self) { picture("board-\($0)") }
                }
                HStack(spacing: 18) {
                    ForEach(["splash", "spray"], id: \.self) { picture($0) }
                }
            } header: {
                SettingsHeader("The boards")
            } footer: {
                Text(tr(SurfingText.boards))
            }
        }
    }

    @ViewBuilder private func picture(_ animation: String) -> some View {
        if let image = PlaySettingsView.props?.frame(animation: animation, time: animation == "splash" ? 0.15 : 0).flatMap(ActionIcons.trimmed) {
            Image(decorative: image, scale: 1).interpolation(.none)
        }
    }
}
