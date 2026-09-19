import Foundation
import Testing
@testable import Ledgelings

@MainActor
@Suite struct SettingsTests {
    func fresh() -> (AppSettings, UserDefaults) {
        let name = "ledgelings-tests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return (AppSettings(defaults: defaults, keychain: Keychain(service: name)), defaults)
    }

    @Test func creaturesCycleThroughTheSpeciesInUseAndBlockyIsTheFallback() {
        let (s, defaults) = fresh()
        #expect(s.species == ["blocky"])
        s.species = ["pip", "blocky"]
        #expect(s.species(forCreature: 0) == "pip" && s.species(forCreature: 1) == "blocky" && s.species(forCreature: 2) == "pip")
        #expect(AppSettings(defaults: defaults).species == ["pip", "blocky"])
        s.species = []
        #expect(s.species(forCreature: 0) == "blocky")
    }

    @Test func theBrainIsLMStudioUntilChosenOtherwise() {
        let (s, _) = fresh()
        #expect(s.brainProvider == .lmStudio)
        #expect(s.openRouterModel == AppSettings.defaultOpenRouterModel)
        #expect(s.openRouterKey == "")
        let client = s.chatClient()
        #expect(client?.provider == .lmStudio)
        #expect(client?.baseURL.absoluteString == "http://localhost:1234/v1")
        #expect(client?.model == AppSettings.defaultTalkModel)
    }

    @Test func choosingOpenRouterBuildsAClientWithTheKeyAndModel() {
        let (s, defaults) = fresh()
        s.brainProvider = .openRouter
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
        let name = "ledgelings-tests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        let keychain = Keychain(service: name)
        defer { keychain.set(nil, for: "openRouterKey") }
        AppSettings(defaults: defaults, keychain: keychain).openRouterKey = "sk-or-kept"
        #expect(AppSettings(defaults: defaults, keychain: keychain).openRouterKey == "sk-or-kept")
    }

    @Test func openRouterWithoutAKeyGivesNoClient() {
        let (s, _) = fresh()
        s.brainProvider = .openRouter
        #expect(s.chatClient() == nil)
    }

    @Test func creaturesSpreadAcrossTheSizeRangeInHalfSteps() {
        let (s, _) = fresh()
        s.minSize = 1; s.maxSize = 4
        #expect(s.size(forShare: 0) == 1)
        #expect(s.size(forShare: 1) == 4)
        #expect(s.size(forShare: 0.5) == 2.5)
        #expect(s.size(forShare: 0.4) == 2)          // 2.2 snaps to the nearest half
    }

    @Test func equalMinAndMaxMakesEveryoneTheSameSize() {
        let (s, _) = fresh()
        s.minSize = 3; s.maxSize = 3
        #expect(Set([0, 0.3, 0.9, 1].map(s.size(forShare:))) == [3])
    }

    @Test func draggingOneSliderPastTheOtherTakesItAlong() {
        let (s, _) = fresh()
        s.minSize = 2; s.maxSize = 3
        s.minSize = 4.5
        #expect(s.maxSize == 4.5)
        s.maxSize = 1.5
        #expect(s.minSize == 1.5)
    }

    @Test func sizesAreSavedAndASwappedPairIsRepairedOnLoad() {
        let (s, defaults) = fresh()
        s.minSize = 2.5; s.maxSize = 4
        let again = AppSettings(defaults: defaults)
        #expect(again.minSize == 2.5 && again.maxSize == 4)

        defaults.set(5.0, forKey: "minSize"); defaults.set(1.0, forKey: "maxSize")
        let repaired = AppSettings(defaults: defaults)
        #expect(repaired.minSize == 1 && repaired.maxSize == 5)
    }

    @Test func aFlowerIsWornForTwoMinutesByDefaultAndTheTimeIsClampedOnLoad() {
        let (s, defaults) = fresh()
        #expect(s.flowerMinutes == 2)
        s.flowerMinutes = 10
        #expect(AppSettings(defaults: defaults).flowerMinutes == 10)
        defaults.set(0.0, forKey: "flowerMinutes")
        #expect(AppSettings(defaults: defaults).flowerMinutes == AppSettings.flowerRange.lowerBound)
    }

    @Test func bubbleTimeDefaultsToFourteenSecondsAndIsClampedOnLoad() {
        let (s, defaults) = fresh()
        #expect(s.bubbleSeconds == 14)
        s.bubbleSeconds = 30
        #expect(AppSettings(defaults: defaults).bubbleSeconds == 30)
        defaults.set(1.0, forKey: "bubbleSeconds")
        #expect(AppSettings(defaults: defaults).bubbleSeconds == AppSettings.bubbleRange.lowerBound)
    }
}
