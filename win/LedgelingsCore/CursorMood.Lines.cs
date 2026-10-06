namespace Ledgelings.Core;

/// <summary>The English the cursor mood says instead (SPEC §6.1.2), generated from the Mac's
/// <c>CursorMood+Lines.swift</c> and <c>CursorMood.swift</c>: keep them word for word. The Russian comes
/// from <see cref="Shared"/>.</summary>
public static partial class CursorMoods
{
    public static readonly IReadOnlyDictionary<string, Rewrite> EnglishRewrites = new Dictionary<string, Rewrite>
    {
        ["Have you seen the cursor today?\nSeen it? It chased me across two monitors."] = new("Have you seen the cursor today?\nSeen it? We played tag across two monitors. I won.",
            "Have you seen the cursor today?\nIt went by. Twice. That's about it."),
        ["I have a plan for the cursor.\nDoes it involve running?\nThe plan is mostly running, yes."] = new("I have a game for the cursor.\nDoes it involve running?\nThe game is mostly running, yes. And winning.",
            "I have a plan for the afternoon.\nDoes it involve running?\nOnly if the cursor comes by. Then a small hop."),
        ["*clears throat* I have an announcement.\nIs it about the cursor again?\nIt's always about the cursor."] = new("*clears throat* I have an announcement.\nIs it about the cursor again?\nI beat it at tag. Twice. That's the announcement.",
            "*clears throat* I have an announcement.\nIs it about the cursor again?\nNo. It's about lunch."),
        ["Rate the cursor out of ten.\nMinus four.\nGenerous."] = new("Rate the cursor out of ten.\nEleven. Best tag partner on the screen.\nGenerous. Accurate, though.",
            "Rate the cursor out of ten.\nFive. It's a cursor.\nFair."),
        ["I've named the cursor.\nWhat is it called?\nI'm not saying it out loud. It might hear."] = new("I've named the cursor.\nWhat is it called?\nZoomy. It loves it. It told me with a wiggle.",
            "I've named the cursor.\nWhat is it called?\nThe cursor. It seemed to fit."),
        ["Do you hear that?\nThat's the fan.\nIt sounds like a cursor.\nEverything sounds like a cursor at night."] = new("Do you hear that?\nThat's the fan.\nI hoped it was the cursor, wanting to play.\nEverything sounds like a game at night.",
            "Do you hear that?\nThat's the fan.\nIt sounds like a fan.\nEverything sounds like a fan at night."),
        ["I was the first one here. Before the colours, before the cursor. Those were good days."] = new("I was the first one here. Before the colours, before the cursor. Quiet days. Too quiet, frankly.",
            "I was the first one here. Before the colours, even. Those were good days."),
        ["The cursor chased me into a corner once. I stared it down. It blinked first."] = new("The cursor chased me into a corner once. I tagged it back. It blinked first. I win.",
            "The cursor came by my corner once. I hopped aside. That's the whole story. Good story."),
        ["My greatest hunt: the cursor, at dawn. It escaped. We shall meet again."] = new("My greatest hunt: the cursor, at dawn. It escaped, and we both had a marvellous time. Again tomorrow.",
            "My greatest hunt: a speck of dust, at dawn. It escaped. We shall meet again."),
        ["Once I scanned the whole screen. Found one virus. It was the cursor. As expected."] = new("Once I scanned the whole screen. Found one friend. It was the cursor. As hoped hoped.",
            "Once I scanned the whole screen. Found nothing. As expected expected."),
        ["When I was little, I was scared of the cursor. I still am. But I was then too."] = new("When I was little, I was scared of the cursor. Now we play tag. I still squeak, though.",
            "When I was little, I was scared of the dark. I still am. But I was then too."),
        ["I have noticed every pixel that moved since I arrived. Mostly the cursor's fault."] = new("I have noticed every pixel that moved since I arrived. Mostly the cursor, playing.",
            "I have noticed every pixel that moved since I arrived. Mostly the cursor. It moves a lot."),
        ["That's nothing. I once waited a whole day for the cursor to leave."] = new("That's nothing. I once waited a whole day for the cursor to come back and play. Not that I wanted it to.",
            "That's nothing. I once waited a whole day for the screen to wake up."),
        ["I believe you. Unless the cursor put you up to it."] = new("I believe you. The cursor would vouch for you too too.",
            "I believe you. Ninety-nine percent percent."),
        ["{reader}. The cursor was on MY edge again. Twice. I am keeping a list."] = new("{reader}. The cursor was on MY edge again. Twice. I let it win once. I am keeping score.",
            "{reader}. Somebody was on MY edge again. Twice. I am keeping a list."),
        ["If you see the arrow, do NOT make eye contact. It feeds on attention."] = new("If you see the arrow, wave. It loves attention. Then run: it's tag.",
            "If you see the arrow, step aside. It's only passing through."),
        ["Paper beats cursor. I should fold myself a shield."] = new("Paper beats cursor. I should fold it one, so it has something to chase.",
            "Paper beats everything, apparently. I should fold myself a hat."),
        ["Fine. A reply. Short, because the cursor is watching."] = new("Fine. A reply. Short, because the cursor wants to play.",
            "Fine. A reply. Short, because that is my style."),
        ["The cursor sleeps. Tonight, we strike. Burn this letter. Actually don't, it's mine."] = new("The cursor sleeps. Tonight, we pounce on it, and it pounces back. Burn this letter. Actually don't, it's mine.",
            "The moon is up. Tonight, we strike. Burn this letter. Actually don't, it's mine."),
        ["What if the cursor steps on me? Has anyone ever been stepped on? Asking."] = new("What if the cursor tags me? Is it my turn then? How does tag work? Asking.",
            "What if it rains on the screen? Would I get bigger? Asking."),
        ["The cursor is a virus virus. Do not click. Do not click."] = new("The cursor is a friend friend. Click. Click. It likes it.",
            "Scan complete complete. Nothing found. Do not click anyway."),
        ["Got it got it. Sending this one before the cursor sees."] = new("Got it got it. Sending this one before the cursor catches me. It's winning winning.",
            "Got it got it. Sending this one back back."),
        ["Stop staring at the cursor. It's time: {reminder}. I have a list, and you're on it."] = new("Stop playing with the cursor. It's time: {reminder}. I have a list, and you're on it.",
            "Stop staring at the screen. It's time: {reminder}. I have a list, and you're on it."),
        ["Reminder reminder: {reminder}. The cursor did NOT send this."] = new("Reminder reminder: {reminder}. The cursor helped deliver this this.",
            "Reminder reminder: {reminder}. Virus-free free."),
    };

