import AuralisPrimaryModels
import AuralisPrimaryPersistence
import ContextCore
import Foundation
import MissionControlFeature
import NFTDomain
import NFTPersistence
import NFTPresentation
import NFTProviderAdapters
import Observation
import PolicyCore
import ProviderKit
import ReceiptsCore

struct ContextRefreshInstrumentation {
    let recordContextRefresh: @MainActor (_ key: String, _ dataClass: ContextDataClass?, _ correlationID: String) async -> Void
    let recordMemoryTouch: @MainActor (_ kind: AgentSessionMemoryTouchKind, _ key: String, _ dataClass: ContextDataClass?, _ correlationID: String) async -> Void
}

@MainActor
@Observable
/// Builds and refreshes the home-context snapshot consumed by Aura shell surfaces.
final class ContextService {
    /// Defines whether a refresh may hit the network or must reuse cached balance data.
    enum RefreshStrategy {
        case remoteAllowed
        case reuseCachedBalance
    }

    private struct CapturedInputs {
        let account: EOAccount?
        let address: String
        let chain: Chain
        let mode: CryptoMode
        let isLoading: Bool
        let refreshedAt: Date?
        let nativeBalanceDisplay: String?
        let nativeBalanceStatusMessage: String?
        let nativeBalanceUpdatedAt: Date?
        let nativeBalanceProvenance: ContextProvenance
        let freshnessTTL: TimeInterval?
        let trackedNFTCount: Int?
        let musicCollectionCount: Int?
        let receiptCount: Int?
        let pinnedActions: [HomeLauncherAction]
        let prefersDemoData: Bool?
        let pinnedItemCount: Int?

        var scope: ContextRequestScope {
            ContextRequestScope(
                accountAddress: account?.address ?? address,
                chainID: chain.rawValue,
                modeID: mode.rawValue
            )
        }
    }

    private let contextSourceBuilder: any ShellContextSourceBuilding
    private let accountProvider: () -> EOAccount?
    private let addressProvider: () -> String
    private let chainProvider: () -> Chain
    private let modeProvider: () -> CryptoMode
    private let loadingProvider: () -> Bool
    private let refreshedAtProvider: () -> Date?
    private let nativeBalanceProvider: any NativeBalanceProviding
    private let freshnessTTLProvider: () -> TimeInterval?
    private let trackedNFTCountProvider: () -> Int?
    private let musicCollectionCountProvider: () -> Int?
    private let receiptCountProvider: () -> Int?
    private let pinnedActionsProvider: () -> [HomeLauncherAction]
    private let prefersDemoDataProvider: () -> Bool?
    private let pinnedItemCountProvider: () -> Int?
    private let beforeResolve: @MainActor () async -> Void

    private(set) var snapshot: ContextSnapshot

    @ObservationIgnored private let refreshCoordinator = ContextRefreshCoordinator()

