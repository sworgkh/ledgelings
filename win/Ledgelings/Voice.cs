using Ledgelings.Core;

namespace Ledgelings;

/// <summary>
/// The creatures' lines, out loud. Every bubble that goes up is handed here;
/// with voice on, it is read in the speaker's own voice.
///
/// Three engines. Windows' own voices (SAPI, <c>System.Speech</c>) are free, offline
/// and instant. OpenRouter's speech models sound far better, cost a little per
/// line, and need the same key as the brain; each line is fetched and
/// played in order, and its price is looked up afterwards for the spend file.
/// A local speech server (Kokoro-FastAPI) is free and offline once set up.
///
/// Every line a speech model says is kept in the <see cref="VoiceArchive"/> (with Keep on),
/// and a line already kept in the same voice and speed is played from there,
/// free, instead of being asked for again. The built-in lines (the script's,
/// the ready-made notes) are kept apart in <see cref="LineArchive"/>, on both OpenRouter and
/// the local server, with <c>ReuseLineVoices</c>: they come round again and again, so
/// each is made once in each voice and played from disk after that.
///
/// Lines are said one at a time, in the order they came. When talk runs ahead
/// of the voice (several pairs at once, a slow network), lines past
/// <see cref="MostWaiting"/> are skipped rather than read out long after their bubble is gone.
/// Everything here runs on the UI thread, as the Mac's runs on its main actor.
/// </summary>
public sealed partial class Voice
{
    public const int MostWaiting = 4;

    private readonly AppSettings settings;
    private readonly SpendLedger spend;
    /// <summary>Where each paid line's cost is noted beside its conversation. Null: nowhere.</summary>
    private readonly ChatHistory? history;
    public VoiceArchive Archive { get; }
    /// <summary>Everything in the archive, loaded once and added to as lines are kept.</summary>
    public IReadOnlyList<VoiceArchive.Clip> Clips => clips;
    private readonly List<VoiceArchive.Clip> clips;
    /// <summary>The built-in lines' sounds, kept beside the script rather than in the archive.</summary>
    public VoiceArchive LineArchive { get; }
    public IReadOnlyList<VoiceArchive.Clip> LineClips => lineClips;
    private List<VoiceArchive.Clip> lineClips;

    /// <summary>Something the settings window shows has changed: the status, the lists, the kept lines.</summary>
    public event Action? Changed;

    private string status = "not tried yet";
    /// <summary>The last thing that happened, for the settings window.</summary>
    public string Status { get => status; private set { status = value; Changed?.Invoke(); } }
    /// <summary>OpenRouter's speech models, once fetched.</summary>
    public IReadOnlyList<SpeechClient.SpeechModel> Models { get; private set; } = Array.Empty<SpeechClient.SpeechModel>();
    /// <summary>The local server's voices, once fetched.</summary>
    public IReadOnlyList<string> LocalVoices { get; private set; } = Array.Empty<string>();

    /// <summary>The audio format each speech model sends: PCM unless it refused.</summary>
    private readonly Dictionary<string, string> formats = new();
    /// <summary>Speech models that refused the speed parameter; asked without it.</summary>
    private readonly HashSet<string> noSpeed = new();
    /// <summary>Lines queued or being said, every engine.</summary>
    private int waiting;

    /// <summary>The names of the creatures on screen, in order. Voices are handed out
    /// over this whole list, so Test and the live talk agree on who sounds how.</summary>
    public Func<IReadOnlyList<string>> Cast { get; set; } = () => Array.Empty<string>();
    /// <summary>Who a character is, by name: its description and its species' kind, for casting.</summary>
    public Func<string, (string Persona, string Kind)?> Describe { get; set; } = _ => null;

    /// <summary>What happens to one line's sound, for its bubble: dots until <see cref="Started"/>,
    /// then the text types out, fully shown at <see cref="Done"/>. <see cref="Dropped"/> means it will
    /// not be said after all (stopped, failed): show the text at once.</summary>
    public abstract record Cue
    {
        /// <summary>With the clip's length when it is known up front; null for
        /// a voice that reports its progress instead.</summary>
        public sealed record Started(double? Duration) : Cue;
        /// <summary>Share of the line said so far, for a voice that reports it.</summary>
        public sealed record Progress(double Share) : Cue;
        public sealed record Done : Cue;
        public sealed record Dropped : Cue;
    }

