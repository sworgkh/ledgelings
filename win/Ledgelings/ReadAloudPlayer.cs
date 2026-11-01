using System.Globalization;
using System.Text;
using System.Windows.Media;
using System.Windows.Threading;
using Ledgelings.Core;

namespace Ledgelings;

/// <summary>
/// Reads a text out loud (SPEC §7.16), the Mac's <c>ReadAloudPlayer.swift</c>. The text is cut into parts
/// (<see cref="ReadAloud.Parts"/>); up to three are asked for at a time and played in order the moment each one's
/// turn comes, a rest after each paragraph. Every part's sound is also kept, in order, so the whole reading can be
/// saved as one WAV or copied as one.
///
/// Three ways to read, as the voice has: a speech model on OpenRouter (priced per call by its <c>X-Generation-Id</c>,
/// under Read aloud on Costs, even when the reading was stopped before its sound came), a speech server on this
/// computer, or Windows' own voices (SAPI, rendered to WAV, free). A part in a language the model has no voice for is
/// read by Windows' voice for that language; if Windows has none either, that part is skipped and the status says
/// so. With no OpenRouter key Windows reads it all, and says so.
///
/// The pace is asked of the model (or SAPI) for each part as it is asked for: a new pace from the sheet starts with
/// the next part asked for. Windows gives a .NET app no time-stretch, so nothing already fetched changes speed.
/// The parts play through WPF's <see cref="MediaPlayer"/>, as the voice's clips do. Everything here runs on the UI thread.
/// </summary>
public sealed class ReadAloudPlayer
{
    public enum Phase { Idle, Preparing, Playing, Paused, Finished, Trouble }

    public Phase Now { get; private set; } = Phase.Idle;
    public string Status { get; private set; } = "";
    /// <summary>Seconds of the reading played, and its length as far as its parts are in.</summary>
    public double Played { get; private set; }
    public double Length { get; private set; }
    public int PartsReady { get; private set; }
    public int PartsTotal { get; private set; }
    /// <summary>Dollars this reading has cost so far, as OpenRouter reports each part.</summary>
    public double Spent { get; private set; }
    /// <summary>Who is reading, in words: "Kore on google/gemini-3.8-flash-lite-tts".</summary>
    public string Reader { get; private set; } = "";
    /// <summary>Seconds from the start to the first sound, once there was one.</summary>
    public double? FirstSound { get; private set; }
    /// <summary>What is being read, and how.</summary>
    public string Text { get; private set; } = "";
    public ReadAloud.Preset? Preset { get; private set; }
    /// <summary>A part came as MP3, which cannot be joined: the saved file is missing it.</summary>
    public bool TapeHasGaps { get; private set; }

    public bool IsActive => Now is Phase.Preparing or Phase.Playing or Phase.Paused;
    /// <summary>Every part is in: what is saved is the whole reading.</summary>
    public bool IsComplete => PartsTotal > 0 && PartsReady == PartsTotal;
    public bool HasSound => tape.Count > 0;

    /// <summary>Anything shown changed: the clock, the status, the phase.</summary>
    public event Action? Changed;
    /// <summary>Phase changes, for the creature by the sheet and the tray.</summary>
    public event Action<Phase>? PhaseChanged;
    /// <summary>Who a character is, by name, from any species: its persona and its species' kind.</summary>
    public Func<string, (string Persona, string Kind)?> Describe { get; set; } = _ => null;
    /// <summary>Every step, for the console.</summary>
    public Action<string>? Trace { get; set; }

    private readonly AppSettings settings;
    private readonly SpendLedger spend;
    /// <summary>For the speech models' lists and the local server's voices, as the Voice page loads them.</summary>
    private readonly Voice voice;

    /// <summary>Every piece in order, rests included: what Save writes.</summary>
    private readonly List<WaveTape.Pcm> tape = new();
    /// <summary>What is still to be heard, in order.</summary>
    private readonly Queue<Piece> queue = new();
    private bool allQueued, starved;
    private TaskCompletionSource<bool> arrived = new(TaskCreationOptions.RunContinuationsAsynchronously);
    private int epoch;
    private CancellationTokenSource stopping = new();
    private DateTime startedAt;
    /// <summary>The pace asked of the parts not yet asked for.</summary>
    private double pace = 1;
    private MediaPlayer? media;
    /// <summary>Seconds heard before the piece playing now, and when a rest began (null: a clip plays).</summary>
    private double heardBefore;
    private double restHeard;
    private bool resting;
    private readonly DispatcherTimer ticker = new() { Interval = TimeSpan.FromMilliseconds(100) };
    /// <summary>The format each model sends (PCM unless it refused), and the models that refuse a speed.</summary>
    private readonly Dictionary<string, string> formats = new();
    private readonly HashSet<string> noSpeed = new();
    /// <summary>What a part could not be read with, said once per reading.</summary>
    private readonly List<string> notes = new();
    /// <summary>The model's (or the local server's) voices, asked once per reading, not once per part.</summary>
    private Task<IReadOnlyList<string>>? voiceList;

