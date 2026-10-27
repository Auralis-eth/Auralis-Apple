import AccountsCore
import AuralisPrimaryModels
import AuralisOperators
import AuralisPolicy
import ProviderKit
import AuralisReceipts
import AuralisRuntime
import AuralisAppShell
import SwiftData

/// App-wide owner of the shared ``RuntimeHost``. One host per SwiftData container, so the event bus,
/// kill switch, capability leases, scheduling engine, and tool registry are global — not per-tab.
///
/// The playbook / performance / execution-record stores are backed by a dedicated on-disk SwiftData
/// container (`AuralisAppShell`) so operator runtime state survives relaunch, independent of
/// the app's main model container. Falls back to the host's in-memory defaults if that container
/// cannot be created.
@MainActor
enum RuntimeAssembly {
    private static var hostsByContainer: [ObjectIdentifier: RuntimeHost] = [:]

    /// The process-wide mode state used when a caller does not supply its own plumbing.
    ///
    /// The host captures its mode hooks as `let` at construction and ``sharedHost(modelContext:receiptStore:activeIdentityProvider:cryptoModeProvider:cryptoModeSetter:)``
    /// can only re-apply the *identity* on a cache hit — so whichever call site builds the host first
    /// permanently fixes the mode plumbing for the whole process. The old default closures made losing
    /// that race silently wrong: a caller with no opinion (e.g. the lazy host in `PrivacyResetServices`)
    /// could pin the host to a hardcoded `.observe`, dropping every `setMode` and reporting Observe to
    /// the policy gate for the life of the process.
    ///
    /// Rather than forbid the defaulted call, the default is made *correct* — see
    /// ``PersistedCryptoMode``, which reads the same persisted `app.mode` key every `ModeState` does,
    /// so a host built from any call site reports the user's real mode.
    ///
    /// Returns the shared host for this container, constructing it on first call.
    static func sharedHost(
        modelContext: ModelContext,
        receiptStore: (any ReceiptStore)? = nil,
        activeIdentityProvider: @escaping @MainActor () -> String? = { nil },
        cryptoModeProvider: @escaping @MainActor @Sendable () -> CryptoMode = { PersistedCryptoMode.current },
        cryptoModeSetter: @escaping @MainActor @Sendable (CryptoMode) -> Void = { PersistedCryptoMode.set($0) }
    ) -> RuntimeHost {
        let key = ObjectIdentifier(modelContext.container)
        if let existing = hostsByContainer[key] {
            // The optional is passed straight through, including `nil`. Applying it only when
            // non-nil meant signing out never *cleared* the identity: `MainTabView` supplies
            // `activeAccountAddress.isEmpty ? nil : activeAccountAddress`, so after disconnecting the
            // active wallet the host kept the previous account, and every governed run, receipt, and
            // worklog entry recorded while no account was active was attributed to it.
            existing.updateActiveIdentity(activeIdentityProvider())
            return existing
        }
        let host = makeHost(
            modelContext: modelContext,
            receiptStore: receiptStore,
            activeIdentityProvider: activeIdentityProvider,
            cryptoModeProvider: cryptoModeProvider,
            cryptoModeSetter: cryptoModeSetter
        )
        hostsByContainer[key] = host
        return host
    }

    private static func makeHost(
        modelContext: ModelContext,
        receiptStore: (any ReceiptStore)?,
        activeIdentityProvider: @escaping @MainActor () -> String?,
        cryptoModeProvider: @escaping @MainActor @Sendable () -> CryptoMode,
        cryptoModeSetter: @escaping @MainActor @Sendable (CryptoMode) -> Void
    ) -> RuntimeHost {
        let resolvedReceiptStore = receiptStore ?? ReceiptStores.live(modelContext: modelContext)
        let operatorDataSource = LiveOnChainOperatorDataSource(
            localDataSource: ReceiptBackedOperatorDataSource(receiptStore: resolvedReceiptStore),
            balanceProvider: ProviderAssembly().makeNativeBalanceProvider()
        )
        return RuntimeHost.persistent(
            receiptStore: resolvedReceiptStore,
            modelRouter: ModelProviderComposition.router,
            modelInferenceClient: ModelProviderComposition.inferenceClient,
            ritualRunNotifier: LocalRitualRunNotifier(),
            operatorDataSource: operatorDataSource,
            // Real wallet-backed executor so an approved Operate action actually signs/submits through the
            // connected wallet. Resolves the live signer lazily (see WalletSignerBox); fails closed when no
            // signing-capable wallet is connected.
            policyActionExecutor: WalletActionExecutor(),
            // `context.fresh` is measured from when a proposal gathered its context to when the check
            // actually runs — and for an escalated action that second moment is when a *person* taps
            // Approve. The library default (5 min) is sized for an unattended host that raises and
            // evaluates in one motion; applied to a human inbox it refuses ordinary think time, and
            // there is no in-app path to re-gather context, so the user is left with a dead approval.
            // 30 minutes covers a person stepping away mid-decision while still refusing context that
            // predates the session. Re-running the action is the remedy, and the check says so.
            standardCheckConfiguration: StandardCheckConfiguration(
                allowedChains: Self.governedChainScope,
                contextMaxAge: 1800
            ),
            activeIdentityProvider: activeIdentityProvider,
            cryptoModeProvider: cryptoModeProvider,
            cryptoModeSetter: cryptoModeSetter
        )
    }

    /// The chains governed work may touch — every EVM chain the app can actually sign for.
    ///
    /// `chain.inScope` and `policy.chain.allowed` both read this, so the read path and the signing
    /// path cannot drift apart. It has to be stated here rather than left to
    /// ``StandardCheckConfiguration``'s default, which is a three-chain set (Ethereum, Sepolia, Base)
    /// sized for a library caller with no wallet. Taking that default refused
    /// `policy.draftTransaction`, `policy.approveSpending`, and `policy.signMessage` on Polygon,
    /// Arbitrum, Optimism and the rest — chains `InAppWalletSigner.resolveChain` signs for,
    /// `LiveOnChainOperatorDataSource` names, and WalletConnect opens sessions on.
    private static let governedChainScope: Set<Chain> = StandardCheckConfiguration.allEVMChains

    /// Writes each live host's coalesced event-checkpoint cursors through to disk.
    ///
    /// Called from the scene's background transition. The hosts are reached through this type
    /// because it owns them — no view in the tree holds one, and threading a host down to
    /// `AuralisApp` only to flush it would be worse than asking their owner.
    static func flushEventCheckpoints() async {
        for host in hostsByContainer.values {
            await host.flushEventCheckpoints()
        }
    }
}
