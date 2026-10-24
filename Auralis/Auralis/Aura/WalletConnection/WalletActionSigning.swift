import Foundation

/// The narrow signing surface the governed ``WalletActionExecutor`` needs, decoupled from the concrete
/// `AuralisWalletConnectionService` so the executor is testable and the service stays the single owner of
/// session/topic resolution.
///
/// Two implementations back this, one per wallet family:
/// - **External** wallets sign through the connector `request` seam, which opens the wallet app for the
///   user to approve the key operation (see `AuralisWalletConnectionService`).
/// - Auralis's own **in-app self-custodial** wallet signs *locally in code* with key material generated
///   and stored on-device (Secure Enclave / Keychain) — it never leaves the process and does not route
///   through any connector or third-party SDK.
/// The governed ``WalletActionExecutor`` resolves whichever signer owns the acting address and is agnostic
/// to which family performs the signature.
@MainActor
protocol WalletActionSigning: AnyObject {
    /// EIP-191 `personal_sign` over human-readable `text` from `address`. Returns the `0x…` signature.
    func signPersonalMessage(_ text: String, address: String, chainID: String?) async throws -> String

    /// Submits an `eth_sendTransaction` from `address`. Returns the transaction hash.
    func sendTransaction(
        from address: String,
        to: String?,
        value: String,
        data: String,
        chainID: String
    ) async throws -> String
}

/// Process-wide resolver that maps an acting address to the signer that owns it.
///
/// Two families coexist: the **external** connector signer (`AuralisWalletConnectionService`, created
/// lazily by the UI only once a wallet-connect account exists) and Auralis's **in-app self-custodial**
/// signer. Because the external service is created after the ``RuntimeHost`` is built, the governed
/// executor can't be handed a stable reference at construction — it resolves the *current* signer here at
/// execution time. `nil` means no signer owns that address, so a cleared crypto action fails closed rather
/// than silently no-op'ing.
@MainActor
final class WalletSignerBox {
    static let shared = WalletSignerBox()

    /// The connected external-wallet signer; weak because the UI owns its lifetime.
    weak var externalSigner: (any WalletActionSigning)?
    /// The in-app self-custodial signer. Stateless (keys live in the keystore), so it's cheap to hold.
    var inAppSigner: (any WalletActionSigning)?

    private init() {}

    /// Returns the signer responsible for `address`: the in-app signer when the address is an Auralis
    /// self-custodial wallet, otherwise the connected external signer.
    ///
    /// The in-app fallback is load-bearing — `inAppSigner` is only assigned by `createWallet`, so on a
    /// relaunch with an existing wallet it is `nil` and routing would otherwise fall through to the
    /// external signer. It is gated on key material actually existing: without the gate, a registry
    /// entry that outlived a partial `deleteWallet` resolved to a live signer, producing a biometric
    /// prompt followed by an opaque `openFailed` instead of a clean `noConnectedWallet`. Setting
    /// `inAppSigner = nil` on delete also had no routing effect at all, since the fallback reinstated it.
    func signer(for address: String) -> (any WalletActionSigning)? {
        if InAppWalletRegistry.owns(address: address) {
            // `hasConfirmedWallet`, so an erroring Keychain does not re-open the prompt-then-`openFailed`
            // path this gate exists to close.
            guard InAppWalletKeystore.hasConfirmedWallet else { return nil }
            return inAppSigner ?? InAppWalletSigner()
        }
        return externalSigner
    }
}
