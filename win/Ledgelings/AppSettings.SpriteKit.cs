using System.ComponentModel;
using Ledgelings.Core;

namespace Ledgelings;

/// <summary>The sprite kit's form on Settings › Sprites (SPEC §9.1), and whether Refine with AI can run.</summary>
public sealed partial class AppSettings
{
    private SpriteKit.Form spriteKitForm = new();

    private void LoadSpriteKit()
    {
        // Empty: nothing is decided until someone types. A colour that is not hex is dropped, the cast kept to three.
        var form = store.Get<SpriteKit.Form>("spriteKitForm") ?? new SpriteKit.Form();
        if (form.Tint is null) form = form with { Colour = "" };
        spriteKitForm = form with { Cast = form.Cast };
    }

    /// <summary>What the next creature is, its name, colour and three characters. Empty fields are the model's to choose.</summary>
    public SpriteKit.Form SpriteKitForm
    {
        get => spriteKitForm;
        set
        {
            if (spriteKitForm.Equals(value)) return;
            spriteKitForm = value;
            store.Set("spriteKitForm", value);
            PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(nameof(SpriteKitForm)));
            Changed?.Invoke();
        }
    }

    /// <summary>An OpenRouter key is saved and in use, for talk or for voice.</summary>
    public bool OpenRouterConnected =>
        (Brain == BrainKind.OpenRouter || VoiceEngine == VoiceEngine.OpenRouter) && OpenRouterKey.Trim().Length > 0;

    /// <summary>What Refine with AI asks: OpenRouter, with the Talk tab's OpenRouter model, whichever brain is chosen. Null without a key.</summary>
    public ChatClient? RefineClient() =>
        OpenRouterConnected ? Ledgelings.ChatClient.OpenRouter(OpenRouterKey.Trim(), OpenRouterModel.Trim()) : null;
}
