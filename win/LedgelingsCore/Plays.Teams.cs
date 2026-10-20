namespace Ledgelings.Core;

/// <summary>Who plays the ball games, and on which side (SPEC §7.10, Ball games). Soccer and baseball are for
/// however many are free: one plays alone, two play each other, three play one goal (soccer), and from four
/// (soccer) or six (baseball) the crowd splits into two teams, best friends on the same side. The Mac's
/// <c>Plays+Teams.swift</c>.</summary>
public static partial class Plays
{
    /// <summary>How a crowd lines up, by how many there are.</summary>
    public enum Lineup
    {
        /// <summary>One: keepy-uppy and shots at an empty goal; practice swings.</summary>
        Solo,
        /// <summary>Two: a goal each; a pitcher and a batter who swap.</summary>
        Duel,
        /// <summary>Three at soccer: one goal, a keeper and two attackers, the keeper changing after each goal.</summary>
        Keeper,
        /// <summary>Every one for itself at baseball, three to five: the rest field while one bats.</summary>
        Rotation,
        /// <summary>Two teams split by friendship.</summary>
        Teams,
    }

    public static Lineup SoccerLineup(int count) => count switch
    {
        <= 1 => Lineup.Solo,
        2 => Lineup.Duel,
        3 => Lineup.Keeper,
        _ => Lineup.Teams,
    };

    public static Lineup BaseballLineup(int count) => count switch
    {
        <= 1 => Lineup.Solo,
        2 => Lineup.Duel,
        <= 5 => Lineup.Rotation,
        _ => Lineup.Teams,
    };

    /// <summary>Players a team game takes at most, and at the least.</summary>
    public const int TeamPlayersMin = 1, TeamPlayersMax = 10;

    /// <summary>The chance a game that is due is a team game, when one is on: more likely the more of them
    /// are free to join.</summary>
    public static double TeamChance(int crowd) => Math.Min(0.75, 0.3 + 0.1 * Math.Max(0, crowd));

    /// <summary>A team game for <paramref name="initiator"/> and whoever else is free (<paramref name="crowd"/>,
    /// with how close each is to it), or null: none is on (<paramref name="enabled"/> holds only those whose turn
    /// it may be), or the dice say a smaller game. Its closest friends join first, then the rest, up to that
    /// game's most.</summary>
    public static (Kind Kind, int[] Players)? ChooseTeamGame(int initiator, IReadOnlyList<(int Index, double Closeness)> crowd,
                                                              IReadOnlySet<Kind> enabled, IReadOnlyDictionary<Kind, int> maxPlayers, Random rng)
    {
        var games = AllKinds.Where(k => enabled.Contains(k) && k.IsTeamGame()).ToList();
        if (games.Count == 0 || rng.NextDouble() >= TeamChance(crowd.Count)) return null;
        var kind = rng.Pick(games);
        return (kind, Joining(initiator, crowd, maxPlayers.TryGetValue(kind, out var most) ? most : 6));
    }

    /// <summary>The initiator, then the crowd closest first (in their order when equally close), <paramref name="max"/> in all.</summary>
    public static int[] Joining(int initiator, IReadOnlyList<(int Index, double Closeness)> crowd, int max) =>
        new[] { initiator }.Concat(crowd.Select((c, n) => (c, n)).OrderByDescending(x => x.c.Closeness).ThenBy(x => x.n)
            .Take(Math.Max(0, max - 1)).Select(x => x.c.Index)).ToArray();

    /// <summary>Two sides out of <paramref name="players"/>, the closest friends together: of every way to split
    /// them into halves (the first player's side the bigger when odd), the one with the most closeness inside
    /// the sides. Each side keeps the players' order.</summary>
    public static int[][] Split(IReadOnlyList<int> players, Func<int, int, double> closeness)
    {
        var n = players.Count;
        if (n < 2) return new[] { players.ToArray(), Array.Empty<int>() };
        double Within(IReadOnlyList<int> side)
        {
            var sum = 0.0;
            for (int a = 0; a < side.Count; a++) for (int b = a + 1; b < side.Count; b++) sum += closeness(side[a], side[b]);
            return sum;
        }
        var size = (n + 1) / 2;
        int? bestMask = null;
        var bestScore = 0.0;
        // Every side of `size` that holds the first player.
        for (int mask = 0; mask < (1 << n); mask++)
        {
            if ((mask & 1) != 1 || System.Numerics.BitOperations.PopCount((uint)mask) != size) continue;
            var a = Enumerable.Range(0, n).Where(i => (mask & (1 << i)) != 0).Select(i => players[i]).ToList();
            var b = Enumerable.Range(0, n).Where(i => (mask & (1 << i)) == 0).Select(i => players[i]).ToList();
            var score = Within(a) + Within(b);
            if (bestMask is null || score > bestScore + 1e-9) { bestScore = score; bestMask = mask; }
        }
        var m = bestMask!.Value;
        return new[]
        {
            Enumerable.Range(0, n).Where(i => (m & (1 << i)) != 0).Select(i => players[i]).ToArray(),
            Enumerable.Range(0, n).Where(i => (m & (1 << i)) == 0).Select(i => players[i]).ToArray(),
        };
    }

    /// <summary>From six players a soccer side has a keeper: the one with the fewest friends on its side (the
    /// last of them when tied), who stays in goal.</summary>
    public static int? Keeper(IReadOnlyList<int> side, Func<int, int, double> closeness)
    {
        if (side.Count < 3) return null;
        double Ties(int p) => side.Where(o => o != p).Sum(o => closeness(p, o));
        int? best = null;
        foreach (var p in side.Reverse())
            if (best is null || Ties(p) < Ties(best.Value)) best = p;
        return best;
    }
}
