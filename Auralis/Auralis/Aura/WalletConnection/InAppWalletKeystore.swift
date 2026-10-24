import CryptoKit
import Foundation
import LocalAuthentication
import Security

/// Secure, biometric-gated storage for the in-app self-custodial wallet's HD **seed**.
///
/// Protection model (per the wallet design decision): a Secure Enclave P-256 key-agreement key
/// *wraps* the raw seed. The seed is sealed with an AES-GCM key derived (ECIES-style) from an ephemeral
/// key and the Enclave key's public half — so **encryption needs no biometric** (public-key only), while
/// **decryption performs the key agreement inside the Enclave** whose access control demands a live
/// Face/Touch ID for every use. The Enclave private key never leaves hardware; only the sealed blob and
/// the Enclave key's persistent representation live in the Keychain (`ThisDeviceOnly`), useless off-device.
///
/// Simulator has no Secure Enclave (`SecureEnclave.isAvailable == false`); there we fall back to a
/// software P-256 key gated behind an explicit `LAContext` biometric evaluation, so the API and prompt
/// behavior match for development. Real devices always use the Enclave.
enum InAppWalletKeystore {
    enum KeystoreError: LocalizedError {
        case walletAlreadyExists
        case noWallet
        case biometricsUnavailable(String)
        case sealFailed
        case openFailed
        case randomFailed
        case keychainWriteFailed(account: String, status: OSStatus)
        case keychainDeleteFailed(account: String, status: OSStatus)
        case secureEnclaveUnavailable

        var errorDescription: String? {
            switch self {
            case .walletAlreadyExists: return "An in-app wallet already exists on this device."
            case .noWallet: return "No in-app wallet has been created on this device."
            case let .biometricsUnavailable(detail): return "Biometric authentication is unavailable: \(detail)"
            case .sealFailed: return "Failed to secure the wallet key."
            case .openFailed: return "Failed to unlock the wallet key."
            case .randomFailed: return "Failed to generate secure random data."
            case let .keychainWriteFailed(account, status):
                return "Failed to store wallet key material (\(account), status \(status)). "
                    + "The wallet was not created."
            case let .keychainDeleteFailed(account, status):
                return "Failed to remove wallet key material (\(account), status \(status)). "
                    + "Some key material may still be on this device."
            case .secureEnclaveUnavailable:
                return "This device has no Secure Enclave, which the in-app wallet requires."
            }
        }
    }

    private static let service = "AuralisInAppWalletKey"
    private static let hkdfSalt = Data("auralis.inapp.wallet.seed.v1".utf8)
    private static let seedByteCount = 32

    /// One complete, self-consistent set of wrapping-key material.
    ///
    /// Account names are **generation-suffixed** so a re-wrap can write an entire new set before
    /// retiring the old one. That is the whole mechanism behind
    /// ``migrateWrappingKeyPolicyIfNeeded(seed:)``'s crash-safety argument: the three items of one
    /// generation are only meaningful together — the sealed seed is bound by AES-GCM to the public
    /// half, which is bound to the private key — so overwriting them in place has a window in which
    /// the private key is from generation N+1 and the sealed blob from generation N, which no
    /// biometric can ever open. For a wallet with no mnemonic that window is unrecoverable loss of
    /// funds. `createWallet()`'s comment records the same hazard arising from a concurrency race;
    /// this is the same hazard arising from a crash.
    struct KeySlot: Equatable, Sendable {
        let enclaveKey: String
        let softwareKey: String
        let sealedSeed: String
        let publicKey: String

        /// Generation 1 — unsuffixed, for wallets created before the policy change. Its Enclave key
        /// carries `.biometryCurrentSet`, which is the exposure
        /// ``migrateWrappingKeyPolicyIfNeeded(seed:)`` exists to retire.
        static let legacy = KeySlot(
            enclaveKey: "wallet-enclave-keyagreement",
            softwareKey: "wallet-software-keyagreement",
            sealedSeed: "wallet-sealed-seed",
            publicKey: "wallet-enclave-public"
        )

        /// Generation 2 — provisioned under `.biometryAny`, so biometric enrollment changes no longer
        /// destroy the seed.
        static let biometryAny = KeySlot(
            enclaveKey: "wallet-enclave-keyagreement.g2",
            softwareKey: "wallet-software-keyagreement.g2",
            sealedSeed: "wallet-sealed-seed.g2",
            publicKey: "wallet-enclave-public.g2"
        )

