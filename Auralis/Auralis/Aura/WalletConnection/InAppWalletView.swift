import SwiftData
import SwiftUI

/// Create / view / remove screen for Auralis's in-app self-custodial wallet.
///
/// Because the wallet has no BIP-39 mnemonic (by design), there is no seed phrase to display or import —
/// so this surface makes the tradeoff explicit rather than offering a phrase backup: recovery is
/// device-bound via the Secure Enclave, and removal is irreversible.
struct InAppWalletView: View {
    @Environment(\.modelContext) private var modelContext
    private let service = InAppWalletService()

    @State private var address: String?
    @State private var errorMessage: String?
    @State private var isWorking = false
    @State private var showDeleteConfirmation = false
    @State private var needsRecovery = false
    /// Mirrors `InAppWalletKeystore.usesLegacyBiometricPolicy`, refreshed with the rest of the state so
    /// the advisory disappears as soon as the opportunistic re-wrap succeeds.
    @State private var usesLegacyBiometricPolicy = false

    var body: some View {
        Form {
            if let address {
                existingWalletSections(address: address)
            } else if needsRecovery {
                recoverySections
            } else {
                creationSections
            }

            if let errorMessage {
                Section {
                    Text(errorMessage).foregroundStyle(.red)
                }
            }
        }
        .navigationTitle("Auralis Wallet")
        .onAppear { refreshState() }
        .confirmationDialog(
            "Remove this wallet? Without a seed phrase this cannot be undone, and any funds will be unrecoverable.",
            isPresented: $showDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Remove Wallet", role: .destructive) { Task { await delete() } }
            Button("Cancel", role: .cancel) {}
        }
    }

    @ViewBuilder
    private func existingWalletSections(address: String) -> some View {
        Section("Your Auralis Wallet") {
            LabeledContent("Address", value: address)
            Label("Secured by Secure Enclave + Face ID", systemImage: "faceid")
            Text("Each signature requires biometric approval on this device.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        // Only for a wallet still on the pre-migration wrapping policy. The re-wrap is opportunistic
        // and runs on the next successful signature, so a user who never signs would otherwise never
        // learn that changing their biometric enrollment destroys this wallet. Stating the remedy
        // matters more than stating the risk: signing once is the fix, and it is a thing they can do.
        if usesLegacyBiometricPolicy {
            Section {
                Label(
                    "Update your wallet's protection",
                    systemImage: "exclamationmark.shield"
                )
                .font(.callout.weight(.semibold))
                Text("This wallet was created before a security update. Until it is updated, adding or removing a fingerprint — or re-enrolling Face ID — will permanently destroy it, and any funds it holds cannot be recovered.")
                Text("The next time you sign something with this wallet it updates automatically, with no extra prompt. Nothing moves and your address does not change.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .accessibilityIdentifier("inAppWallet.legacyBiometricPolicyAdvisory")
        }
        Section {
            Button("Remove Wallet", role: .destructive) { showDeleteConfirmation = true }
                .disabled(isWorking)
        }
    }

    /// Shown when sealed key material exists but no address is registered — after an app reinstall or a
    /// cleared defaults domain. Without this branch the view fell through to `creationSections`, where
    /// Create threw `walletAlreadyExists` forever and no Remove button was reachable, leaving the wallet
    /// permanently inaccessible from the app.
    @ViewBuilder
    private var recoverySections: some View {
        Section("Wallet Found on This Device") {
            Text("This device still holds a wallet's secure key material, but the app no longer has its address — this happens after reinstalling. Restore access to use it again.")
            Label("Restoring requires Face ID and does not move any funds.", systemImage: "faceid")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        Section {
            Button { Task { await recover() } } label: {
                if isWorking {
                    ProgressView()
                } else {
                    Text("Restore Wallet Access")
                }
            }
            .disabled(isWorking)
        }
        Section {
            Button("Remove Wallet", role: .destructive) { showDeleteConfirmation = true }
                .disabled(isWorking)
        } footer: {
            Text("If you no longer want this wallet, removing it clears the key material and lets you create a new one.")
        }
    }

    @ViewBuilder
    private var creationSections: some View {
        Section {
            Text("Create a self-custodial wallet whose keys are generated and stored only on this device, protected by the Secure Enclave and Face ID.")
        }
        Section {
            Label(
                "No seed phrase. Recovery is device-only — if you lose or reset this device, the wallet and its funds cannot be recovered.",
                systemImage: "exclamationmark.triangle.fill"
            )
            .foregroundStyle(.orange)
        }
        Section {
            Button { Task { await create() } } label: {
                if isWorking {
                    ProgressView()
                } else {
                    Text("Create Auralis Wallet")
                }
            }
            .disabled(isWorking)
        }
    }

    private func refreshState() {
        address = service.primaryAddress()
        needsRecovery = address == nil && service.needsRecovery
        usesLegacyBiometricPolicy = address != nil && service.usesLegacyBiometricPolicy
    }

    private func create() async {
        // `.disabled(isWorking)` cannot carry this on its own: the flag is set inside the button's
        // `Task { }` body, so it lands a turn after the tap handler returns. Two taps in the same frame
        // both enqueued, both reached `createWallet`, and raced inside the keystore. Re-checking here
        // closes the window before any key material is touched.
        guard !isWorking else { return }
        isWorking = true
        errorMessage = nil
        do {
            _ = try await service.createWallet(modelContext: modelContext)
            // Re-read rather than assigning the two fields by hand: `usesLegacyBiometricPolicy`
            // is part of this state too, and hand-assignment left it stale.
            refreshState()
        } catch {
            errorMessage = error.localizedDescription
            refreshState()
        }
        isWorking = false
    }

    private func recover() async {
        guard !isWorking else { return }
        isWorking = true
        errorMessage = nil
        do {
            _ = try await service.recoverWallet(modelContext: modelContext)
            // Matters most on this path: recovered key material is pre-existing, so it is the most
            // likely to still be on the legacy wrapping policy, and hand-assigning the two fields
            // suppressed the advisory that tells the user how to clear it.
            refreshState()
        } catch {
            // A declined or failed biometric leaves the wallet exactly as it was; keep the recovery
            // screen up so the user can retry rather than dropping them back to Create.
            errorMessage = error.localizedDescription
            refreshState()
        }
        isWorking = false
    }

    private func delete() async {
        guard !isWorking else { return }
        isWorking = true
        errorMessage = nil
        do {
            try await service.deleteWallet(modelContext: modelContext)
            address = nil
            needsRecovery = false
        } catch {
            // A partial removal throws *without* clearing the registry, so the address is still here
            // and the Remove button stays reachable for a retry. Re-read it rather than assuming
            // either outcome, and surface the error instead of implying the wallet is gone.
            refreshState()
            errorMessage = error.localizedDescription
        }
        isWorking = false
    }
}
