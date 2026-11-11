using T = Ledgelings.Core.Translate;

namespace Ledgelings.Core.Tests;

/// <summary>SPEC §7.14.3, the Mac's <c>SavedTranslationsTests.swift</c>: the star's rules, the drawer's search and
/// order, the file, and which side the drawer opens on.</summary>
public class SavedTranslationsTests
{
    private static readonly DateTimeOffset Day0 = DateTimeOffset.FromUnixTimeSeconds(1_800_000_000);

    private static T.Saved Entry(string text, string translation = "x", string from = "en", string to = "ru", double minutes = 0, string? app = null) =>
        T.Saved.New(text, from, translation, to, Day0.AddMinutes(minutes), app);

    [Fact]
    public void SavingAndUnsaving()
    {
        var book = new T.SavedBook();
        Assert.True(book.Toggle(Entry("Good morning", "Доброе утро"), 500));
        Assert.Equal("Доброе утро", book.Find("Good morning", "en", "ru")?.Translation);
        Assert.False(book.Toggle(Entry("Good morning", "Доброе утро", minutes: 1), 500));
        Assert.True(book.IsEmpty);
    }

    [Fact]
    public void TheSameTextAndPairIsSavedOnce()
    {
        var book = new T.SavedBook();
        book.Save(Entry("Good morning", "Доброе утро", app: "Notepad"), 500);
        var id = book.Entries[0].Id;
        book.Save(Entry("  Good morning\n", "С добрым утром", minutes: 5), 500);
        Assert.Equal(1, book.Count);
        Assert.Equal(id, book.Entries[0].Id);
        Assert.Equal("С добрым утром", book.Entries[0].Translation);
        Assert.Equal("Notepad", book.Entries[0].App);
        Assert.Equal(Day0.AddMinutes(5), book.Entries[0].SavedAt);
        book.Save(Entry("Good morning", "בוקר טוב", to: "he", minutes: 6), 500);
        book.Save(Entry("good morning", "Доброе утро", minutes: 7), 500);
        Assert.Equal(3, book.Count);
    }

    [Fact]
    public void TheOldestBeyondTheCapAreDropped()
    {
        var book = new T.SavedBook();
        for (var i = 0; i < 60; i++) book.Save(Entry($"text {i}", minutes: i), 50);
        Assert.Equal(50, book.Count);
        Assert.Equal("text 59", book.Entries[0].Text);
        Assert.Equal("text 10", book.Entries[^1].Text);
        book.Prune(20);
        Assert.Equal(20, book.Count);
        Assert.Equal("text 40", book.Entries[^1].Text);
    }

    [Fact]
    public void NewestFirst()
    {
        var book = new T.SavedBook(new[] { Entry("b", minutes: 2), Entry("a", minutes: 1), Entry("c", minutes: 3) });
        Assert.Equal(new[] { "c", "b", "a" }, book.Entries.Select(e => e.Text));
        book.Save(Entry("d", minutes: 0), 500);
        Assert.Equal("d", book.Entries[0].Text);
    }

    [Fact]
    public void SearchLooksInBothTexts()
    {
        var book = new T.SavedBook();
        book.Save(Entry("Can you send me the report?", "Можешь прислать мне отчёт?", minutes: 1), 500);
        book.Save(Entry("אני אגיע מאוחר היום", "I'll be late today", from: "he", to: "en", minutes: 2), 500);
        book.Save(Entry("Ещё раз", "Once again", from: "ru", to: "en", minutes: 3), 500);
        Assert.Equal(new[] { "Can you send me the report?" }, book.Search("REPORT").Select(e => e.Text));
        Assert.Single(book.Search("отчет"));
        Assert.Equal("he", book.Search("late")[0].From);
        Assert.Single(book.Search("мне send"));
        Assert.Empty(book.Search("nothing like it"));
        Assert.Equal(3, book.Search("  ").Count);
        Assert.Equal("Ещё раз", book.Search("")[0].Text);
    }