        /// Newest first. Resolution order, not merely a list: ``liveSlot(presence:)`` returns the
        /// first *complete* slot, so a half-written migration is skipped in favour of the intact
        /// older generation.
        static let allNewestFirst = [biometryAny, legacy]

        /// Sealed seed first, matching ``deleteWallet()``'s ordering — it is the item whose absence
        /// means "no wallet", so removing it first cannot leave a readable wallet behind.
        var allAccounts: [String] { [sealedSeed, enclaveKey, softwareKey, publicKey] }
    }

    /// Serializes ``createWallet()``'s check-then-write against concurrent invocations, and the
    /// migration's read-generate-write-retire sequence against both.
    private static let creationLock = NSLock()

    /// Whether sealed seed material exists on this device.
    ///
    /// Fails **closed**: only a definitive `errSecItemNotFound` counts as "no wallet". This used to be
    /// `loadKey(...) != nil`, and `loadKey` discards every `OSStatus`, so a transient
    /// `errSecInteractionNotAllowed` (Keychain locked) or `errSecMissingEntitlement` read as `false` —
    /// which let ``createWallet()`` pass its `!hasWallet` guard and seal a *second* seed over key
    /// material it merely could not read, orphaning the first wallet and its funds.
    static var hasWallet: Bool {
        sealedSeedPresence() != .absent
    }

    /// Whether the Keychain *affirmatively* reports sealed seed material.
    ///
    /// The counterpart to ``hasWallet``, and the distinction matters. `hasWallet` fails closed so the
    /// write guard in ``createWallet()`` never seals a second seed over material it merely could not
    /// read. But "fail closed" is the wrong answer for anything that *routes the user*: treating an
    /// indeterminate Keychain as "a wallet exists" showed a brand-new user a recovery screen for a
    /// wallet that was never created, where Restore throws `noWallet` and the creation screen is
    /// unreachable — strictly worse than before, because they could previously just create one.
    /// Predicates that decide what a person sees use this; write guards use `hasWallet`.
    static var hasConfirmedWallet: Bool {
        sealedSeedPresence() == .present
    }

    enum ItemPresence: Equatable, Sendable {
        case present
        case absent
        /// The Keychain could not answer. Treated as `present` by every caller that fails closed.
        case indeterminate
    }