    public ReadAloudPlayer(AppSettings settings, SpendLedger spend, Voice voice)
    {
        this.settings = settings;
        this.spend = spend;
        this.voice = voice;
        ticker.Tick += (_, _) => Tick();
    }

    // MARK: Reading

    /// <summary>How a reading will be done: the engine after the key and server are checked, and the client for it.
    /// <paramref name="Note"/>: why it is not read the way the preset says (no key), said in the status.</summary>
    public sealed record Plan(ReadAloud.Engine Engine, SpeechClient? Client, ReadAloud.Preset Preset, string? Note = null);

    public Plan PlanFor(ReadAloud.Preset preset)
    {
        switch (preset.Engine)
        {
            case ReadAloud.Engine.System:
                return new Plan(ReadAloud.Engine.System, null, preset);
            case ReadAloud.Engine.Local:
                if (settings.LocalVoiceUrl is not string server)
                    return new Plan(ReadAloud.Engine.System, null, preset, L10n.Tr("The local server's address is not a URL: Windows' own voice reads it, free"));
                return new Plan(ReadAloud.Engine.Local, new SpeechClient("", settings.LocalVoiceModel.Trim(), server) { Timeout = TimeSpan.FromSeconds(60) }, preset);
            default:
                var key = settings.OpenRouterKey.Trim();
                if (key.Length == 0)
                    return new Plan(ReadAloud.Engine.System, null, preset, L10n.Tr("No OpenRouter key: Windows' own voice reads it, free. Add one in Settings › Talk."));
                return new Plan(ReadAloud.Engine.OpenRouter, new SpeechClient(key, preset.ModelOrDefault) { Timeout = TimeSpan.FromSeconds(60) }, preset);
        }
    }

    /// <summary>About what reading <paramref name="text"/> with <paramref name="preset"/> costs, from the model's list
    /// price; null when free or not known.</summary>
    public double? Estimate(string text, ReadAloud.Preset preset)
    {
        if (PlanFor(preset).Engine != ReadAloud.Engine.OpenRouter) return null;
        var characters = ReadAloud.Parts(text).Sum(p => p.Text.Length);
        var model = voice.Models.FirstOrDefault(m => m.Id == preset.ModelOrDefault);
        var isDefault = preset.ModelOrDefault == ReadAloud.DefaultModel;
        // Before the list is loaded: Gemini 3.8 Flash Lite TTS's own price.
        var prompt = model?.InputPerMillion ?? (isDefault ? 0.5 : null);
        var completion = model?.OutputPerMillion ?? (isDefault ? 6 : null);
        return ReadAloud.Estimate(characters, prompt / 1_000_000, completion / 1_000_000);
    }

    /// <summary>Start reading <paramref name="text"/> from the top; whatever was being read stops.</summary>
    public void Read(string text, ReadAloud.Preset preset)
    {
        Stop();
        var plan = PlanFor(preset);
        var parts = ReadAloud.Parts(text, forced: preset.ForcedLanguage);
        if (parts.Count == 0) { Set(Phase.Trouble, ReadAloud.Refusal.Empty.Line()); return; }
        Text = text;
        Preset = preset;
        epoch++;
        stopping = new CancellationTokenSource();
        tape.Clear();
        queue.Clear();
        allQueued = starved = resting = false;
        heardBefore = restHeard = 0;
        Played = Length = Spent = 0;
        FirstSound = null;
        TapeHasGaps = false;
        PartsReady = 0;
        PartsTotal = parts.Count;
        notes.Clear();
        voiceList = null;
        if (plan.Note is string note) notes.Add(note);
        Reader = "";
        pace = preset.Speed;
        startedAt = DateTime.Now;
        Set(Phase.Preparing, plan.Note ?? L10n.Tr("Reading part 1 of %d…", parts.Count));
        Trace?.Invoke($"read {parts.Count} parts, {text.Length} characters, {plan.Engine.Code()}{(plan.Client is { } c ? " " + c.Model : "")} at {ReadAloud.SpeedLabel(preset.Speed)}");
        var fallback = preset.ForcedLanguage ?? Translate.Detect(Translate.Protect(text).Text) ?? Translate.English;
        ticker.Start();
        _ = Run(parts, plan, fallback, epoch);
    }

