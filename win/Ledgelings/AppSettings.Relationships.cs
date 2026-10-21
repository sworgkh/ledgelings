using Ledgelings.Core;

namespace Ledgelings;

/// <summary>The Relationships tab's settings (SPEC §6.5.2.2, §6.5.2.3): deeds from talk, which ones and how often,
/// and the pairs' long-term memory, the nightly diary and the seed from the chat log. The Mac's keys, defaults and ranges.</summary>
public sealed partial class AppSettings
{
    // MARK: Deeds

    /// <summary>Minutes the colony waits after one deed before another may start; 0: no wait.</summary>
    public const double DeedGapMin = 0, DeedGapMax = 60;
    /// <summary>Deeds started in an hour; 0: no limit.</summary>
    public const int DeedsPerHourMin = 0, DeedsPerHourMax = 120;
    /// <summary>Minutes before the same pair takes the same deed again; 0: no wait.</summary>
    public const double DeedPairGapMin = 0, DeedPairGapMax = 240;
    /// <summary>Minutes an invitation stays open for its answer.</summary>
    public const double InviteOpenMin = 1, InviteOpenMax = 60;
    /// <summary>Minutes an agreed deed waits for both to be free.</summary>
    public const double DeedWaitMin = 0.5, DeedWaitMax = 15;
    /// <summary>Percent of built-in letters and talks that invite; percent chance a built-in answer is yes.</summary>
    public const double PercentMin = 0, PercentMax = 100;
    /// <summary>Seconds one creature follows another.</summary>
    public const double FollowSecondsMin = 5, FollowSecondsMax = 300;

    private bool deedsEnabled, deedGames, deedTea, deedFlower, deedLetter, deedVisit, deedFollow, deedSleep;
    private double deedGapMinutes, deedPairGapMinutes, inviteOpenMinutes, deedWaitMinutes, builtInInviteShare, builtInAcceptChance, followSeconds;
    private int deedsPerHour;

    // MARK: Memory

    public const int MemoryTokensMin = 0, MemoryTokensMax = 2000;
    public const int MemoryFactsMin = 0, MemoryFactsMax = 20;
    public const int MemoryDaysMin = 0, MemoryDaysMax = 365;
    public const double DiaryEveryMin = 1, DiaryEveryMax = 48;
    public const int DiaryPairsMin = 0, DiaryPairsMax = 50;
    public const int DayContextItemsMin = 0, DayContextItemsMax = 10;
    public const int SeedDaysMin = 1, SeedDaysMax = 60;
    public const int SeedLinesMin = 5, SeedLinesMax = 200;

    private bool memoryEnabled, memoryNotes, diaryEnabled, dayContextEnabled;
    private int memoryTokens, memoryFacts, memoryDays, diaryPairsPerNight, dayContextItems, seedDays, seedLines;
    private double diaryEveryHours;

