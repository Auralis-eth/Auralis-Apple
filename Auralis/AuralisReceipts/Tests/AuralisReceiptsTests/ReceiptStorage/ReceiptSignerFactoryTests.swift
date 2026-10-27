import CryptoKit
import Foundation
@testable import AuralisReceipts
import AuralisRuntime
import Security
import Testing

struct ReceiptSignerFactoryTests {
    @Test("software signing identity is restored across signer instances")
    func softwareIdentityPersists() async throws {
        let store = InMemorySigningKeyStore()
        let first = DeviceReceiptSigner(keyStore: store, secureEnclaveAvailable: false)
        let second = DeviceReceiptSigner(keyStore: store, secureEnclaveAvailable: false)

        let firstSignature = try await first.sign("first")
        let secondSignature = try await second.sign("second")

        #expect(firstSignature.publicKeyRepresentation == secondSignature.publicKeyRepresentation)
        #expect(second.verify("second", signature: secondSignature))
        #expect(await store.saveCount == 1)
    }

    @Test("concurrent first writes resolve to a single signing identity")
    func concurrentFirstWritesShareOneIdentity() async throws {
        // The first-ever receipt write on a fresh install, hit concurrently: one shared
        // `DeviceReceiptSigner` (there is one per model container) and an empty key store. Without
        // single-flight resolution the actor's reentrancy across the key-store `await` let each task
        // mint and persist its own key, so the chain's device identity forked on the very first
        // receipts while each signature still verified against its own embedded public key.
        let store = InMemorySigningKeyStore()
        let signer = DeviceReceiptSigner(keyStore: store, secureEnclaveAvailable: false)

        let signatures = try await withThrowingTaskGroup(of: ReceiptSignature.self) { group in
            for index in 0..<8 {
                group.addTask { try await signer.sign("receipt-\(index)") }
            }
            return try await group.reduce(into: [ReceiptSignature]()) { $0.append($1) }
        }

        let identities = Set(signatures.map(\.publicKeyRepresentation))
        #expect(identities.count == 1)
        #expect(await store.saveCount == 1)
        // The persisted identity is the one that actually signed, not a discarded sibling.
        #expect(try await signer.publicKeyRepresentation() == identities.first)
    }

