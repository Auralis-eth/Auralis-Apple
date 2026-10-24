import Foundation
@testable import ReceiptStorage
import Security
import Testing

/// The two real Keychain implementations, which every other suite replaces with an in-memory double.
///
/// That left the actual query construction unverified, and the failure mode is silent rather than
/// loud: a wrong attribute key in ``KeychainReceiptIntegrityHeadStore/loadAllHeads()`` would make
/// every anchor invisible, so every account would report "No local integrity anchor exists", the
/// whole ledger would quietly drop to `.unattested` — which `isValid` accepts — and nothing would
/// fail. The anchors are the durable half of the tamper-evidence; they need at least one test that
/// touches the real thing.
///
/// These run against the data-protection keychain under *namespaced* service names — never the
/// production ones, because each test starts by clearing everything — and are
/// gated on whether the host can reach it at all — see ``keychainIsAvailable()``. A bare `swift test`
/// binary cannot, so on this repo's host they *skip*; they are not a substitute for the in-memory
/// coverage, they are the one place the real API is touched when the host allows it.
struct KeychainReceiptStoreTests {
    /// Whether this process can use the keychain, decided by trying rather than assumed.
    ///
    /// Measured on this repo's macOS host: a bare `swift test` binary is unsigned and has no keychain
    /// access group, so `SecItemAdd` returns `errSecMissingEntitlement` (-34018) and these tests are
    /// skipped rather than run. They are kept because they *do* run wherever the test host has
    /// keychain access — an xcodebuild-hosted run or a signed CI image — and because the alternative
    /// is that the durable half of the tamper-evidence has no test against the real API anywhere.
    static func keychainIsAvailable() -> Bool {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "AuralisReceiptStorageAvailabilityProbe",
            kSecAttrAccount as String: "probe",
            kSecValueData as String: Data("probe".utf8),
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly as String
        ]
        #if os(macOS)
        query[kSecUseDataProtectionKeychain as String] = true
        #endif
        let status = SecItemAdd(query as CFDictionary, nil)
        defer {
            var delete: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: "AuralisReceiptStorageAvailabilityProbe"
            ]
            #if os(macOS)
            delete[kSecUseDataProtectionKeychain as String] = true
            #endif
            SecItemDelete(delete as CFDictionary)
        }
        return status == errSecSuccess || status == errSecDuplicateItem
    }

    /// Round-trips anchors through the real store: save, read one, read all, overwrite, delete.
    ///
    /// The overwrite is the part worth having. `saveHead` adds, and on `errSecDuplicateItem` falls
    /// through to `SecItemUpdate` — a path every append after an account's first one takes, and one
    /// that no in-memory double models at all.
    @Test(
        "the real integrity-head store round-trips, overwrites, and clears anchors",
        .enabled(if: KeychainReceiptStoreTests.keychainIsAvailable(), "this host has no keychain access")
    )
    func keychainHeadStoreRoundTrip() async throws {
        // Namespaced, never the production service names: both tests below open with
        // `clearAllHeads()`, which against the real services would delete a co-installed Auralis
        // ledger's anchors and mark and leave it reporting tampering until a history-destroying
        // `resetAll()`.
        let store = KeychainReceiptIntegrityHeadStore(serviceNamespace: "tests")
        // Left behind by an interrupted earlier run, if any.
        try await store.clearAllHeads()

        let accountA = "0x1111111111111111111111111111111111111111"
        let accountB = "0x2222222222222222222222222222222222222222"

        try await store.saveHead("hash-a", for: accountA)
        try await store.saveHead("hash-b", for: accountB)

        #expect(try await store.loadHead(for: accountA) == "hash-a")
        // The attribute-parsing loop: `kSecAttrAccount` back out as the key, `kSecValueData` as UTF-8.
        #expect(try await store.loadAllHeads() == [accountA: "hash-a", accountB: "hash-b"])

        // The duplicate-item update path, which is what an append to an existing account exercises.
        try await store.saveHead("hash-a2", for: accountA)
        #expect(try await store.loadHead(for: accountA) == "hash-a2")
        #expect(try await store.loadAllHeads()[accountB] == "hash-b", "updating one anchor disturbed another")

        try await store.clearHead(for: accountA)
        #expect(try await store.loadHead(for: accountA) == nil)
        #expect(try await store.loadAllHeads() == [accountB: "hash-b"])

        // Absent is `nil`/`[:]`, not a throw — the distinction the restored-device path depends on.
        try await store.clearAllHeads()
        #expect(try await store.loadAllHeads().isEmpty)
        #expect(try await store.loadHead(for: accountB) == nil)
        // Clearing nothing is not an error, which is what makes a partly-failed reset re-runnable.
        try await store.clearAllHeads()
    }

    /// The ledger high-water mark against the real Keychain.
    ///
    /// Every mark assertion elsewhere runs against ``InMemoryReceiptIntegrityHeadStore``, whose
    /// monotonic `max(…)` is a *reimplementation* of the real read-then-write rather than the same
    /// code — so the `SecItemAdd` → `errSecDuplicateItem` → `SecItemUpdate` path, the decimal-string
    /// decode, and the two-service ordering in `clearAllHeads()` had no coverage against the real API.
    /// A silent regression in any of them turns the mark permanently absent, which downgrades every
    /// ledger to `.unattested` without failing anything.
    @Test(
        "the real head store round-trips the ledger high-water mark and keeps it out of the anchors",
        .enabled(if: KeychainReceiptStoreTests.keychainIsAvailable(), "this host has no keychain access")
    )
    func keychainLedgerHighWaterMarkRoundTrip() async throws {
        // Namespaced, never the production service names: both tests below open with
        // `clearAllHeads()`, which against the real services would delete a co-installed Auralis
        // ledger's anchors and mark and leave it reporting tampering until a history-destroying
        // `resetAll()`.
        let store = KeychainReceiptIntegrityHeadStore(serviceNamespace: "tests")
        try await store.clearAllHeads()

        // Absent is `nil`, not a throw — the distinction the restored-device path depends on.
        #expect(try await store.loadLedgerHighWaterMark() == nil)

        // The add path, then the duplicate-item update path that every later raise takes.
        try await store.saveLedgerHighWaterMark(1)
        #expect(try await store.loadLedgerHighWaterMark() == 1)
        try await store.saveLedgerHighWaterMark(42)
        #expect(try await store.loadLedgerHighWaterMark() == 42)

        // Monotonic in the real implementation, not just in the double.
        try await store.saveLedgerHighWaterMark(7)
        #expect(try await store.loadLedgerHighWaterMark() == 42, "the real store let the mark fall back")

        // The separate service is what keeps the mark from being read back as an account anchor —
        // which `verifyIntegrity()` would report as a protected head with no receipts, i.e. tampering.
        let account = "0x1111111111111111111111111111111111111111"
        try await store.saveHead("hash-a", for: account)
        #expect(try await store.loadAllHeads() == [account: "hash-a"])
        #expect(try await store.loadLedgerHighWaterMark() == 42, "the anchor write disturbed the mark")

        // And `clearAllHeads()` has to clear both services, or an honest `resetAll()` leaves a mark
        // over zero rows and reads as a ledger that lost everything it had.
        try await store.clearAllHeads()
        #expect(try await store.loadAllHeads().isEmpty)
        #expect(try await store.loadLedgerHighWaterMark() == nil, "reset left the mark behind")
    }

    /// The envelope-version floor against the real Keychain.
    ///
    /// This item carries a *verdict*, unlike the mark beside it: a row declaring a version above the
    /// floor is `.tampered`, because raising that column is what disables the chain-hash recomputation
    /// and a store-only attacker must not be able to license that themselves. So the two failure
    /// directions both matter and both are real-API-specific — a floor that silently fails to persist
    /// leaves every ledger in the permissive state the bypass needed, and a floor that fails to clear
    /// on reset is a stale value vouching for versions nothing here wrote.
    ///
    /// It shares a service with the mark and differs only by account name, which is the part most
    /// worth touching the real `SecItem` API for: an attribute mistake that collapsed the two would
    /// make one silently overwrite the other, and no in-memory double models that at all.
    @Test(
        "the real head store round-trips the envelope-version floor and keeps it apart from the mark",
        .enabled(if: KeychainReceiptStoreTests.keychainIsAvailable(), "this host has no keychain access")
    )
    func keychainEnvelopeVersionFloorRoundTrip() async throws {
        let store = KeychainReceiptIntegrityHeadStore(serviceNamespace: "tests")
        try await store.clearAllHeads()

        // Absent is `nil`, not a throw, and absent is the permissive case — so this distinction is
        // the one the whole concession turns on.
        #expect(try await store.loadHighestEnvelopeVersion() == nil)

        // Add, then the duplicate-item update path every later raise takes.
        try await store.saveHighestEnvelopeVersion(1)
        #expect(try await store.loadHighestEnvelopeVersion() == 1)
        try await store.saveHighestEnvelopeVersion(3)
        #expect(try await store.loadHighestEnvelopeVersion() == 3)

        // Monotonic in the real implementation, not only in the double: a floor that could fall would
        // let a downgrade lower it and re-open the concession it exists to bound.
        try await store.saveHighestEnvelopeVersion(2)
        #expect(try await store.loadHighestEnvelopeVersion() == 3, "the real store let the floor fall back")

        // Separate accounts inside one service: neither scalar may disturb the other, and neither may
        // appear in the anchor set — a protected head with no receipts reads as tampering.
        try await store.saveLedgerHighWaterMark(42)
        #expect(try await store.loadHighestEnvelopeVersion() == 3, "the mark write disturbed the floor")
        #expect(try await store.loadLedgerHighWaterMark() == 42, "the floor write disturbed the mark")
        #expect(try await store.loadAllHeads().isEmpty, "a ledger scalar came back as an account anchor")

        // And the reset clears it. `performResetAll()` re-records the current version immediately
        // afterwards, precisely because *absent* is permissive rather than neutral — but this level
        // has to actually delete it, or that re-record would be writing over a stale higher value.
        try await store.clearAllHeads()
        #expect(try await store.loadHighestEnvelopeVersion() == nil, "reset left the floor behind")
        #expect(try await store.loadLedgerHighWaterMark() == nil)
    }

    /// The signing key store, including the first-mint refusal added so a race cannot clobber a key
    /// that has already signed rows.
    @Test(
        "the real signing-key store round-trips and refuses to overwrite on a first mint",
        .enabled(if: KeychainReceiptStoreTests.keychainIsAvailable(), "this host has no keychain access")
    )
    func keychainSigningKeyStoreRoundTrip() async throws {
        let store = KeychainReceiptSigningKeyStore()
        let account = "receipt-storage-test-p256"
        try await store.deleteKeyForTesting(account: account)

        #expect(try await store.loadKey(account: account) == nil)

        let first = Data("first-key-material".utf8)
        try await store.saveKey(first, account: account, replacingExisting: false)
        #expect(try await store.loadKey(account: account) == first)

        // A first mint that finds an item already there must fail rather than replace it: the item
        // belongs to a resolution that won a race, and its key may already have signed receipts.
        let second = Data("second-key-material".utf8)
        await #expect(throws: ReceiptSigningKeyStoreError.existingKeyWouldBeOverwritten(account: account)) {
            try await store.saveKey(second, account: account, replacingExisting: false)
        }
        #expect(try await store.loadKey(account: account) == first, "a refused save still overwrote the key")

        // A rotation, which has written off the stored blob, does replace it.
        try await store.saveKey(second, account: account, replacingExisting: true)
        #expect(try await store.loadKey(account: account) == second)

        try await store.deleteKeyForTesting(account: account)
        #expect(try await store.loadKey(account: account) == nil)
    }
}