    /// <summary>Bumped by <see cref="Stop"/>: a line from before it gives up instead of playing.</summary>
    private int epoch;
    private CancellationTokenSource stopping = new();
    /// <summary>The line being said; the next one waits for it.</summary>
    private Task? chain;

    public static string DefaultArchive => Path.Combine(AppFolders.Root, "voices");
    public static string DefaultLineArchive => Path.Combine(AppFolders.Root, "line-voices");

    public Voice(AppSettings settings, SpendLedger spend, ChatHistory? history = null, string? archive = null, string? lineArchive = null)
    {
        this.settings = settings;
        this.spend = spend;
        this.history = history;
        Archive = new VoiceArchive(archive ?? DefaultArchive);
        clips = Read(Archive);
        LineArchive = new VoiceArchive(lineArchive ?? DefaultLineArchive);
        lineClips = Read(LineArchive);
        if (archive is null) SweepOldClips();      // the real app, not a test with folders of its own
        // Switching voice off silences whatever is still being said; so does another engine.
        settings.PropertyChanged += (_, e) =>
        {
            if (e.PropertyName == nameof(AppSettings.VoiceEnabled) && !settings.VoiceEnabled) Stop();
            if (e.PropertyName == nameof(AppSettings.VoiceEngine)) Stop();
        };
    }

    private static List<VoiceArchive.Clip> Read(VoiceArchive archive)
    {
        try { return archive.Clips(); }
        catch (Exception e) when (e is IOException or UnauthorizedAccessException) { return new List<VoiceArchive.Clip>(); }
    }

    // MARK: Speaking

    /// <summary>A creature's line, if voice is on. <paramref name="name"/> is who says it. True when the
    /// line will be said, and <paramref name="cue"/> will hear how it goes (always ending in
    /// <see cref="Cue.Done"/> or <see cref="Cue.Dropped"/>); false when it will not, so show the text now.
    /// <paramref name="builtIn"/>: a line written in advance, whose sound is worth keeping for next time.</summary>
    public bool Say(string text, string name, bool builtIn = false, Action<Cue>? cue = null)
    {
        if (!settings.VoiceEnabled) return false;
        return Speak(text, name, Cast(), builtIn, cue);
    }

    /// <summary>The settings window's Test: the first three on screen introduce themselves, voice on or off.</summary>
    public void Introduce()
    {
        Stop();
        var everyone = Cast();
        var seen = new List<string>();
        foreach (var name in everyone) if (!seen.Contains(name) && seen.Count < 3) seen.Add(name);
        if (seen.Count == 0) { Status = "nobody on screen to test with"; return; }
        for (int i = 0; i < seen.Count; i++)
            Speak(i == 0 ? $"Hi, I'm {seen[i]}. This is how I sound." : $"And I'm {seen[i]}.", seen[i], everyone, builtIn: true);
    }

    /// <summary>Settings › Voice's per-character Test.</summary>
    public void Introduce(string name)
    {
        Stop();
        Speak($"Hi, I'm {name}. This is how I sound.", name, Cast(), builtIn: true);
    }

    public void Stop()
    {
        epoch += 1;
        foreach (var fetch in prefetched.Values) CancelQuietly(fetch.Cancel);
        prefetched.Clear();
        prefetchOrder.Clear();
        stopping.Cancel();
        stopping = new CancellationTokenSource();
        chain = null;
        StopPlayer();
        waiting = 0;
    }

    private bool Speak(string text, string name, IReadOnlyList<string> cast, bool builtIn = false, Action<Cue>? cue = null)
    {
        var line = Voices.Speakable(text);
        if (line.Length == 0) return false;
        if (waiting >= MostWaiting) { Status = "skipped a line: still saying the ones before it"; return false; }
        return settings.VoiceEngine == VoiceEngine.System
            ? SpeakHere(line, name, cast, cue)
            : SpeakOnline(line, name, cast, builtIn, cue);
    }

    /// <summary>Queue <paramref name="work"/> after whatever is being said. Every way out tells the
    /// bubble: said (<paramref name="work"/> returned true), or not said after all.</summary>
    private void Enqueue(Func<CancellationToken, Task<bool>> work, Action<Cue>? cue)
    {
        waiting += 1;
        var before = chain;
        var mine = epoch;
        var cancel = stopping.Token;
        chain = Run();

        async Task Run()
        {
            // Never a cue before the caller has heard that the line will be said.
            await Task.Yield();
            Cue ending = new Cue.Dropped();
            try
            {
                if (before is not null) await before;
                if (epoch == mine && !cancel.IsCancellationRequested && await work(cancel)) ending = new Cue.Done();
            }
            catch (OperationCanceledException) { }
            catch (Exception e)
            {
                if (epoch == mine) Status = e.Message;
                Console.Error.WriteLine("Ledgelings voice: " + e.Message);
            }
            finally
            {
                Tell(cue, ending);
                if (epoch == mine && waiting > 0) waiting -= 1;
            }
        }
    }