    /// Probes for an item without reading its data (so no ACL-gated item would ever prompt).
    private static func itemPresence(account: String) -> ItemPresence {
        var query = baseQuery(account: account)
        query[kSecReturnAttributes as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: AnyObject?
        switch SecItemCopyMatching(query as CFDictionary, &result) {
        case errSecSuccess: return .present
        case errSecItemNotFound: return .absent
        default: return .indeterminate
        }
    }

    /// The sealed-seed presence across **every** generation, collapsed to one verdict.
    ///
    /// Order of precedence is deliberate and is what preserves both halves of the
    /// ``hasWallet`` / ``hasConfirmedWallet`` contract once there is more than one slot: any
    /// affirmative `present` means a wallet exists (so `hasConfirmedWallet` is `true`), and otherwise
    /// a single `indeterminate` poisons the answer (so `hasWallet` still fails closed). Returning
    /// `.absent` while one generation merely could not be read is exactly the bug the `loadKey(...) != nil`
    /// version had, one slot wider.
    static func collapsedPresence(_ presences: [ItemPresence]) -> ItemPresence {
        if presences.contains(.present) { return .present }
        if presences.contains(.indeterminate) { return .indeterminate }
        return .absent
    }

    private static func sealedSeedPresence() -> ItemPresence {
        collapsedPresence(KeySlot.allNewestFirst.map { itemPresence(account: $0.sealedSeed) })
    }

    /// Whether a slot holds material that can actually be opened.
    ///
    /// All three of sealed seed, public half, and *some* wrapping key must be affirmatively present.
    /// "Affirmatively" matters: an `indeterminate` must not count as complete, because treating a
    /// slot as live on a Keychain that could not answer is how a half-written generation would shadow
    /// an intact older one. Pure so the resolution order can be tested without a Keychain.
    static func isSlotComplete(
        sealedSeed: ItemPresence,
        publicKey: ItemPresence,
        enclaveKey: ItemPresence,
        softwareKey: ItemPresence
    ) -> Bool {
        sealedSeed == .present
            && publicKey == .present
            && (enclaveKey == .present || softwareKey == .present)
    }

    /// The newest complete slot, or `nil` when none is openable.
    ///
    /// `presence` is injected so the whole resolution rule — including the "skip a half-written
    /// generation in favour of the intact older one" property the migration's crash-safety rests on —
    /// is testable without a Secure Enclave or a device.
    static func liveSlot(presence: (String) -> ItemPresence) -> KeySlot? {
        KeySlot.allNewestFirst.first { slot in
            isSlotComplete(
                sealedSeed: presence(slot.sealedSeed),
                publicKey: presence(slot.publicKey),
                enclaveKey: presence(slot.enclaveKey),
                softwareKey: presence(slot.softwareKey)
            )
        }
    }

    private static func liveSlot() -> KeySlot? {
        liveSlot(presence: itemPresence(account:))
    }

    /// Whether the openable wallet is still wrapped under the legacy `.biometryCurrentSet` policy.
    ///
    /// Drives the ``InAppWalletView`` advisory for a user who holds a pre-migration wallet and has not
    /// signed since — the migration is opportunistic and only runs on a successful unseal, so someone
    /// who never signs would otherwise never be told that changing their biometric enrollment can
    /// destroy the wallet.
    static var usesLegacyBiometricPolicy: Bool {
        liveSlot() == .legacy
    }

    /// True when sealed key material survives but no address is registered to route to it.
    ///
    /// This is the **app-reinstall** state, and before it was handled it permanently bricked the wallet.
    /// The sealed seed is a Keychain item, which iOS preserves across an app uninstall; the address
    /// registry is `UserDefaults`, which it erases. After a reinstall (or any defaults-domain reset)
    /// ``InAppWalletService/primaryAddress()`` returned `nil`, so ``InAppWalletView`` offered *creation*,
    /// `createWallet()` threw `walletAlreadyExists` on every attempt, and the Remove button — reachable
    /// only from the existing-wallet screen — was gone. The funds at the derived address became
    /// unreachable from the app with no self-service remedy. ``recoverAddressRegistration(localizedReason:)``
    /// is the way back.
    /// Uses ``hasConfirmedWallet``, not ``hasWallet``: this predicate decides which screen the user
    /// sees, and an indeterminate Keychain must not strand them on a recovery screen for a wallet that
    /// may not exist.
    static var needsAddressRecovery: Bool {
        hasConfirmedWallet && InAppWalletRegistry.all().isEmpty
    }

    /// Re-derives the wallet's address from the surviving sealed seed and re-registers it for routing.
    ///
    /// Costs one biometric prompt, because it has to actually unseal the seed — the address is not
    /// recoverable from the wrapping key alone.
    @discardableResult
    static func recoverAddressRegistration(localizedReason: String) async throws -> String {
        guard hasWallet else { throw KeystoreError.noWallet }
        let address = try await withSeed(localizedReason: localizedReason) { seed in
            try InAppWalletDerivation.ethereumAddress(seed: seed)
        }
        InAppWalletRegistry.register(address: address)
        return address
    }

    /// Generates a fresh seed, seals it under the Enclave (or software fallback) key, and returns the
    /// primary EOA address (`m/44'/60'/0'/0/0`). No biometric prompt — the seed is derived in-memory at
    /// creation and encryption uses only public-key material.
    @discardableResult
    static func createWallet() throws -> String {
        // Serializes the whole check-then-write sequence. `hasWallet` (:58), the wrapping-key writes, and
        // the sealed-seed write were previously unsynchronized while every caller runs the function from
        // a `Task.detached` — so two creations genuinely raced on different threads. Interleaved, T2's
        // `provisionWrappingKey` overwrote the enclave key and public half that T1 had just sealed
        // against, leaving a private key and a sealed blob from different generations: `unsealSeed`
        // could never open it, and the registry's first entry (what the UI displays and what `EOAccount`
        // records) belonged to a seed the app no longer held. For a wallet with no mnemonic that is
        // unrecoverable loss of funds, and nothing on the path threw at creation time.
        creationLock.lock()
        defer { creationLock.unlock() }

        guard !hasWallet else { throw KeystoreError.walletAlreadyExists }

        var seed = Data(count: seedByteCount)
        let status = seed.withUnsafeMutableBytes { buffer -> OSStatus in
            guard let base = buffer.baseAddress else { return errSecParam }
            return SecRandomCopyBytes(kSecRandomDefault, seedByteCount, base)
        }
        guard status == errSecSuccess else { throw KeystoreError.randomFailed }
        defer { seed.resetBytes(in: 0..<seed.count) }

        // All-or-nothing: the address is only registered once the sealed seed is durably stored.
        // Any failure between provisioning the wrapping key and persisting the seed rolls the
        // partial key material back, so a later `createWallet()` starts from a clean slate instead
        // of sealing a new seed against a stale wrapping key it can no longer open.
        let address: String
        do {
            // New wallets are minted directly into the modern slot, so they never carry the legacy
            // policy and never need migrating.
            let publicKey = try provisionWrappingKey(into: .biometryAny)
            let sealed = try seal(seed, to: publicKey)
            try saveKey(sealed, account: KeySlot.biometryAny.sealedSeed)
            address = try InAppWalletDerivation.ethereumAddress(seed: seed)
        } catch {
            for account in KeySlot.biometryAny.allAccounts {
                deleteKey(account: account)
            }
            throw error
        }

        InAppWalletRegistry.register(address: address)
        return address
    }

    /// Runs `body` with the decrypted seed after a successful biometric authentication, then wipes it.
    /// Executed off the main thread because the Enclave key-agreement call blocks while the system
    /// biometric sheet is up.
    static func withSeed<T: Sendable>(
        localizedReason: String,
        _ body: @escaping @Sendable (Data) throws -> T
    ) async throws -> T {
        try await Task.detached(priority: .userInitiated) {
            var seed = try await unsealSeed(localizedReason: localizedReason)
            defer { seed.resetBytes(in: 0..<seed.count) }
            // Opportunistic, and this is the only moment it can happen: re-wrapping needs the seed in
            // plaintext, and a successful unseal is simultaneously proof that the user *can* satisfy
            // the current biometric. Deliberately after the unseal and before `body`, so the caller's
            // work is never delayed behind a migration that is not needed, and never skipped because
            // the caller threw.
            migrateWrappingKeyPolicyIfNeeded(seed: seed)
            return try body(seed)
        }.value
    }

    /// Re-wraps a legacy wallet's seed under the `.biometryAny` policy. Best-effort and non-throwing.
    ///
    /// **Why this is safe to attempt and safe to fail.** The only destructive step is retiring the old
    /// slot, and that runs *after* the new slot is complete and therefore openable. Every earlier step
    /// writes to generation-2 account names that nothing reads until all three items exist — see
    /// ``KeySlot`` — so an abort at any point leaves generation 1 intact and authoritative:
    ///
    /// 1. provision a new wrapping key into the g2 slot (key + public half),
    /// 2. seal the seed under it and write the g2 sealed seed **last**, which is the single write that
    ///    makes g2 live (``isSlotComplete(sealedSeed:publicKey:enclaveKey:softwareKey:)`` requires it),
    /// 3. only then delete the g1 items.
    ///
    /// A crash between 1 and 2 leaves an incomplete g2 that `liveSlot` skips. A crash between 2 and 3
    /// leaves both slots complete, and `liveSlot` prefers g2 — the newly-written one, which is correct,
    /// and the stale g1 is cleaned up by the next successful unseal. **No window exists in which the
    /// stored private key and the stored sealed blob come from different generations**, which is the
    /// failure `createWallet()` documents as unrecoverable loss of funds.
    ///
    /// Non-throwing on purpose: a failed migration must never turn a working signature into an error.
    /// The wallet keeps working under the old policy and the next unseal tries again, which is strictly
    /// better than surfacing a failure the user cannot act on. `InAppWalletView` keeps showing the
    /// legacy advisory until it succeeds, so the exposure is never silent.
    ///
    /// Takes ``creationLock`` so a migration cannot interleave with `createWallet()`'s check-then-write.
    private static func migrateWrappingKeyPolicyIfNeeded(seed: Data) {
        creationLock.lock()
        defer { creationLock.unlock() }

        // Re-resolved under the lock rather than trusting the caller's earlier read.
        guard liveSlot() == .legacy else { return }

        let target = KeySlot.biometryAny
        do {
            let publicKey = try provisionWrappingKey(into: target)
            let sealed = try seal(seed, to: publicKey)
            try saveKey(sealed, account: target.sealedSeed)
        } catch {
            // Roll the partial generation back so a later attempt starts clean and `liveSlot` cannot
            // be confused by leftovers. The old slot was never touched.
            for account in target.allAccounts { deleteKey(account: account) }
            return
        }

        // g2 is now complete and preferred, so retiring g1 is no longer load-bearing for openability —
        // a failure here leaves a harmless orphan, not a broken wallet.
        for account in KeySlot.legacy.allAccounts { deleteKey(account: account) }
    }

    /// Destroys every piece of wallet key material, throwing if any of it survived.
    ///
    /// Every account is attempted before the first failure is reported, so one stuck item does not
    /// strand the rest. The throw ensures "Remove Wallet" cannot report an irreversible deletion while
    /// the sealed seed is still in the Keychain.
    ///
    /// The registry is cleared **only on full success**. Clearing it unconditionally produced a wallet
    /// that was neither visible nor re-creatable: `hasWallet` still read `true` from the surviving
    /// sealed seed, so `createWallet()` kept throwing `walletAlreadyExists`, while
    /// ``InAppWalletView`` — which keys off `primaryAddress()` — showed the creation screen with no
    /// Remove button to retry from. Leaving the registry intact keeps the retry path reachable.
    static func deleteWallet() throws {
        var failure: (account: String, status: OSStatus)?
        // Every generation, not just the live one. Leaving a retired slot behind would keep
        // `sealedSeedPresence()` reporting `.present`, so `hasWallet` would stay `true` and
        // `createWallet()` would keep throwing `walletAlreadyExists` after a "successful" removal.
        for account in KeySlot.allNewestFirst.flatMap(\.allAccounts) {
            let status = deleteKey(account: account)
            if status != errSecSuccess, failure == nil {
                failure = (account, status)
            }
        }
        if let failure {
            throw KeystoreError.keychainDeleteFailed(account: failure.account, status: failure.status)
        }
        InAppWalletRegistry.clear()
    }

    // MARK: - Wrapping key provisioning

    /// Mints a fresh wrapping key and returns its public half for sealing.
    ///
    /// Always creates — it never re-reads an existing key, which is why ``createWallet()`` guards on
    /// `!hasWallet` and rolls back on failure. Provisioning over a live wallet would orphan the
    /// already-sealed seed.
    private static func provisionWrappingKey(into slot: KeySlot) throws -> P256.KeyAgreement.PublicKey {
        if SecureEnclave.isAvailable {
            let access = try biometricAccessControl()
            let key = try SecureEnclave.P256.KeyAgreement.PrivateKey(accessControl: access)
            try saveKey(key.dataRepresentation, account: slot.enclaveKey)
            try saveKey(key.publicKey.rawRepresentation, account: slot.publicKey)
            return key.publicKey
        }

        // The software fallback stores a raw P-256 private key as an ordinary generic password with no
        // `SecAccessControl` — anything that can read the app's Keychain recovers the wrapping key and
        // the sealed seed together, bypassing the `LAContext` check in `wrappingSharedSecret` entirely.
        // That is acceptable only for development. Gating on the compile-time environment rather than
        // the runtime `SecureEnclave.isAvailable` ensures a release build on an Enclave-less target
        // (Catalyst, a future macOS target) refuses instead of silently inheriting software-only wrapping.
        #if targetEnvironment(simulator) || DEBUG
        let key = P256.KeyAgreement.PrivateKey()
        try saveKey(key.rawRepresentation, account: slot.softwareKey)
        try saveKey(key.publicKey.rawRepresentation, account: slot.publicKey)
        return key.publicKey
        #else
        throw KeystoreError.secureEnclaveUnavailable
        #endif
    }

    /// Access control for the wrapping key: device-only, and gated on **any** currently-enrolled
    /// biometric.
    ///
    /// `.biometryAny` rather than `.biometryCurrentSet`, because this key wraps the only copy of the
    /// seed and the wallet has no mnemonic to restore from. `.biometryCurrentSet` invalidates the key
    /// "if fingers are added or removed for Touch ID, or if the user re-enrolls for Face ID" — so
    /// enrolling a second fingerprint, on the same device, with nothing lost or reset, would have
    /// permanently destroyed the seed and any funds held at the derived address. That is not a
    /// disclosed outcome: ``InAppWalletView`` warns only that recovery fails if the device itself is
    /// lost or reset. `.biometryAny` keeps the live-biometric requirement for every signature while
    /// surviving enrollment changes.
    ///
    /// Not `.userPresence`, which would also accept the device passcode and weaken the gate from
    /// "this person's biometrics" to "whoever knows the passcode".
    ///
    /// Note this governs *newly provisioned* keys only — an access-control policy is fixed when the
    /// Enclave key is created. A wallet created before this change keeps `.biometryCurrentSet` and
    /// stays exposed to the loss path; there is no way to re-wrap without the seed, which requires a
    /// biometric the user may no longer be able to satisfy.
    private static func biometricAccessControl() throws -> SecAccessControl {
        var error: Unmanaged<CFError>?
        guard let access = SecAccessControlCreateWithFlags(
            nil,
            kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
            [.privateKeyUsage, .biometryAny],
            &error
        ) else {
            let detail = (error?.takeRetainedValue()).map { String(describing: $0) } ?? "unknown"
            throw KeystoreError.biometricsUnavailable(detail)
        }
        return access
    }

    // MARK: - ECIES-style seal / unseal

    private static func seal(_ seed: Data, to wrappingPublicKey: P256.KeyAgreement.PublicKey) throws -> Data {
        let ephemeral = P256.KeyAgreement.PrivateKey()
        let shared = try ephemeral.sharedSecretFromKeyAgreement(with: wrappingPublicKey)
        let symmetricKey = shared.hkdfDerivedSymmetricKey(
            using: SHA256.self,
            salt: hkdfSalt,
            sharedInfo: ephemeral.publicKey.rawRepresentation + wrappingPublicKey.rawRepresentation,
            outputByteCount: 32
        )
        guard let sealedBox = try? AES.GCM.seal(seed, using: symmetricKey),
              let combined = sealedBox.combined else {
            throw KeystoreError.sealFailed
        }
        // Wire format: ephemeral public key (65 bytes, X9.63) ‖ AES-GCM combined box.
        return ephemeral.publicKey.x963Representation + combined
    }

    private static func unsealSeed(localizedReason: String) async throws -> Data {
        guard let slot = liveSlot(),
              let sealed = loadKey(account: slot.sealedSeed),
              let wrappingPublicKeyData = loadKey(account: slot.publicKey) else {
            throw KeystoreError.noWallet
        }
        let wrappingPublicKey = try P256.KeyAgreement.PublicKey(rawRepresentation: wrappingPublicKeyData)

        // Split the wire format: 65-byte X9.63 ephemeral public key, then the sealed box.
        guard sealed.count > 65 else { throw KeystoreError.openFailed }
        let ephemeralPublicKey = try P256.KeyAgreement.PublicKey(x963Representation: sealed.prefix(65))
        let boxData = sealed.suffix(from: sealed.startIndex + 65)

        let shared = try await wrappingSharedSecret(
            with: ephemeralPublicKey,
            in: slot,
            localizedReason: localizedReason
        )
        let symmetricKey = shared.hkdfDerivedSymmetricKey(
            using: SHA256.self,
            salt: hkdfSalt,
            sharedInfo: ephemeralPublicKey.rawRepresentation + wrappingPublicKey.rawRepresentation,
            outputByteCount: 32
        )
        guard let box = try? AES.GCM.SealedBox(combined: boxData),
              let seed = try? AES.GCM.open(box, using: symmetricKey) else {
            throw KeystoreError.openFailed
        }
        return seed
    }

    /// Performs the wrapping key agreement — the biometric-gated step. On the Enclave this triggers the
    /// system biometric sheet via the key's access control; on the software fallback we require an
    /// explicit `LAContext` biometric evaluation first, for parity.
    private static func wrappingSharedSecret(
        with ephemeralPublicKey: P256.KeyAgreement.PublicKey,
        in slot: KeySlot,
        localizedReason: String
    ) async throws -> SharedSecret {
        if SecureEnclave.isAvailable, let blob = loadKey(account: slot.enclaveKey) {
            let context = LAContext()
            context.localizedReason = localizedReason
            let key = try SecureEnclave.P256.KeyAgreement.PrivateKey(
                dataRepresentation: blob,
                authenticationContext: context
            )
            return try key.sharedSecretFromKeyAgreement(with: ephemeralPublicKey)
        } else if let blob = loadKey(account: slot.softwareKey) {
            try await requireBiometricEvaluation(localizedReason: localizedReason)
            let key = try P256.KeyAgreement.PrivateKey(rawRepresentation: blob)
            return try key.sharedSecretFromKeyAgreement(with: ephemeralPublicKey)
        }
        throw KeystoreError.noWallet
    }

    /// Awaits an explicit biometric evaluation, suspending rather than blocking while the sheet is up.
    ///
    /// This used to park a cooperative-pool thread on `DispatchSemaphore.wait()` for the entire time
    /// the system biometric sheet was on screen — an unbounded, user-paced wait on a pool whose whole
    /// budget is a handful of threads. It was only ever reachable on the **non-Enclave fallback**
    /// (simulator, and Macs without a Secure Enclave), never on a real iOS device, so it was a
    /// development-path hazard rather than a shipping one; the continuation costs nothing and removes
    /// it anyway. It also removes the `Mutex` and the cross-domain handoff the semaphore needed: the
    /// callback now resumes directly, and the non-`Sendable` `NSError` is reduced to its description
    /// at the callback rather than carried out of it.
    ///
    /// Note this is *not* the Enclave path. There, key agreement itself blocks while the sheet is up
    /// and cannot be made async — which is why ``withSeed(localizedReason:_:)`` still runs the whole
    /// unseal on a detached task.
    private static func requireBiometricEvaluation(localizedReason: String) async throws {
        let context = LAContext()
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) else {
            throw KeystoreError.biometricsUnavailable(error?.localizedDescription ?? "not enrolled")
        }
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
            context.evaluatePolicy(
                .deviceOwnerAuthenticationWithBiometrics,
                localizedReason: localizedReason
            ) { success, err in
                guard success else {
                    continuation.resume(
                        throwing: KeystoreError.biometricsUnavailable(
                            err?.localizedDescription ?? "authentication failed"
                        )
                    )
                    return
                }
                continuation.resume()
            }
        }
    }

    // MARK: - Keychain (mirrors ReceiptSignerFactory conventions)

    private static func baseQuery(account: String) -> [String: Any] {
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

    private static func loadKey(account: String) -> Data? {
        var query = baseQuery(account: account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess else { return nil }
        return result as? Data
    }

    /// Persists key material, throwing on every failing `OSStatus`.
    ///
    /// This must never fail silently. It used to return `Void` and discard both the `SecItemAdd` and
    /// `SecItemUpdate` statuses, which meant a locked or unavailable Keychain let ``createWallet()``
    /// return a derived address whose seed was never stored — an account the app then presented as a
    /// signing-capable self-custodial wallet with no recoverable key. Funds sent to it would have been
    /// permanently lost, and there is no seed phrase to fall back on.
    private static func saveKey(_ data: Data, account: String) throws {
        var query = baseQuery(account: account)
        query[kSecValueData as String] = data
        query[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly as String
        let addStatus = SecItemAdd(query as CFDictionary, nil)

        switch addStatus {
        case errSecSuccess:
            return
        case errSecDuplicateItem:
            // The accessibility class is reapplied on update, not just on add. `SecItemUpdate` only
            // changes the attributes it is given, so an item left behind by an earlier build under a
            // weaker class kept it — and the newly-written sealed seed silently inherited a
            // backup/restore-eligible protection class, which is exactly the property the
            // "useless off-device" guarantee in this file's header rests on.
            let updateStatus = SecItemUpdate(
                baseQuery(account: account) as CFDictionary,
                [
                    kSecValueData as String: data,
                    kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly as String
                ] as CFDictionary
            )
            guard updateStatus == errSecSuccess else {
                throw KeystoreError.keychainWriteFailed(account: account, status: updateStatus)
            }
        default:
            throw KeystoreError.keychainWriteFailed(account: account, status: addStatus)
        }
    }

    /// Removes key material, reporting the `OSStatus` so callers can tell "gone" from "still there".
    ///
    /// `errSecItemNotFound` is success: the item is absent, which is the state the caller asked for.
    /// Anything else means the material may still be on the device, and ``deleteWallet()`` must not
    /// report an irreversible removal that did not happen.
    @discardableResult
    private static func deleteKey(account: String) -> OSStatus {
        let status = SecItemDelete(baseQuery(account: account) as CFDictionary)
        return status == errSecItemNotFound ? errSecSuccess : status
    }
}
