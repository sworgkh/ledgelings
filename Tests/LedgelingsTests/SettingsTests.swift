import Foundation
import Testing
@testable import Ledgelings

@MainActor
@Suite struct SettingsTests {
    func fresh() -> (AppSettings, UserDefaults) {
        let name = "ledgelings-tests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return (AppSettings(defaults: defaults), defaults)
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
}