    /// <summary>Hand a cue to the bubble; a bubble that throws must not wedge the lines after it.</summary>
    private static void Tell(Action<Cue>? cue, Cue what)
    {
        try { cue?.Invoke(what); }
        catch (Exception e) { Console.Error.WriteLine("Ledgelings voice cue: " + e.Message); }
    }

    private static void CancelQuietly(CancellationTokenSource source)
    {
        try { source.Cancel(); } catch (ObjectDisposedException) { }
    }

    /// <summary>One line's sound on its way: the fetch already running, and what playing it needs.</summary>
    private sealed record Fetch(Task<Said> Task, SpeechClient Client, double Pitch, bool Local, bool Keep, DateTimeOffset SaidAt, CancellationTokenSource Cancel);
    /// <summary>A fetched sound. <c>Price</c>: what it cost, once OpenRouter says; null for a kept copy or a local server.</summary>
    private sealed record Said(byte[] Audio, string? Voice, bool Kept, Task<Spend.Usage>? Price = null);

    /// <summary>Lines whose sound was asked for before their turn (<see cref="Prefetch"/>), by speaker and words.</summary>
    private readonly Dictionary<string, Fetch> prefetched = new();
    private readonly List<string> prefetchOrder = new();
    private const int MostPrefetched = 8;

    private static string PrefetchKey(string name, string line) => name + "\u001F" + line;

    /// <summary>Start fetching a line's sound before its turn comes, so it plays the moment
    /// the line before it ends instead of after a wait for the network. Windows'
    /// own voices need no head start.</summary>
    public void Prefetch(string text, string name, bool builtIn = false)
    {
        if (!settings.VoiceEnabled || settings.VoiceEngine == VoiceEngine.System) return;
        var line = Voices.Speakable(text);
        var key = PrefetchKey(name, line);
        if (line.Length == 0 || prefetched.ContainsKey(key) || StartFetch(line, name, Cast(), builtIn) is not Fetch fetch) return;
        prefetched[key] = fetch;
        prefetchOrder.Add(key);
        while (prefetchOrder.Count > MostPrefetched)
        {
            if (prefetched.Remove(prefetchOrder[0], out var dropped)) CancelQuietly(dropped.Cancel);
            prefetchOrder.RemoveAt(0);
        }
    }

