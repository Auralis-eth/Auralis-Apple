import Foundation
import Observation

@MainActor
@Observable
final class ContextService {
    struct RequestScope: Equatable {
        let accountAddress: String
        let chain: Chain
        let mode: AppMode
    }

    private struct CapturedInputs {
        let account: EOAccount?
        let address: String
        let chain: Chain
        let mode: AppMode
        let isLoading: Bool
        let refreshedAt: Date?
        let nativeBalanceDisplay: String?
        let nativeBalanceUpdatedAt: Date?
        let nativeBalanceProvenance: ContextProvenance
        let freshnessTTL: TimeInterval?
        let trackedNFTCount: Int?
        let musicCollectionCount: Int?
        let receiptCount: Int?
        let prefersDemoData: Bool?
        let pinnedItemCount: Int?

        var scope: RequestScope {
            RequestScope(
                accountAddress: account?.address ?? address,
                chain: chain,
                mode: mode
            )
        }
    }

    private let contextSourceBuilder: any ShellContextSourceBuilding
    private let accountProvider: () -> EOAccount?
    private let addressProvider: () -> String
    private let chainProvider: () -> Chain
    private let modeProvider: () -> AppMode
    private let loadingProvider: () -> Bool
    private let refreshedAtProvider: () -> Date?
    private let nativeBalanceProvider: any NativeBalanceProviding
    private let freshnessTTLProvider: () -> TimeInterval?
    private let trackedNFTCountProvider: () -> Int?
    private let musicCollectionCountProvider: () -> Int?
    private let receiptCountProvider: () -> Int?
    private let prefersDemoDataProvider: () -> Bool?
    private let pinnedItemCountProvider: () -> Int?
    private let beforeResolve: @MainActor () async -> Void

    private(set) var snapshot: ContextSnapshot

    @ObservationIgnored private var inFlightTask: Task<ContextSnapshot, Never>?
    @ObservationIgnored private var inFlightScope: RequestScope?
    @ObservationIgnored private var refreshGeneration: Int = 0

    init(
        contextSourceBuilder: any ShellContextSourceBuilding,
        accountProvider: @escaping () -> EOAccount?,
        addressProvider: @escaping () -> String,
        chainProvider: @escaping () -> Chain,
        modeProvider: @escaping () -> AppMode,
        loadingProvider: @escaping () -> Bool,
        refreshedAtProvider: @escaping () -> Date?,
        nativeBalanceProvider: any NativeBalanceProviding,
        freshnessTTLProvider: @escaping () -> TimeInterval?,
        trackedNFTCountProvider: @escaping () -> Int?,
        musicCollectionCountProvider: @escaping () -> Int?,
        receiptCountProvider: @escaping () -> Int?,
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
            nativeBalanceUpdatedAt: nil,
            nativeBalanceProvenance: .localCache,
            freshnessTTL: freshnessTTLProvider(),
            trackedNFTCount: trackedNFTCountProvider(),
            musicCollectionCount: musicCollectionCountProvider(),
            receiptCount: receiptCountProvider(),
            prefersDemoData: prefersDemoDataProvider(),
            pinnedItemCount: pinnedItemCountProvider()
        )
        self.snapshot = Self.makeSnapshot(
            from: initialInputs,
            using: contextSourceBuilder
        )
    }

    func cachedSnapshot() -> ContextSnapshot {
        snapshot
    }

    @discardableResult
    func refresh(
        correlationID: String? = nil,
        receiptEventLogger: ReceiptEventLogger? = nil
    ) async -> ContextSnapshot {
        let capturedInputs = await captureInputs()

        if let inFlightTask, inFlightScope == capturedInputs.scope {
            return await inFlightTask.value
        }

        inFlightTask?.cancel()
        refreshGeneration += 1
        let generation = refreshGeneration

        let task = Task { @MainActor [capturedInputs, contextSourceBuilder, beforeResolve] in
            await beforeResolve()
            return Self.makeSnapshot(from: capturedInputs, using: contextSourceBuilder)
        }

        inFlightTask = task
        inFlightScope = capturedInputs.scope

        let resolvedSnapshot = await task.value
        let didWinGeneration = generation == refreshGeneration
        if didWinGeneration {
            snapshot = resolvedSnapshot
            inFlightTask = nil
            inFlightScope = nil
        }

        receiptEventLogger?.recordContextBuilt(
            snapshot: resolvedSnapshot,
            correlationID: correlationID
        )

        return didWinGeneration ? snapshot : resolvedSnapshot
    }
}