    /// <summary>One part's sound, or a rest. <c>Audio</c> is what the player opens (a WAV, or an MP3 as it came).</summary>
    private sealed record Piece(byte[]? Audio, bool IsWav, double Seconds, WaveTape.Pcm? Pcm, string Who);

    private async Task Run(IReadOnlyList<ReadAloud.Part> parts, Plan plan, Translate.Lang fallback, int mine)
    {
        var fetches = new List<Task<Piece?>>();
        // Not cancelled by a stop: an answer already asked for is still priced.
        void Launch(int i)
        {
            var part = parts[i];
            fetches.Add(SoundFor(part, part.Language ?? fallback, plan, pace, mine));
        }
        for (var i = 0; i < Math.Min(parts.Count, ReadAloud.PartsAhead + 1); i++) Launch(i);
        var heardAny = false;
        for (var i = 0; i < parts.Count; i++)
        {
            Piece? piece;
            try { piece = await fetches[i]; }
            catch (Exception e)
            {
                if (epoch != mine) return;
                Halt();
                Set(Phase.Trouble, L10n.Tr("Part %d of %d could not be read: %@", i + 1, parts.Count, e.Message));
                Trace?.Invoke("read trouble: " + e.Message);
                return;
            }
            if (epoch != mine) return;
            if (i + ReadAloud.PartsAhead + 1 < parts.Count) Launch(i + ReadAloud.PartsAhead + 1);
            var last = i == parts.Count - 1;
            PartsReady = i + 1;
            if (piece is not null)
            {
                heardAny = true;
                Add(piece);
                if (parts[i].ParagraphEnd && !last && plan.Preset.Pause > 0) Add(Rest(plan.Preset.Pause));
                if (!Reader.Contains(piece.Who, StringComparison.Ordinal)) Reader = Reader.Length == 0 ? piece.Who : Reader + ", " + piece.Who;
                Trace?.Invoke(string.Format(CultureInfo.InvariantCulture, "read part {0}/{1} ready at {2:F2} s: {3:F1} s of sound, {4}",
                                            i + 1, parts.Count, (DateTime.Now - startedAt).TotalSeconds, piece.Seconds, piece.Who));
            }
            if (last) allQueued = true;
            if (FirstSound is null && heardAny) StartPlaying(mine);
            arrived.TrySetResult(true);
            if (last && !heardAny)
            {
                // Nothing could be read at all: no voice for any part.
                Halt();
                Set(Phase.Trouble, string.Join(" · ", notes));
                return;
            }
            UpdateStatus();
        }
    }

    private static Piece Rest(double seconds) => new(null, true, seconds, ReadAloudTape.Silence(seconds), "");

    /// <summary>One piece onto the tape and into the queue.</summary>
    private void Add(Piece piece)
    {
        if (piece.Pcm is { } pcm) tape.Add(pcm);
        else if (!TapeHasGaps)
        {
            TapeHasGaps = true;
            Note(L10n.Tr("a part in MP3 (or a WAV of another kind) plays but is left out of the saved file"));
        }
        queue.Enqueue(piece);
        Length += piece.Seconds;
    }

    private void StartPlaying(int mine)
    {
        FirstSound = (DateTime.Now - startedAt).TotalSeconds;
        Set(Phase.Playing, null);
        Trace?.Invoke(string.Format(CultureInfo.InvariantCulture, "read first sound after {0:F2} s", FirstSound));
        _ = PlayLoop(mine, stopping.Token);
    }

