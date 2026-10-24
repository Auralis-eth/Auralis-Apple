import CryptoKit
import Foundation
import OSLog
import RuntimeCore
import Security

public enum ReceiptSigningKeyStoreError: Error, Equatable, Sendable {
    case operationFailed(operation: String, status: OSStatus)
    /// The Keychain returned an item for this account whose value is not `Data`. Its own case rather
    /// than an `operationFailed(operation: "load-invalid-data", status: errSecParam)`, which made
    /// `operation` double as an error *kind* and attached a fabricated `OSStatus` the Keychain never
    /// produced.
    case invalidStoredKeyData(account: String)
    /// A first mint found an item already present for this account, so someone else resolved an
    /// identity first. Refused rather than overwritten — see
    /// ``ReceiptSigningKeyStoring/saveKey(_:account:replacingExisting:)``.
    case existingKeyWouldBeOverwritten(account: String)
}

protocol ReceiptSigningKeyStoring: Sendable {
    func loadKey(account: String) async throws -> Data?
    /// - Parameter replacingExisting: Whether an item already stored for `account` may be overwritten.
    ///
    ///   The two callers need opposite answers and the distinction is load-bearing. The *rotation*
    ///   path has just written off a blob as unrestorable and must overwrite it, or the rotation is
    ///   rediscovered on every launch. A *first mint* is only reached after `loadKey` returned `nil`,
    ///   so finding an item there means another resolution won a race — and overwriting it would
    ///   destroy a key that has already signed rows, making every one of them permanently
    ///   unattestable. An unconditional overwrite served both, which was safe only because exactly
    ///   one `DeviceReceiptSigner` exists per container today; `ReceiptSignerFactory.deviceSigner()`
    ///   is public and returns a fresh instance per call, so that was one call site away from being
    ///   wrong.
    func saveKey(_ data: Data, account: String, replacingExisting: Bool) async throws
}

/// Builds Secure Enclave signers, so the on-device branch of ``DeviceReceiptSigner`` is reachable
/// from a test.
///
/// Without this the branch called the concrete `SecureEnclaveReceiptSigner` initializers directly,
/// which means it could only run where a real Enclave exists — not the simulator, not CI. Every case
/// in the factory's test suite passed `secureEnclaveAvailable: false`, so the path that actually runs
/// in production, including its key-rotation decision, had no coverage at all.
///
/// The requirements are `async` so an actor can conform. The live implementation never suspends —
/// the Enclave calls are synchronous — but a stub that records what it was asked needs isolated
/// state, and ``ReceiptSigningKeyStoring`` alongside it is async for the same reason.
protocol SecureEnclaveReceiptSignerBuilding: Sendable {
    func makeSigner() async throws -> (signer: any ReceiptSigning, keyDataRepresentation: Data)
    func restoreSigner(dataRepresentation: Data) async throws -> any ReceiptSigning
}

struct LiveSecureEnclaveReceiptSignerBuilder: SecureEnclaveReceiptSignerBuilding {
    func makeSigner() throws -> (signer: any ReceiptSigning, keyDataRepresentation: Data) {
        let signer = try SecureEnclaveReceiptSigner()
        return (signer, signer.keyDataRepresentation)
    }

    func restoreSigner(dataRepresentation: Data) throws -> any ReceiptSigning {
        try SecureEnclaveReceiptSigner(dataRepresentation: dataRepresentation)
    }
}

