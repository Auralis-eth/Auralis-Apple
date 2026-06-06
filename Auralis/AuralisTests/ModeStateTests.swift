@testable import Auralis
import AuralisTestSupport
import Foundation
import PolicyCore
import Testing

@MainActor
struct ModeStateTests {
    @Test("shipped app modes remain observe-only until WEB3-001 future gates exist")
    func appModesRemainObserveOnly() {
        #expect(AppMode.allCases == [.observe])
        #expect(AppMode.allCases.map(\.rawValue) == ["Observe"])
    }

    @Test("mode state always restores observe mode and overwrites stale storage")
    func modeStateForcesObserveModeIntoStorage() throws {
        let (defaults, cleanup) = try TestSupport.temporaryUserDefaults(prefix: "ModeStateTests")
        defer { cleanup() }
        defaults.set("Execute", forKey: "app.mode")

        let state = ModeState(userDefaults: defaults, storageKey: "app.mode")

        #expect(state.mode == .observe)
        #expect(defaults.string(forKey: "app.mode") == AppMode.observe.rawValue)
    }

    @Test("mode receipt augmentor always stamps the active observe mode")
    func modeReceiptAugmentorAttachesModeField() throws {
        let (defaults, cleanup) = try TestSupport.temporaryUserDefaults(prefix: "ModeStateTests")
        defer { cleanup() }
        let state = ModeState(userDefaults: defaults, storageKey: "mode")

        let payload = ModeReceiptAugmentor.attachMode(to: ["scope": "test"], modeState: state)

        #expect(payload["scope"] as? String == "test")
        #expect(payload["mode"] as? String == AppMode.observe.rawValue)
    }
}
