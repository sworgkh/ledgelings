import AppKit
import Carbon.HIToolbox
import Combine
import LedgelingsCore

/// Dictation from the outside (§7.13): the shortcut (and the menu item) start
/// and stop a recording here; the audio goes to the chosen OpenRouter model, the
/// words come back onto the clipboard and into the clipboard history, pasted
/// into the app in front when asked, and every call is priced. A creature holds
/// the microphone while it listens; without one, a toast says how it went.
@MainActor
final class DictationController {
    private let settings: AppSettings
    private let spend: SpendLedger
    private let colony: () -> Colony?
    private let clips: ClipBook
    private let watcher: () -> ClipWatcher?
    private var shortcut: GlobalShortcut?
    private var recorder = Dictation.Recorder()
    private var microphone: DictationRecorder?
    private var clock: Timer?
    private var started = Date()
    private var lastTick = Date()
    /// Esc and ⏎ are taken from every app only while it listens.
    private let escapeID = HotKeys.shared.newID()
    private let enterID = HotKeys.shared.newID()
    /// The app in front when it started: the words are pasted back into it.
    private var front: NSRunningApplication?
    /// Every step with its time, for `--dictate-demo` and `--shortcut`.
    var trace: ((String) -> Void)?
    /// What a finished dictation came to, for `--dictate-demo`: the words, or the trouble.
    var finished: ((Result<String, DictationFailure>) -> Void)?

    struct DictationFailure: Error { let trouble: Dictation.Trouble }

    init(settings: AppSettings, spend: SpendLedger, clips: ClipBook, colony: @escaping () -> Colony?, watcher: @escaping () -> ClipWatcher?) {
        self.settings = settings
        self.spend = spend
        self.clips = clips
        self.colony = colony
        self.watcher = watcher
    }

    var isRecording: Bool { recorder.isRecording }
    var isBusy: Bool { recorder.state != .idle }

    /// Takes the shortcut from every app, following the settings.
    func takeShortcut(pressed: @escaping () -> Void = {}) {
        let enabled = settings.$dictationEnabled.combineLatest(settings.$dictationShortcutEnabled).map { $0 && $1 }
        shortcut = GlobalShortcut(settings: settings, enabled: enabled, shortcut: settings.$dictationShortcut,
                                  problem: { [weak settings] in if settings?.dictationShortcutProblem != $0 { settings?.dictationShortcutProblem = $0 } },
                                  pressed: { [weak self] in pressed(); self?.press() },
                                  released: { [weak self] in self?.release() })
    }

    // MARK: Pressing

    /// The shortcut or the menu: starts, or (pressed again) stops and sends.
    func press() {
        switch recorder.press(at: now, hold: settings.dictationHoldToTalk) {
        case .start: begin()
        case .send(let seconds, let cut): send(seconds: seconds, cut: cut)
        case .discard(let short): discard(tooShort: short)
        case .none: if recorder.state == .transcribing { trace?("busy: still writing the last one down") }
        }
    }

    /// Let go of the shortcut: holding to talk, that stops and sends.
    func release() {
        switch recorder.release(at: now, hold: settings.dictationHoldToTalk) {
        case .send(let seconds, let cut): send(seconds: seconds, cut: cut)
        case .discard(let short): discard(tooShort: short)
        default: break
        }
    }

    /// ⏎ while listening: stop and send.
    func enter() {
        switch recorder.enter(at: now) {
        case .send(let seconds, let cut): send(seconds: seconds, cut: cut)
        case .discard(let short): discard(tooShort: short)
        default: break
        }
    }

    /// Esc while listening: nothing is sent.
    func cancel() {
        guard case .discard = recorder.cancel() else { return }
        trace?("cancelled: nothing sent")
        stopListening()
        colony()?.dictationGoHome()
        finished?(.failure(DictationFailure(trouble: .tooShort)))
    }

    private var now: Double { Date().timeIntervalSince(started) }

    // MARK: Listening

    private func begin() {
        front = NSWorkspace.shared.frontmostApplication
        settings.retryOpenRouterKey()
        let key = settings.openRouterKey.trimmingCharacters(in: .whitespaces)
        guard !key.isEmpty else { recorder.done(); fail(.noKey); return }
        switch DictationRecorder.permission {
        case .granted: listen()
        case .refused: recorder.done(); fail(.microphoneRefused)
        case .notAsked:
            // macOS asks; it listens once allowed, from the moment it was.
            trace?("asking for the microphone")
            Task { @MainActor in
                if await DictationRecorder.askForPermission(), recorder.isRecording { listen() } else { recorder.done(); fail(.microphoneRefused) }
            }
        }
    }

    private func listen() {
        let made = DictationRecorder()
        do { try made.start() } catch {
            recorder.done()
            if case DictationRecorder.Failure.notAllowed = error { fail(.microphoneRefused) } else { fail(.noMicrophone) }
            return
        }
        microphone = made
        trace?("listening on \(DictationRecorder.microphoneName ?? "?"), at most \(settings.dictationMaxSeconds) s")
        recorder.maxSeconds = Double(settings.dictationMaxSeconds)
        takeKeys(true)
        if settings.dictationCreature { colony()?.dictationCome() }
        lastTick = Date()
        clock = Timer.scheduledTimer(withTimeInterval: 1.0 / 20, repeats: true) { [weak self] _ in MainActor.assumeIsolated { self?.tick() } }
    }

