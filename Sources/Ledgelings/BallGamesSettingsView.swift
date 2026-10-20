import LedgelingsCore
import SwiftUI

/// Settings › Ball games: soccer on the left, baseball on the right; how often,
/// how long, and how many join. Each is switched on or off on the Play tab too,
/// with the other games.
struct BallGamesSettingsView: View {
    @ObservedObject var settings: AppSettings

    var body: some View {
        TwoColumns {
            Section {
                Toggle(tr("Soccer (anyone free, in teams)"), isOn: $settings.playSoccerEnabled)
                SliderRow(tr("Soccer at most every"), value: $settings.soccerEveryMinutes, in: AppSettings.ballGameEveryRange, step: 1, unit: tr(" min"))
                SliderRow(tr("A match lasts up to"), value: $settings.soccerMinutes, in: AppSettings.soccerMinutesRange, step: 0.5, unit: tr(" min"))
                Stepper(value: $settings.soccerGoals, in: AppSettings.soccerGoalsRange) {
                    LabeledContent(tr("Goals to win"), value: "\(settings.soccerGoals)")
                }
                Stepper(value: $settings.soccerPlayers, in: AppSettings.ballPlayersRange) {
                    LabeledContent(tr("Soccer players at most"), value: "\(settings.soccerPlayers)")
                }
            } header: {
                Text(tr("Soccer"))
            } footer: {
                Text(tr("On the widest floor there is, a little net at each end. One plays keepy-uppy and shoots at an empty goal; two have a goal each; three share one goal and take turns in it; four or more split into teams of friends, a keeper each from six. First to the goals, or the best score when time is up."))
            }
            .disabled(!settings.playEnabled)

            Section {
                HStack(spacing: 18) {
                    ForEach(["soccer", "net", "bat", "baseball", "base", "base-taken"], id: \.self) { picture($0) }
                }
            } header: {
                Text(tr("The props"))
            } footer: {
                Text(tr("Drawn like the creatures, and the same for every species, your own imported ones too."))
            }
        } right: {
            Section {
                Toggle(tr("Baseball (anyone free, round every edge)"), isOn: $settings.playBaseballEnabled)
                SliderRow(tr("Baseball at most every"), value: $settings.baseballEveryMinutes, in: AppSettings.ballGameEveryRange, step: 1, unit: tr(" min"))
                Stepper(value: $settings.baseballInnings, in: AppSettings.baseballInningsRange) {
                    LabeledContent(tr("Innings"), value: "\(settings.baseballInnings)")
                }
                Stepper(value: $settings.baseballPlayers, in: AppSettings.ballPlayersRange) {
                    LabeledContent(tr("Baseball players at most"), value: "\(settings.baseballPlayers)")
                }
            } header: {
                Text(tr("Baseball"))
            } footer: {
                Text(tr("Home where the batter stands, the bases on the three edges furthest apart, the pitcher on the batter's floor. One practises; two to five bat in turn, a runner who must bat again leaving a pennant on its base; six or more play as two teams. Out over the top of the screen is a home run."))
            }
            .disabled(!settings.playEnabled)

            Section {
                Text(tr("Whoever is free joins, closest friends first, up to the most set here; playing together brings them closer. A ball game may come up only this many minutes after the last one ended. A scoreboard sits at the top of the screen while it lasts. Their lines come with Say something on the Play tab."))
                    .foregroundStyle(.secondary)
            } header: {
                Text(tr("Who plays"))
            }
        }
    }

    @ViewBuilder private func picture(_ animation: String) -> some View {
        if let image = PlaySettingsView.props?.frame(animation: animation, time: 0).flatMap(ActionIcons.trimmed) {
            Image(decorative: image, scale: 0.5).interpolation(.none)
        }
    }
}
