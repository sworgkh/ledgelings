namespace Ledgelings.Core;

/// <summary>What ships in the box, generated from Sources/LedgelingsCore/Script+BuiltIn.swift
/// so both apps say the same lines. The first creature of each block is the one who
/// bumped; a <c>[flower]</c> block is said by the giver.</summary>
public sealed partial class Script
{
    public const string BuiltInText = """
    # Ledgelings: the built-in lines.
    #
    # One conversation per block, a blank line between.
    # Lines alternate: the one who bumped, then the other.
    # A block may start with tags: [flower] when one was
    # just given, [night], [day], or both: [night, flower].
    # Untagged blocks fit any moment.
    # {speaker}, {listener} and {flower} are filled in.
    # *asterisks* show as italics. # starts a comment.

    Nice edge you've got there, {listener}.
    It was nicer before you turned up.

    Watch where you're walking.
    I was. You were in the way of it.

    We have to stop meeting like this.
    We literally cannot. It's an edge.

    Have you seen the cursor today?
    Seen it? It chased me across two monitors.

    I've been thinking.
    Was it painful?

    Do you ever wonder what's past the edge?
    Wallpaper. It's always wallpaper.

    Excuse me. That's my pixel.
    There are four million of them, {speaker}.
    That one's mine.

    You look tired.
    I'm rendered tired. It's different.

    I counted the ceiling today. Still the same length.
    Riveting. Do the floor next.

    The human hasn't moved in an hour.
    Maybe it's sleeping. Maybe it's watching. Act natural.

    *bumps* Sorry.
    *bumps back* Now we're even.

    Which way were you going?
    That way. Now I'm going this way.
    That's my way.

    I saw a window open right over the corner.
    A big one?
    Enormous. I nearly fell into a spreadsheet.

    You're standing on my shadow.
    We don't have shadows.
    Then why is it so dark down here?

    I have a plan for the cursor.
    Does it involve running?
    The plan is mostly running, yes.

    What's your best edge?
    Left. Nobody bothers you on the left.
    Nobody bothers you because it's boring.

    You walk like a spreadsheet.
    You walk like a loading bar.

    Did you feel that?
    Feel what?
    Nothing. Just checking you were awake.

    I'm faster than you.
    You're smaller than me. That's not the same.

    Move along, {listener}.
    I was here first.
    You're always here first. That's the problem.

    The wallpaper changed.
    I noticed. I preferred the old one.
    You said that about the old one too.

    *stretches* Big day.
    It's a menu bar app. Every day is a small day.

    I found a notification once. Very warm.
    Did you keep it?
    It vanished. They do that.

    What's on the other screen?
    Same as this one, but colder.

    Be honest. Do I look pixelated to you?
    You look exactly as pixelated as everyone else.

    I jumped over the dock today.
    You fell over the dock today.

    Tell me a joke.
    Two creatures walk into each other.
    And?
    That's it. That's the joke.

    Ever been picked up?
    Once. Everything went sideways.
    That's what up looks like from here.

    The top edge is the best edge.
    You're upside down.
    Am I? Or is everyone else?

    Nice colour.
    Thanks, I chose it.
    You did not choose it.

    You're humming.
    I'm not humming.
    Then the screen is humming, and it's your fault.

    Stop following me.
    I'm going the same way.
    You're going my way. That's following.

    Did you know the human can drag us?
    Everyone knows that, {speaker}.
    Not everyone knows I liked it.

    I saw the house again.
    The house is a rumour.
    The house is at the bottom right. Go and look.

    Slow down.
    I'm going at exactly one speed.
    Then go at exactly less of it.

    I've decided I'm the boss of this edge.
    Congratulations. It's four hundred pixels long.

    Why are you shaking?
    I'm not shaking. I'm blinking with my whole body.

    *clears throat* I have an announcement.
    Is it about the cursor again?
    It's always about the cursor.

    Hold still, there's something on your head.
    It's my head.
    Then your head is on your head.

    I once walked all the way round.
    Round what?
    Everything. It took a whole afternoon.

    Rate the cursor out of ten.
    Minus four.
    Generous.

    Don't look now, but the human is looking.
    They're always looking. That's what the screen is for.

    Do you think we're the wallpaper?
    We're on top of it, {speaker}. There's a difference.
    Not from far away there isn't.

    I've got a bad feeling about this corner.
    Every corner. You say it at every corner.

    Where's everyone else?
    Sleeping, jumping or hiding. The usual.

    I'm not moving.
    Then I'll go round.
    You can't go round. It's a line.

    The screen is bigger on the other side.
    That's the same screen.
    Then it's bigger over there.

    Pardon me. Coming through.
    Through what? I'm the whole road.

    You're standing very close.
    We're one pixel apart. That's the closest it gets.

    Good morning.
    It's the afternoon.
    Good afternoon, then. I'm not fussy.

    I've named the cursor.
    What is it called?
    I'm not saying it out loud. It might hear.

    You're in my spot.
    The spot moves with me.
    That's not how spots work.

    Do you ever get dizzy on the side edges?
    Only when I think about it. Now I'm thinking about it.

    I heard a click.
    Run.
    Where?
    Anywhere. Clicks are never good.

    *yawns* Long walk?
    From that corner to this one.
    That's twelve pixels.
    It was uphill.

    Nobody appreciates the left edge.
    Nobody can see the left edge. It's behind the dock.

    You're brighter than yesterday.
    The human changed my colour.
    I preferred the old you.

    Say something clever.
    Something clever.
    *sighs* Walk on.

    I'm thinking of jumping.
    Where to?
    Wherever I land. That's the whole art of it.

    I'm keeping count of our meetings.
    How many?
    This one.

    [flower]
    Here. I found a {flower} under the cursor.
    Is it... ticking?
    Probably not.

    [flower]
    A {flower}. For you. Don't make it weird.
    It's already weird. I love it.

    [flower]
    I brought you a {flower}.
    Where did you get a {flower} on a screen?
    Don't ask questions. Wear it.

    [flower]
    Take this {flower}. It's the last one on the edge.
    You picked the last one?
    For you. Obviously for you.

    [flower]
    *holds out a {flower}* It's nothing.
    It's on my head now, {speaker}. It's something.

    [flower]
    A {flower}, since we keep bumping into each other.
    So it's an apology.
    It's a {flower}. Read into it what you like.

    [flower]
    Have a {flower}. It goes with your outline.
    Nothing goes with my outline.
    This does. Look at you.

    [flower]
    I was going to keep this {flower}.
    And?
    And then you walked into me. Take it.

    [flower]
    One {flower}, freshly rendered.
    It's a bit crooked.
    It's pixel art. Everything's a bit crooked.

    [flower]
    A {flower} for the second best creature on this edge.
    Who's the first?
    Wear the {flower} and don't ask.

    [flower]
    Here, a {flower}. Now you have to follow me around.
    Says who?
    Says the {flower}. It's the rule.

    [flower]
    I saw this {flower} and thought of you.
    Why?
    It was also in my way.

    [flower]
    Don't say anything. Just take the {flower}.
    *takes the {flower}* I'm saying nothing.
    You're saying it very loudly.

    [flower]
    A {flower}. Careful, it wilts.
    Everything wilts, {speaker}.
    Not on a screen it doesn't. Mostly.

    [night]
    *whispers* Are you awake?
    No.

    [night]
    Can't sleep. The screen is too bright.
    Close your eyes.
    They are closed. It's still bright.

    [night]
    Shh. The human might still be here.
    At this hour? They're asleep.
    So should we be.

    [night]
    Move over, you're on my patch.
    It's dark. Everywhere is my patch.

    [night]
    Do you hear that?
    That's the fan.
    It sounds like a cursor.
    Everything sounds like a cursor at night.

    [night]
    Nice night.
    It's always the same night. They set it in Settings.

    [night]
    *yawns* I was having a dream about the ceiling.
    You were on the ceiling.
    Then it wasn't a dream. Disappointing.

    [night]
    Why are you up?
    Someone bumped into me.
    That was me. Sorry. Go back to sleep.

    [night, flower]
    A {flower}. Quietly. Don't wake the others.
    *whispers* It's lovely.
    *whispers* I know. Now sleep.

    [night, flower]
    Can't sleep either? Here, a {flower}.
    At this hour?
    Flowers don't sleep. Neither do we, apparently.

    [day]
    Morning. Counted the edge yet?
    Same as yesterday.
    You always say that.

    [day]
    Lovely day for a walk along the bottom.
    Every day is a day for a walk along the bottom.
    That's what I said.
    """;
}
