import LedgelingsCore
import SwiftUI

/// Settings › Play: whether they play, which games and how often on the left;
/// how each game goes on the right, with the props it is played with.
struct PlaySettingsView: View {
    @ObservedObject var settings: AppSettings

    /// The props, cut once.
    private static let props: SpriteAtlas.Frames? = (try? SpriteAtlas(named: "play"))?.frames()

    var body: some View {
        TwoColumns {
            Section {
                Toggle(tr("They play now and then"), isOn: $settings.playEnabled)
            } header: {
                Text(tr("Playing"))
            } footer: {
                Text(tr("Now and then a creature stops walking and plays, the way the worms in Worms fool about between turns, with nobody hurt. One game at a time, never in the middle of a talk, a tea party, a flower, a plane, a grab or sleep; the players are left alone until it is over."))
            }

            Section {
                Toggle(tr("Catch me if you can (two)"), isOn: $settings.playTagEnabled)
                Toggle(tr("Ninja rope swing"), isOn: $settings.playRopeEnabled)
                Toggle(tr("Parachute jump"), isOn: $settings.playParachuteEnabled)
                Toggle(tr("Basketball (alone, or two taking turns)"), isOn: $settings.playBasketballEnabled)
            } header: {
                Text(tr("Which games"))
            } footer: {
                Text(tr("Tag is for two: they chase each other round the edges, and a touch makes the other one \"it\". The rope is fired at the ceiling to swing across the floor; the parachute jump starts from the ceiling; the hoop goes on a wall at the end of a floor. Off, a game is never played, and its row on the Activities page is greyed."))
            }
            .disabled(!settings.playEnabled)

            Section {
                SliderRow(tr("A game about every"), value: $settings.playEveryMinutes, in: AppSettings.playEveryRange, step: 1, unit: tr(" min"))
                SliderRow(tr("Friends play more often by"), value: $settings.playBondBoost, in: AppSettings.playBondBoostRange, step: 10, unit: "%")
            } header: {
                Text(tr("How often"))
            } footer: {
                Text(tr("The wait between games is this many minutes, give or take, shortened by how close the closest pair on screen is: at 100 % the best of friends play twice as often. Close pairs (who have shared a few talks, tea parties, flowers) play tag and take turns at the hoop; strangers play alone."))
            }
            .disabled(!settings.playEnabled)
        } right: {
            Section {
                SliderRow(tr("Tag lasts"), value: $settings.tagSeconds, in: AppSettings.tagSecondsRange, step: 5, unit: tr(" s"))
                SliderRow(tr("Parachute comes down at"), value: $settings.parachuteFallSpeed, in: AppSettings.parachuteFallRange, step: 5, unit: tr(" pt/s"))
                SliderRow(tr("Ball keeps on each bounce"), value: $settings.ballBounce, in: AppSettings.ballBounceRange, step: 5, unit: "%")
                Stepper(value: $settings.basketballThrows, in: AppSettings.basketballThrowsRange) {
                    LabeledContent(tr("Throws at the hoop each"), value: "\(settings.basketballThrows)")
                }
            } header: {
                Text(tr("How the games go"))
            } footer: {
                Text(tr("After tag both stand puffing for a few seconds. The parachute sways as it comes down; slower is longer to watch. The ball bounces off the floor, the board and the rim; at 0 % it drops dead. About half the throws are aimed true; the rest fall short or bang off the board."))
            }
            .disabled(!settings.playEnabled)

            Section {
                Toggle(tr("Say something as a game starts and ends"), isOn: $settings.playTalk)
            } header: {
                Text(tr("Talking about it"))
            } footer: {
                Text(tr("Whoever starts a game says so in its own voice, and someone has the last word when it is over. With a model set up on the Talk tab, the first line is written by the model (counted under Plays on the Costs tab); otherwise, and for the last word, built-in lines. Needs Talk on."))
            }
            .disabled(!settings.playEnabled)

            Section {
                HStack(spacing: 18) {
                    ForEach(["ball", "hoop", "chute", "hook", "drop"], id: \.self) { picture($0) }
                }
            } header: {
                Text(tr("The props"))
            } footer: {
                Text(tr("Drawn like the creatures, and the same for every species, your own imported ones too."))
            }
        }
    }

    @ViewBuilder private func picture(_ animation: String) -> some View {
        if let image = Self.props?.frame(animation: animation, time: 0).flatMap(ActionIcons.trimmed) {
            Image(decorative: image, scale: 0.5).interpolation(.none)
        }
    }
}
