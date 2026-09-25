import Foundation
import LedgelingsCore
import Testing
@testable import Ledgelings

/// Serialized: every test shares one defaults domain, wiped before each, so the
/// suite leaves one (empty) plist behind instead of one per run.
@MainActor
@Suite(.serialized) struct SettingsTests {
    /// The shared throwaway defaults domain, empty at the start of each test.
    @MainActor final class Sandbox {
        let name = "ledgelings-tests"
        let defaults: UserDefaults
        let settings: AppSettings
        init() {
            defaults = UserDefaults(suiteName: name)!
            defaults.removePersistentDomain(forName: name)
            settings = AppSettings(defaults: defaults, keychain: Keychain(service: name))
        }
        /// Called from a `defer` at the top of each test: by the time the test's
        /// own references die, the writes it made may still be landing.
        func forget() {
            defaults.synchronize()
            defaults.removePersistentDomain(forName: name)
            defaults.synchronize()
        }
    }

    func fresh() -> Sandbox { Sandbox() }

    @Test func followingTheGiverIsOnByDefaultAndRemembered() {
        let box = fresh(), s = box.settings, defaults = box.defaults
        defer { box.forget() }
        #expect(s.followGiver)
        s.followGiver = false
        #expect(!AppSettings(defaults: defaults).followGiver)
    }

    @Test func speciesThatNoLongerExistAreDroppedAndBlockyFillsAnEmptyList() {
        let box = fresh(), s = box.settings
        defer { box.forget() }
        s.species = ["cat", "rabbit", "frog"]
        s.keepSpecies(among: ["blocky", "cat", "frog"])
        #expect(s.species == ["cat", "frog"])
        s.keepSpecies(among: ["blocky"])
        #expect(s.species == ["blocky"])
    }

    @Test func creaturesCycleThroughTheSpeciesInUseAndBlockyIsTheFallback() {
        let box = fresh(), s = box.settings, defaults = box.defaults
        defer { box.forget() }
        #expect(s.species == ["blocky"])
        s.species = ["pip", "blocky"]
        #expect(s.species(forCreature: 0) == "pip" && s.species(forCreature: 1) == "blocky" && s.species(forCreature: 2) == "pip")
        #expect(AppSettings(defaults: defaults).species == ["pip", "blocky"])
        s.species = []
        #expect(s.species(forCreature: 0) == "blocky")
    }

    @Test func aFreshInstallTalksFromTheBuiltInLinesAndAnOldOneKeepsLMStudio() {
        let box = fresh(), s = box.settings, defaults = box.defaults
        defer { box.forget() }
        #expect(s.brain == .script, "no model to set up: it talks out of the box")
        #expect(s.chatClient() == nil)
        #expect(s.script == Script.builtInText)
        defaults.set("google/gemma-3-4b", forKey: "talkModel")
        #expect(AppSettings(defaults: defaults).brain == .lmStudio, "someone who set up LM Studio before the lines existed keeps it")
        defaults.set("openRouter", forKey: "brainProvider")
        #expect(AppSettings(defaults: defaults).brain == .openRouter)
    }

    @Test func theLinesAreRememberedAndResetBringsTheBuiltInOnesBack() {
        let box = fresh(), s = box.settings, defaults = box.defaults
        defer { box.forget() }
        s.script = "Hello.\nHi."
        #expect(AppSettings(defaults: defaults).script == "Hello.\nHi.")
        s.resetScript()
        #expect(s.script == Script.builtInText)
    }

    @Test func theBrainIsLMStudioWhenChosen() {
        let box = fresh(), s = box.settings
        defer { box.forget() }
        s.brain = .lmStudio
        #expect(s.openRouterModel == AppSettings.defaultOpenRouterModel)
        #expect(s.openRouterKey == "")
        let client = s.chatClient()
        #expect(client?.provider == .lmStudio)
        #expect(client?.baseURL.absoluteString == "http://localhost:1234/v1")
        #expect(client?.model == AppSettings.defaultTalkModel)
    }

