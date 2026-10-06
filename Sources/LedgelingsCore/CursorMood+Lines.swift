extension CursorMood {
    /// Every shipped English line about the cursor that the bad mood says as it
    /// is, with what the good and neutral moods say instead. A conversation is
    /// keyed by its lines joined with newlines and rewritten whole, the same
    /// number of lines, so who says what stays as it was. Each rewrite keeps its
    /// character's voice: Blocky stays proud, Glitch repeats repeats.
    public static let englishRewrites: [String: Rewrite] = [
        // The built-in script
        "Have you seen the cursor today?\nSeen it? It chased me across two monitors.": Rewrite(
            good: "Have you seen the cursor today?\nSeen it? We played tag across two monitors. I won.",
            neutral: "Have you seen the cursor today?\nIt went by. Twice. That's about it."),
        "I have a plan for the cursor.\nDoes it involve running?\nThe plan is mostly running, yes.": Rewrite(
            good: "I have a game for the cursor.\nDoes it involve running?\nThe game is mostly running, yes. And winning.",
            neutral: "I have a plan for the afternoon.\nDoes it involve running?\nOnly if the cursor comes by. Then a small hop."),
        "*clears throat* I have an announcement.\nIs it about the cursor again?\nIt's always about the cursor.": Rewrite(
            good: "*clears throat* I have an announcement.\nIs it about the cursor again?\nI beat it at tag. Twice. That's the announcement.",
            neutral: "*clears throat* I have an announcement.\nIs it about the cursor again?\nNo. It's about lunch."),
        "Rate the cursor out of ten.\nMinus four.\nGenerous.": Rewrite(
            good: "Rate the cursor out of ten.\nEleven. Best tag partner on the screen.\nGenerous. Accurate, though.",
            neutral: "Rate the cursor out of ten.\nFive. It's a cursor.\nFair."),
        "I've named the cursor.\nWhat is it called?\nI'm not saying it out loud. It might hear.": Rewrite(
            good: "I've named the cursor.\nWhat is it called?\nZoomy. It loves it. It told me with a wiggle.",
            neutral: "I've named the cursor.\nWhat is it called?\nThe cursor. It seemed to fit."),
        "Do you hear that?\nThat's the fan.\nIt sounds like a cursor.\nEverything sounds like a cursor at night.": Rewrite(
            good: "Do you hear that?\nThat's the fan.\nI hoped it was the cursor, wanting to play.\nEverything sounds like a game at night.",
            neutral: "Do you hear that?\nThat's the fan.\nIt sounds like a fan.\nEverything sounds like a fan at night."),

        // Tea party stories and replies
        "I was the first one here. Before the colours, before the cursor. Those were good days.": Rewrite(
            good: "I was the first one here. Before the colours, before the cursor. Quiet days. Too quiet, frankly.",
            neutral: "I was the first one here. Before the colours, even. Those were good days."),
        "The cursor chased me into a corner once. I stared it down. It blinked first.": Rewrite(
            good: "The cursor chased me into a corner once. I tagged it back. It blinked first. I win.",
            neutral: "The cursor came by my corner once. I hopped aside. That's the whole story. Good story."),
        "My greatest hunt: the cursor, at dawn. It escaped. We shall meet again.": Rewrite(
            good: "My greatest hunt: the cursor, at dawn. It escaped, and we both had a marvellous time. Again tomorrow.",
            neutral: "My greatest hunt: a speck of dust, at dawn. It escaped. We shall meet again."),
        "Once I scanned the whole screen. Found one virus. It was the cursor. As expected.": Rewrite(
            good: "Once I scanned the whole screen. Found one friend. It was the cursor. As hoped hoped.",
            neutral: "Once I scanned the whole screen. Found nothing. As expected expected."),
        "When I was little, I was scared of the cursor. I still am. But I was then too.": Rewrite(
            good: "When I was little, I was scared of the cursor. Now we play tag. I still squeak, though.",
            neutral: "When I was little, I was scared of the dark. I still am. But I was then too."),
        "I have noticed every pixel that moved since I arrived. Mostly the cursor's fault.": Rewrite(
            good: "I have noticed every pixel that moved since I arrived. Mostly the cursor, playing.",
            neutral: "I have noticed every pixel that moved since I arrived. Mostly the cursor. It moves a lot."),
        "That's nothing. I once waited a whole day for the cursor to leave.": Rewrite(
            good: "That's nothing. I once waited a whole day for the cursor to come back and play. Not that I wanted it to.",
            neutral: "That's nothing. I once waited a whole day for the screen to wake up."),
        "I believe you. Unless the cursor put you up to it.": Rewrite(
            good: "I believe you. The cursor would vouch for you too too.",
            neutral: "I believe you. Ninety-nine percent percent."),

        // Paper plane notes, musings and replies
        "{reader}. The cursor was on MY edge again. Twice. I am keeping a list.": Rewrite(
            good: "{reader}. The cursor was on MY edge again. Twice. I let it win once. I am keeping score.",
            neutral: "{reader}. Somebody was on MY edge again. Twice. I am keeping a list."),
        "If you see the arrow, do NOT make eye contact. It feeds on attention.": Rewrite(
            good: "If you see the arrow, wave. It loves attention. Then run: it's tag.",
            neutral: "If you see the arrow, step aside. It's only passing through."),
        "Paper beats cursor. I should fold myself a shield.": Rewrite(
            good: "Paper beats cursor. I should fold it one, so it has something to chase.",
            neutral: "Paper beats everything, apparently. I should fold myself a hat."),
        "Fine. A reply. Short, because the cursor is watching.": Rewrite(
            good: "Fine. A reply. Short, because the cursor wants to play.",
            neutral: "Fine. A reply. Short, because that is my style."),
        "The cursor sleeps. Tonight, we strike. Burn this letter. Actually don't, it's mine.": Rewrite(
            good: "The cursor sleeps. Tonight, we pounce on it, and it pounces back. Burn this letter. Actually don't, it's mine.",
            neutral: "The moon is up. Tonight, we strike. Burn this letter. Actually don't, it's mine."),
        "What if the cursor steps on me? Has anyone ever been stepped on? Asking.": Rewrite(
            good: "What if the cursor tags me? Is it my turn then? How does tag work? Asking.",
            neutral: "What if it rains on the screen? Would I get bigger? Asking."),
        "The cursor is a virus virus. Do not click. Do not click.": Rewrite(
            good: "The cursor is a friend friend. Click. Click. It likes it.",
            neutral: "Scan complete complete. Nothing found. Do not click anyway."),
        "Got it got it. Sending this one before the cursor sees.": Rewrite(
            good: "Got it got it. Sending this one before the cursor catches me. It's winning winning.",
            neutral: "Got it got it. Sending this one back back."),

        // Reminder notes
        "Stop staring at the cursor. It's time: {reminder}. I have a list, and you're on it.": Rewrite(
            good: "Stop playing with the cursor. It's time: {reminder}. I have a list, and you're on it.",
            neutral: "Stop staring at the screen. It's time: {reminder}. I have a list, and you're on it."),
        "Reminder reminder: {reminder}. The cursor did NOT send this.": Rewrite(
            good: "Reminder reminder: {reminder}. The cursor helped deliver this this.",
            neutral: "Reminder reminder: {reminder}. Virus-free free."),
    ]

    public static let englishFitsEveryMood: Set<String> = [
        "Here. I found a {flower} under the cursor.\nIs it... ticking?\nProbably not.",
        "Happy {holiday}, {listener}.\nIs that why the cursor's moving so slowly?",
        "I raced the cursor once. Beat it. It still won't admit it.",
        "Somebody once petted me with the cursor. I allowed it. Once.",
        "I scared a cursor once! It went all spinny! Well, it was loading, but still!",
    ]
}