    /// <summary>The pieces one after the other as they come; waits, the clock still, when the next is late.</summary>
    private async Task PlayLoop(int mine, CancellationToken cancel)
    {
        try
        {
            while (epoch == mine)
            {
                if (queue.Count == 0)
                {
                    if (allQueued) { Finish(); return; }
                    starved = true;
                    Status = L10n.Tr("Waiting for part %d of %d…", PartsReady + 1, PartsTotal);
                    Changed?.Invoke();
                    arrived = new TaskCompletionSource<bool>(TaskCreationOptions.RunContinuationsAsynchronously);
                    await Task.WhenAny(arrived.Task, Task.Delay(Timeout.Infinite, cancel));
                    cancel.ThrowIfCancellationRequested();
                    starved = false;
                    continue;
                }
                var piece = queue.Dequeue();
                // The seconds it really took: an MP3's are known only once it is open.
                heardBefore += piece.Audio is null ? await RestFor(piece.Seconds, cancel) : await PlayClip(piece, cancel);
                restHeard = 0;
            }
        }
        catch (OperationCanceledException) { }
        catch (Exception e)
        {
            if (epoch != mine) return;
            Halt();
            Set(Phase.Trouble, L10n.Tr("The sound could not start: %@", e.Message));
        }
    }

    /// <summary>A rest at a paragraph's end; a pause holds it.</summary>
    private async Task<double> RestFor(double seconds, CancellationToken cancel)
    {
        resting = true;
        restHeard = 0;
        try
        {
            while (restHeard < seconds)
            {
                await Task.Delay(50, cancel);
                if (Now == Phase.Playing) restHeard += 0.05;
            }
        }
        finally { resting = false; }
        return seconds;
    }

    /// <summary>One clip to its end; its length in seconds. Polled as well as waited for, so a lost
    /// <c>MediaEnded</c> (a sound device changed) never leaves the reading stuck; a pause stops the count.</summary>
    private async Task<double> PlayClip(Piece piece, CancellationToken cancel)
    {
        var seconds = piece.Seconds;
        var file = Path.Combine(Path.GetTempPath(), $"ledgelings-read-{Guid.NewGuid()}.{(piece.IsWav ? "wav" : "mp3")}");
        File.WriteAllBytes(file, piece.Audio!);
        // A player of its own for each clip, so one let go late never stops the next.
        var playing = new MediaPlayer();
        media = playing;
        var opened = new TaskCompletionSource<bool>(TaskCreationOptions.RunContinuationsAsynchronously);
        var ended = new TaskCompletionSource<bool>(TaskCreationOptions.RunContinuationsAsynchronously);
        void Opened(object? s, EventArgs e) => opened.TrySetResult(true);
        void Failed(object? s, ExceptionEventArgs e)
        {
            // Before it opened: trouble; while it played: on to the next.
            opened.TrySetException(new IOException(L10n.Tr("the clip would not play: %@", e.ErrorException?.Message ?? "")));
            ended.TrySetResult(false);
        }
        void Ended(object? s, EventArgs e) => ended.TrySetResult(true);
        playing.MediaOpened += Opened;
        playing.MediaFailed += Failed;
        playing.MediaEnded += Ended;
        try
        {
            playing.Open(new Uri(file));
            if (await Task.WhenAny(opened.Task, Task.Delay(TimeSpan.FromSeconds(10), cancel)) != opened.Task)
            {
                cancel.ThrowIfCancellationRequested();
                throw new IOException(L10n.Tr("the clip would not open"));
            }
            await opened.Task;
            // A clip not joined (an MP3, a WAV this cannot read): its length is known once it is open, and the clock takes it instead of the guess.
            if (piece.Pcm is null && playing.NaturalDuration.HasTimeSpan)
            {
                seconds = playing.NaturalDuration.TimeSpan.TotalSeconds;
                Length += seconds - piece.Seconds;
            }
            playing.Volume = settings.VoiceVolume;
            if (Now == Phase.Playing) playing.Play();
            while (!ended.Task.IsCompleted)
            {
                await Task.WhenAny(ended.Task, Task.Delay(250, cancel));
                cancel.ThrowIfCancellationRequested();
                if (Now == Phase.Playing && playing.Position.TotalSeconds >= seconds + 0.3) break;
            }
        }
        finally
        {
            playing.MediaOpened -= Opened;
            playing.MediaFailed -= Failed;
            playing.MediaEnded -= Ended;
            playing.Stop();
            playing.Close();
            if (ReferenceEquals(media, playing)) media = null;
            _ = DeleteSoon(file);
        }
        return seconds;
    }

    private void Finish()
    {
        ticker.Stop();
        Played = Length;
        StopMedia();
        Set(Phase.Finished, null);
        UpdateStatus();
        Trace?.Invoke(string.Format(CultureInfo.InvariantCulture, "read done: {0:F1} s of sound, {1} parts, {2}", Length, PartsTotal, Spend.Label(Spent)));
    }

