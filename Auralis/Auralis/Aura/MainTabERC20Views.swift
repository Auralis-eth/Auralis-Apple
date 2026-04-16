import SwiftData
import SwiftUI

struct ERC20TokensRootView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var holdings: [TokenHolding]

    let currentAccountAddress: String
    let currentChain: Chain
    let contextSnapshot: ContextSnapshot
    let nftService: NFTService
    let refreshAction: @MainActor () async -> Void
    let router: AppRouter
    let tokenHoldingsStoreFactory: @MainActor (ModelContext) -> TokenHoldingsStore
    let tokenHoldingsProviderFactory: () -> any TokenHoldingsProviding

    @StateObject private var syncCoordinator = ERC20HoldingsSyncCoordinator()
    @State private var persistenceErrorMessage: String?
    @State private var providerErrorMessage: String?
    @State private var isSyncingTokenHoldings = false
    @State private var activeTokenSyncViewID: UUID?

    init(
        currentAccountAddress: String,
        currentChain: Chain,
        contextSnapshot: ContextSnapshot,
        nftService: NFTService,
        refreshAction: @escaping @MainActor () async -> Void,
        router: AppRouter,
        tokenHoldingsStoreFactory: @escaping @MainActor (ModelContext) -> TokenHoldingsStore,
        tokenHoldingsProviderFactory: @escaping () -> any TokenHoldingsProviding
    ) {
        self.currentAccountAddress = currentAccountAddress
        self.currentChain = currentChain
        self.contextSnapshot = contextSnapshot
        self.nftService = nftService
        self.refreshAction = refreshAction
        self.router = router
        self.tokenHoldingsStoreFactory = tokenHoldingsStoreFactory
        self.tokenHoldingsProviderFactory = tokenHoldingsProviderFactory

        let normalizedAccountAddress = NFT.normalizedScopeComponent(currentAccountAddress) ?? ""
        let chainRawValue = currentChain.rawValue
        _holdings = Query(
            filter: #Predicate<TokenHolding> {
                $0.accountAddressRawValue == normalizedAccountAddress &&
                $0.chainRawValue == chainRawValue
            },
            sort: [
                SortDescriptor(\TokenHolding.sortPriority, order: .forward),
                SortDescriptor(\TokenHolding.displayName, order: .forward)
            ]
        )
    }

    private var rowModels: [TokenHoldingRowModel] {
        holdings.map(TokenHoldingRowModel.init(holding:))
    }

    private var nativeHoldingCount: Int {
        rowModels.filter { $0.kind == .native }.count
    }

    private var tokenHoldingCount: Int {
        rowModels.filter { $0.kind == .erc20 }.count
    }

    private var holdingsSubtitle: String {
        "\(rowModels.count) assets scoped to \(currentChain.routingDisplayName)"
    }

    private var freshnessTitle: String {
        contextSnapshot.freshness.label
    }

    private var nativeBalanceDisplay: String? {
        contextSnapshot.balances.nativeBalanceDisplay.value
    }

    private var nativeBalanceUpdatedAt: Date? {
        contextSnapshot.balances.nativeBalanceDisplay.updatedAt
            ?? contextSnapshot.freshness.lastSuccessfulRefreshAt
    }

    private var syncKey: ERC20HoldingsSyncKey {
        ERC20HoldingsSyncKey(
            accountAddress: NFT.normalizedScopeComponent(currentAccountAddress) ?? "",
            chain: currentChain,
            nativeBalanceDisplay: nativeBalanceDisplay,
            updatedAt: nativeBalanceUpdatedAt,
            refreshAnchor: contextSnapshot.freshness.lastSuccessfulRefreshAt
        )
    }

    var body: some View {
        Group {
            if holdings.isEmpty {
                AuraScenicScreen(contentAlignment: .center) {
                    if isSyncingTokenHoldings {
                        ERC20HoldingsLoadingView(chain: currentChain)
                    } else if let providerErrorMessage {
                        ShellStatusCard(
                            eyebrow: "Provider Error",
                            title: "Token Holdings Unavailable",
                            message: providerErrorMessage,
                            systemImage: "externaldrive.badge.wifi",
                            tone: .critical,
                            primaryAction: ShellStatusAction(
                                title: "Retry",
                                systemImage: "arrow.clockwise",
                                handler: refresh
                            )
                        )
                    } else if let failure = nftService.providerFailurePresentation(isShowingCachedContent: false) {
                        ShellProviderFailureStateView(
                            failure: failure,
                            retry: refresh
                        )
                    } else {
                        ShellEmptyLibraryStateView(
                            kind: .token,
                            snapshot: contextSnapshot
                        )
                    }
                }
            } else {
                AuraScenicScreen(horizontalPadding: 12, verticalPadding: 12) {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 16) {
                            holdingsStatusBanner

                            ERC20HoldingsOverviewCard(
                                walletAddress: currentAccountAddress,
                                chainTitle: currentChain.routingDisplayName,
                                holdingsSubtitle: holdingsSubtitle,
                                freshnessTitle: freshnessTitle,
                                nativeHoldingCount: nativeHoldingCount,
                                tokenHoldingCount: tokenHoldingCount,
                                isSyncing: isSyncingTokenHoldings
                            )

                            VStack(alignment: .leading, spacing: 14) {
                                AuraSectionHeader(
                                    title: "Wallet Holdings",
                                    subtitle: "Native balance and ERC-20 assets stay grouped under the active wallet and chain scope."
                                ) {
                                    AuraPill(
                                        freshnessTitle,
                                        systemImage: isSyncingTokenHoldings ? "arrow.triangle.2.circlepath.circle.fill" : "clock.arrow.circlepath",
                                        emphasis: isSyncingTokenHoldings ? .accent : .neutral
                                    )
                                }

                                LazyVStack(spacing: 14) {
                                    ForEach(rowModels) { row in
                                        if row.canOpenDetail, let contractAddress = row.contractAddress {
                                            Button {
                                                router.showERC20Token(
                                                    contractAddress: contractAddress,
                                                    chain: currentChain,
                                                    symbol: row.symbol ?? row.title
                                                )
                                            } label: {
                                                ERC20HoldingRow(row: row)
                                            }
                                            .buttonStyle(.plain)
                                            .accessibilityIdentifier("erc20.row.\(row.id)")
                                        } else {
                                            ERC20HoldingRow(row: row)
                                                .accessibilityIdentifier("erc20.row.\(row.id)")
                                        }
                                    }
                                }
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
        }
        .navigationTitle("ERC-20")
        .accessibilityIdentifier("erc20.root")
        .task(id: syncKey) {
            await syncHoldings()
        }
    }

    private func refresh() {
        Task {
            await refreshAction()
        }
    }

    private func syncHoldings() async {
        syncNativeHoldingIfAvailable()

        let viewSyncID = UUID()
        activeTokenSyncViewID = viewSyncID
        isSyncingTokenHoldings = true
        defer {
            if activeTokenSyncViewID == viewSyncID {
                isSyncingTokenHoldings = false
            }
        }

        guard !currentAccountAddress.isEmpty,
              currentChain.supportsERC20Holdings else {
            providerErrorMessage = nil
            persistenceErrorMessage = nil
            return
        }

        let request = ERC20HoldingsSyncCoordinator.Request(
            accountAddress: currentAccountAddress,
            chain: currentChain
        )
        let hadNoHoldings = holdings.isEmpty
        let result = await syncCoordinator.sync(
            request: request,
            fetch: { request in
                try await tokenHoldingsProviderFactory().tokenHoldings(
                    for: request.accountAddress,
                    chain: request.chain
                )
            },
            persist: { request, providerHoldings in
                try tokenHoldingsStoreFactory(modelContext).replaceERC20Holdings(
                    accountAddress: request.accountAddress,
                    chain: request.chain,
                    holdings: providerHoldings
                )
            }
        )

        guard activeTokenSyncViewID == viewSyncID else {
            return
        }

        switch result {
        case .applied:
            providerErrorMessage = nil
            persistenceErrorMessage = nil
        case .fetchFailed:
            providerErrorMessage = hadNoHoldings
                ? "Auralis could not load token holdings for the active wallet and chain just now. Try again in a moment."
                : "Auralis kept the last saved ERC-20 holdings because the live token provider did not respond cleanly for this scope."
        case .persistFailed:
            providerErrorMessage = nil
            persistenceErrorMessage = "Auralis kept the last saved ERC-20 holdings, but the refreshed token rows could not be written on this device."
        case .dropped, .cancelled:
            return
        }
    }

    private func syncNativeHoldingIfAvailable() {
        guard let nativeBalanceDisplay,
              let updatedAt = nativeBalanceUpdatedAt,
              !currentAccountAddress.isEmpty else {
            return
        }

        do {
            try tokenHoldingsStoreFactory(modelContext).upsertNativeHolding(
                accountAddress: currentAccountAddress,
                chain: currentChain,
                amountDisplay: nativeBalanceDisplay,
                updatedAt: updatedAt
            )
            persistenceErrorMessage = nil
        } catch {
            persistenceErrorMessage = "Auralis kept the last saved holdings view, but the latest native balance could not be written on this device."
        }
    }

    @ViewBuilder
    private var holdingsStatusBanner: some View {
        if let persistenceErrorMessage {
            ShellStatusBanner(
                title: "Local holdings could not be updated",
                message: persistenceErrorMessage,
                systemImage: "externaldrive.badge.exclamationmark",
                tone: .warning,
                action: nil
            )
        } else if let providerErrorMessage {
            ShellStatusBanner(
                title: "Showing Last Saved Holdings",
                message: providerErrorMessage,
                systemImage: "externaldrive.badge.wifi",
                tone: .warning,
                action: ShellStatusAction(
                    title: "Retry",
                    systemImage: "arrow.clockwise",
                    handler: refresh
                )
            )
        } else if let failure = nftService.providerFailurePresentation(isShowingCachedContent: true) {
            ShellStatusBanner(
                title: failure.title,
                message: failure.message,
                systemImage: failure.systemImage,
                tone: .warning,
                action: failure.isRetryable ? ShellStatusAction(
                    title: "Retry",
                    systemImage: "arrow.clockwise",
                    handler: refresh
                ) : nil
            )
        }
    }
}
