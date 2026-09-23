using Ledgelings.Core;

namespace Ledgelings;

/// <summary>The built-in lines: a conversation from the script, said on the colony's own clock.</summary>
public sealed partial class Colony
{
    /// <summary>A line from the script, waiting for its moment. <c>Closes</c>: the pair to let go once this, their last line, is out.</summary>
    private sealed record ScheduledLine(double At, int Speaker, string Text, (int, int)? Closes);

    /// <summary>Lines from the built-in script still to be said, by when.</summary>
    private readonly List<ScheduledLine> scheduled = new();
    /// <summary>The script conversations used lately, oldest first, so the same one is not heard twice running.</summary>
    private List<int> recentLines = new();

    /// <summary>Say a conversation from the script: the first line now, each next one
    /// when the one before has been up a while. Written to the log up front.</summary>
    private bool Recite(int speaker, int listener, string? flower, string situation)
    {
        Script script;
        try { script = Script.Parse(Settings.Script); }
        catch (Script.ParseException e) { TalkStatus = "the built-in lines: " + e.Message; return false; }
        var moment = new HashSet<string> { IsNight ? "night" : "day" };
        if (flower is not null) moment.Add("flower");
        if (script.Pick(moment, recentLines, rng) is not int chosen) { TalkStatus = "no built-in line fits right now"; return false; }
        recentLines = recentLines.Append(chosen).TakeLast(Math.Max(1, script.Conversations.Count / 2)).ToList();
        var a = CharacterFor(speaker);
        var b = CharacterFor(listener);
        var lines = script.Conversations[chosen].Lines.Select((line, i) =>
        {
            var mine = i % 2 == 0;
            return (Who: mine ? speaker : listener,
                    Text: Script.Fill(line, mine ? a.Name : b.Name, mine ? b.Name : a.Name, flower));
        }).ToList();
        busy.Add(speaker); busy.Add(listener);
        var at = Elapsed;
        for (int i = 0; i < lines.Count; i++)
        {
            var last = i == lines.Count - 1;
            scheduled.Add(new ScheduledLine(at, lines[i].Who, lines[i].Text, last ? (speaker, listener) : null));
            at += Banter.ShowTime(lines[i].Text, Settings.BubbleSeconds) * 0.6;
        }
        SayScheduledLines();
        History.Record(new ChatLog.Exchange
        {
            Time = DateTimeOffset.Now, Situation = situation, Provider = AppSettings.BrainTitle(BrainKind.Script), Model = "",
            Lines = lines.Select(l => new ChatLog.Line(CharacterFor(l.Who).Name, l.Text)).ToList(),
        });
        return true;
    }

    /// <summary>Every frame: the scripted lines whose time has come.</summary>
    private void SayScheduledLines()
    {
        var due = scheduled.Where(l => l.At <= Elapsed).ToList();
        if (due.Count == 0) return;
        scheduled.RemoveAll(l => l.At <= Elapsed);
        foreach (var line in due)
        {
            if (line.Speaker < creatures.Count)
            {
                Say(line.Text, line.Speaker);
                TalkStatus = $"{CharacterFor(line.Speaker).Name}: {line.Text}";
            }
            if (line.Closes is (int i, int j))
            {
                busy.Remove(i); busy.Remove(j);
                EndChat(i, j, 1.2);
            }
        }
    }
}