    public void Pause()
    {
        if (Now != Phase.Playing) return;
        media?.Pause();
        Set(Phase.Paused, null);
        UpdateStatus();
    }

    public void Resume()
    {
        if (Now != Phase.Paused) return;
        Set(Phase.Playing, null);
        if (!starved && !resting) media?.Play();
        UpdateStatus();
    }

    /// <summary>Silence now; what is on its way is still priced, its sound dropped.</summary>
    public void Stop()
    {
        if (!IsActive) return;
        Halt();
        Set(Phase.Idle, PartsReady > 0 ? L10n.Tr("Stopped after %@ of %@", ReadAloud.Clock(Played), ReadAloud.Clock(Length)) : L10n.Tr("Stopped"));
        Trace?.Invoke("read stopped");
    }

    /// <summary>Nothing more of this reading is played: a stop, or trouble.</summary>
    private void Halt()
    {
        epoch++;
        stopping.Cancel();
        ticker.Stop();
        StopMedia();
    }

    private void StopMedia()
    {
        media?.Stop();
        media?.Close();
        media = null;
    }

    /// <summary>The pace for the parts not yet asked for; Windows cannot stretch the ones already here.</summary>
    public void SetPace(double wanted)
    {
        pace = Math.Clamp(wanted, ReadAloud.SpeedMin, ReadAloud.SpeedMax);
        Trace?.Invoke("read pace " + ReadAloud.SpeedLabel(pace) + " from the next part");
    }

    private void Tick()
    {
        if (!IsActive) return;
        var now = heardBefore + (resting ? restHeard : media?.Position.TotalSeconds ?? 0);
        Played = Math.Min(now, Length);
        Changed?.Invoke();
    }

    private void Set(Phase phase, string? line)
    {
        var was = Now;
        Now = phase;
        if (line is not null) Status = line;
        if (was != phase) PhaseChanged?.Invoke(phase);
        Changed?.Invoke();
    }

    private void UpdateStatus()
    {
        string line;
        switch (Now)
        {
            case Phase.Finished:
                line = L10n.Tr("Read: %@ · %@", ReadAloud.Clock(Length), L10n.TrCount(PartsTotal, "part", "parts"));
                if (FirstSound is double first) line += " · " + L10n.Tr("first sound after %.1f s", first);
                break;
            case Phase.Paused:
                line = L10n.Tr("Paused at %@", ReadAloud.Clock(Played));
                break;
            default:
                line = PartsReady < PartsTotal ? L10n.Tr("Part %d of %d in", PartsReady, PartsTotal) : L10n.TrCount(PartsTotal, "part", "parts");
                break;
        }
        if (Reader.Length > 0) line += " · " + Reader;
        if (Spent > 0) line += " · " + Spend.Label(Spent);
        if (notes.Count > 0) line += " · " + string.Join(" · ", notes);
        Status = line;
        Changed?.Invoke();
    }

    private void Note(string line)
    {
        if (!notes.Contains(line)) notes.Add(line);
    }

    // MARK: One part's sound

    /// <summary>Null when no voice speaks the part's language: it is skipped, and the status says so.</summary>
    private async Task<Piece?> SoundFor(ReadAloud.Part part, Translate.Lang language, Plan plan, double speed, int mine)
    {
        if (plan.Engine != ReadAloud.Engine.System && plan.Client is { } client)
        {
            var voices = await (voiceList ??= VoiceList(plan));
            // Stopped while the list came: nothing asked for, nothing paid.
            if (epoch != mine) return null;
            var pool = ReadAloud.VoicesSpeaking(voices, language);
            if (voices.Count == 0 || pool.Count > 0)
                return await SpeakOnline(part.Text, client, OnlineVoice(plan, pool, voices), speed, plan.Engine == ReadAloud.Engine.Local, mine);
            Note(L10n.Tr("%@ has no %@ voice: Windows' reads it", client.Model, language.Title));
        }
        return await SpeakHere(part.Text, language, plan, speed);
    }

    /// <summary>The model's voices, or the local server's; empty when the list cannot be had (then the voice is sent as chosen).</summary>
    private async Task<IReadOnlyList<string>> VoiceList(Plan plan)
    {
        try { return plan.Engine == ReadAloud.Engine.Local ? await voice.LoadLocalVoices() : await voice.VoicesOf(plan.Client?.Model ?? ""); }
        catch (Exception e) when (e is not OperationCanceledException) { return Array.Empty<string>(); }
    }

