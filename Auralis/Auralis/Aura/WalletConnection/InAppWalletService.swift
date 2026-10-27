import AuralisCrypto
import Foundation
import SwiftData

/// App-facing coordinator for Auralis's in-app self-custodial wallet: bridges the biometric keystore to
/// the SwiftData account model and the signer router.
///
/// Creation is a two-step commit — the keystore seals a new seed and returns the derived address, then a
/// signing-capable `EOAccount(source: .inAppWallet)` is inserted so the rest of the app treats it like any
/// other wallet account, and the in-app signer is registered for routing.
@MainActor
struct InAppWalletService {
    var hasWallet: Bool { InAppWalletKeystore.hasWallet }

    /// Whether the wallet is still wrapped under the legacy `.biometryCurrentSet` policy, where a
    /// biometric enrollment change destroys the seed. Drives the advisory in ``InAppWalletView``;
    /// clears itself once the opportunistic re-wrap in `withSeed` succeeds.
    var usesLegacyBiometricPolicy: Bool { InAppWalletKeystore.usesLegacyBiometricPolicy }

    /// Sealed key material exists but nothing is registered to route to it — the app-reinstall state.
    /// See ``InAppWalletKeystore/needsAddressRecovery``.
    var needsRecovery: Bool { InAppWalletKeystore.needsAddressRecovery }

    func primaryAddress() -> String? { InAppWalletRegistry.all().first }

    /// Restores access to a wallet whose sealed seed survived but whose address registration did not
    /// (app reinstall, or a cleared defaults domain). Re-derives the address behind one biometric
    /// prompt, re-registers it for routing, and re-attaches its `EOAccount`.
    @discardableResult
    func recoverWallet(modelContext: ModelContext) async throws -> EOAccount {
        let address = try await InAppWalletKeystore.recoverAddressRegistration(
            localizedReason: "Authenticate to restore access to your Auralis wallet"
        )
        do {
            let account = try upsertAccount(address: address, in: modelContext)
            WalletSignerBox.shared.inAppSigner = InAppWalletSigner()
            return account
        } catch {
            // Un-register on failure, which is what keeps the Restore path reachable. `needsRecovery`
            // is "sealed seed present AND registry empty", so leaving the address registered after a
            // failed `save()` flipped the view to the existing-wallet screen permanently: no Restore
            // button (registry non-empty), no `EOAccount` (the save is what failed) so the wallet is
            // invisible to every account list, and the only remaining control is the irreversible
            // Remove. A transient disk or migration error would have turned a recoverable wallet into
            // one whose sole self-service action destroys it.
            //
            // Unlike `createWallet`'s rollback this must NOT touch key material — the seed here is a
            // pre-existing, possibly funded wallet. Clearing the registry is safe precisely because
            // the sealed seed is untouched, so a retry re-derives the same address.
            InAppWalletRegistry.clear()
            throw error
        }
    }

    /// Generates the wallet (no biometric prompt) and records its account. Throws
    /// `InAppWalletKeystore.KeystoreError.walletAlreadyExists` if one already exists.
    @discardableResult
    func createWallet(modelContext: ModelContext) async throws -> EOAccount {
        // Secure Enclave key generation and the Keychain writes are slow enough to drop frames, and this
        // runs behind a `ProgressView` that can only appear if the main actor is free to draw it.
        let address = try await Task.detached(priority: .userInitiated) {
            try InAppWalletKeystore.createWallet()
        }.value

        // All-or-nothing across both stores. The keystore has already sealed the seed and registered the
        // address by this point, so a SwiftData failure would otherwise leave a wallet that exists
        // cryptographically but has no `EOAccount` — and that can never be re-created, because every
        // retry hits `walletAlreadyExists`. Roll the key material back so a retry starts clean.
        do {
            let account = try upsertAccount(address: address, in: modelContext)
            WalletSignerBox.shared.inAppSigner = InAppWalletSigner()
            return account
        } catch {
            // The rollback is best-effort: if it also fails, the original error is the one worth
            // reporting. A fully-successful rollback clears the registry; a partial one leaves it
            // intact, which is what keeps the Remove path reachable for a manual retry.
            await Task.detached(priority: .userInitiated) {
                try? InAppWalletKeystore.deleteWallet()
            }.value
            throw error
        }
    }

    /// Deletes the on-device keys and the associated account(s). Irreversible — without a seed phrase there
    /// is no way to recover the wallet afterward.
    func deleteWallet(modelContext: ModelContext) async throws {
        // SwiftData rows go first, and are found by `source == .inAppWallet` rather than by the
        // registry. Deleting key material first meant a `save()` failure afterwards left an
        // `EOAccount(source: .inAppWallet)` the app still presents as a signing-capable wallet while
        // its keys are gone — and unreachable by any retry, because the keystore had already cleared
        // the registry the retry reads its addresses from. Querying the rows directly makes the
        // cleanup idempotent no matter which half failed last time.
        for account in try inAppWalletAccounts(in: modelContext) {
            modelContext.delete(account)
        }
        try modelContext.save()
        WalletSignerBox.shared.inAppSigner = nil

        // Only now the key material. A throw here means some of it survived, which the user must be
        // told about — but the account rows are already gone, so there is nothing left to strand.
        try await Task.detached(priority: .userInitiated) {
            try InAppWalletKeystore.deleteWallet()
        }.value
    }

    /// Inserts or re-marks the signing-capable `EOAccount` for `address` and saves. Shared by creation
    /// and recovery so both paths converge on the same account shape.
    private func upsertAccount(address: String, in modelContext: ModelContext) throws -> EOAccount {
        let account = try existingAccount(address: address, in: modelContext)
            ?? EOAccount(
                address: address,
                access: .wallet,
                source: .inAppWallet,
                addedAt: .now,
                lastSelectedAt: .now
            )
        if account.modelContext == nil {
            modelContext.insert(account)
        }
        account.access = .wallet
        account.source = .inAppWallet
        try modelContext.save()
        return account
    }

    /// Every account this device created as an in-app wallet, independent of the registry.
    private func inAppWalletAccounts(in modelContext: ModelContext) throws -> [EOAccount] {
        let registered = Set(InAppWalletRegistry.all().map { $0.lowercased() })
        return try modelContext.fetch(FetchDescriptor<EOAccount>())
            .filter { $0.source == .inAppWallet || registered.contains($0.address.lowercased()) }
    }

    private func existingAccount(address: String, in modelContext: ModelContext) throws -> EOAccount? {
        let lowered = address.lowercased()
        return try modelContext.fetch(FetchDescriptor<EOAccount>())
            .first { $0.address.lowercased() == lowered }
    }
}
