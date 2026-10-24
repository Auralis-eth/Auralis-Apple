@testable import Auralis
import AuralisTestSupport
import Foundation
import PolicyCore
import Testing

@MainActor
struct ModeStateTests {
    @Test("app exposes Observe Assist and Operate crypto modes")
    func appModesExposeOperatorPostures() {
        #expect(CryptoMode.allCases == [.observe, .assist, .operate])
        #expect(CryptoMode.allCases.map(\.rawValue) == ["Observe", "Assist", "Operate"])
    }

    @Test("mode state restores persisted modes and normalizes unknown storage")
    func modeStateRestoresPersistedMode() throws {
        let (defaults, cleanup) = try TestSupport.temporaryUserDefaults(prefix: "ModeStateTests")
        defer { cleanup() }
        defaults.set(CryptoMode.assist.rawValue, forKey: "app.mode")

        let state = ModeState(userDefaults: defaults, storageKey: "app.mode")

        #expect(state.mode == .assist)
        #expect(defaults.string(forKey: "app.mode") == CryptoMode.assist.rawValue)

        defaults.set("Execute", forKey: "unknown.mode")
        let unknown = ModeState(userDefaults: defaults, storageKey: "unknown.mode")
        #expect(unknown.mode == .observe)
        #expect(defaults.string(forKey: "unknown.mode") == CryptoMode.observe.rawValue)
    }

    @Test("mode state persists explicit mode changes")
    func modeStatePersistsModeChanges() throws {
        let (defaults, cleanup) = try TestSupport.temporaryUserDefaults(prefix: "ModeStateTests")
        defer { cleanup() }
        let state = ModeState(userDefaults: defaults, storageKey: "mode")

        state.setMode(.operate)

        #expect(state.mode == .operate)
        #expect(defaults.string(forKey: "mode") == CryptoMode.operate.rawValue)
    }

    @Test("mode receipt augmentor stamps the active mode")
    func modeReceiptAugmentorAttachesModeField() throws {
        let (defaults, cleanup) = try TestSupport.temporaryUserDefaults(prefix: "ModeStateTests")
        defer { cleanup() }
        let state = ModeState(userDefaults: defaults, storageKey: "mode")
        state.setMode(.assist)

        let payload = ModeReceiptAugmentor.attachMode(to: ["scope": "test"], modeState: state)

        #expect(payload["scope"] as? String == "test")
        #expect(payload["mode"] as? String == CryptoMode.assist.rawValue)
    }
}