    /// <summary>The voice for a part: the preset's own; else the character's (its own on the Voice page for the same
    /// model, or cast from its persona); else the first.</summary>
    public string? OnlineVoice(Plan plan, IReadOnlyList<string> pool, IReadOnlyList<string> all)
    {
        var preset = plan.Preset;
        if (preset.Voice.Length > 0 && (all.Count == 0 || pool.Contains(preset.Voice))) return preset.Voice;
        if (preset.Character.Length == 0) return pool.FirstOrDefault();
        var name = preset.Character;
        var own = settings.CharacterVoices.TryGetValue(name, out var set) ? set : null;
        var model = plan.Client?.Model;
        var mine = plan.Engine == ReadAloud.Engine.Local
            ? (settings.LocalVoiceModel.Trim() == model ? own?.LocalVoice : null)
            : (settings.VoiceModel.Trim() == model ? own?.OpenRouterVoice : null);
        if (mine is not null && pool.Contains(mine)) return mine;
        var traits = Describe(name) is { } who ? Casting.TraitsOf(who.Persona, who.Kind) : Casting.Traits.Neutral;
        var tags = pool.Distinct().ToDictionary(v => v, v => Casting.TagsOfVoice(v));
        return Casting.Assign(new[] { name }, new Dictionary<string, Casting.Traits> { [name] = traits }, pool, tags).GetValueOrDefault(name) ?? pool.FirstOrDefault();
    }