    /// Creates a context service from shell-owned providers and a context-source builder.
    ///
    /// - Parameters:
    ///   - contextSourceBuilder: Builder used to assemble a `ContextSource` from live shell providers.
    ///   - accountProvider: Returns the current account, if one is active.
    ///   - addressProvider: Returns the current address string mirrored into shell state.
    ///   - chainProvider: Returns the currently selected chain.
    ///   - modeProvider: Returns the active app mode.
    ///   - loadingProvider: Returns whether the shell is currently refreshing data.
    ///   - refreshedAtProvider: Returns the last successful shell refresh timestamp.
    ///   - nativeBalanceProvider: Provider used to resolve native token balances.
    ///   - freshnessTTLProvider: Returns the current freshness TTL for context staleness messaging.
    ///   - trackedNFTCountProvider: Returns the persisted NFT count for the current scope.
    ///   - musicCollectionCountProvider: Returns the current music library collection count.
    ///   - receiptCountProvider: Returns the current receipt count for the active scope.
    ///   - pinnedActionsProvider: Returns the current home launcher pin set.
    ///   - prefersDemoDataProvider: Returns whether the shell is currently favoring guest/demo data.
    ///   - pinnedItemCountProvider: Returns the count of pinned home items.
    ///   - beforeResolve: Async hook that runs immediately before snapshot resolution.
    init(
        contextSourceBuilder: any ShellContextSourceBuilding,
        accountProvider: @escaping () -> EOAccount?,
        addressProvider: @escaping () -> String,
        chainProvider: @escaping () -> Chain,
        modeProvider: @escaping () -> CryptoMode,
        loadingProvider: @escaping () -> Bool,
        refreshedAtProvider: @escaping () -> Date?,
        nativeBalanceProvider: any NativeBalanceProviding,
        freshnessTTLProvider: @escaping () -> TimeInterval?,
        trackedNFTCountProvider: @escaping () -> Int?,
        musicCollectionCountProvider: @escaping () -> Int?,
        receiptCountProvider: @escaping () -> Int?,
        pinnedActionsProvider: @escaping () -> [HomeLauncherAction],
        prefersDemoDataProvider: @escaping () -> Bool?,
        pinnedItemCountProvider: @escaping () -> Int?,
        beforeResolve: @escaping @MainActor () async -> Void = {
            await Task.yield()
        }
    ) {
        self.contextSourceBuilder = contextSourceBuilder
        self.accountProvider = accountProvider
        self.addressProvider = addressProvider
        self.chainProvider = chainProvider
        self.modeProvider = modeProvider
        self.loadingProvider = loadingProvider
        self.refreshedAtProvider = refreshedAtProvider
        self.nativeBalanceProvider = nativeBalanceProvider
        self.freshnessTTLProvider = freshnessTTLProvider
        self.trackedNFTCountProvider = trackedNFTCountProvider
        self.musicCollectionCountProvider = musicCollectionCountProvider
        self.receiptCountProvider = receiptCountProvider
        self.pinnedActionsProvider = pinnedActionsProvider
        self.prefersDemoDataProvider = prefersDemoDataProvider
        self.pinnedItemCountProvider = pinnedItemCountProvider
        self.beforeResolve = beforeResolve

        let initialInputs = CapturedInputs(
            account: accountProvider(),
            address: addressProvider(),
            chain: chainProvider(),
            mode: modeProvider(),
            isLoading: loadingProvider(),
            refreshedAt: refreshedAtProvider(),
            nativeBalanceDisplay: nil,
            nativeBalanceStatusMessage: nil,
            nativeBalanceUpdatedAt: nil,
            nativeBalanceProvenance: .localCache,
            freshnessTTL: freshnessTTLProvider(),
            trackedNFTCount: trackedNFTCountProvider(),
            musicCollectionCount: musicCollectionCountProvider(),
            receiptCount: receiptCountProvider(),
            pinnedActions: pinnedActionsProvider(),
            prefersDemoData: prefersDemoDataProvider(),
            pinnedItemCount: pinnedItemCountProvider()
        )
        self.snapshot = Self.makeSnapshot(
            from: initialInputs,
            using: contextSourceBuilder
        )
    }

    /// Returns the most recently resolved snapshot without triggering refresh work.
    func cachedSnapshot() -> ContextSnapshot {
        snapshot
    }

    /// Refreshes the context snapshot for the current shell scope and returns the resolved value.
    @discardableResult
    func refresh(
        correlationID: String? = nil,
        receiptEventLogger: ReceiptEventLogger? = nil,
        strategy: RefreshStrategy = .remoteAllowed,
        instrumentation: ContextRefreshInstrumentation? = nil
    ) async -> ContextSnapshot {
        let capturedInputs = await captureInputs(strategy: strategy)

        let resolution = await refreshCoordinator.resolve(scope: capturedInputs.scope) {
            [capturedInputs, contextSourceBuilder, beforeResolve] in
            await beforeResolve()
            return Self.makeSnapshot(from: capturedInputs, using: contextSourceBuilder)
        }
        let resolvedSnapshot = resolution.snapshot

        if resolution.reusedInFlightRefresh {
            await recordInstrumentation(
                snapshot: resolvedSnapshot,
                inputs: capturedInputs,
                strategy: strategy,
                correlationID: correlationID,
                instrumentation: instrumentation,
                reusedInFlightRefresh: true
            )
            return resolvedSnapshot
        }

        if resolution.shouldCommit {
            snapshot = resolvedSnapshot
        }

        if let receiptEventLogger {
            _ = try? await receiptEventLogger.recordContextBuilt(
                snapshot: resolvedSnapshot,
                correlationID: correlationID
            )
        }
        await recordInstrumentation(
            snapshot: resolvedSnapshot,
            inputs: capturedInputs,
            strategy: strategy,
            correlationID: correlationID,
            instrumentation: instrumentation,
            reusedInFlightRefresh: false
        )

        return resolution.shouldCommit ? snapshot : resolvedSnapshot
    }
}