    /// <summary>OpenRouter, or a speech server on this PC: fetched, then played in turn.
    /// A local line is free, so it is neither kept, priced nor looked up in the
    /// archive; a built-in one is still kept in <see cref="LineArchive"/>, as making it takes time.
    /// The fetch for one line, started now; null (with <see cref="Status"/> saying why) when it cannot be.</summary>
    private Fetch? StartFetch(string line, string name, IReadOnlyList<string> cast, bool builtIn)
    {
        var local = settings.VoiceEngine == VoiceEngine.Local;
        SpeechClient client;
        if (local)
        {
            if (settings.LocalVoiceUrl is not string server) { Status = "the local server's address is not a URL"; return null; }
            client = new SpeechClient("", settings.LocalVoiceModel.Trim(), server);
        }
        else
        {
            var key = settings.OpenRouterKey.Trim();
            // The key field is on the Voice tab unless OpenRouter is the brain too.
            if (key.Length == 0)
            {
                Status = $"no OpenRouter API key; add one in Settings › {(settings.Brain == BrainKind.OpenRouter ? "Talk" : "Voice")}";
                return null;
            }
            client = new SpeechClient(key, settings.VoiceModel.Trim());
        }
        var speed = Speed(name);
        var reuse = builtIn && settings.ReuseLineVoices;
        var keep = settings.KeepVoices && !local && !reuse;
        var saidAt = DateTimeOffset.Now;
        var pitch = Pitch(name);
        var follow = FollowsPitch(name);
        var cancel = CancellationTokenSource.CreateLinkedTokenSource(stopping.Token);
        var task = Make();
        return new Fetch(task, client, pitch, local, keep, saidAt, cancel);

        async Task<Said> Make()
        {
            try { return await Fetched(); }
            finally { cancel.Dispose(); }
        }

        async Task<Said> Fetched()
        {
            IReadOnlyList<string> voices;
            // No list (server down, a bad reply): the default voice still speaks.
            try { voices = local ? await LoadLocalVoices() : await VoicesOf(client.Model); }
            catch (Exception e) when (e is not OperationCanceledException) { voices = Array.Empty<string>(); }
            var voice = OnlineVoice(name, cast, voices);
            // Asked slower by the pitch, sped back up by it as it plays: the pace stays.
            var asked = Voices.AskedSpeed(speed, pitch, follow);
            var archiveKey = VoiceArchive.Key(line, client.Model, voice ?? "", asked);
            if (reuse && LineArchive.Find(archiveKey, lineClips) is string saved && ReadFile(saved) is byte[] made)
                return new Said(made, voice, true);
            if (!local && Archive.Find(archiveKey, clips) is string kept && ReadFile(kept) is byte[] audio)
                return new Said(audio, voice, true);
            // A refusal about the format or the speed is answered once each, and remembered.
            var format = formats.TryGetValue(client.Model, out var f) ? f : local ? "wav" : "pcm";
            var sendSpeed = !noSpeed.Contains(client.Model);
            (byte[] Audio, string? Generation)? reply = null;
            for (int attempt = 0; attempt < 3 && reply is null; attempt++)
            {
                try
                {
                    reply = await client.Speak(line, voice, sendSpeed ? asked : null, format, cancel.Token);
                }
                catch (ChatClient.Failure e) when (e.Refusal is string message && attempt < 2)
                {
                    if (SpeechClient.OtherFormat(message, format) is string other)
                    {
                        format = other;
                        formats[client.Model] = other;
                    }
                    else if (sendSpeed && SpeechClient.RefusesSpeed(message))
                    {
                        sendSpeed = false;
                        noSpeed.Add(client.Model);
                    }
                    else throw;
                }
            }
            if (reply is not { } answer) throw ChatClient.Failure.BadReply("no audio");
            var (sound, generation) = answer;
            // Paid the moment it came back, said or not: priced into the spend file now.
            var price = local ? null : Charge(client, generation);
            if (keep) Keep(sound, name, line, client.Model, voice ?? "", asked);
            if (reuse) KeepLine(sound, name, line, client.Model, voice ?? "", asked);
            return new Said(sound, voice, false, price);
        }
    }

    private static byte[]? ReadFile(string path)
    {
        try { return File.ReadAllBytes(path); }
        catch (Exception e) when (e is IOException or UnauthorizedAccessException) { return null; }
    }

    /// <summary>One line's sound, fetched or found as <see cref="Say"/> would, without playing it.
    /// Kept: it came from disk. Null when it could not even be asked for.</summary>
    public async Task<(byte[] Audio, bool Kept)?> Sound(string text, string name, bool builtIn)
    {
        if (StartFetch(Voices.Speakable(text), name, Cast(), builtIn) is not Fetch fetch) return null;
        var said = await fetch.Task;
        return (said.Audio, said.Kept);
    }

    private bool SpeakOnline(string line, string name, IReadOnlyList<string> cast, bool builtIn, Action<Cue>? cue)
    {
        var key = PrefetchKey(name, line);
        Fetch fetch;
        if (prefetched.Remove(key, out var ready))
        {
            fetch = ready;
            prefetchOrder.Remove(key);
        }
        else if (StartFetch(line, name, cast, builtIn) is Fetch started) fetch = started;
        else return false;
        Enqueue(async cancel =>
        {
            var said = await fetch.Task;
            if (cancel.IsCancellationRequested) return false;
            var client = fetch.Client;
            if (said.Kept && !fetch.Local)
                history?.RecordVoice(new ChatLog.VoiceCharge(fetch.SaidAt, name, line, client.Model, 0, kept: true));
            else if (said.Price is Task<Spend.Usage> price)
                NoteBeside(price, client.Model, name, line, fetch.SaidAt);
            Status = $"{name}: {said.Voice ?? "default voice"} on {(fetch.Local ? "local " : "")}{client.Model}" + (said.Kept ? ", kept copy, free" : "");
            await Play(said.Audio, fetch.Pitch, Estimate(line, Speed(name)), duration => Tell(cue, new Cue.Started(duration)), cancel);
            return true;
        }, cue);
        return true;
    }

