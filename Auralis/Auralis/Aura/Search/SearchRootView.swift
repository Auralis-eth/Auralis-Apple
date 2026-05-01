import OSLog
import SwiftData
import SwiftUI

// SwiftLint currently misclassifies these file-scope snapshot helpers as overly nested.
private struct SearchLocalIndexRefreshKey: Equatable {
    let currentAccountAddress: String?
    let currentChain: Chain
    let nftIDs: [PersistentIdentifier]
    let holdingIDs: [PersistentIdentifier]
}

enum SearchRootPresentationContent: Equatable {
    case history
    case safety
    case noResults
    case results
}

struct SearchRootPresentation: Equatable {
    let showsDetection: Bool
    let content: SearchRootPresentationContent
}

struct SearchRootView: View {
    private let logger = Logger(subsystem: "Auralis", category: "SearchRootView")

    @Environment(\.modelContext) private var modelContext
    @Query private var accounts: [EOAccount]
    @Query private var nfts: [NFT]
    @Query private var holdings: [TokenHolding]

    let router: AppRouter
    let currentAccountAddress: String?
    let currentChain: Chain
    let historyStore: SearchHistoryStore

    @State private var query = ""
    @State private var historyEntries: [SearchHistoryEntry] = []
    @State private var historyErrorMessage: String?
    @State private var localIndex: SearchLocalIndex = .empty
    @State private var accountMatches: [SearchLocalMatch] = []
    @State private var ensMatches: [SearchLocalMatch] = []
    @FocusState private var isQueryFieldFocused: Bool

    private let parser = SearchQueryParser()