private extension ContextService {
    private func recordInstrumentation(
        snapshot: ContextSnapshot,
        inputs: CapturedInputs,
        strategy: RefreshStrategy,
        correlationID: String?,
        instrumentation: ContextRefreshInstrumentation?,
        reusedInFlightRefresh: Bool
    ) async {
        guard let instrumentation else { return }
        let resolvedCorrelationID = correlationID ?? Self.generatedContextCorrelationID(for: inputs.scope)
        await instrumentation.recordContextRefresh(
            "shell.context.snapshot",
            .derived,
            resolvedCorrelationID
        )
        await instrumentation.recordMemoryTouch(
            .memoryRead,
            "shell.context.account",
            .publicIdentifier,
            resolvedCorrelationID
        )
        await instrumentation.recordMemoryTouch(
            .memoryRead,
            "shell.context.chain",
            .publicIdentifier,
            resolvedCorrelationID
        )
        await instrumentation.recordMemoryTouch(
            .memoryRead,
            "shell.context.mode",
            .localPreference,
            resolvedCorrelationID
        )
        await instrumentation.recordMemoryTouch(
            strategy == .reuseCachedBalance ? .memoryRead : .contextRefresh,
            "shell.context.nativeBalance.\(snapshot.balances.nativeBalanceDisplay.provenance.rawValue)",
            strategy == .reuseCachedBalance ? .localPreference : .publicIdentifier,
            resolvedCorrelationID
        )
        if reusedInFlightRefresh {
            await instrumentation.recordMemoryTouch(
                .memoryRead,
                "shell.context.inFlightRefresh",
                .derived,
                resolvedCorrelationID
            )
        }
        if inputs.pinnedItemCount != nil || inputs.prefersDemoData != nil {
            await instrumentation.recordMemoryTouch(
                .memoryRead,
                "shell.context.localPreferences",
                .localPreference,
                resolvedCorrelationID
            )
        }
    }

    private static func generatedContextCorrelationID(for scope: ContextRequestScope) -> String {
        let address = scope.accountAddress.isEmpty ? "none" : scope.accountAddress
        return "context.refresh.\(scope.chainID).\(address).\(UUID().uuidString)"
    }

    private func captureInputs(
        strategy: RefreshStrategy
    ) async -> CapturedInputs {
        await Self.captureInputs(
            accountProvider: accountProvider,
            addressProvider: addressProvider,
            chainProvider: chainProvider,
            modeProvider: modeProvider,
            loadingProvider: loadingProvider,
            refreshedAtProvider: refreshedAtProvider,
            nativeBalanceProvider: nativeBalanceProvider,
            freshnessTTLProvider: freshnessTTLProvider,
            trackedNFTCountProvider: trackedNFTCountProvider,
            musicCollectionCountProvider: musicCollectionCountProvider,
            receiptCountProvider: receiptCountProvider,
            pinnedActionsProvider: pinnedActionsProvider,
            prefersDemoDataProvider: prefersDemoDataProvider,
            pinnedItemCountProvider: pinnedItemCountProvider,
            strategy: strategy,
            cachedSnapshot: snapshot
        )
    }