/// Serializes every receipt-signing Keychain operation away from the main actor and preserves all
/// `OSStatus` failures. A locked or unavailable Keychain is a write failure, never permission to
/// mint a replacement signing identity.
actor KeychainReceiptSigningKeyStore: ReceiptSigningKeyStoring {
    private let service = "AuralisReceiptSigningKey"

    func loadKey(account: String) throws -> Data? {
        var query = baseQuery(account: account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        switch status {
        case errSecSuccess:
            guard let data = result as? Data else {
                throw ReceiptSigningKeyStoreError.invalidStoredKeyData(account: account)
            }
            return data
        case errSecItemNotFound:
            return nil
        default:
            throw ReceiptSigningKeyStoreError.operationFailed(operation: "load", status: status)
        }
    }

    func saveKey(_ data: Data, account: String, replacingExisting: Bool) throws {
        var addQuery = baseQuery(account: account)
        addQuery[kSecValueData as String] = data
        addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly as String
        let addStatus = SecItemAdd(addQuery as CFDictionary, nil)

        switch addStatus {
        case errSecSuccess:
            return
        case errSecDuplicateItem:
            // Fails closed rather than clobbering. The caller that reaches here without asking for a
            // replacement has already seen `loadKey` return `nil`, so the item appeared underneath it
            // and belongs to an identity that may already have signed rows. Throwing fails this one
            // write; the next attempt's `loadKey` finds the winner's key and restores it.
            guard replacingExisting else {
                throw ReceiptSigningKeyStoreError.existingKeyWouldBeOverwritten(account: account)
            }
            let updateStatus = SecItemUpdate(
                baseQuery(account: account) as CFDictionary,
                [
                    kSecValueData as String: data,
                    // Re-asserted on update, not only on add. An item that somehow exists with weaker
                    // accessibility would otherwise keep it for the life of the install, and
                    // `ThisDeviceOnly` is the property that stops a signing key riding a backup onto
                    // another device.
                    kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly as String
                ] as CFDictionary
            )
            guard updateStatus == errSecSuccess else {
                throw ReceiptSigningKeyStoreError.operationFailed(operation: "update", status: updateStatus)
            }
        default:
            throw ReceiptSigningKeyStoreError.operationFailed(operation: "save", status: addStatus)
        }
    }

    #if DEBUG
    /// Removes an item so the real-Keychain tests can start from a known state. There is deliberately
    /// no production delete: nothing in this package is entitled to destroy a signing identity, since
    /// doing so makes every receipt it signed permanently unattestable.
    func deleteKeyForTesting(account: String) throws {
        let status = SecItemDelete(baseQuery(account: account) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw ReceiptSigningKeyStoreError.operationFailed(operation: "delete", status: status)
        }
    }
    #endif

    private func baseQuery(account: String) -> [String: Any] {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        #if os(macOS)
        query[kSecUseDataProtectionKeychain as String] = true
        #endif
        return query
    }
}

/// Lazily restores the device signing identity on the first receipt write.
///
/// Simultaneous first writes are collapsed onto a single identity by the in-flight `resolution`
/// task, not by actor isolation on its own — see the note on that property.
actor DeviceReceiptSigner: ReceiptSigning {
    private static let logger = Logger(subsystem: "Auralis", category: "ReceiptSigner")

    /// How many unclassifiable Enclave restore failures are treated as transient before the blob is
    /// written off as unrestorable.
    ///
    /// Small on purpose. Each attempt is a failed receipt write, so this is the number of governed
    /// actions that go unrecorded before the device recovers its ability to sign. Counted per signer
    /// instance, which in practice means per process, and a genuinely transient condition clears
    /// inside the budget: the retry that succeeds caches its identity and no further attempt is ever
    /// made. Deliberately not persisted — durable state here would itself need something to reset it,
    /// and nothing is better placed to re-judge the blob than a fresh process.
    private static let ambiguousEnclaveFailureLimit = 3

    private let enclaveAccount = "secure-enclave-p256"
    private let softwareAccount = "software-p256"
    private let keyStore: any ReceiptSigningKeyStoring
    private let enclaveBuilder: any SecureEnclaveReceiptSignerBuilding
    private let secureEnclaveAvailable: Bool
    private var resolvedSigner: (any ReceiptSigning)?
    /// The in-flight first resolution, so concurrent first writes await *one* identity instead of
    /// each minting their own. An actor alone does not give this: `resolveSigner()` awaits the key
    /// store, and the actor is reentrant across that suspension, so a plain
    /// check-nil-then-await-then-assign lets a second caller past the nil check while the first is
    /// still loading. Cleared on completion so a failed resolution is retried rather than cached.
    private var resolution: Task<any ReceiptSigning, Error>?
    /// Enclave restore failures this signer could not classify.
    ///
    /// Never reset, because it cannot need to be. A resolution that succeeds caches its identity in
    /// ``resolvedSigner``, so ``secureEnclaveSigner()`` never runs a second time on this instance —
    /// the counter only ever advances across *failed* resolutions, and a success ends its life
    /// outright. It previously carried `= 0` resets on both success paths and a doc claiming "reset on
    /// any success"; the caching made those unreachable, so the code described a policy it did not
    /// implement.
    private var ambiguousEnclaveFailures = 0

    init(
        keyStore: any ReceiptSigningKeyStoring = KeychainReceiptSigningKeyStore(),
        enclaveBuilder: any SecureEnclaveReceiptSignerBuilding = LiveSecureEnclaveReceiptSignerBuilder(),
        secureEnclaveAvailable: Bool = SecureEnclaveReceiptSigner.isAvailable
    ) {
        self.keyStore = keyStore
        self.enclaveBuilder = enclaveBuilder
        self.secureEnclaveAvailable = secureEnclaveAvailable
    }

    func sign(_ message: String) async throws -> ReceiptSignature {
        let signer = try await resolveSigner()
        return try await signer.sign(message)
    }

    func publicKeyRepresentation() async throws -> Data {
        let signer = try await resolveSigner()
        return try await signer.publicKeyRepresentation()
    }

    nonisolated func verify(_ message: String, signature: ReceiptSignature) -> Bool {
        SoftwareReceiptSigner.verifyStatic(message, signature: signature)
    }

    private func resolveSigner() async throws -> any ReceiptSigning {
        if let resolvedSigner {
            return resolvedSigner
        }
        // Joining an in-flight resolution rather than starting a second one. The check and the
        // assignment below are not separated by an `await`, so they are atomic on this actor.
        if let resolution {
            return try await resolution.value
        }

        let task = Task<any ReceiptSigning, Error> {
            if secureEnclaveAvailable {
                return try await secureEnclaveSigner()
            }
            return try await softwareSigner()
        }
        resolution = task

        do {
            let signer = try await task.value
            resolvedSigner = signer
            resolution = nil
            return signer
        } catch {
            // A locked or unavailable Keychain must not become a permanent refusal to sign.
            resolution = nil
            throw error
        }
    }

    private func secureEnclaveSigner() async throws -> any ReceiptSigning {
        // Whether the mint below is replacing a blob this method just wrote off, as opposed to
        // creating this device's first identity. Only the former may overwrite.
        var isReplacingWrittenOffKey = false
        if let blob = try await keyStore.loadKey(account: enclaveAccount) {
            do {
                return try await enclaveBuilder.restoreSigner(dataRepresentation: blob)
            } catch {
                isReplacingWrittenOffKey = true
                // Classified before rotating, not swallowed with `try?`. The consequence below is
                // irreversible — it ends this device's ability to attest to everything it has already
                // written — so it may only follow a failure that is genuinely permanent. A `try?`
                // treated "this blob's Enclave key no longer exists" and "the Enclave did not answer
                // just now" as the same answer and burned the identity on the second one.
                if Self.isUnrestorableKeyMaterial(error) {
                    logUnrestorableKey(account: enclaveAccount, error: error)
                } else {
                    ambiguousEnclaveFailures += 1
                    guard ambiguousEnclaveFailures >= Self.ambiguousEnclaveFailureLimit else {
                        Self.logger.error(
                            "Receipt signing key '\(self.enclaveAccount, privacy: .public)' could not be restored (attempt \(self.ambiguousEnclaveFailures, privacy: .public) of \(Self.ambiguousEnclaveFailureLimit, privacy: .public)); failing this write rather than rotating: \(error.localizedDescription, privacy: .public)"
                        )
                        throw error
                    }
                    logExhaustedEnclaveRetries(error: error)
                }
            }
        }

        let created = try await enclaveBuilder.makeSigner()
        // On a rotation this overwrites the unrestorable blob through `saveKey`'s duplicate-item
        // update path, so the rotation happens once rather than on every launch. On a first mint it
        // refuses to overwrite, because an item appearing after `loadKey` returned `nil` belongs to a
        // resolution that beat this one and may already have signed rows.
        try await keyStore.saveKey(
            created.keyDataRepresentation,
            account: enclaveAccount,
            replacingExisting: isReplacingWrittenOffKey
        )
        return created.signer
    }

    private func softwareSigner() async throws -> any ReceiptSigning {
        var isReplacingWrittenOffKey = false
        if let blob = try await keyStore.loadKey(account: softwareAccount) {
            do {
                // No classification needed here, unlike the Enclave path above, and the asymmetry is
                // the point: this is pure local arithmetic over 32 bytes with no hardware and no
                // transient mode, so a throw can only mean the stored bytes are not a P-256 scalar.
                return SoftwareReceiptSigner(privateKey: try P256.Signing.PrivateKey(rawRepresentation: blob))
            } catch {
                isReplacingWrittenOffKey = true
                logUnrestorableKey(account: softwareAccount, error: error)
            }
        }

        let key = P256.Signing.PrivateKey()
        try await keyStore.saveKey(
            key.rawRepresentation,
            account: softwareAccount,
            replacingExisting: isReplacingWrittenOffKey
        )
        return SoftwareReceiptSigner(privateKey: key)
    }

    /// Whether a failure to reconstruct stored signing material is permanent, and so whether rotating
    /// onto a new identity is the right response.
    ///
    /// Permanent: the blob is structurally not a key, or this Enclave cannot unwrap it. A Secure
    /// Enclave key is device-bound, so an item that survives a restore-in-place while its Enclave key
    /// does not can never be reconstructed, and refusing to rotate there failed every append for the
    /// life of the install with reinstalling — destroying the ledger — as the only exit.
    ///
    /// Not permanent: `underlyingCoreCryptoError` and anything unrecognized. The Enclave can decline
    /// for reasons that pass — it is unavailable early in boot, or busy — and rotating on one of those
    /// throws away a perfectly good identity for good. Those fail the write instead, which is the same
    /// way this file already treats a Keychain that will not answer.
    ///
    /// **This split is a judgement about an opaque error domain, so it is not trusted to be right.**
    /// CryptoKit wraps most `SecKey`/CoreCrypto failures as `underlyingCoreCryptoError`, which is very
    /// likely how a genuinely lost Enclave key surfaces too — meaning the permanent case would be
    /// classified transient and every append would fail for the life of the install: the exact brick
    /// this classification exists to avoid, reached from the other direction. That is why
    /// ``ambiguousEnclaveFailureLimit`` exists. An unclassifiable failure fails the write, but only
    /// finitely often: a transient blip resolves well inside the limit — and a resolution that
    /// succeeds caches its identity, so the counter stops mattering entirely — while a permanent one
    /// exhausts the limit and rotates. Neither reading of the error domain can strand the ledger.
    /// Worth confirming on a real device and tightening, but not worth being wrong about.
    private static func isUnrestorableKeyMaterial(_ error: Error) -> Bool {
        guard let cryptoKitError = error as? CryptoKitError else {
            return false
        }
        switch cryptoKitError {
        case .incorrectKeySize, .incorrectParameterSize, .invalidParameter,
             .authenticationFailure, .unwrapFailure, .wrapFailure:
            return true
        case .underlyingCoreCryptoError:
            return false
        @unknown default:
            return false
        }
    }

    /// The bounded escape from an unclassifiable Enclave failure. Logged separately from
    /// ``logUnrestorableKey(account:error:)`` because the two are different admissions: that one says
    /// the blob is known-dead, this one says the device gave up deciding.
    private func logExhaustedEnclaveRetries(error: Error) {
        Self.logger.fault(
            "Receipt signing key '\(self.enclaveAccount, privacy: .public)' failed to restore \(Self.ambiguousEnclaveFailureLimit, privacy: .public) times with an unclassifiable error (\(error.localizedDescription, privacy: .public)); treating it as unrestorable and rotating to a new device identity. Receipts written before this point become unattestable by this device."
        )
    }

    /// Stored signing material that will not reconstruct — distinct from a Keychain that refuses to
    /// answer, which still fails closed above.
    ///
    /// Rotating here rather than throwing, because the two failures need opposite treatment. A locked
    /// or unavailable Keychain is transient and minting a replacement would abandon a perfectly good
    /// identity, so `loadKey` propagates and no receipt is written. A blob that cannot be restored is
    /// *permanent*: a Secure Enclave key is device-bound, so an item that survives a restore-in-place
    /// while its Enclave key does not can never be reconstructed. Throwing there failed every append
    /// for the life of the install, with reinstalling — destroying the ledger — as the only exit.
    ///
    /// Which of the two a given error is, is decided by ``isUnrestorableKeyMaterial(_:)``, not assumed.
    ///
    /// Rotation is safe because it only ever moves forward onto a key that has never signed anything.
    /// Rows already in the ledger carry their own signer key *inside* the hashed envelope, so they
    /// keep verifying on their own merits, and `verifyIntegrity()` reports the pre-rotation prefix as
    /// `.unattested` rather than tampered — the same verdict a device restore produces. Nothing an
    /// attacker gains: corrupting the blob grants no ability to forge a row, and anyone who can write
    /// this Keychain item could already replace the key outright.
    ///
    /// Logged at fault level because it is silent from the UI: the device stops being able to attest
    /// to everything it wrote before this point.
    private func logUnrestorableKey(account: String, error: Error) {
        Self.logger.fault(
            "Receipt signing key '\(account, privacy: .public)' could not be restored (\(error.localizedDescription, privacy: .public)); rotating to a new device identity. Receipts written before this point become unattestable by this device."
        )
    }
}

public enum ReceiptSignerFactory {
    /// Returns a lazy actor-backed signer. Keychain failures surface on the first receipt append.
    public static func deviceSigner() -> any ReceiptSigning {
        DeviceReceiptSigner()
    }

    /// A throwaway signing identity that lives and dies with the returned value, for tests and
    /// previews.
    ///
    /// Never for production: nothing it signs can be attested to after the instance goes away, and
    /// because `ReceiptPersistenceStore.verifyIntegrity()` then matches no row against the current
    /// identity, the anchor-tamper check it drives goes quiet too. Named so that choosing it is
    /// visible at the call site — that is the whole reason ``ReceiptPersistenceStore`` takes its
    /// signer as a required parameter instead of defaulting to one of these.
    public static func ephemeralSigner() -> any ReceiptSigning {
        SoftwareReceiptSigner()
    }
}
