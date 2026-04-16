import SwiftData
import SwiftUI

@MainActor
final class ERC20HoldingsSyncCoordinator: ObservableObject {
    struct Request: Equatable, Sendable {
        let accountAddress: String
        let chain: Chain
    }

    enum Result: Equatable {
        case applied
        case fetchFailed
        case persistFailed
        case dropped
        case cancelled
    }

    private var activeSyncID: UUID?

    func sync(
        request: Request,
        fetch: @escaping (Request) async throws -> [ProviderTokenHolding],
        persist: @escaping @MainActor (Request, [ProviderTokenHolding]) throws -> Void
    ) async -> Result {
        let syncID = UUID()
        activeSyncID = syncID

        do {
            let holdings = try await fetch(request)
            try Task.checkCancellation()
            guard activeSyncID == syncID else {
                return .dropped
            }

            do {
                try persist(request, holdings)
            } catch {
                guard activeSyncID == syncID else {
                    return .dropped
                }
                complete(syncID)
                return .persistFailed
            }

            try Task.checkCancellation()
            guard activeSyncID == syncID else {
                return .dropped
            }

            complete(syncID)
            return .applied
        } catch is CancellationError {
            if activeSyncID == syncID {
                complete(syncID)
                return .cancelled
            }
            return .dropped
        } catch {
            guard activeSyncID == syncID else {
                return .dropped
            }
            complete(syncID)
            return .fetchFailed
        }
    }

    private func complete(_ syncID: UUID) {
        if activeSyncID == syncID {
            activeSyncID = nil
        }
    }
}

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

struct ERC20TokenDetailView: View {
    let route: ERC20TokenRoute
    let currentAccountAddress: String

    @Query private var holdings: [TokenHolding]

    init(route: ERC20TokenRoute, currentAccountAddress: String) {
        self.route = route
        self.currentAccountAddress = currentAccountAddress

        let normalizedAccountAddress = NFT.normalizedScopeComponent(currentAccountAddress) ?? ""
        let contractAddress = NFT.normalizedScopeComponent(route.contractAddress) ?? route.contractAddress
        let chainRawValue = route.chain.rawValue
        _holdings = Query(
            filter: #Predicate<TokenHolding> {
                $0.accountAddressRawValue == normalizedAccountAddress &&
                $0.chainRawValue == chainRawValue &&
                $0.contractAddressRawValue == contractAddress
            }
        )
    }

    private var presentation: ERC20TokenDetailPresentation {
        ERC20TokenDetailPresentation(
            route: route,
            holding: holdings.first
        )
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                AuraSurfaceCard(style: .soft, cornerRadius: 28, padding: 18) {
                    VStack(alignment: .leading, spacing: 12) {
                        AuraTrustLabel(kind: .provider)

                        Text(presentation.title)
                            .font(.title2.weight(.bold))
                            .foregroundStyle(Color.textPrimary)
                            .accessibilityIdentifier("erc20.detail.title")

                        if let symbol = presentation.symbol {
                            Text(symbol)
                                .font(.title3.weight(.medium))
                                .foregroundStyle(Color.textSecondary)
                        }

                        HStack(spacing: 10) {
                            BadgeLabel(title: presentation.chainTitle)

                            if presentation.isPlaceholder {
                                BadgeLabel(title: "Metadata pending")
                            }

                            if presentation.isAmountHidden {
                                BadgeLabel(title: "Amount hidden")
                            }

                            if presentation.isMetadataStale {
                                BadgeLabel(title: "Metadata stale")
                            }

                            if presentation.isNativeStyleFallback {
                                BadgeLabel(title: "Native-style fallback")
                            }
                        }

                        if let metadataStatus = presentation.metadataStatus {
                            SecondaryText(metadataStatus)
                        }
                    }
                }

                AuraSurfaceCard(style: .soft, cornerRadius: 24, padding: 16) {
                    VStack(alignment: .leading, spacing: 12) {
                        HeadlineFontText("Balance")
                        ERC20TokenDetailRow(title: "Amount", value: presentation.amountDisplay)
                        ERC20TokenDetailRow(title: "Scope", value: presentation.scopeTitle)
                        ERC20TokenDetailRow(title: "Updated", value: presentation.updatedLabel)
                    }
                }

                AuraSurfaceCard(style: .soft, cornerRadius: 24, padding: 16) {
                    VStack(alignment: .leading, spacing: 12) {
                        HeadlineFontText("Token Identity")
                        ERC20TokenDetailRow(title: "Name", value: presentation.title)
                        ERC20TokenDetailRow(title: "Symbol", value: presentation.symbol)
                        ERC20TokenDetailRow(title: "Contract", value: presentation.contractAddress)
                    }
                }
            }
            .padding()
        }
        .navigationTitle(presentation.navigationTitle)
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("erc20.detail.screen")
    }
}

