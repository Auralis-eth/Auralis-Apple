@testable import Auralis
import Foundation
import Testing

@Suite
struct ModeStateTests {
    @Test("mode state always restores observe mode and overwrites stale storage")
    func modeStateForcesObserveModeIntoStorage() {
        let suiteName = "ModeStateTests.modeStateForcesObserveModeIntoStorage"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defaults.set("Execute", forKey: "app.mode")

        let state = ModeState(userDefaults: defaults, storageKey: "app.mode")

        #expect(state.mode == .observe)
        #expect(defaults.string(forKey: "app.mode") == AppMode.observe.rawValue)
    }

    @Test("mode receipt augmentor always stamps the active observe mode")
    func modeReceiptAugmentorAttachesModeField() {
        let defaults = UserDefaults(suiteName: "ModeStateTests.modeReceiptAugmentorAttachesModeField")!
        defaults.removePersistentDomain(forName: "ModeStateTests.modeReceiptAugmentorAttachesModeField")
        let state = ModeState(userDefaults: defaults, storageKey: "mode")

        let payload = ModeReceiptAugmentor.attachMode(to: ["scope": "test"], modeState: state)

        #expect(payload["scope"] as? String == "test")
        #expect(payload["mode"] as? String == AppMode.observe.rawValue)
    }
}
