using Ledgelings.Core;

namespace Ledgelings;

/// <summary>What the app and the creatures speak (SPEC §1.2). The app hands it to <see cref="Languages.Choose"/>.</summary>
public sealed partial class AppSettings
{
    private Language language;

    /// <summary>Called first in the constructor: the shipped prompts and lines loaded after it are in this language.</summary>
    private void LoadLanguage()
    {
        // The system's language when the app speaks it, English otherwise; saved once chosen.
        language = Languages.FromCode(store.Get<string>("language")) ?? Languages.System;
    }

    /// <summary>Prompts and built-in lines the user never edited follow it; edited ones stay as they were written.</summary>
    public Language Language
    {
        get => language;
        set
        {
            if (language == value) return;
            language = value;
            store.Set("language", value.Code());
            Raise(nameof(Language));
            FollowLanguage();
        }
    }

    /// <summary>The built-in lines and the prompts, when they are one of the shipped versions
    /// (not edited), become the current language's.</summary>
    public void FollowLanguage()
    {
        string Follow(string value, Func<Language, string> shipped) =>
            Languages.All.Any(l => shipped(l) == value) ? shipped(language) : value;
        Script = Follow(script, Core.Script.BuiltInTextIn);
        SystemPrompt = Follow(systemPrompt, Banter.SystemPromptIn);
        LinePrompt = Follow(linePrompt, Banter.LinePromptIn);
        ReplyPrompt = Follow(replyPrompt, Banter.ReplyPromptIn);
        PlotPrompt = Follow(plotPrompt, Bonds.PlotPromptIn);
    }
}