    private func tick() {
        let dt = Date().timeIntervalSince(lastTick)
        lastTick = Date()
        if let microphone { colony()?.dictationHear(level: microphone.level, seconds: recorder.seconds(at: now), dt: dt) }
        if case .send(let seconds, let cut) = recorder.tick(at: now) { send(seconds: seconds, cut: cut) }
    }

    /// Esc and ⏎, from every app, while it listens; let go after.
    private func takeKeys(_ on: Bool) {
        HotKeys.shared.hold(escapeID, on ? Shortcut(keyCode: kVK_Escape, modifiers: []) : nil) { [weak self] in self?.cancel() }
        HotKeys.shared.hold(enterID, on ? Shortcut(keyCode: kVK_Return, modifiers: []) : nil) { [weak self] in self?.enter() }
    }

    private func stopListening() -> [Int16] {
        clock?.invalidate()
        clock = nil
        takeKeys(false)
        let samples = microphone?.stop() ?? []
        microphone = nil
        return samples
    }

    private func discard(tooShort: Bool) {
        _ = stopListening()
        trace?(tooShort ? "too short: nothing sent" : "discarded")
        if tooShort { tell(Dictation.Trouble.tooShort.line, voiced: false) } else { colony()?.dictationGoHome() }
        finished?(.failure(DictationFailure(trouble: .tooShort)))
    }

    // MARK: Writing it down

    private func send(seconds: Double, cut: Bool) {
        let samples = stopListening()
        let heard = Double(samples.count) / Double(Dictation.sampleRate)
        trace?(String(format: "stopped%@ after %.1f s: %d samples", cut ? " at the longest length" : "", heard, samples.count))
        guard heard >= Dictation.shortest else { recorder.done(); fail(.tooShort); return }
        colony()?.dictationThink()
        Task { @MainActor in await transcribe(Dictation.wav(samples), seconds: heard) }
    }

    /// Sends a recording (a WAV) and delivers the words. The WAV lives only in
    /// this call: it is never written anywhere and is gone once it returns.
    func transcribe(_ wav: Data, seconds: Double) async {
        let key = settings.openRouterKey.trimmingCharacters(in: .whitespaces)
        let model = settings.dictationModel.trimmingCharacters(in: .whitespaces)
        guard !key.isEmpty else { recorder.done(); fail(.noKey); return }
        let client = DictationClient(key: key, model: model)
        let instruction = Dictation.instruction(language: settings.dictationLanguage, cleanUp: settings.dictationCleanUp)
        trace?(String(format: "sending %.0f KB to %@", Double(wav.count) / 1024, model))
        let sent = Date()
        do {
            let answer = try await client.transcribe(wav: wav, instruction: instruction, seconds: seconds)
            // Paid for whatever it says, empty or not.
            let usage = answer.usage ?? Spend.Usage(promptTokens: 0, completionTokens: 0, cost: nil)
            spend.record(provider: .openRouter, model: model, usage: usage, purpose: .dictation)
            trace?(String(format: "answered in %.1f s: %d tokens in, %d out, %@", Date().timeIntervalSince(sent),
                          usage.promptTokens, usage.completionTokens, usage.cost.map(Spend.label) ?? "price unknown"))
            recorder.done()
            let text = Dictation.cleaned(answer.text)
            guard !text.isEmpty else { fail(.nothingHeard); return }
            deliver(text)
        } catch let failure as ChatClient.Failure {
            recorder.done()
            switch failure {
            case .serverDown(let why): fail(.network(why))
            case .refused(let why): fail(.refused(why))
            default: fail(.refused(failure.description))
            }
        } catch {
            recorder.done()
            fail(.network(error.localizedDescription))
        }
    }

    /// Onto the clipboard and into its history; into the app in front when asked.
    private func deliver(_ text: String) {
        let board = NSPasteboard.general
        board.clearContents()
        board.setString(text, forType: .string)
        if settings.clipboardEnabled, settings.clipHistoryEnabled {
            watcher()?.ownWrite()
            clips.add(Clipboard.Clip(text: text, copiedAt: Date(), app: tr("Dictation")), limit: settings.clipHistoryLimit, days: settings.clipKeepDays)
        }
        trace?("copied \(text.count) characters: \(text.prefix(80))")
        if settings.dictationPaste {
            front?.activate()
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(120))
                trace?(ClipPaster.pressPaste() ? "pasted into \(front?.localizedName ?? "the app in front")" : "not pasted: no Accessibility")
            }
        }
        tell(Dictation.copiedBubble(text), voiced: false)
        finished?(.success(text))
    }

    private func fail(_ trouble: Dictation.Trouble) {
        trace?("trouble: \(trouble.line)")
        tell(trouble.line, voiced: true)
        finished?(.failure(DictationFailure(trouble: trouble)))
    }

    /// The creature says it when there is one (coming to say it, if it is not
    /// out yet); otherwise a toast does.
    private func tell(_ text: String, voiced: Bool) {
        if settings.dictationCreature, let colony = colony(), colony.dictationHelper != nil || colony.dictationCome() {
            colony.dictationTell(text, voiced: voiced)
        } else {
            ClipToast.show(text, near: nil)
        }
    }
}
