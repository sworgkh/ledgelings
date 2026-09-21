namespace Ledgelings.Core;

public static partial class SpriteText
{
    // MARK: Reading

    public static Sheet Parse(string text)
    {
        string? name = null;
        string? kind = null;
        var cast = new List<Character>();
        Tint? colour = null;
        var poses = new Dictionary<string, Ink[][]>();
        string? current = null;
        var rows = new List<Ink[]>();

        void Finish()
        {
            if (current is not string pose) return;
            if (rows.Count != Cell) throw new ParseException($"pose {pose} has {rows.Count} rows, not {Cell}");
            Validate(pose, rows);
            poses[pose] = rows.ToArray();
            rows = new List<Ink[]>();
        }

        foreach (var raw in text.Split('\n'))
        {
            var line = raw.Trim();
            // An empty line is nothing; a line of spaces inside a pose is a row of nothing.
            if (raw.Trim('\r', '\n').Length == 0 || line.StartsWith('#')) continue;
            if (line.Length == 0 && current is null) continue;
            if (Keyed(line, "name") is string n) { name = n; continue; }
            if (Keyed(line, "kind") is string k) { kind = k.Length == 0 ? null : k; continue; }
            if ((Keyed(line, "colour") ?? Keyed(line, "color")) is string c)
            {
                colour = Tint.FromHex(c) ?? throw new ParseException($"colour must be six hex digits like #f0a0b0, not \"{c}\"");
                continue;
            }
            if (Keyed(line, "character") is string who)
            {
                // "Name: what they are like" — the first colon splits them.
                var colon = who.IndexOf(':');
                var first = (colon < 0 ? who : who[..colon]).Trim();
                var rest = colon < 0 ? "" : who[(colon + 1)..].Trim();
                if (first.Length > 0) cast.Add(new Character(first, rest));
                continue;
            }
            if (Keyed(line, "pose") is string p)
            {
                Finish();
                if (!Poses.Contains(p)) throw new ParseException($"pose {p} is not one of {string.Join(", ", Poses)}");
                current = p;
                continue;
            }
            if (current is not string inPose) continue;
            var row = new List<Ink>();
            foreach (var letter in raw)
            {
                if (InkFor(letter) is Ink ink) row.Add(ink);
                else if (letter == ' ' || letter == '-' || letter == '_') row.Add(Ink.Clear);
                else if (letter == '\t' || letter == '\r') continue;
                else throw new ParseException($"pose {inPose}, row {rows.Count + 1}: `{letter}` is not one of . o b l s k x");
            }
            while (row.Count > Cell && row[^1] == Ink.Clear) row.RemoveAt(row.Count - 1);
            if (row.Count < Cell && row.All(i => i == Ink.Clear)) row.AddRange(Enumerable.Repeat(Ink.Clear, Cell - row.Count));
            if (row.Count != Cell) throw new ParseException($"pose {inPose}, row {rows.Count + 1} has {row.Count} letters, not {Cell}");
            rows.Add(row.ToArray());
        }
        Finish();
        if (string.IsNullOrEmpty(name)) throw new ParseException("the first line should be `name: something`");
        foreach (var pose in Poses) if (!poses.ContainsKey(pose)) throw new ParseException($"pose {pose} is missing");
        return new Sheet { Name = name, Kind = kind, Cast = cast, Colour = colour, Poses = poses };
    }

    private static string? Keyed(string line, string key)
    {
        if (!line.StartsWith(key + ":", StringComparison.OrdinalIgnoreCase)) return null;
        return line[(key.Length + 1)..].Trim(' ', '\t');
    }

    private static void Validate(string pose, List<Ink[]> rows)
    {
        bool any = false, onFloor = false;
        for (int y = 0; y < rows.Count; y++)
        {
            for (int x = 0; x < rows[y].Length; x++)
            {
                if (rows[y][x] == Ink.Clear) continue;
                any = true;
                if (x < Box.X || x >= Box.X + Box.W || y < Box.Y || y >= Box.Y + Box.H)
                    throw new ParseException($"pose {pose} has ink at row {y + 1}, column {x + 1}, outside columns {Box.X + 1}–{Box.X + Box.W} and rows {Box.Y + 1}–{Box.Y + Box.H}");
                if (y == Floor - 1) onFloor = true;
            }
        }
        if (!any) throw new ParseException($"pose {pose} is empty");
        if (!onFloor) throw new ParseException($"pose {pose} does not stand on the floor: row {Floor} is empty");
    }

    // MARK: Eyes

    /// <summary>The lids come down: <c>half</c> keeps the lower half of each vertical run of
    /// eye pixels, <c>closed</c> keeps its bottom row. What the lid covers becomes body.</summary>
    public static Ink[][] Variant(Ink[][] open, string variant)
    {
        if (variant == "open") return open;
        var grid = open.Select(r => (Ink[])r.Clone()).ToArray();
        var columns = open.Length == 0 ? 0 : open[0].Length;
        for (int x = 0; x < columns; x++)
        {
            int y = 0;
            while (y < open.Length)
            {
                if (open[y][x] != Ink.Eye) { y++; continue; }
                var end = y;
                while (end < open.Length && open[end][x] == Ink.Eye) end++;
                var run = end - y;
                var keep = variant == "closed" ? 1 : (run + 1) / 2;
                for (int row = y; row < end - keep; row++) grid[row][x] = Ink.Body;
                y = end;
            }
        }
        return grid;
    }
}
