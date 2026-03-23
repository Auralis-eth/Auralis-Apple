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
        let freshnessTTL: TimeInterval?
        let trackedNFTCount: Int?
        let prefersDemoData: Bool?

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
    private let freshnessTTLProvider: () -> TimeInterval?
    private let trackedNFTCountProvider: () -> Int?
    private let prefersDemoDataProvider: () -> Bool?
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
        freshnessTTLProvider: @escaping () -> TimeInterval?,
        trackedNFTCountProvider: @escaping () -> Int?,
        prefersDemoDataProvider: @escaping () -> Bool?,
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
        self.freshnessTTLProvider = freshnessTTLProvider
        self.trackedNFTCountProvider = trackedNFTCountProvider
        self.prefersDemoDataProvider = prefersDemoDataProvider
        self.beforeResolve = beforeResolve

        let initialInputs = Self.captureInputs(
            accountProvider: accountProvider,
            addressProvider: addressProvider,
            chainProvider: chainProvider,
            modeProvider: modeProvider,
            loadingProvider: loadingProvider,
            refreshedAtProvider: refreshedAtProvider,
            freshnessTTLProvider: freshnessTTLProvider,
            trackedNFTCountProvider: trackedNFTCountProvider,
            prefersDemoDataProvider: prefersDemoDataProvider
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
        let capturedInputs = captureInputs()

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
    private func captureInputs() -> CapturedInputs {
        Self.captureInputs(
            accountProvider: accountProvider,
            addressProvider: addressProvider,
            chainProvider: chainProvider,
            modeProvider: modeProvider,
            loadingProvider: loadingProvider,
            refreshedAtProvider: refreshedAtProvider,
            freshnessTTLProvider: freshnessTTLProvider,
            trackedNFTCountProvider: trackedNFTCountProvider,
            prefersDemoDataProvider: prefersDemoDataProvider
        )
    }

    private static func captureInputs(
        accountProvider: () -> EOAccount?,
        addressProvider: () -> String,
        chainProvider: () -> Chain,
        modeProvider: () -> AppMode,
        loadingProvider: () -> Bool,
        refreshedAtProvider: () -> Date?,
        freshnessTTLProvider: () -> TimeInterval?,
        trackedNFTCountProvider: () -> Int?,
        prefersDemoDataProvider: () -> Bool?
    ) -> CapturedInputs {
        CapturedInputs(
            account: accountProvider(),
            address: addressProvider(),
            chain: chainProvider(),
            mode: modeProvider(),
            isLoading: loadingProvider(),
            refreshedAt: refreshedAtProvider(),
            freshnessTTL: freshnessTTLProvider(),
            trackedNFTCount: trackedNFTCountProvider(),
            prefersDemoData: prefersDemoDataProvider()
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
            freshnessTTLProvider: { inputs.freshnessTTL },
            trackedNFTCountProvider: { inputs.trackedNFTCount },
            prefersDemoDataProvider: { inputs.prefersDemoData }
        ).snapshot()
    }
}