    [Fact]
    public void TheFileSurvivesAReload()
    {
        var dir = Path.Combine(Path.GetTempPath(), "saved-translations-" + Guid.NewGuid());
        try
        {
            var store = new T.SavedStore(dir);
            Assert.True(store.Load().IsEmpty);
            var book = new T.SavedBook();
            book.Save(Entry("Good morning", "Доброе утро", minutes: 1, app: "Edge"), 500);
            book.Save(Entry("שלום", "Hello", from: "he", to: "en", minutes: 2), 500);
            store.Save(book);
            Assert.Equal("translations.json", Path.GetFileName(store.File));
            var again = store.Load();
            Assert.Equal(book.Entries, again.Entries);
            Assert.Equal("שלום", again.Entries[0].Text);
            Assert.Equal("Edge", again.Entries[^1].App);
            File.WriteAllText(store.File, "not json");
            Assert.True(store.Load().IsEmpty);
        }
        finally { if (Directory.Exists(dir)) Directory.Delete(dir, true); }
    }

    [Fact]
    public void TheMacsFileReads()
    {
        var dir = Path.Combine(Path.GetTempPath(), "saved-translations-" + Guid.NewGuid());
        Directory.CreateDirectory(dir);
        try
        {
            File.WriteAllText(Path.Combine(dir, "translations.json"), """
                { "entries" : [ { "app" : "Notes", "from" : "en", "id" : "2B1C7A52-37C3-4B53-9E7A-1F2D2F7A0C11", "savedAt" : "2026-11-11T09:30:00Z", "text" : "Good morning", "to" : "ru", "translation" : "Доброе утро" } ] }
                """);
            var entry = Assert.Single(new T.SavedStore(dir).Load().Entries);
            Assert.Equal("Доброе утро", entry.Translation);
            Assert.Equal("Notes", entry.App);
            Assert.Equal(new DateTimeOffset(2026, 11, 11, 9, 30, 0, TimeSpan.Zero), entry.SavedAt);
        }
        finally { Directory.Delete(dir, true); }
    }

    [Fact]
    public void TheDrawerOpensOnTheRightUnlessThereIsNoRoom()
    {
        Assert.Equal(T.DrawerSide.Right, T.Side(400, 760, 350, 1728));
        Assert.Equal(T.DrawerSide.Left, T.Side(900, 760, 350, 1728));
        Assert.Equal(T.DrawerSide.Right, T.Side(100, 760, 350, 1000));
    }

    [Fact]
    public void APairTagAndADate()
    {
        Assert.Equal("HE → EN", Entry("x", from: "he", to: "en").Pair);
        Languages.With(Language.English, () =>
        {
            var local = Day0.ToLocalTime();
            Assert.Equal($"{local.Day} {local:MMM}", T.SavedDate(Day0, Day0));
            Assert.EndsWith(" " + local.Year, T.SavedDate(Day0, Day0.AddDays(400)));
            return 0;
        });
    }

    [Fact]
    public void TheLimitsAreChosen() => Assert.Equal((500, 50, 5_000), (T.DefaultSavedLimit, T.SavedLimitMin, T.SavedLimitMax));

    [Fact]
    public void TheStarAndTheDrawerSayWhatTheyDo()
    {
        Languages.With(Language.English, () =>
        {
            Assert.Equal("Save this translation (Ctrl+D)", T.Button.Save.Tooltip());
            Assert.Equal("Remove from saved (Ctrl+D)", T.Button.Save.Tooltip(on: true));
            Assert.Equal("Show saved translations (Ctrl+L)", T.Button.SavedList.Tooltip());
            Assert.Contains("Ctrl+L", T.Button.SavedList.Tooltip(on: true));
            Assert.Equal("Copy this translation (Ctrl+C)", T.Button.CopySaved.Tooltip());
            Assert.Equal("Delete from saved (Delete)", T.Button.DeleteSaved.Tooltip());
            return 0;
        });
        var filled = T.Button.Save.Icon(on: true);
        Assert.NotEqual(T.Button.Save.Icon(), filled);
        Assert.True(filled.Count == 11 && filled.All(r => r.Length == 11));
        Assert.Equal(T.Button.Copy.Icon(), T.Button.Copy.Icon(on: true));
        foreach (var button in Enum.GetValues<T.Button>())
            Assert.Contains(button.Key(), Languages.With(Language.Russian, () => button.Tooltip(on: true)));
    }
}
