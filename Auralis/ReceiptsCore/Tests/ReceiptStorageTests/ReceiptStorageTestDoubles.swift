import Foundation
import ReceiptsCore
@testable import ReceiptStorage
import RuntimeCore

/// Doubles shared across the suites in this target.
///
/// They live here because they were duplicated: `SlowSigner` existed twice with different sleep
/// durations, so a suite could be tuned without the other noticing, and each copy was private to its
/// file. One definition, one behaviour.

/// Widens the window inside `append` between reading the ledger and inserting the row, so a
/// concurrent verify or reset actually lands in it rather than passing by chance.
struct SlowSigner: ReceiptSigning {
    private let inner = SoftwareReceiptSigner()
    private let delay: Duration

    /// - Parameter delay: How long `sign(_:)` suspends. The reentrancy window exists regardless; this
    ///   only makes a concurrent caller land in it reliably.
    init(delay: Duration = .milliseconds(10)) {
        self.delay = delay
    }

    func sign(_ message: String) async throws -> ReceiptSignature {
        try? await Task.sleep(for: delay)
        return try await inner.sign(message)
    }

    func publicKeyRepresentation() async throws -> Data {
        try await inner.publicKeyRepresentation()
    }

    nonisolated func verify(_ message: String, signature: ReceiptSignature) -> Bool {
        SoftwareReceiptSigner.verifyStatic(message, signature: signature)
    }
}

/// Signs normally until revoked, then behaves like a signer whose Keychain has locked: it can
/// neither sign nor state its own public key.
actor RevocableSigner: ReceiptSigning {
    private let inner = SoftwareReceiptSigner()
    private var isRevoked = false

    enum Failure: Error {
        case keychainLocked
    }

    func revoke() {
        isRevoked = true
    }

    func sign(_ message: String) async throws -> ReceiptSignature {
        guard !isRevoked else { throw Failure.keychainLocked }
        return try await inner.sign(message)
    }

    func publicKeyRepresentation() async throws -> Data {
        guard !isRevoked else { throw Failure.keychainLocked }
        return try await inner.publicKeyRepresentation()
    }

    nonisolated func verify(_ message: String, signature: ReceiptSignature) -> Bool {
        SoftwareReceiptSigner.verifyStatic(message, signature: signature)
    }
}

/// Signs with one identity, then — on ``rotate()`` — reports and uses a *different* one, exactly as
/// `DeviceReceiptSigner.secureEnclaveSigner()` does when it writes off an unrestorable Enclave blob.
///
/// Distinct from `RevocableSigner`, and the distinction is the point: a revoked signer cannot answer
/// at all, so `verifyIntegrity()` treats every identity check as "unknown". A rotated signer answers
/// perfectly well — it just names a key that signed none of the existing rows, which leaves
/// `currentIdentitySeen` empty for a device that has a working signer.
actor RotatingSigner: ReceiptSigning {
    private let original = SoftwareReceiptSigner()
    private var replacement: SoftwareReceiptSigner?

    func rotate() {
        replacement = SoftwareReceiptSigner()
    }

    private var active: SoftwareReceiptSigner {
        replacement ?? original
    }

    func sign(_ message: String) async throws -> ReceiptSignature {
        try await active.sign(message)
    }

    func publicKeyRepresentation() async throws -> Data {
        try await active.publicKeyRepresentation()
    }

    nonisolated func verify(_ message: String, signature: ReceiptSignature) -> Bool {
        SoftwareReceiptSigner.verifyStatic(message, signature: signature)
    }
}

/// A head store whose *reads* fail, which no other double here does.
///
/// Every existing double fails a write (`saveHead`, `clearAllHeads`), so the locked-Keychain read —
/// `errSecInteractionNotAllowed` out of `loadAllHeads()`, the single most likely Keychain failure in
/// the field — had no coverage at all, and `performVerifyIntegrity()` read the anchors with a plain
/// `try` for exactly as long.
actor FailingLoadAllReceiptIntegrityHeadStore: ReceiptIntegrityHeadStoring {
    private var heads: [String: String] = [:]
    private var ledgerHighWaterMark: Int?
    private var highestEnvelopeVersion: Int?
    private let error: ReceiptIntegrityHeadStoreError
    private var isFailing: Bool

    init(
        error: ReceiptIntegrityHeadStoreError = .operationFailed(
            operation: "loadAll",
            status: errSecInteractionNotAllowed
        ),
        isFailingFromTheStart: Bool = true
    ) {
        self.error = error
        self.isFailing = isFailingFromTheStart
    }

    /// Whether *writes* fail too. Separate from the read flag on purpose: the locked-Keychain read
    /// case needs anchors that were written successfully by a working device and only then became
    /// unreadable, while the append-compensation case needs the write itself to fail.
    private var isFailingSaves = false

    /// Lets a test write anchors normally and only then lock the Keychain, which is the real ordering:
    /// the rows and anchors were written by a working device.
    func startFailing() {
        isFailing = true
    }

    func stopFailing() {
        isFailing = false
    }

    func startFailingSaves() {
        isFailingSaves = true
    }

    func stopFailingSaves() {
        isFailingSaves = false
    }

    func loadHead(for accountKey: String) throws -> String? {
        if isFailing { throw error }
        return heads[accountKey]
    }

    func loadAllHeads() throws -> [String: String] {
        if isFailing { throw error }
        return heads
    }

    func saveHead(_ hash: String, for accountKey: String) throws {
        if isFailingSaves { throw error }
        heads[accountKey] = hash
    }

    func clearHead(for accountKey: String) {
        heads.removeValue(forKey: accountKey)
    }

    func clearAllHeads() {
        heads.removeAll()
        ledgerHighWaterMark = nil
        highestEnvelopeVersion = nil
    }

    /// Fails under the *read* flag, alongside `loadAllHeads()`, because in the field both are the
    /// same locked Keychain — a double that could produce a mark while refusing the anchors would
    /// exercise a state the real store cannot reach.
    func loadLedgerHighWaterMark() throws -> Int? {
        if isFailing { throw error }
        return ledgerHighWaterMark
    }

    func saveLedgerHighWaterMark(_ sequenceID: Int) throws {
        if isFailingSaves { throw error }
        ledgerHighWaterMark = max(ledgerHighWaterMark ?? 0, sequenceID)
    }

    /// Fails under the *read* flag alongside the mark and the anchors, because in the field all three
    /// are the same locked Keychain. That matters for what this double proves: an unreadable floor
    /// falls back to the permissive concession, so a suite using this store is exercising the lenient
    /// path rather than the strict one.
    func loadHighestEnvelopeVersion() throws -> Int? {
        if isFailing { throw error }
        return highestEnvelopeVersion
    }

    func saveHighestEnvelopeVersion(_ version: Int) throws {
        if isFailingSaves { throw error }
        highestEnvelopeVersion = max(highestEnvelopeVersion ?? 0, version)
    }
}