    @Test("Keychain load failure fails closed without minting a replacement identity")
    func loadFailureDoesNotRotateIdentity() async {
        let expected = ReceiptSigningKeyStoreError.operationFailed(
            operation: "load",
            status: errSecInteractionNotAllowed
        )
        let store = InMemorySigningKeyStore(loadError: expected)
        let signer = DeviceReceiptSigner(keyStore: store, secureEnclaveAvailable: false)

        await #expect(throws: expected) {
            _ = try await signer.sign("receipt")
        }
        #expect(await store.saveCount == 0)
    }

    @Test("Keychain save failure prevents use of an unpersisted identity")
    func saveFailurePreventsSigning() async {
        let expected = ReceiptSigningKeyStoreError.operationFailed(
            operation: "save",
            status: errSecNotAvailable
        )
        let store = InMemorySigningKeyStore(saveError: expected)
        let signer = DeviceReceiptSigner(keyStore: store, secureEnclaveAvailable: false)

        await #expect(throws: expected) {
            _ = try await signer.sign("receipt")
        }
    }

    /// Unrestorable material is the one load outcome that must *not* fail closed. A Secure Enclave
    /// key is device-bound, so a Keychain item that survives a restore-in-place while its Enclave key
    /// does not can never be reconstructed — throwing failed every append for the life of the
    /// install, with reinstalling (destroying the ledger) as the only exit.
    @Test("corrupt persisted signing material rotates forward instead of bricking appends")
    func corruptKeyRotatesForward() async throws {
        let corrupt = Data("not-a-p256-key".utf8)
        let store = InMemorySigningKeyStore(values: ["software-p256": corrupt])
        let signer = DeviceReceiptSigner(keyStore: store, secureEnclaveAvailable: false)

        let signature = try await signer.sign("receipt")
        #expect(signer.verify("receipt", signature: signature))

        // Rotated onto a usable identity, and the corrupt blob was replaced rather than left to be
        // rediscovered on the next launch.
        let persisted = try #require(await store.value(forAccount: "software-p256"))
        #expect(persisted != corrupt)
        #expect(await store.saveCount == 1)

        // Forward only: the replacement is a key that has never signed anything, so rows already in
        // the ledger read as `.unattested` rather than tampered.
        let restored = DeviceReceiptSigner(keyStore: store, secureEnclaveAvailable: false)
        #expect(try await restored.publicKeyRepresentation() == signature.publicKeyRepresentation)
    }

    /// The rotation above must not become the answer to a Keychain that is merely unavailable.
    @Test("an unreadable Keychain still fails closed rather than rotating")
    func unreadableKeychainDoesNotRotate() async {
        let store = InMemorySigningKeyStore(
            values: ["software-p256": Data("not-a-p256-key".utf8)],
            loadError: .operationFailed(operation: "load", status: errSecInteractionNotAllowed)
        )
        let signer = DeviceReceiptSigner(keyStore: store, secureEnclaveAvailable: false)

        await #expect(throws: ReceiptSigningKeyStoreError.self) {
            _ = try await signer.sign("receipt")
        }
        #expect(await store.saveCount == 0)
    }

    // MARK: - The Secure Enclave branch

    // Everything above runs with `secureEnclaveAvailable: false`, which is the simulator's answer —
    // so until the enclave signer became injectable, the branch that actually runs on device, and the
    // irreversible key-rotation decision inside it, had no coverage at all.

    @Test("the Secure Enclave identity is restored from its persisted blob")
    func enclaveIdentityPersists() async throws {
        let store = InMemorySigningKeyStore()
        let builder = StubEnclaveSignerBuilder()

        let first = try await DeviceReceiptSigner(
            keyStore: store,
            enclaveBuilder: builder,
            secureEnclaveAvailable: true
        ).sign("first")
        let second = try await DeviceReceiptSigner(
            keyStore: store,
            enclaveBuilder: builder,
            secureEnclaveAvailable: true
        ).sign("second")

        #expect(first.publicKeyRepresentation == second.publicKeyRepresentation)
        // One mint, one save: the second instance restored rather than rotating.
        #expect(await builder.makeCount == 1)
        #expect(await builder.restoreCount == 1)
        #expect(await store.saveCount == 1)
        // The blob under the Enclave account, not the software one.
        #expect(await store.value(forAccount: "secure-enclave-p256") != nil)
        #expect(await store.value(forAccount: "software-p256") == nil)
    }

    /// A blob this Enclave cannot unwrap is permanent — the key is device-bound, so an item that
    /// survives a restore-in-place while its Enclave key does not can never be reconstructed. Refusing
    /// to rotate there failed every append for the life of the install.
    @Test("a Secure Enclave blob that cannot be unwrapped rotates forward")
    func unrestorableEnclaveBlobRotatesForward() async throws {
        let store = InMemorySigningKeyStore(values: ["secure-enclave-p256": Data("stale-blob".utf8)])
        let builder = StubEnclaveSignerBuilder(restoreError: CryptoKitError.authenticationFailure)
        let signer = DeviceReceiptSigner(
            keyStore: store,
            enclaveBuilder: builder,
            secureEnclaveAvailable: true
        )

        let signature = try await signer.sign("receipt")
        #expect(signer.verify("receipt", signature: signature))
        // Replaced, so the rotation happens once rather than being rediscovered on every launch.
        #expect(await store.value(forAccount: "secure-enclave-p256") != Data("stale-blob".utf8))
        #expect(await builder.makeCount == 1)
    }

    /// The failure the previous `try?` could not distinguish, and the reason it mattered.
    ///
    /// An Enclave that declines for a reason that passes — unavailable early in boot, or busy —
    /// reports `underlyingCoreCryptoError`, and rotating on that discards a perfectly good identity
    /// permanently. This has to fail the write instead, the same way an unreadable Keychain already
    /// does, and leave the stored blob exactly as it found it.
    @Test("a transient Secure Enclave failure fails the write instead of rotating the identity")
    func transientEnclaveFailureDoesNotRotate() async throws {
        let blob = Data("good-blob".utf8)
        let store = InMemorySigningKeyStore(values: ["secure-enclave-p256": blob])
        let builder = StubEnclaveSignerBuilder(
            restoreError: CryptoKitError.underlyingCoreCryptoError(error: -1)
        )
        let signer = DeviceReceiptSigner(
            keyStore: store,
            enclaveBuilder: builder,
            secureEnclaveAvailable: true
        )

        await #expect(throws: CryptoKitError.self) {
            _ = try await signer.sign("receipt")
        }
        #expect(await builder.makeCount == 0, "a transient failure minted a replacement identity")
        #expect(await store.saveCount == 0)
        #expect(await store.value(forAccount: "secure-enclave-p256") == blob)

        // And it is genuinely transient: once the Enclave answers, the stored blob's own identity
        // comes back rather than having been abandoned. Nothing cached the failure.
        await builder.clearRestoreError()
        let signature = try await signer.sign("receipt")
        #expect(signer.verify("receipt", signature: signature))
        #expect(await builder.makeCount == 0)
        #expect(await store.saveCount == 0)
        // The identity is the blob's, and it is stable — which is the part that says "restored"
        // rather than "quietly replaced with something that also works".
        let restoredKey = try await signer.publicKeyRepresentation()
        #expect(restoredKey == signature.publicKeyRepresentation)
        #expect(try await builder.restoreSigner(dataRepresentation: blob).publicKeyRepresentation() == restoredKey)
    }

    /// The bounded escape from an error the classifier cannot read.
    ///
    /// `isUnrestorableKeyMaterial` is a judgement about an opaque error domain, and the plausible
    /// mistake is the dangerous one: CryptoKit wraps most `SecKey`/CoreCrypto failures as
    /// `underlyingCoreCryptoError`, which is very likely how a genuinely lost Enclave key surfaces
    /// too. Classified transient, that failure would repeat forever and every append would fail for
    /// the life of the install — the same brick the classification exists to prevent, reached from
    /// the other side. So an unclassifiable failure fails the write, but only finitely often.
    @Test("an unclassifiable Secure Enclave failure rotates after a bounded number of retries")
    func repeatedAmbiguousEnclaveFailureEventuallyRotates() async throws {
        let blob = Data("good-blob".utf8)
        let store = InMemorySigningKeyStore(values: ["secure-enclave-p256": blob])
        let builder = StubEnclaveSignerBuilder(
            restoreError: CryptoKitError.underlyingCoreCryptoError(error: -1)
        )
        let signer = DeviceReceiptSigner(
            keyStore: store,
            enclaveBuilder: builder,
            secureEnclaveAvailable: true
        )

        // Fails closed while the failure could still be a passing condition.
        for _ in 0..<2 {
            await #expect(throws: CryptoKitError.self) {
                _ = try await signer.sign("receipt")
            }
            #expect(await builder.makeCount == 0)
        }

        // Then gives up deciding and recovers the install rather than refusing forever.
        let signature = try await signer.sign("receipt")
        #expect(signer.verify("receipt", signature: signature))
        #expect(await builder.makeCount == 1)
        #expect(await store.value(forAccount: "secure-enclave-p256") != blob)
    }

    /// A resolution that succeeds ends the retry budget outright, rather than resetting it.
    ///
    /// This replaces a test that asserted "a success between transient failures *resets* the budget"
    /// and proved nothing: it measured the reset by constructing a **fresh** `DeviceReceiptSigner`,
    /// whose counter is zero by construction, so it passed identically with the source's `= 0` resets
    /// deleted — which is what they were, unreachable. `resolveSigner()` caches the resolved identity,
    /// so the Enclave restore path never runs twice on one instance and there is no second failure for
    /// a reset to matter to. This pins the behaviour that actually holds.
    @Test("a resolved identity is cached, so later Enclave failures cannot spend the retry budget")
    func successEndsTheAmbiguousFailureBudget() async throws {
        let blob = Data("good-blob".utf8)
        let store = InMemorySigningKeyStore(values: ["secure-enclave-p256": blob])
        let builder = StubEnclaveSignerBuilder(
            restoreError: CryptoKitError.underlyingCoreCryptoError(error: -1)
        )
        let signer = DeviceReceiptSigner(
            keyStore: store,
            enclaveBuilder: builder,
            secureEnclaveAvailable: true
        )

        // One of the three spent on a failure that could still be transient.
        await #expect(throws: CryptoKitError.self) {
            _ = try await signer.sign("receipt")
        }
        await builder.clearRestoreError()
        let resolved = try await signer.sign("receipt")

        // The Enclave starts declining again. It no longer reaches the counter — or the builder at
        // all — because this signer has resolved: the identity stays the blob's however many further
        // writes arrive, and nothing rotates.
        await builder.setRestoreError(CryptoKitError.underlyingCoreCryptoError(error: -1))
        for index in 0..<4 {
            let later = try await signer.sign("receipt-\(index)")
            #expect(later.publicKeyRepresentation == resolved.publicKeyRepresentation)
        }
        #expect(await builder.restoreCount == 1, "a cached identity re-entered Enclave resolution")
        #expect(await builder.makeCount == 0)
        #expect(await store.saveCount == 0)
    }

    @Test("a Secure Enclave that cannot mint a key fails the write")
    func enclaveMintFailureFailsClosed() async {
        let store = InMemorySigningKeyStore()
        let builder = StubEnclaveSignerBuilder(makeError: CryptoKitError.underlyingCoreCryptoError(error: -2))
        let signer = DeviceReceiptSigner(
            keyStore: store,
            enclaveBuilder: builder,
            secureEnclaveAvailable: true
        )

        await #expect(throws: CryptoKitError.self) {
            _ = try await signer.sign("receipt")
        }
        // The Enclave really was asked. Asserted through `makeAttemptCount` rather than `makeCount`,
        // which counts only *successful* mints and so cannot distinguish "minting failed" from
        // "minting was never attempted" in a case where the mint is rigged to throw.
        #expect(await builder.makeAttemptCount == 1)
        // No silent fallback to a software key: the ledger would then be attested by an identity
        // weaker than the one it claims, with nothing recording the downgrade.
        #expect(await store.value(forAccount: "software-p256") == nil)
        #expect(await store.saveCount == 0)
    }
}

