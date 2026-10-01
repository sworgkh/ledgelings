using System.Windows.Controls;
using Ledgelings.UI;

namespace Ledgelings.Tests;

/// <summary>SPEC §1.2 in the windows: the Creature Actions sheet and the XAML labels speak the chosen language.</summary>
public class LanguageUiTests
{
    [Fact]
    public void TheActionTilesSpeakRussian()
    {
        Languages.With(Language.Russian, () =>
        {
            var s = new ActionsState(Planted: 5);
            Assert.Equal(L10n.Lookup("MAKE THEM JUMP", Language.Russian), ActionsTile.Jump.Title(s));
            Assert.NotEqual("MAKE THEM JUMP", ActionsTile.Jump.Title(s));
            Assert.DoesNotContain("FLOWERS", ActionsTile.Flowers.Title(s));
            Assert.Contains("5", ActionsTile.Flowers.Title(s));
            Assert.Equal(L10n.Tr("dusk in %@", "1:15"), ActionsTile.Sleep.Detail(new ActionsState(PhaseLeft: 75)));
            Assert.Equal(L10n.Lookup("TILL 8:00", Language.Russian), ActionsSheet.HideChoices[^1].Title);
        });
        Languages.With(Language.English, () => Assert.Equal("CLEAR 5 FLOWERS", ActionsTile.Flowers.Title(new ActionsState(Planted: 5))));
    }

    [Fact]
    public void NumbersAreWrittenTheLanguagesWay()
    {
        Languages.With(Language.Russian, () => Assert.Equal("2,5", Tr.Number(2.5)));
        Languages.With(Language.English, () => Assert.Equal("2.5", Tr.Number(2.5)));
    }

    [Fact]
    public void MarkedTextFollowsALanguageChange() => OnSta(() =>
    {
        var label = new TextBlock();
        var value = new TextBlock();
        Languages.With(Language.English, () =>
        {
            Tr.SetText(label, "Day lasts");
            Tr.SetUnit(value, " min");
            Tr.SetValue(value, 2.5);
            Assert.Equal("Day lasts", label.Text);
            Assert.Equal("2.5 min", value.Text);
        });
        Languages.With(Language.Russian, () =>
        {
            Tr.Refresh();
            Assert.Equal(L10n.Lookup("Day lasts", Language.Russian), label.Text);
            Assert.Equal("2,5" + L10n.Lookup(" min", Language.Russian), value.Text);
            Tr.SetZero(value, "never");
            Tr.SetValue(value, 0.0);
            Assert.Equal(L10n.Lookup("never", Language.Russian), value.Text);
        });
    });

    private static void OnSta(Action body)
    {
        Exception? failed = null;
        var thread = new Thread(() => { try { body(); } catch (Exception e) { failed = e; } });
        thread.SetApartmentState(ApartmentState.STA);
        thread.Start();
        thread.Join();
        if (failed is not null) throw new Xunit.Sdk.XunitException(failed.ToString());
    }
}