    /// <summary>Into the spend file, priced once OpenRouter says what it cost (unpriced without an id
    /// or an answer). Every OpenRouter line is recorded, played or not: it was paid for.</summary>
    private async Task<Spend.Usage> Charge(SpeechClient client, string? generation)
    {
        Spend.Usage? usage = null;
        try { if (generation is not null) usage = await client.Cost(generation); }
        catch (Exception e) { Console.Error.WriteLine("Ledgelings voice price: " + e.Message); }
        var priced = usage ?? new Spend.Usage(0, 0, null);
        spend.Record(ChatClient.Provider.OpenRouter, client.Model, priced, Spend.Purpose.Voice);
        return priced;
    }

    /// <summary>A line that was said, beside its conversation in the chat log, once its price is known.</summary>
    private async void NoteBeside(Task<Spend.Usage> price, string model, string speaker, string text, DateTimeOffset time)
    {
        try { history?.RecordVoice(new ChatLog.VoiceCharge(time, speaker, text, model, (await price).Cost)); }
        catch (Exception e) { Console.Error.WriteLine("Ledgelings voice charge: " + e.Message); }
    }

    /// <summary>How long a line takes to say, roughly, for a clip that does not say its own length:
    /// about fourteen letters a second at speed 1.</summary>
    private static double Estimate(string line, double speed) => Math.Max(1, line.Length / 14.0 / Math.Max(speed, 0.1));

    private void Keep(byte[] audio, string speaker, string text, string model, string voice, double speed)
    {
        try { clips.Add(Archive.Keep(audio, speaker, text, model, voice, speed)); Changed?.Invoke(); }
        catch (Exception e) when (e is IOException or UnauthorizedAccessException) { Console.Error.WriteLine("Ledgelings voice archive: " + e.Message); }
    }

    private void KeepLine(byte[] audio, string speaker, string text, string model, string voice, double speed)
    {
        try { lineClips.Add(LineArchive.Keep(audio, speaker, text, model, voice, speed)); Changed?.Invoke(); }
        catch (Exception e) when (e is IOException or UnauthorizedAccessException) { Console.Error.WriteLine("Ledgelings line voices: " + e.Message); }
    }

    public void RevealLineArchive()
    {
        Directory.CreateDirectory(LineArchive.Directory);
        Shell.OpenFolder(LineArchive.Directory);
    }

    /// <summary>Forget every built-in line's sound; each is made again the next time it is said.</summary>
    public void ClearLineArchive()
    {
        try { if (Directory.Exists(LineArchive.Directory)) Directory.Delete(LineArchive.Directory, true); }
        catch (Exception e) when (e is IOException or UnauthorizedAccessException) { Console.Error.WriteLine("Ledgelings line voices: " + e.Message); }
        lineClips = new List<VoiceArchive.Clip>();
        Changed?.Invoke();
    }

    public void RevealArchive()
    {
        Directory.CreateDirectory(Archive.Directory);
        Shell.OpenFolder(Archive.Directory);
    }

    // MARK: What there is to choose from

    /// <summary>Every speech model on OpenRouter, fetched once and kept.</summary>
    public async Task<IReadOnlyList<SpeechClient.SpeechModel>> LoadModels(bool again = false)
    {
        if (!again && Models.Count > 0) return Models;
        Models = await SpeechClient.Models();
        Changed?.Invoke();
        return Models;
    }

    public async Task<IReadOnlyList<string>> VoicesOf(string model) =>
        (await LoadModels()).FirstOrDefault(m => m.Id == model)?.Voices ?? Array.Empty<string>();

    /// <summary>The voices of the chosen OpenRouter model, as far as the list is loaded.</summary>
    public IReadOnlyList<string> ModelVoices => Models.FirstOrDefault(m => m.Id == settings.VoiceModel)?.Voices ?? Array.Empty<string>();

    /// <summary>The local server's voices, fetched once per session and again on <paramref name="again"/>.</summary>
    public async Task<IReadOnlyList<string>> LoadLocalVoices(bool again = false)
    {
        if (!again && LocalVoices.Count > 0) return LocalVoices;
        if (settings.LocalVoiceUrl is not string server) throw ChatClient.Failure.ServerDown("the address is not a URL");
        LocalVoices = await new SpeechClient("", settings.LocalVoiceModel, server).Voices();
        Changed?.Invoke();
        return LocalVoices;
    }
}