    private void LoadRelationships()
    {
        deedsEnabled = store.Get<bool?>("deedsEnabled") ?? true;
        // Four minutes and eight an hour: something happens now and then, not after every line.
        deedGapMinutes = Math.Clamp(store.Get<double?>("deedGapMinutes") ?? 4, DeedGapMin, DeedGapMax);
        deedsPerHour = Math.Clamp(store.Get<int?>("deedsPerHour") ?? 8, DeedsPerHourMin, DeedsPerHourMax);
        // Twenty minutes: the same two do not play soccer twice in a row.
        deedPairGapMinutes = Math.Clamp(store.Get<double?>("deedPairGapMinutes") ?? 20, DeedPairGapMin, DeedPairGapMax);
        inviteOpenMinutes = Math.Clamp(store.Get<double?>("inviteOpenMinutes") ?? 10, InviteOpenMin, InviteOpenMax);
        deedWaitMinutes = Math.Clamp(store.Get<double?>("deedWaitMinutes") ?? 3, DeedWaitMin, DeedWaitMax);
        // One built-in letter or talk in five invites; most invitations are taken up.
        builtInInviteShare = Math.Clamp(store.Get<double?>("builtInInviteShare") ?? 20, PercentMin, PercentMax);
        builtInAcceptChance = Math.Clamp(store.Get<double?>("builtInAcceptChance") ?? 65, PercentMin, PercentMax);
        followSeconds = Math.Clamp(store.Get<double?>("followSeconds") ?? 30, FollowSecondsMin, FollowSecondsMax);
        deedGames = store.Get<bool?>("deedGames") ?? true;
        deedTea = store.Get<bool?>("deedTea") ?? true;
        deedFlower = store.Get<bool?>("deedFlower") ?? true;
        deedLetter = store.Get<bool?>("deedLetter") ?? true;
        deedVisit = store.Get<bool?>("deedVisit") ?? true;
        deedFollow = store.Get<bool?>("deedFollow") ?? true;
        deedSleep = store.Get<bool?>("deedSleep") ?? true;
        memoryEnabled = store.Get<bool?>("memoryEnabled") ?? true;
        // 600 tokens: the busiest pair's whole story, five facts, today and yesterday, in Russian.
        // The old default, 150, cut the story; a saved 150 moves to the new one once, a value
        // chosen by hand stays.
        if (store.Get<bool?>("memoryTokensMoved") != true)
        {
            if (store.Get<int?>("memoryTokens") == Bonds.OldMemoryTokens) store.Set("memoryTokens", Bonds.MemoryTokens);
            store.Set("memoryTokensMoved", true);
        }
        memoryTokens = Math.Clamp(store.Get<int?>("memoryTokens") ?? Bonds.MemoryTokens, MemoryTokensMin, MemoryTokensMax);
        memoryFacts = Math.Clamp(store.Get<int?>("memoryFacts") ?? Bonds.MemoryFacts, MemoryFactsMin, MemoryFactsMax);
        // Two months of timeline: enough to see a friendship grow, a few KB a pair.
        memoryDays = Math.Clamp(store.Get<int?>("memoryDays") ?? Bonds.MemoryDays, MemoryDaysMin, MemoryDaysMax);
        memoryNotes = store.Get<bool?>("memoryNotes") ?? true;
        diaryEnabled = store.Get<bool?>("diaryEnabled") ?? true;
        // Eight hours: a pair's memory is written down about twice a working day.
        diaryEveryHours = Math.Clamp(store.Get<double?>("diaryEveryHours") ?? 8, DiaryEveryMin, DiaryEveryMax);
        diaryPairsPerNight = Math.Clamp(store.Get<int?>("diaryPairsPerNight") ?? 8, DiaryPairsMin, DiaryPairsMax);
        dayContextEnabled = store.Get<bool?>("dayContextEnabled") ?? true;
        dayContextItems = Math.Clamp(store.Get<int?>("dayContextItems") ?? 4, DayContextItemsMin, DayContextItemsMax);
        // Two weeks, forty lines a pair: about 2 500 tokens a pair, a fraction of a cent.
        seedDays = Math.Clamp(store.Get<int?>("seedDays") ?? 14, SeedDaysMin, SeedDaysMax);
        seedLines = Math.Clamp(store.Get<int?>("seedLines") ?? 40, SeedLinesMin, SeedLinesMax);
    }