    private async Task<Piece> SpeakOnline(string text, SpeechClient client, string? name, double speed, bool local, int mine)
    {
        var format = formats.TryGetValue(client.Model, out var f) ? f : local ? "wav" : "pcm";
        var sendSpeed = !noSpeed.Contains(client.Model);
        (byte[] Audio, string? Generation)? reply = null;
        for (var attempt = 0; attempt < 3 && reply is null; attempt++)
        {
            try { reply = await client.Speak(text, name, sendSpeed ? speed : null, format); }
            catch (SpeechClient.Unusable paid)
            {
                // Paid for, though there is nothing to play: priced, then the trouble said.
                if (!local) Charge(client, paid.Generation, mine);
                throw paid.Failure;
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
        if (reply is not { } answer) throw ChatClient.Failure.BadReply(L10n.Tr("no audio"));
        // Priced before anything can go wrong with the sound: it was paid for.
        if (!local) Charge(client, answer.Generation, mine);
        if (!sendSpeed && Math.Abs(speed - 1) > 0.01) Note(L10n.Tr("%@ takes no pace: read at its own", client.Model));
        var who = (name ?? L10n.Tr("its own voice")) + " " + (local ? L10n.Tr("on local %@", client.Model) : L10n.Tr("on %@", client.Model));
        var isWav = answer.Audio.Length >= 4 && Encoding.ASCII.GetString(answer.Audio, 0, 4) == "RIFF";
        if (!isWav) return new Piece(answer.Audio, false, ReadAloud.Seconds(text.Length, speed), null, who);
        // A WAV this cannot read (32-bit float, 24-bit, as some local servers send) plays as it came, like an MP3, but is not joined.
        if (ReadAloudTape.Decode(answer.Audio) is not { } pcm) return new Piece(answer.Audio, true, ReadAloud.Seconds(text.Length, speed), null, who);
        return new Piece(WaveTape.Write(pcm), true, pcm.Duration, pcm, who);
    }

    /// <summary>Into the spend file under Read aloud, priced once OpenRouter says what it cost (unpriced without an id).</summary>
    private async void Charge(SpeechClient client, string? generation, int mine)
    {
        Spend.Usage? usage = null;
        try { if (generation is not null) usage = await client.Cost(generation); }
        catch (Exception e) { Console.Error.WriteLine("Ledgelings read aloud price: " + e.Message); }
        var priced = usage ?? new Spend.Usage(0, 0, null);
        spend.Record(ChatClient.Provider.OpenRouter, client.Model, priced, Spend.Purpose.ReadAloud);
        if (priced.Cost is not double cost || mine != epoch) return;
        Spent += cost;
        Trace?.Invoke($"read priced {Spend.Label(cost)}: {priced.PromptTokens} tokens in, {priced.CompletionTokens} out");
        if (Now != Phase.Preparing) UpdateStatus();
    }

    // MARK: Windows' own voices

    private async Task<Piece?> SpeakHere(string text, Translate.Lang language, Plan plan, double speed)
    {
        if (WindowsVoice(language, plan.Preset, settings, Describe) is not { } chosen)
        {
            Note(L10n.Tr("Windows has no %@ voice: those parts are skipped", language.Title));
            return null;
        }
        var wav = await Task.Run(() => Voice.Render(text, chosen.Name, speed, null, chosen.Culture));
        if (ReadAloudTape.Decode(wav) is not { Frames: > 0 } pcm) throw ChatClient.Failure.BadReply(L10n.Tr("Windows' voice said nothing"));
        return new Piece(WaveTape.Write(pcm), true, pcm.Duration, pcm, chosen.Name);
    }

    /// <summary>A Windows voice for <paramref name="language"/>: the preset's own when it speaks it; for a character, its
    /// own voice on the Voice page, else one cast from its persona; for a narrator, SAPI's default when it speaks the
    /// language, else one of the user's region. Null when Windows has no voice for the language.</summary>
    public static Voice.SystemVoiceInfo? WindowsVoice(Translate.Lang language, ReadAloud.Preset preset, AppSettings settings,
                                                       Func<string, (string Persona, string Kind)?> describe)
    {
        var all = Voice.Installed.Where(v => v.Culture.StartsWith(language.Code, StringComparison.OrdinalIgnoreCase)).ToList();
        if (all.Count == 0) return null;
        if (preset.Engine == ReadAloud.Engine.System && preset.Voice.Length > 0 && all.FirstOrDefault(v => v.Name == preset.Voice) is { } own) return own;
        if (preset.Character.Length > 0)
        {
            var name = preset.Character;
            if (settings.VoiceOf(name).SystemVoice is string mine && all.FirstOrDefault(v => v.Name == mine) is { } kept) return kept;
            var traits = describe(name) is { } who ? Casting.TraitsOf(who.Persona, who.Kind) : Casting.Traits.Neutral;
            var pool = all.Select(v => v.Name).Distinct().ToList();
            var tags = all.GroupBy(v => v.Name).ToDictionary(g => g.Key, g => Voice.TagsOf(g.First()));
            if (Casting.Assign(new[] { name }, new Dictionary<string, Casting.Traits> { [name] = traits }, pool, tags).GetValueOrDefault(name) is string id
                && all.FirstOrDefault(v => v.Name == id) is { } cast) return cast;
        }
        if (Voice.SapiDefault is string standard && all.FirstOrDefault(v => v.Name == standard) is { } chosen) return chosen;
        var region = RegionInfo.CurrentRegion.TwoLetterISORegionName;
        return all.OrderBy(v => v.Culture.EndsWith(region, StringComparison.OrdinalIgnoreCase) ? 0 : 1).ThenBy(v => v.Name, StringComparer.Ordinal).First();
    }

    // MARK: Saving and copying

    /// <summary>What Save writes, whatever the format chosen: Windows has no AAC encoder without a new dependency.</summary>
    public const ReadAloud.Format SavedFormat = ReadAloud.Format.Wav;

    /// <summary>The reading so far as one 16-bit WAV.</summary>
    public void Write(string path)
    {
        if (tape.Count == 0) throw new InvalidOperationException(L10n.Tr("nothing read yet"));
        File.WriteAllBytes(path, ReadAloudTape.Wav(tape));
    }

    /// <summary>A reading's sound set straight, as if read: for the tests of Save and Copy.</summary>
    public void Load(IEnumerable<WaveTape.Pcm> pieces)
    {
        tape.Clear();
        tape.AddRange(pieces);
        PartsTotal = PartsReady = 1;
        Length = tape.Sum(p => p.Duration);
    }

    /// <summary>Where Copy writes the file it puts on the clipboard: beside the app's other files, kept until the next copy.</summary>
    public static string CopyFolder => Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "Ledgelings", "Read aloud");

    /// <summary>The player may hold the file a moment after Close: try again for a few seconds.</summary>
    private static async Task DeleteSoon(string file)
    {
        for (var attempt = 0; attempt < 5; attempt++)
        {
            try { File.Delete(file); return; }
            catch (Exception e) when (e is IOException or UnauthorizedAccessException) { await Task.Delay(TimeSpan.FromSeconds(1 + attempt)); }
        }
    }
}