/// Stands in for the Secure Enclave. Emits ordinary software P-256 identities, because the branch
/// under test is the restore/rotate decision, not the Enclave's cryptography — which is identical
/// either way, since both emit standard P-256 signatures and public keys.
private actor StubEnclaveSignerBuilder: SecureEnclaveReceiptSignerBuilding {
    private var restoreError: Error?
    private let makeError: Error?
    private var mintedByBlob: [Data: SoftwareReceiptSigner] = [:]
    /// Successful mints.
    private(set) var makeCount = 0
    /// Mints *attempted*, incremented before `makeError` is thrown.
    ///
    /// Separate from ``makeCount`` so a case that rigs the mint to fail can still assert the Enclave
    /// was asked. With one counter incremented after the throw, `makeCount == 0` in such a case is
    /// true no matter what the code under test does — an assertion that cannot fail.
    private(set) var makeAttemptCount = 0
    /// Successful restores.
    private(set) var restoreCount = 0

    init(restoreError: Error? = nil, makeError: Error? = nil) {
        self.restoreError = restoreError
        self.makeError = makeError
    }

    func clearRestoreError() {
        restoreError = nil
    }

    func setRestoreError(_ error: Error) {
        restoreError = error
    }

    func makeSigner() throws -> (signer: any ReceiptSigning, keyDataRepresentation: Data) {
        makeAttemptCount += 1
        if let makeError {
            throw makeError
        }
        makeCount += 1
        let key = P256.Signing.PrivateKey()
        // The blob stands in for the Enclave-encrypted representation: opaque to everyone but this
        // builder, which is exactly the property that makes it unrestorable elsewhere.
        let blob = Data("enclave-blob-\(makeCount)".utf8)
        mintedByBlob[blob] = SoftwareReceiptSigner(privateKey: key)
        return (SoftwareReceiptSigner(privateKey: key), blob)
    }

    func restoreSigner(dataRepresentation: Data) throws -> any ReceiptSigning {
        if let restoreError {
            throw restoreError
        }
        restoreCount += 1
        if let signer = mintedByBlob[dataRepresentation] {
            return signer
        }
        // A blob this stub did not mint still restores, deterministically. Failing here instead would
        // conflate "the Enclave declined" with "this blob is unusable" — the exact distinction under
        // test — and turn a transient-failure case into a silent rotation.
        let signer = SoftwareReceiptSigner()
        mintedByBlob[dataRepresentation] = signer
        return signer
    }
}

private actor InMemorySigningKeyStore: ReceiptSigningKeyStoring {
    private var values: [String: Data]
    private let loadError: ReceiptSigningKeyStoreError?
    private let saveError: ReceiptSigningKeyStoreError?
    private(set) var saveCount = 0

    init(
        values: [String: Data] = [:],
        loadError: ReceiptSigningKeyStoreError? = nil,
        saveError: ReceiptSigningKeyStoreError? = nil
    ) {
        self.values = values
        self.loadError = loadError
        self.saveError = saveError
    }

    func value(forAccount account: String) -> Data? {
        values[account]
    }

    func loadKey(account: String) throws -> Data? {
        if let loadError {
            throw loadError
        }
        return values[account]
    }

    func saveKey(_ data: Data, account: String, replacingExisting: Bool) throws {
        if let saveError {
            throw saveError
        }
        values[account] = data
        saveCount += 1
    }
}