    /// <summary>What creatures say can turn into what they do: a letter "soccer?" answered
    /// "yes" starts the match (<see cref="Deeds"/>).</summary>
    public bool DeedsEnabled { get => deedsEnabled; set => Put(ref deedsEnabled, value, "deedsEnabled"); }
    public double DeedGapMinutes { get => deedGapMinutes; set => Put(ref deedGapMinutes, Math.Clamp(value, DeedGapMin, DeedGapMax), "deedGapMinutes"); }
    public int DeedsPerHour { get => deedsPerHour; set => Put(ref deedsPerHour, Math.Clamp(value, DeedsPerHourMin, DeedsPerHourMax), "deedsPerHour"); }
    public double DeedPairGapMinutes { get => deedPairGapMinutes; set => Put(ref deedPairGapMinutes, Math.Clamp(value, DeedPairGapMin, DeedPairGapMax), "deedPairGapMinutes"); }
    public double InviteOpenMinutes { get => inviteOpenMinutes; set => Put(ref inviteOpenMinutes, Math.Clamp(value, InviteOpenMin, InviteOpenMax), "inviteOpenMinutes"); }
    public double DeedWaitMinutes { get => deedWaitMinutes; set => Put(ref deedWaitMinutes, Math.Clamp(value, DeedWaitMin, DeedWaitMax), "deedWaitMinutes"); }
    public double BuiltInInviteShare { get => builtInInviteShare; set => Put(ref builtInInviteShare, Math.Clamp(value, PercentMin, PercentMax), "builtInInviteShare"); }
    public double BuiltInAcceptChance { get => builtInAcceptChance; set => Put(ref builtInAcceptChance, Math.Clamp(value, PercentMin, PercentMax), "builtInAcceptChance"); }
    public double FollowSeconds { get => followSeconds; set => Put(ref followSeconds, Math.Clamp(value, FollowSecondsMin, FollowSecondsMax), "followSeconds"); }
    /// <summary>Which deeds may be offered.</summary>
    public bool DeedGames { get => deedGames; set => Put(ref deedGames, value, "deedGames"); }
    public bool DeedTea { get => deedTea; set => Put(ref deedTea, value, "deedTea"); }
    public bool DeedFlower { get => deedFlower; set => Put(ref deedFlower, value, "deedFlower"); }
    public bool DeedLetter { get => deedLetter; set => Put(ref deedLetter, value, "deedLetter"); }
    public bool DeedVisit { get => deedVisit; set => Put(ref deedVisit, value, "deedVisit"); }
    public bool DeedFollow { get => deedFollow; set => Put(ref deedFollow, value, "deedFollow"); }
    public bool DeedSleep { get => deedSleep; set => Put(ref deedSleep, value, "deedSleep"); }

    public Deeds.Limits DeedLimits => new(deedGapMinutes * 60, deedsPerHour, deedPairGapMinutes * 60);

    /// <summary>Pairs remember each other in every conversation: facts, games, their days, their story.</summary>
    public bool MemoryEnabled { get => memoryEnabled; set => Put(ref memoryEnabled, value, "memoryEnabled"); }
    public int MemoryTokens { get => memoryTokens; set => Put(ref memoryTokens, Math.Clamp(value, MemoryTokensMin, MemoryTokensMax), "memoryTokens"); }
    public int MemoryFacts { get => memoryFacts; set => Put(ref memoryFacts, Math.Clamp(value, MemoryFactsMin, MemoryFactsMax), "memoryFacts"); }
    public int MemoryDays { get => memoryDays; set => Put(ref memoryDays, Math.Clamp(value, MemoryDaysMin, MemoryDaysMax), "memoryDays"); }
    /// <summary>The model may write a fact down as it speaks (<c>NOTE:</c>).</summary>
    public bool MemoryNotes { get => memoryNotes; set => Put(ref memoryNotes, value, "memoryNotes"); }
    /// <summary>At the colony's nightfall the model condenses a pair's memory: one call per pair.</summary>
    public bool DiaryEnabled { get => diaryEnabled; set => Put(ref diaryEnabled, value, "diaryEnabled"); }
    public double DiaryEveryHours { get => diaryEveryHours; set => Put(ref diaryEveryHours, Math.Clamp(value, DiaryEveryMin, DiaryEveryMax), "diaryEveryHours"); }
    public int DiaryPairsPerNight { get => diaryPairsPerNight; set => Put(ref diaryPairsPerNight, Math.Clamp(value, DiaryPairsMin, DiaryPairsMax), "diaryPairsPerNight"); }
    /// <summary>Each creature knows what it did today (games, tea, flowers, letters).</summary>
    public bool DayContextEnabled { get => dayContextEnabled; set => Put(ref dayContextEnabled, value, "dayContextEnabled"); }
    public int DayContextItems { get => dayContextItems; set => Put(ref dayContextItems, Math.Clamp(value, DayContextItemsMin, DayContextItemsMax), "dayContextItems"); }
    /// <summary>How far back the seed reads the chat log, and how many lines it shows the model per pair.</summary>
    public int SeedDays { get => seedDays; set => Put(ref seedDays, Math.Clamp(value, SeedDaysMin, SeedDaysMax), "seedDays"); }
    public int SeedLines { get => seedLines; set => Put(ref seedLines, Math.Clamp(value, SeedLinesMin, SeedLinesMax), "seedLines"); }
}
