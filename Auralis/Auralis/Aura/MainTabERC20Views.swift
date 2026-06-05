import AuralisPrimaryModels
import AuralisPrimaryPersistence
import ChainProviders
import SwiftData
import SwiftUI
import AuraUI
import NFTDomain
import NFTPersistence
import NFTPresentation
import NFTProviderAdapters
import TokenStorage

struct ERC20TokensRootView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var holdings: [TokenHolding]

    let currentAccountAddress: String
    let currentChain: Chain
    let contextSnapshot: ContextSnapshot
    let nftService: NFTService
    let refreshAction: @MainActor () async -> Void
    let router: AppRouter
    let holdingsSyncerFactory: @MainActor (ModelContext) -> any ERC20HoldingsSyncing

    @State private var persistenceErrorMessage: String?
    @State private var providerErrorMessage: String?
    @State private var providerWarningMessage: String?
    @State private var isSyncingTokenHoldings = false
    @State private var activeTokenSyncViewID: UUID?
    @State private var holdingsSyncer: (any ERC20HoldingsSyncing)?

    init(
        currentAccountAddress: String,
        currentChain: Chain,
        contextSnapshot: ContextSnapshot,
        nftService: NFTService,
        refreshAction: @escaping @MainActor () async -> Void,
        router: AppRouter,
        holdingsSyncerFactory: @escaping @MainActor (ModelContext) -> any ERC20HoldingsSyncing
    ) {
        self.currentAccountAddress = currentAccountAddress
        self.currentChain = currentChain
        self.contextSnapshot = contextSnapshot
        self.nftService = nftService
        self.refreshAction = refreshAction
        self.router = router
        self.holdingsSyncerFactory = holdingsSyncerFactory

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
        holdings.map { TokenHoldingRowModel(holding: $0) }
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

    private var nativeBalanceStatusMessage: String? {
        contextSnapshot.balances.nativeBalanceStatusMessage.value
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
                    } else if let persistenceErrorMessage {
                        ShellStatusCard(
                            eyebrow: "Local Storage",
                            title: "Token Holdings Not Saved",
                            message: persistenceErrorMessage,
                            systemImage: "externaldrive.badge.exclamationmark",
                            tone: .warning,
                            primaryAction: ShellStatusAction(
                                title: "Retry",
                                systemImage: "arrow.clockwise",
                                handler: refresh
                            )
                        )
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
        let viewSyncID = UUID()
        activeTokenSyncViewID = viewSyncID
        isSyncingTokenHoldings = true
        AuraAccessibilityAnnouncer.announce(String(localized: "Syncing token holdings"))
        defer {
            if activeTokenSyncViewID == viewSyncID {
                isSyncingTokenHoldings = false
            }
        }

        let request = ERC20HoldingsSyncRequest(
            accountAddress: currentAccountAddress,
            chain: currentChain,
            nativeBalanceDisplay: nativeBalanceDisplay,
            nativeBalanceUpdatedAt: nativeBalanceUpdatedAt,
            hadNoHoldings: holdings.isEmpty
        )
        let result = await currentHoldingsSyncer().sync(request: request)

        guard activeTokenSyncViewID == viewSyncID else {
            return
        }

        providerWarningMessage = result.providerWarningMessage
        providerErrorMessage = result.providerErrorMessage
        persistenceErrorMessage = result.persistenceErrorMessage
        if result.providerErrorMessage != nil || result.persistenceErrorMessage != nil {
            AuraAccessibilityAnnouncer.announce(String(localized: "Token holdings sync failed"))
        } else if result.providerWarningMessage != nil {
            AuraAccessibilityAnnouncer.announce(String(localized: "Token holdings synced with warnings"))
        } else {
            AuraAccessibilityAnnouncer.announce(String(localized: "Token holdings updated"))
        }
    }

    private func currentHoldingsSyncer() -> any ERC20HoldingsSyncing {
        if let holdingsSyncer {
            return holdingsSyncer
        }

        let syncer = holdingsSyncerFactory(modelContext)
        holdingsSyncer = syncer
        return syncer
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
        } else if let providerWarningMessage {
            ShellStatusBanner(
                title: "Token Metadata Limited",
                message: providerWarningMessage,
                systemImage: "exclamationmark.arrow.trianglehead.2.clockwise.rotate.90",
                tone: .warning,
                action: ShellStatusAction(
                    title: "Retry",
                    systemImage: "arrow.clockwise",
                    handler: refresh
                )
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
        } else if let nativeBalanceStatusMessage {
            ShellStatusBanner(
                title: nativeBalanceDisplay == nil ? "Native Balance Unavailable" : "Native Balance Limited",
                message: nativeBalanceStatusMessage,
                systemImage: "bitcoinsign.circle",
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