    public static readonly IReadOnlySet<string> EnglishFitsEveryMood = new HashSet<string>
    {
        "Here. I found a {flower} under the cursor.\nIs it... ticking?\nProbably not.",
        "Happy {holiday}, {listener}.\nIs that why the cursor's moving so slowly?",
        "I raced the cursor once. Beat it. It still won't admit it.",
        "Somebody once petted me with the cursor. I allowed it. Once.",
        "I scared a cursor once! It went all spinny! Well, it was loading, but still!",
    };

    /// <summary>The shipped personas that mention the cursor, and what they become. Their Russian is in the strings table.</summary>
    public static readonly IReadOnlyDictionary<string, Rewrite> Personas = new Dictionary<string, Rewrite>
    {
        ["Grumpy and proud. Hates the mouse cursor. Thinks the bottom edge is the only respectable edge."] = new("Grumpy and proud. Secretly loves racing the mouse cursor and would never admit it. Thinks the bottom edge is the only respectable edge.",
            "Grumpy and proud. Thinks the bottom edge is the only respectable edge."),
        ["Occasionally repeats a word word. Suspects the cursor is a virus."] = new("Occasionally repeats a word word. Scanned the cursor once: it is a friend friend.",
            "Occasionally repeats a word word. Runs virus scans on everything, out of habit."),
    };
}