    init(
        router: AppRouter,
        currentAccountAddress: String?,
        currentChain: Chain,
        historyStore: SearchHistoryStore
    ) {
        self.router = router
        self.currentAccountAddress = currentAccountAddress
        self.currentChain = currentChain
        self.historyStore = historyStore

        let normalizedAccountAddress = NFT.normalizedScopeComponent(currentAccountAddress) ?? ""
        let chainRawValue = currentChain.rawValue
        _accounts = Query(
            sort: [
                SortDescriptor(\EOAccount.lastSelectedAt, order: .reverse),
                SortDescriptor(\EOAccount.addedAt, order: .reverse),
                SortDescriptor(\EOAccount.address)
            ]
        )
        _nfts = Query(
            filter: #Predicate<NFT> {
                $0.accountAddressRawValue == normalizedAccountAddress &&
                $0.networkRawValue == chainRawValue
            }
        )
        _holdings = Query(
            filter: #Predicate<TokenHolding> {
                $0.accountAddressRawValue == normalizedAccountAddress &&
                $0.chainRawValue == chainRawValue
            }
        )
    }

    private var localIndexRefreshKey: SearchLocalIndexRefreshKey {
        SearchLocalIndexRefreshKey(
            currentAccountAddress: currentAccountAddress,
            currentChain: currentChain,
            nftIDs: nfts.map(\.persistentModelID),
            holdingIDs: holdings.map(\.persistentModelID)
        )
    }

    private var baseClassification: SearchQueryClassification {
        parser.classify(query: query, index: localIndex)
    }

    private var classification: SearchQueryClassification {
        switch baseClassification.kind {
        case .walletAddress, .contractAddress, .ambiguousAddress:
            let contractMatches = baseClassification.localMatches.filter { $0.kind == .contract }
            let combinedMatches = Array((accountMatches + contractMatches).prefix(6))
            let kind: SearchQueryKind

            if !accountMatches.isEmpty, contractMatches.isEmpty {
                kind = .walletAddress
            } else if accountMatches.isEmpty, !contractMatches.isEmpty {
                kind = .contractAddress
            } else {
                kind = .ambiguousAddress
            }

            return SearchQueryClassification(
                rawQuery: baseClassification.rawQuery,
                normalizedQuery: baseClassification.normalizedQuery,
                kind: kind,
                localMatches: combinedMatches
            )

        case .ensName:
            return SearchQueryClassification(
                rawQuery: baseClassification.rawQuery,
                normalizedQuery: baseClassification.normalizedQuery,
                kind: .ensName,
                localMatches: ensMatches
            )

        default:
            return baseClassification
        }
    }

    private var presentation: SearchRootPresentation {
        Self.makePresentation(
            classification: classification,
            historyEntries: historyEntries
        )
    }

    var body: some View {
        AuraScenicScreen(horizontalPadding: 12, verticalPadding: 12) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if let historyErrorMessage {
                        AuraErrorBanner(
                            title: "Search History Unavailable",
                            message: historyErrorMessage,
                            systemImage: "exclamationmark.triangle"
                        )
                    }

                    SearchInputCard(
                        query: $query,
                        isFocused: _isQueryFieldFocused
                    )

                    if presentation.showsDetection {
                        SearchDetectionCard(classification: classification)
                    }

                    switch presentation.content {
                    case .history:
                        SearchHistoryCard(
                            historyEntries: historyEntries,
                            onSelect: recallHistory,
                            onDelete: deleteHistoryEntry,
                            onClearAll: clearHistory
                        )
                    case .safety:
                        AuraEmptyState(
                            eyebrow: "Search",
                            title: classification.kind.title,
                            message: classification.kind.feedbackMessage,
                            systemImage: "exclamationmark.triangle",
                            tone: .critical
                        )
                    case .noResults:
                        SearchNoResultsCard(classification: classification)
                    case .results:
                        SearchLocalMatchesCard(
                            matches: classification.localMatches,
                            onOpenMatch: openMatch
                        )
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .navigationTitle("Search")
        .navigationBarTitleDisplayMode(.large)
        .accessibilityIdentifier("search.root")
        .onAppear {
            if query.isEmpty {
                isQueryFieldFocused = true
            }
            reloadHistory()
        }
        .onChange(of: currentAccountAddress, initial: true) {
            reloadHistory()
        }
        .onSubmit(of: .text) {
            commitQuery()
        }
        .task(id: localIndexRefreshKey) {
            await refreshLocalIndex()
        }
        .task(id: accountLookupRefreshKey) {
            await refreshAccountMatches()
        }
    }

    private func openMatch(_ match: SearchLocalMatch) {
        commitQuery()
        Self.route(match: match, router: router)
    }

    private func commitQuery() {
        Task {
            do {
                try await historyStore.recordCommittedQuery(query, accountAddress: currentAccountAddress)
                historyErrorMessage = nil
                reloadHistory()
            } catch {
                handleHistoryWriteFailure(error, operation: "save")
            }
        }
    }

    private func reloadHistory() {
        historyEntries = historyStore.entries(for: currentAccountAddress)
    }

    private func recallHistory(_ entry: SearchHistoryEntry) {
        query = entry.query
        isQueryFieldFocused = false
    }

    private func deleteHistoryEntry(_ entry: SearchHistoryEntry) {
        Task {
            do {
                try await historyStore.removeEntry(id: entry.id)
                historyErrorMessage = nil
                reloadHistory()
            } catch {
                handleHistoryWriteFailure(error, operation: "delete")
            }
        }
    }

    private func clearHistory() {
        Task {
            do {
                try await historyStore.clear(accountAddress: currentAccountAddress)
                historyErrorMessage = nil
                reloadHistory()
            } catch {
                handleHistoryWriteFailure(error, operation: "clear")
            }
        }
    }

    private func refreshLocalIndex() async {
        let nftSnapshots = nfts.map {
            SearchLocalIndex.NFTSnapshot(
                id: $0.id,
                name: $0.name,
                collectionName: $0.collectionName,
                collectionDisplayName: $0.collection?.name,
                contractAddress: $0.contract.address,
                accountAddressRawValue: $0.accountAddressRawValue,
                networkRawValue: $0.networkRawValue
            )
        }
        let holdingSnapshots = holdings.map {
            SearchLocalIndex.HoldingSnapshot(
                accountAddressRawValue: $0.accountAddressRawValue,
                chainRawValue: $0.chainRawValue,
                balanceKind: $0.balanceKind,
                contractAddress: $0.contractAddress,
                symbol: $0.symbol,
                displayName: $0.displayName
            )
        }
        do {
            let refreshedIndex = await Task.detached(priority: .userInitiated) {
                SearchLocalIndex.make(
                    nftSnapshots: nftSnapshots,
                    holdingSnapshots: holdingSnapshots,
                    accountSnapshots: [],
                    currentAccountAddress: currentAccountAddress,
                    currentChain: currentChain
                )
            }.value
            try Task.checkCancellation()
            localIndex = refreshedIndex
        } catch is CancellationError {
            return
        } catch {
            logger.error("Failed to rebuild local search index: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func refreshAccountMatches() async {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedQuery = trimmedQuery.lowercased()

        guard !trimmedQuery.isEmpty else {
            accountMatches = []
            ensMatches = []
            return
        }

        do {
            if let normalizedAddress = trimmedQuery.extractedEthereumAddress?.lowercased() {
                accountMatches = try fetchAccountMatches(address: normalizedAddress)
                ensMatches = []
                return
            }

            if SearchQueryParser.looksLikeENSName(trimmedQuery) {
                ensMatches = try fetchENSMatches(name: normalizedQuery)
                accountMatches = []
                return
            }

            accountMatches = []
            ensMatches = []
        } catch {
            logger.error("Failed to refresh account search matches: \(error.localizedDescription, privacy: .public)")
            accountMatches = []
            ensMatches = []
        }
    }

    private var accountLookupRefreshKey: SearchAccountLookupRefreshKey {
        SearchAccountLookupRefreshKey(
            normalizedQuery: query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
            accountSignals: accounts.map {
                SearchAccountSignal(
                    id: $0.persistentModelID,
                    address: $0.address,
                    name: $0.name
                )
            }
        )
    }

    private func fetchAccountMatches(address: String) throws -> [SearchLocalMatch] {
        let descriptor = FetchDescriptor<EOAccount>(
            predicate: #Predicate<EOAccount> { account in
                account.address == address
            },
            sortBy: [
                SortDescriptor(\EOAccount.lastSelectedAt, order: .reverse),
                SortDescriptor(\EOAccount.addedAt, order: .reverse),
                SortDescriptor(\EOAccount.address)
            ]
        )

        return try modelContext.fetch(descriptor).map {
            SearchLocalMatch(
                kind: .account,
                title: $0.name ?? $0.address.displayAddress,
                subtitle: $0.address.displayAddress,
                destination: .profile(address: $0.address)
            )
        }
    }

    private func fetchENSMatches(name: String) throws -> [SearchLocalMatch] {
        let descriptor = FetchDescriptor<EOAccount>(
            predicate: #Predicate<EOAccount> { account in
                account.normalizedName == name
            },
            sortBy: [
                SortDescriptor(\EOAccount.lastSelectedAt, order: .reverse),
                SortDescriptor(\EOAccount.addedAt, order: .reverse),
                SortDescriptor(\EOAccount.address)
            ]
        )

        return try modelContext.fetch(descriptor)
            .compactMap { account in
                guard let accountName = account.name?.trimmingCharacters(in: .whitespacesAndNewlines),
                      !accountName.isEmpty else {
                    return nil
                }

                return SearchLocalMatch(
                    kind: .ens,
                    title: accountName,
                    subtitle: account.address.displayAddress,
                    destination: .profile(address: account.address)
                )
            }
    }

    private func handleHistoryWriteFailure(_ error: Error, operation: String) {
        logger.error("Failed to \(operation, privacy: .public) search history: \(error.localizedDescription, privacy: .public)")
        historyErrorMessage = "Auralis could not \(operation) recent searches right now. Existing results are still shown."
        reloadHistory()
    }

    static func makePresentation(
        classification: SearchQueryClassification,
        historyEntries: [SearchHistoryEntry]
    ) -> SearchRootPresentation {
        if classification.kind == .empty {
            return SearchRootPresentation(
                showsDetection: false,
                content: .history
            )
        }

        if classification.kind.isInvalidInput {
            return SearchRootPresentation(
                showsDetection: true,
                content: .safety
            )
        }

        if classification.localMatches.isEmpty {
            return SearchRootPresentation(
                showsDetection: true,
                content: .noResults
            )
        }

        return SearchRootPresentation(
            showsDetection: true,
            content: .results
        )
    }

    static func route(match: SearchLocalMatch, router: AppRouter) {
        switch match.destination {
        case .profile(let address):
            router.showProfileDetail(address: address)
        case .token(let contractAddress, let chain, let symbol):
            router.showERC20Token(
                contractAddress: contractAddress,
                chain: chain,
                symbol: symbol
            )
        case .nftItem(let id):
            router.showNFTTokensDetail(id: id)
        case .nftCollection(let contractAddress, let title, let chain):
            router.showNFTCollectionDetail(
                contractAddress: contractAddress,
                title: title,
                chain: chain
            )
        }
    }
}

