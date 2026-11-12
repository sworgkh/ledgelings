using System.ComponentModel;
using System.Windows;
using Ledgelings.Core;

namespace Ledgelings.UI;

/// <summary>Settings › Effects and Settings › Moments (SPEC §7.19), the Mac's EffectsSettingsView and
/// MomentsSettingsView: the master switch, Reduce motion, how often and how long, and a switch and a Play
/// button for each of the five styles and the twenty moments, grouped by the feature they belong to.</summary>
public sealed partial class SettingsWindow
{
    /// <summary>Plays a style or a moment (by its code, <c>frost</c>, <c>goal</c>) on a creature now; false when nobody is free.</summary>
    public Func<string, bool>? PreviewEffect { get; set; }

    private sealed record EffectChoice(string Title, int Index);

    /// <summary>One row: the switch reads and writes the setting itself, so the colony sees it at once.</summary>
    private sealed class EffectRow(AppSettings settings, string key, string code, string title, string detail, bool busy, string feature)
        : INotifyPropertyChanged
    {
        public event PropertyChangedEventHandler? PropertyChanged;
        public string Code => code;
        public string Title => title;
        public string Feature => feature;
        public string Detail => busy ? detail + " · " + L10n.Tr("off with Reduce motion") : detail;
        public string PlayTip => L10n.Tr("Play %@ on a creature now", title);
        public bool On { get => settings.EffectOn(key); set => settings.SetEffect(key, value); }
        public void Refresh() => PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(nameof(On)));
    }

    private static readonly Effects.Moment[] CreatureMoments =
    [
        Effects.Moment.LeaveScreen, Effects.Moment.ArriveScreen, Effects.Moment.HardLanding, Effects.Moment.Dizzy, Effects.Moment.Goal,
        Effects.Moment.Friends, Effects.Moment.NewArrival, Effects.Moment.Poof, Effects.Moment.Bloom, Effects.Moment.Asleep,
    ];
    private static readonly Effects.Moment[] SeasonMoments = [Effects.Moment.Night, Effects.Moment.Winter, Effects.Moment.Autumn, Effects.Moment.Spring];
    private static readonly Effects.Moment[] ToolMoments =
    [
        Effects.Moment.HeyLook, Effects.Moment.ClockTicking, Effects.Moment.Listening, Effects.Moment.Translating,
        Effects.Moment.Copied, Effects.Moment.MoneySpent,
    ];

    private readonly List<EffectRow> effectRows = new();

    private void InitEffects()
    {
        EffectsReduceMotionBox.ItemsSource = Enum.GetValues<Effects.ReduceMotion>().Select(r => new EffectChoice(r.Title(), (int)r)).ToList();
        EffectsFrequencyBox.ItemsSource = Enum.GetValues<Effects.Frequency>().Select(f => new EffectChoice(f.Title(), (int)f)).ToList();
        EffectRow Row(Effects.Moment m) => new(settings, m.Key(), m.Code(), m.Title(), m.Detail(), m.Busy(), m.FeatureOf().Title());
        var styles = Effects.Styles.Select(s => new EffectRow(settings, s.Key(), s.Code(), s.Title(), s.Detail(), s.Busy(), "")).ToList();
        var creatures = CreatureMoments.Select(Row).ToList();
        var seasons = SeasonMoments.Select(Row).ToList();
        var tools = ToolMoments.Select(Row).ToList();
        EffectStyleList.ItemsSource = styles;
        MomentCreatureList.ItemsSource = creatures;
        MomentSeasonList.ItemsSource = seasons;
        MomentToolList.ItemsSource = tools;
        effectRows.AddRange(styles.Concat(creatures).Concat(seasons).Concat(tools));
        settings.PropertyChanged += (_, e) =>
        {
            if (e.PropertyName == nameof(AppSettings.EffectsOff)) foreach (var row in effectRows) row.Refresh();
        };
    }

    private void EffectPlay_Click(object sender, RoutedEventArgs e)
    {
        if (sender is FrameworkElement { Tag: string code } && PreviewEffect?.Invoke(code) == true) return;
        System.Media.SystemSounds.Beep.Play();
    }
}