struct ERC20TokenDetailPresentation: Equatable {
    let title: String
    let navigationTitle: String
    let symbol: String?
    let amountDisplay: String
    let chainTitle: String
    let scopeTitle: String
    let contractAddress: String
    let updatedLabel: String?
    let isPlaceholder: Bool
    let isAmountHidden: Bool
    let isMetadataStale: Bool
    let isNativeStyleFallback: Bool
    let metadataStatus: String?

    init(route: ERC20TokenRoute, holding: TokenHolding?) {
        let resolvedTitle = Self.cleanedText(holding?.displayName)
            ?? Self.cleanedText(route.symbol)
            ?? "Token Detail"
        let resolvedSymbol = Self.cleanedText(holding?.symbol)
            ?? Self.cleanedText(route.symbol)
        let resolvedAmount = Self.cleanedText(holding?.amountDisplay)
            ?? "Balance unavailable"
        let resolvedContract = Self.cleanedText(holding?.contractAddress)
            ?? route.contractAddress

        self.title = resolvedTitle
        self.navigationTitle = resolvedTitle
        self.symbol = resolvedSymbol
        self.amountDisplay = resolvedAmount
        self.chainTitle = route.chain.routingDisplayName
        self.scopeTitle = "\(route.chain.routingDisplayName) token scope"
        self.contractAddress = resolvedContract
        self.updatedLabel = holding?.updatedAt.formatted(date: .abbreviated, time: .shortened)
        self.isPlaceholder = holding?.isPlaceholder ?? false
        self.isAmountHidden = holding?.hidesAmountUntilMetadataLoads ?? false
        self.isMetadataStale = holding?.hasStaleMetadata ?? false
        self.isNativeStyleFallback = holding?.balanceKind == .native

        if holding == nil {
            self.metadataStatus = "This token route is valid, but a scoped local holding is not currently available."
        } else if isNativeStyleFallback {
            self.metadataStatus = "This screen is using a native-style holding fallback inside the token detail contract."
        } else if isMetadataStale {
            self.metadataStatus = "Cached token metadata is older than the ERC-20 freshness window, so Auralis is refreshing it in the background."
        } else if isAmountHidden {
            self.metadataStatus = "Balance is hidden until token decimals load, so Auralis does not guess at base-unit values."
        } else if isPlaceholder || resolvedSymbol == nil {
            self.metadataStatus = "Some token metadata is still sparse for this holding."
        } else {
            self.metadataStatus = nil
        }
    }

    private static func cleanedText(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
            return nil
        }
        return trimmed
    }
}

private struct ERC20TokenDetailRow: View {
    let title: String
    let value: String?

    var body: some View {
        if let value, !value.isEmpty {
            HStack(alignment: .top, spacing: 12) {
                Text(title)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Color.textSecondary)

                Spacer(minLength: 12)

                Text(value)
                    .font(.subheadline)
                    .foregroundStyle(Color.textPrimary)
                    .multilineTextAlignment(.trailing)
            }
        }
    }
}

private struct ERC20HoldingRow: View {
    let row: TokenHoldingRowModel