private struct SearchAccountLookupRefreshKey: Equatable {
    let normalizedQuery: String
    let accountSignals: [SearchAccountSignal]
}

private struct SearchAccountSignal: Equatable {
    let id: PersistentIdentifier
    let address: String
    let name: String?
}

private struct SearchInputCard: View {
    @Binding var query: String
    @FocusState var isFocused: Bool

    var body: some View {
        AuraSurfaceCard(style: .regular, cornerRadius: 24, padding: 18) {
            VStack(alignment: .leading, spacing: 12) {
                Text("Query")
                    .font(.headline)
                    .foregroundStyle(Color.textPrimary)

                TextField(
                    "Search ENS, wallet, contract, symbol, NFT, collection",
                    text: $query
                )
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .focused($isFocused)
                .font(.body)
                .foregroundStyle(Color.textPrimary)
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Color.white.opacity(0.08))
                )
                .accessibilityIdentifier("search.queryField")
            }
        }
    }
}

private struct SearchDetectionCard: View {
    let classification: SearchQueryClassification

    var body: some View {
        AuraSurfaceCard(style: .regular, cornerRadius: 24, padding: 18) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Detection")
                            .font(.headline)
                            .foregroundStyle(Color.textPrimary)

                        Text(classification.kind.feedbackMessage)
                            .font(.subheadline)
                            .foregroundStyle(Color.textSecondary)
                    }