private extension ContextService {
    private func captureInputs() async -> CapturedInputs {
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
            prefersDemoDataProvider: prefersDemoDataProvider,
            pinnedItemCountProvider: pinnedItemCountProvider
        )
    }

    private static func captureInputs(
        accountProvider: () -> EOAccount?,
        addressProvider: () -> String,
        chainProvider: () -> Chain,
        modeProvider: () -> AppMode,
        loadingProvider: () -> Bool,
        refreshedAtProvider: () -> Date?,
        nativeBalanceProvider: any NativeBalanceProviding,
        freshnessTTLProvider: () -> TimeInterval?,
        trackedNFTCountProvider: () -> Int?,
        musicCollectionCountProvider: () -> Int?,
        receiptCountProvider: () -> Int?,
        prefersDemoDataProvider: () -> Bool?,
        pinnedItemCountProvider: () -> Int?
    ) async -> CapturedInputs {
        let address = addressProvider()
        let chain = chainProvider()
        let nativeBalanceSnapshot = await resolveNativeBalance(
            address: address,
            chain: chain,
            provider: nativeBalanceProvider
        )

        return CapturedInputs(
            account: accountProvider(),
            address: address,
            chain: chain,
            mode: modeProvider(),
            isLoading: loadingProvider(),
            refreshedAt: refreshedAtProvider(),
            nativeBalanceDisplay: nativeBalanceSnapshot.displayValue,
            nativeBalanceUpdatedAt: nativeBalanceSnapshot.updatedAt,
            nativeBalanceProvenance: nativeBalanceSnapshot.provenance,
            freshnessTTL: freshnessTTLProvider(),
            trackedNFTCount: trackedNFTCountProvider(),
            musicCollectionCount: musicCollectionCountProvider(),
            receiptCount: receiptCountProvider(),
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
            nativeBalanceUpdatedAtProvider: { inputs.nativeBalanceUpdatedAt },
            nativeBalanceProvenanceProvider: { inputs.nativeBalanceProvenance },
            freshnessTTLProvider: { inputs.freshnessTTL },
            trackedNFTCountProvider: { inputs.trackedNFTCount },
            musicCollectionCountProvider: { inputs.musicCollectionCount },
            receiptCountProvider: { inputs.receiptCount },
            prefersDemoDataProvider: { inputs.prefersDemoData },
            pinnedItemCountProvider: { inputs.pinnedItemCount }
        ).snapshot()
    }

    private struct NativeBalanceSnapshot {
        let displayValue: String?
        let updatedAt: Date?
        let provenance: ContextProvenance
    }

    private static func resolveNativeBalance(
        address: String,
        chain: Chain,
        provider: any NativeBalanceProviding
    ) async -> NativeBalanceSnapshot {
        guard !address.isEmpty else {
            return NativeBalanceSnapshot(
                displayValue: nil,
                updatedAt: nil,
                provenance: .localCache
            )
        }

        do {
            let balance = try await provider.nativeBalance(for: address, chain: chain)
            return NativeBalanceSnapshot(
                displayValue: balance.formattedEtherDisplay,
                updatedAt: .now,
                provenance: .onChain
            )
        } catch {
            return NativeBalanceSnapshot(
                displayValue: nil,
                updatedAt: nil,
                provenance: .localCache
            )
        }
    }
}