    var body: some View {
        AuraSurfaceCard(style: .soft, cornerRadius: 26, padding: 16) {
            VStack(alignment: .leading, spacing: 14) {
                AuraTrustLabel(kind: .provider)

                HStack(alignment: .top, spacing: 14) {
                    tokenMark

                    VStack(alignment: .leading, spacing: 10) {
                        HStack(alignment: .top, spacing: 12) {
                            VStack(alignment: .leading, spacing: 6) {
                                Text(row.title)
                                    .font(.headline.weight(.semibold))
                                    .foregroundStyle(Color.textPrimary)
                                    .fixedSize(horizontal: false, vertical: true)

                                Text(row.subtitle)
                                    .font(.subheadline)
                                    .foregroundStyle(Color.textSecondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }

                            Spacer(minLength: 12)

                            VStack(alignment: .trailing, spacing: 6) {
                                Text(row.amountDisplay)
                                    .font(.headline.weight(.bold))
                                    .foregroundStyle(Color.textPrimary)
                                    .multilineTextAlignment(.trailing)

                                if row.canOpenDetail {
                                    Label("Open detail", systemImage: "arrow.up.right")
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(Color.accent.opacity(0.9))
                                }
                            }
                        }

                        ViewThatFits(in: .vertical) {
                            HStack(spacing: 8) {
                                primaryPills
                            }

                            VStack(alignment: .leading, spacing: 8) {
                                primaryPills
                            }
                        }
                    }
                }

                HStack(alignment: .center, spacing: 10) {
                    Label(row.updatedLabel, systemImage: "clock")
                        .font(.caption)
                        .foregroundStyle(Color.textSecondary)

                    Spacer(minLength: 8)

                    if let symbol = row.symbol, !symbol.isEmpty {
                        Text(symbol)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Color.textSecondary)
                    }
                }
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var tokenMark: some View {
        ZStack {
            Circle()
                .fill(markGradient)
                .frame(width: 48, height: 48)

            Text(row.symbolGlyph)
                .font(.subheadline.weight(.black))
                .foregroundStyle(Color.white.opacity(0.96))
        }
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private var primaryPills: some View {
        AuraPill(
            row.kindTitle,
            systemImage: row.kind == .native ? "bolt.fill" : "bitcoinsign.circle",
            emphasis: row.kind == .native ? .accent : .neutral
        )

        if row.isPlaceholder {
            AuraPill("Metadata Pending", systemImage: "sparkles", emphasis: .neutral)
        }

        if row.isAmountHidden {
            AuraPill("Amount Hidden", systemImage: "eye.slash", emphasis: .neutral)
        }

        if row.isMetadataStale {
            AuraPill("Stale", systemImage: "clock.arrow.circlepath", emphasis: .neutral)
        }
    }

    private var markGradient: LinearGradient {
        let colors: [Color]
        switch row.kind {
        case .native:
            colors = [Color.accent.opacity(0.95), Color.deepBlue.opacity(0.9)]
        case .erc20:
            if row.isMetadataStale {
                colors = [Color.orange.opacity(0.9), Color.accent.opacity(0.75)]
            } else if row.isPlaceholder {
                colors = [Color.deepBlue.opacity(0.95), Color.secondary.opacity(0.8)]
            } else {
                colors = [Color.secondary.opacity(0.9), Color.accent.opacity(0.8)]
            }
        }

        return LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing)
    }
}

private struct ERC20HoldingsOverviewCard: View {
    let walletAddress: String
    let chainTitle: String
    let holdingsSubtitle: String
    let freshnessTitle: String
    let nativeHoldingCount: Int
    let tokenHoldingCount: Int
    let isSyncing: Bool

    var body: some View {
        AuraSurfaceCard(style: .regular, cornerRadius: 30, padding: 18) {
            VStack(alignment: .leading, spacing: 16) {
                AuraTrustLabel(kind: .provider)

                AuraSectionHeader(
                    title: "Token Scope",
                    subtitle: holdingsSubtitle
                ) {
                    AuraPill(
                        isSyncing ? "Syncing" : freshnessTitle,
                        systemImage: isSyncing ? "arrow.triangle.2.circlepath.circle.fill" : "clock.arrow.circlepath",
                        emphasis: isSyncing ? .accent : .neutral
                    )
                }

                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(walletAddress.displayAddress)
                            .font(.title3.weight(.bold))
                            .foregroundStyle(Color.textPrimary)

                        Text("\(chainTitle) wallet scope")
                            .font(.subheadline)
                            .foregroundStyle(Color.textSecondary)
                    }

                    Spacer(minLength: 12)
                }

                HStack(spacing: 10) {
                    metricCard(
                        title: "Native",
                        value: "\(nativeHoldingCount)",
                        systemImage: "bolt.fill"
                    )
                    metricCard(
                        title: "ERC-20",
                        value: "\(tokenHoldingCount)",
                        systemImage: "bitcoinsign.circle"
                    )
                }
            }
        }
    }

    private func metricCard(title: String, value: String, systemImage: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: systemImage)
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color.textSecondary)

            Text(value)
                .font(.title3.weight(.black))
                .foregroundStyle(Color.textPrimary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
        }
    }
}

private extension TokenHoldingRowModel {
    var kindTitle: String {
        switch kind {
        case .native:
            return "Native"
        case .erc20:
            return "ERC-20"
        }
    }

    var symbolGlyph: String {
        let source = (symbol?.isEmpty == false ? symbol : title)
            .map { String($0.prefix(2)).uppercased() }
        return (source?.isEmpty == false ? source : nil) ?? "TK"
    }

    var updatedLabel: String {
        "Updated \(updatedAt.formatted(date: .abbreviated, time: .shortened))"
    }
}

private struct ERC20HoldingsLoadingView: View {
    let chain: Chain

    var body: some View {
        VStack(spacing: 16) {
            ProgressView()
                .controlSize(.large)

            Text("Syncing Token Holdings")
                .font(.headline)
                .foregroundStyle(Color.textPrimary)

            Text("Fetching \(chain.routingDisplayName) balances and metadata for the active wallet.")
                .font(.subheadline)
                .foregroundStyle(Color.textSecondary)
                .multilineTextAlignment(.center)
        }
        .padding(24)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("erc20.loading")
    }
}

private struct ERC20HoldingsSyncKey: Hashable {
    let accountAddress: String
    let chain: Chain
    let nativeBalanceDisplay: String?
    let updatedAt: Date?
    let refreshAnchor: Date?
}