                    Spacer(minLength: 12)

                    AuraPill(
                        classification.kind.title,
                        systemImage: detectionSymbol,
                        emphasis: classification.kind.isInvalidInput ? .accent : .accent
                    )
                }

                if !classification.trimmedQuery.isEmpty {
                    Text(classification.trimmedQuery)
                        .font(.system(.footnote, design: .monospaced))
                        .foregroundStyle(Color.textPrimary)
                        .textSelection(.enabled)
                }
            }
        }
    }

    private var detectionSymbol: String {
        switch classification.kind {
        case .empty:
            return "text.cursor"
        case .walletAddress:
            return "person.crop.circle"
        case .contractAddress:
            return "shippingbox"
        case .ambiguousAddress:
            return "questionmark.circle"
        case .invalidAddress, .invalidENSLike:
            return "exclamationmark.triangle"
        case .ensName:
            return "globe"
        case .tokenSymbol:
            return "tag"
        case .nftName:
            return "photo"
        case .collectionName:
            return "square.stack.3d.up"
        case .text:
            return "textformat"
        }
    }
}

private struct SearchLocalMatchesCard: View {
    let matches: [SearchLocalMatch]
    let onOpenMatch: (SearchLocalMatch) -> Void

    var body: some View {
        AuraSurfaceCard(style: .regular, cornerRadius: 24, padding: 18) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top) {
                    Text("Local Matches")
                        .font(.headline)
                        .foregroundStyle(Color.textPrimary)

                    Spacer(minLength: 12)

                    AuraTrustLabel(kind: .metadata)
                }

                ForEach(matches) { match in
                    Button {
                        onOpenMatch(match)
                    } label: {
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Badge(match.kind.title)
                                Text(match.title)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(Color.textPrimary)
                            }

                            Text(match.subtitle)
                                .font(.caption)
                                .foregroundStyle(Color.textSecondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("search.match.\(match.id)")
                }
            }
        }
    }
}

private struct SearchNoResultsCard: View {
    let classification: SearchQueryClassification

    var body: some View {
        AuraEmptyState(
            eyebrow: "Search",
            title: "No local matches yet",
            message: "Auralis classified this as \(classification.kind.title.lowercased()), but the active account scope does not currently have a matching local result.",
            systemImage: "magnifyingglass",
            tone: .neutral
        )
    }
}

private struct SearchHistoryCard: View {
    let historyEntries: [SearchHistoryEntry]
    let onSelect: (SearchHistoryEntry) -> Void
    let onDelete: (SearchHistoryEntry) -> Void
    let onClearAll: () -> Void

    var body: some View {
        if historyEntries.isEmpty {
            EmptyView()
        } else {
            AuraSurfaceCard(style: .regular, cornerRadius: 24, padding: 18) {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("Recent Searches")
                            .font(.headline)
                            .foregroundStyle(Color.textPrimary)

                        Spacer(minLength: 12)

                        Button("Clear All", action: onClearAll)
                            .font(.caption.weight(.semibold))
                    }

                    ForEach(historyEntries) { entry in
                        HStack(spacing: 12) {
                            Button {
                                onSelect(entry)
                            } label: {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(entry.query)
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(Color.textPrimary)

                                    Text(entry.recordedAt.formatted(date: .abbreviated, time: .shortened))
                                        .font(.caption)
                                        .foregroundStyle(Color.textSecondary)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .buttonStyle(.plain)

                            Button {
                                onDelete(entry)
                            } label: {
                                Image(systemName: "trash")
                                    .foregroundStyle(Color.textSecondary)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Delete \(entry.query)")
                        }
                    }
                }
            }
        }
    }
}

private struct Badge: View {
    let title: String

    init(_ title: String) {
        self.title = title
    }

    var body: some View {
        Text(title)
            .font(.caption.weight(.semibold))
            .foregroundStyle(Color.textPrimary)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color.white.opacity(0.08), in: Capsule())
    }
}