    private static func captureInputs(
        accountProvider: () -> EOAccount?,
        addressProvider: () -> String,
        chainProvider: () -> Chain,
        modeProvider: () -> CryptoMode,
        loadingProvider: () -> Bool,
        refreshedAtProvider: () -> Date?,
        nativeBalanceProvider: any NativeBalanceProviding,
        freshnessTTLProvider: () -> TimeInterval?,
        trackedNFTCountProvider: () -> Int?,
        musicCollectionCountProvider: () -> Int?,
        receiptCountProvider: () -> Int?,
        pinnedActionsProvider: () -> [HomeLauncherAction],
        prefersDemoDataProvider: () -> Bool?,
        pinnedItemCountProvider: () -> Int?,
        strategy: RefreshStrategy,
        cachedSnapshot: ContextSnapshot
    ) async -> CapturedInputs {
        let address = addressProvider()
        let chain = chainProvider()
        let nativeBalanceSnapshot = await resolveNativeBalance(
            address: address,
            chain: chain,
            provider: nativeBalanceProvider,
            strategy: strategy,
            cachedSnapshot: cachedSnapshot
        )

        return CapturedInputs(
            account: accountProvider(),
            address: address,
            chain: chain,
            mode: modeProvider(),
            isLoading: loadingProvider(),
            refreshedAt: refreshedAtProvider(),
            nativeBalanceDisplay: nativeBalanceSnapshot.displayValue,
            nativeBalanceStatusMessage: nativeBalanceSnapshot.statusMessage,
            nativeBalanceUpdatedAt: nativeBalanceSnapshot.updatedAt,
            nativeBalanceProvenance: nativeBalanceSnapshot.provenance,
            freshnessTTL: freshnessTTLProvider(),
            trackedNFTCount: trackedNFTCountProvider(),
            musicCollectionCount: musicCollectionCountProvider(),
            receiptCount: receiptCountProvider(),
            pinnedActions: pinnedActionsProvider(),
            prefersDemoData: prefersDemoDataProvider(),
            pinnedItemCount: pinnedItemCountProvider()
        )
    }

    private static func makeSnapshot(
        from inputs: CapturedInputs,
        using builder: any ShellContextSourceBuilding
    ) -> ContextSnapshot {
        builder.makeContextSource(
            accountProvider: { inputs.account },
            addressProvider: { inputs.address },
            chainProvider: { inputs.chain },
            modeProvider: { inputs.mode },
            loadingProvider: { inputs.isLoading },
            refreshedAtProvider: { inputs.refreshedAt },
            nativeBalanceDisplayProvider: { inputs.nativeBalanceDisplay },
            nativeBalanceStatusMessageProvider: { inputs.nativeBalanceStatusMessage },
            nativeBalanceUpdatedAtProvider: { inputs.nativeBalanceUpdatedAt },
            nativeBalanceProvenanceProvider: { inputs.nativeBalanceProvenance },
            freshnessTTLProvider: { inputs.freshnessTTL },
            trackedNFTCountProvider: { inputs.trackedNFTCount },
            musicCollectionCountProvider: { inputs.musicCollectionCount },
            receiptCountProvider: { inputs.receiptCount },
            pinnedActionsProvider: { inputs.pinnedActions },
            prefersDemoDataProvider: { inputs.prefersDemoData },
            pinnedItemCountProvider: { inputs.pinnedItemCount }
        ).snapshot()
    }

    private struct NativeBalanceSnapshot {
        let displayValue: String?
        let statusMessage: String?
        let updatedAt: Date?
        let provenance: ContextProvenance
    }