    /// Counts reads, so a test can prove the keychain was left alone.
    final class SpyStore: SecretStore, @unchecked Sendable {
        var reads = 0, writes = 0
        var stored: [String: String] = [:]
        func get(_ account: String) -> String? { reads += 1; return stored[account] }
        func set(_ value: String?, for account: String) { writes += 1; stored[account] = value }
    }

    @Test func writingTheKeyItAlreadyHasDoesNotTouchTheKeychain() {
        let box = fresh()
        defer { box.forget() }
        let spy = SpyStore()
        spy.stored["openRouterKey"] = "sk-or-kept"
        let s = AppSettings(defaults: box.defaults, keychain: spy)
        s.openRouterKey = "sk-or-kept"            // what the key field does when it loses focus
        #expect(spy.reads == 1 && spy.writes == 0, "read once to compare, nothing written")
        s.openRouterKey = "sk-or-new"
        #expect(spy.writes == 1)
    }

    @Test func theKeychainIsNotTouchedUntilOpenRouterNeedsTheKey() {
        let box = fresh()
        defer { box.forget() }
        let spy = SpyStore()
        spy.stored["openRouterKey"] = "sk-or-kept"
        let s = AppSettings(defaults: box.defaults, keychain: spy)
        #expect(spy.reads == 0, "launching does not open the keychain")
        s.brain = .lmStudio
        #expect(s.chatClient() != nil && spy.reads == 0, "LM Studio never needs it")
        s.brain = .openRouter
        #expect(s.chatClient()?.apiKey == "sk-or-kept")
        #expect(spy.reads == 1)
        _ = s.chatClient()
        #expect(spy.reads == 1, "read once, then remembered")
        s.openRouterKey = "sk-or-new"
        #expect(spy.stored["openRouterKey"] == "sk-or-new" && s.chatClient()?.apiKey == "sk-or-new" && spy.reads == 1)
    }

    @Test func choosingOpenRouterBuildsAClientWithTheKeyAndModel() {
        let box = fresh(), s = box.settings, defaults = box.defaults
        defer { box.forget() }
        s.brain = .openRouter
        s.openRouterKey = "sk-or-abc"
        s.openRouterModel = "openai/gpt-4o-mini"
        let client = s.chatClient()
        #expect(client?.provider == .openRouter)
        #expect(client?.apiKey == "sk-or-abc")
        #expect(client?.model == "openai/gpt-4o-mini")
        #expect(client?.baseURL == ChatClient.openRouterURL)
        #expect(defaults.string(forKey: "brainProvider") == "openRouter")
        #expect(defaults.string(forKey: "openRouterKey") == nil, "the key never lands in the preferences file")
        s.openRouterKey = ""
    }

    @Test func theKeyComesBackFromTheKeychainOnTheNextLaunch() {
        let name = "ledgelings-tests"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        let keychain = Keychain(service: name)
        defer { keychain.set(nil, for: "openRouterKey"); defaults.removePersistentDomain(forName: name) }
        AppSettings(defaults: defaults, keychain: keychain).openRouterKey = "sk-or-kept"
        #expect(AppSettings(defaults: defaults, keychain: keychain).openRouterKey == "sk-or-kept")
    }

    @Test func openRouterWithoutAKeyGivesNoClient() {
        let box = fresh(), s = box.settings
        defer { box.forget() }
        s.brain = .openRouter
        #expect(s.chatClient() == nil)
    }

    @Test func creaturesSpreadAcrossTheSizeRangeInHalfSteps() {
        let box = fresh(), s = box.settings
        defer { box.forget() }
        s.minSize = 1; s.maxSize = 4
        #expect(s.size(forShare: 0) == 1)
        #expect(s.size(forShare: 1) == 4)
        #expect(s.size(forShare: 0.5) == 2.5)
        #expect(s.size(forShare: 0.4) == 2)          // 2.2 snaps to the nearest half
    }

    @Test func equalMinAndMaxMakesEveryoneTheSameSize() {
        let box = fresh(), s = box.settings
        defer { box.forget() }
        s.minSize = 3; s.maxSize = 3
        #expect(Set([0, 0.3, 0.9, 1].map(s.size(forShare:))) == [3])
    }