    private static func resolveNativeBalance(
        address: String,
        chain: Chain,
        provider: any NativeBalanceProviding,
        strategy: RefreshStrategy,
        cachedSnapshot: ContextSnapshot
    ) async -> NativeBalanceSnapshot {
        guard !address.isEmpty else {
            return NativeBalanceSnapshot(
                displayValue: nil,
                statusMessage: nil,
                updatedAt: nil,
                provenance: .localCache
            )
        }

        if strategy == .reuseCachedBalance,
           cachedSnapshot.scope.accountAddress.value == address,
           cachedSnapshot.scope.selectedChains.value?.map(\.id) == [chain.rawValue] {
            return NativeBalanceSnapshot(
                displayValue: cachedSnapshot.balances.nativeBalanceDisplay.value,
                statusMessage: cachedSnapshot.balances.nativeBalanceStatusMessage.value,
                updatedAt: cachedSnapshot.balances.nativeBalanceDisplay.updatedAt,
                provenance: cachedSnapshot.balances.nativeBalanceDisplay.provenance
            )
        }

        do {
            let balance = try await provider.nativeBalance(for: address, chain: chain)
            return NativeBalanceSnapshot(
                displayValue: balance.formattedEtherDisplay,
                statusMessage: nil,
                updatedAt: .now,
                provenance: .onChain
            )
        } catch {
            if cachedSnapshot.scope.accountAddress.value == address,
               cachedSnapshot.scope.selectedChains.value?.map(\.id) == [chain.rawValue],
               let cachedDisplayValue = cachedSnapshot.balances.nativeBalanceDisplay.value {
                return NativeBalanceSnapshot(
                    displayValue: cachedDisplayValue,
                    statusMessage: nativeBalanceStatusMessage(for: error, hadCachedBalance: true),
                    updatedAt: cachedSnapshot.balances.nativeBalanceDisplay.updatedAt,
                    provenance: .localCache
                )
            }

            return NativeBalanceSnapshot(
                displayValue: nil,
                statusMessage: nativeBalanceStatusMessage(for: error, hadCachedBalance: false),
                updatedAt: nil,
                provenance: .localCache
            )
        }
    }

    private static func nativeBalanceStatusMessage(
        for error: Error,
        hadCachedBalance: Bool
    ) -> String {
        if let providerError = error as? ProviderAbstractionError {
            switch providerError {
            case .unauthorized:
                return "Auralis could not refresh the native balance because the provider rejected this build's credentials."
            case .rateLimited:
                return hadCachedBalance
                    ? "Auralis kept the last native balance because the provider is rate-limiting requests right now."
                    : "Auralis could not load the native balance because the provider is rate-limiting requests right now."
            case .offline:
                return hadCachedBalance
                    ? "Auralis kept the last native balance because this device appears to be offline."
                    : "Auralis could not load the native balance because this device appears to be offline."
            case .unavailable:
                return hadCachedBalance
                    ? "Auralis kept the last native balance because the provider is temporarily unavailable for this wallet and chain."
                    : "Auralis could not load the native balance because the provider is temporarily unavailable for this wallet and chain."
            case .invalidResponse:
                return hadCachedBalance
                    ? "Auralis kept the last native balance because the provider returned data it could not read for this wallet and chain."
                    : "Auralis could not load the native balance because the provider returned data it could not read for this wallet and chain."
            case .badStatus(let statusCode, _):
                return hadCachedBalance
                    ? "Auralis kept the last native balance because the provider returned HTTP \(statusCode)."
                    : "Auralis could not load the native balance because the provider returned HTTP \(statusCode)."
            case .providerError:
                return hadCachedBalance
                    ? "Auralis kept the last native balance because the provider reported an error for this wallet and chain."
                    : "Auralis could not load the native balance because the provider reported an error for this wallet and chain."
            case .missingAPIKey:
                return "Auralis could not refresh the native balance because this build is missing provider configuration."
            case .unsupportedChain:
                return "Auralis cannot refresh the native balance for this chain yet."
            case .invalidURL:
                return "Auralis could not refresh the native balance because the provider URL is invalid."
            case .invalidAddress:
                return "Auralis could not refresh the native balance because the wallet address is invalid."
            case .invalidBalancePayload:
                return hadCachedBalance
                    ? "Auralis kept the last native balance because the provider returned an unreadable balance payload."
                    : "Auralis could not load the native balance because the provider returned an unreadable balance payload."
            case .paginationStalled:
                return hadCachedBalance
                    ? "Auralis kept the last native balance because the provider stopped paginating cleanly."
                    : "Auralis could not load the native balance because the provider stopped paginating cleanly."
            case .unsupportedMethod:
                return "Auralis could not refresh the native balance because the provider does not support the required method."
            }
        }

        return hadCachedBalance
            ? "Auralis kept the last native balance because the live provider did not respond cleanly for this wallet and chain."
            : "Auralis could not load the native balance for the active wallet and chain just now. Try again in a moment."
    }
}