    @Test func draggingOneSliderPastTheOtherTakesItAlong() {
        let box = fresh(), s = box.settings
        defer { box.forget() }
        s.minSize = 2; s.maxSize = 3
        s.minSize = 4.5
        #expect(s.maxSize == 4.5)
        s.maxSize = 1.5
        #expect(s.minSize == 1.5)
    }

    @Test func sizesAreSavedAndASwappedPairIsRepairedOnLoad() {
        let box = fresh(), s = box.settings, defaults = box.defaults
        defer { box.forget() }
        s.minSize = 2.5; s.maxSize = 4
        let again = AppSettings(defaults: defaults)
        #expect(again.minSize == 2.5 && again.maxSize == 4)

        defaults.set(5.0, forKey: "minSize"); defaults.set(1.0, forKey: "maxSize")
        let repaired = AppSettings(defaults: defaults)
        #expect(repaired.minSize == 1 && repaired.maxSize == 5)
    }

    @Test func aFlowerIsWornForTwoMinutesByDefaultAndTheTimeIsClampedOnLoad() {
        let box = fresh(), s = box.settings, defaults = box.defaults
        defer { box.forget() }
        #expect(s.flowerMinutes == 2)
        s.flowerMinutes = 10
        #expect(AppSettings(defaults: defaults).flowerMinutes == 10)
        defaults.set(0.0, forKey: "flowerMinutes")
        #expect(AppSettings(defaults: defaults).flowerMinutes == AppSettings.flowerRange.lowerBound)
    }

    @Test func bubbleTimeDefaultsToFourteenSecondsAndIsClampedOnLoad() {
        let box = fresh(), s = box.settings, defaults = box.defaults
        defer { box.forget() }
        #expect(s.bubbleSeconds == 14)
        s.bubbleSeconds = 30
        #expect(AppSettings(defaults: defaults).bubbleSeconds == 30)
        defaults.set(1.0, forKey: "bubbleSeconds")
        #expect(AppSettings(defaults: defaults).bubbleSeconds == AppSettings.bubbleRange.lowerBound)
    }

    @Test func voiceIsOffUntilAskedAndEveryVoiceSettingIsRemembered() {
        let box = fresh(), s = box.settings, defaults = box.defaults
        defer { box.forget() }
        #expect(!s.voiceEnabled, "it must not start talking out loud unasked")
        #expect(s.voiceEngine == .system && s.voicePerCharacter)
        #expect(s.voiceModel == AppSettings.defaultVoiceModel && s.voiceSpeed == 1 && s.voicePitch == 1 && s.voiceVolume == 0.8)
        #expect(s.keepVoices, "paid-for sounds are kept unless asked not to")
        #expect(s.cartoonVoices, "desktop pets, not newsreaders")
        s.cartoonVoices = false
        #expect(!AppSettings(defaults: defaults).cartoonVoices)
        s.keepVoices = false
        #expect(!AppSettings(defaults: defaults).keepVoices)
        s.voiceEnabled = true
        s.voiceEngine = .openRouter
        s.voicePerCharacter = false
        s.systemVoice = "com.apple.voice.compact.en-US.Samantha"
        s.voiceModel = "deepgram/flux-tts:free"
        s.openRouterVoice = "flux-kit-en"
        s.voiceSpeed = 1.5; s.voicePitch = 0.75; s.voiceVolume = 0.3
        let back = AppSettings(defaults: defaults)
        #expect(back.voiceEnabled && back.voiceEngine == .openRouter && !back.voicePerCharacter)
        #expect(back.systemVoice == "com.apple.voice.compact.en-US.Samantha")
        #expect(back.voiceModel == "deepgram/flux-tts:free" && back.openRouterVoice == "flux-kit-en")
        #expect(back.voiceSpeed == 1.5 && back.voicePitch == 0.75 && back.voiceVolume == 0.3)
        defaults.set(9.0, forKey: "voiceSpeed")
        #expect(AppSettings(defaults: defaults).voiceSpeed == AppSettings.voiceSpeedRange.upperBound)
    }
}
