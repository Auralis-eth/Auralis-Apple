import AuralisPrimaryModels
import AuralisPrimaryPersistence
import OSLog
import SwiftData
import SwiftUI
import AuraUI

// SwiftLint currently misclassifies these file-scope snapshot helpers as overly nested.
private struct SearchLocalIndexRefreshKey: Equatable {
    let currentAccountAddress: String?
    let currentChain: Chain
}

private struct SearchAssistantRefreshKey: Equatable {
    let query: String
    let currentAccountAddress: String?
    let currentChain: Chain
    let selectedScope: SearchResultScope
}

enum SearchRootPresentationContent: Equatable {
    case history
    case safety
    case noResults
    case results
    case resultsAndAssistant
    case assistant
}

enum SearchResultScope: String, CaseIterable, Equatable, Identifiable, Sendable {
    case all
    case nfts
    case tokens
    case music
    case receipts
    case accounts

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all:
            return "All"
        case .nfts:
            return "NFTs"
        case .tokens:
            return "Tokens"
        case .music:
            return "Music"
        case .receipts:
            return "Receipts"
        case .accounts:
            return "Accounts"
        }
    }

    var emptyStateName: String {
        switch self {
        case .all:
            return "the active account"
        default:
            return title.lowercased()
        }
    }

    func includes(matchKind: SearchLocalMatch.Kind) -> Bool {
        switch self {
        case .all:
            return true
        case .nfts:
            return matchKind == .nftName || matchKind == .collectionName || matchKind == .contract
        case .tokens:
            return matchKind == .tokenSymbol
        case .music:
            return matchKind == .musicItem
        case .receipts:
            return matchKind == .receipt
        case .accounts:
            return matchKind == .account || matchKind == .ens
        }
    }
}

struct SearchSuggestion: Equatable, Identifiable, Sendable {
    let completion: String
    let detail: String
    let kind: SearchLocalMatch.Kind

    var id: String {
        "\(kind.rawValue):\(completion.lowercased()):\(detail.lowercased())"
    }
}

struct SearchRootPresentation: Equatable {
    let showsDetection: Bool
    let content: SearchRootPresentationContent
}

struct SearchRootView: View {
    private let logger = Logger(subsystem: "Auralis", category: "SearchRootView")

    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.modelContext) private var modelContext

    let router: AppRouter
    let currentAccountAddress: String?
    let currentChain: Chain
    let historyStore: SearchHistoryStore
    let spotlightIndexer: any SearchSpotlightIndexing
    let assistantProvider: any SearchAssistantProviding

    @State private var query = ""
    @State private var historyEntries: [SearchHistoryEntry] = []
    @State private var historyErrorMessage: String?
    @State private var localIndex: SearchLocalIndex = .empty
    @State private var assistantState: SearchAssistantState = .idle
    @State private var debouncedClassification: SearchQueryClassification?
    @State private var announcedClassificationTitle: String?
    @State private var selectedScope: SearchResultScope = .all
    @State private var isSearchPresented = false
    @State private var searchTokens: [SearchToken] = []

    private let parser = SearchQueryParser()

    init(
        router: AppRouter,
        currentAccountAddress: String?,
        currentChain: Chain,
        historyStore: SearchHistoryStore,
        spotlightIndexer: any SearchSpotlightIndexing,
        assistantProvider: any SearchAssistantProviding
    ) {
        self.router = router
        self.currentAccountAddress = currentAccountAddress
        self.currentChain = currentChain
        self.historyStore = historyStore
        self.spotlightIndexer = spotlightIndexer
        self.assistantProvider = assistantProvider
    }

    private var localIndexRefreshKey: SearchLocalIndexRefreshKey {
        SearchLocalIndexRefreshKey(
            currentAccountAddress: currentAccountAddress,
            currentChain: currentChain
        )
    }

    private var assistantRefreshKey: SearchAssistantRefreshKey {
        SearchAssistantRefreshKey(
            query: query,
            currentAccountAddress: currentAccountAddress,
            currentChain: currentChain,
            selectedScope: selectedScope
        )
    }

    private var baseClassification: SearchQueryClassification {
        parser.classify(query: query, index: localIndex)
    }

    private var filterState: SearchFilterState {
        SearchFilterState(
            selectedScope: selectedScope,
            tokens: searchTokens,
            currentAccountAddress: currentAccountAddress,
            currentChain: currentChain
        )
    }

    private var classification: SearchQueryClassification {
        Self.classification(
            baseClassification,
            applying: filterState,
            index: localIndex
        )
    }

    private var presentation: SearchRootPresentation {
        Self.makePresentation(
            classification: classification,
            historyEntries: historyEntries,
            allowsAssistant: allowsAssistantForCurrentScope
        )
    }

    private var shouldAutofocusQuery: Bool {
        !ProcessInfo.processInfo.arguments.contains("-accessibility-audit")
    }

    private var searchScope: SearchScope {
        SearchScope(accountAddress: currentAccountAddress, chain: currentChain)
    }

    private var suggestions: [SearchSuggestion] {
        Self.makeSuggestions(
            query: query,
            index: localIndex,
            filter: filterState,
            historyEntries: historyEntries
        )
    }

    private var suggestedSearchTokens: [SearchToken] {
        Self.makeTokenSuggestions(
            query: query,
            index: localIndex,
            currentAccountAddress: currentAccountAddress,
            currentChain: currentChain,
            selectedTokens: searchTokens
        )
    }

    private var allowsAssistantForCurrentScope: Bool {
        guard assistantProvider.availability == .available else {
            return false
        }
        return selectedScope == .all ||
            !classification.localMatches.isEmpty ||
            baseClassification.localMatches.isEmpty
    }

    @ViewBuilder
    private var searchSuggestionsContent: some View {
        ForEach(suggestedSearchTokens) { token in
            SearchTokenSuggestionRow(token: token)
                .searchCompletion(token)
        }

        if query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            ForEach(historyEntries.prefix(5)) { entry in
                Label(entry.query, systemImage: "clock.arrow.circlepath")
                    .searchCompletion(entry.query)
                    .accessibilityLabel(String(localized: "Recent search \(entry.query.accessibilitySpokenQuery)"))
            }
        } else {
            ForEach(suggestions) { suggestion in
                SearchCompletionSuggestionRow(query: query, suggestion: suggestion)
                    .searchCompletion(suggestion.completion)
            }
        }
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

                    SearchScopeBar(selectedScope: $selectedScope)

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
                        SearchNoResultsCard(
                            classification: classification,
                            selectedScope: selectedScope
                        )
                    case .results:
                        SearchLocalMatchesCard(
                            matches: classification.localMatches,
                            onOpenMatch: openMatch
                        )
                    case .resultsAndAssistant:
                        SearchLocalMatchesCard(
                            matches: classification.localMatches,
                            onOpenMatch: openMatch
                        )
                        SearchAssistantCard(
                            state: assistantState,
                            onOpenMatch: openMatch
                        )
                    case .assistant:
                        SearchAssistantCard(
                            state: assistantState,
                            onOpenMatch: openMatch
                        )
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .navigationTitle("Search")
        .navigationBarTitleDisplayMode(.large)
        .searchable(
            text: $query,
            tokens: $searchTokens,
            isPresented: $isSearchPresented,
            placement: .automatic,
            prompt: "Search ENS, wallet, contract, symbol, NFT, collection"
        ) { token in
            SearchTokenLabel(token: token)
        }
        .searchSuggestions {
            searchSuggestionsContent
        }
        .accessibilityIdentifier(A11yID.Search.root)
        .onAppear {
            if shouldAutofocusQuery && query.isEmpty {
                isSearchPresented = true
            }
            reloadHistory()
        }
        .onChange(of: currentAccountAddress, initial: true) {
            reloadHistory()
        }
        .onSubmit(of: .text) {
            commitQuery()
        }
        .onSubmit(of: .search) {
            commitQuery()
        }
        .task(id: localIndexRefreshKey) {
            await refreshLocalIndex()
        }
        .task(id: localIndexRefreshKey) {
            await observeModelContextSaves()
        }
        .task(id: query) {
            await updateDebouncedClassificationAnnouncement()
        }
        .task(id: assistantRefreshKey) {
            await runAssistantSearchIfNeeded()
        }
        .onChange(of: scenePhase) { _, newValue in
            guard newValue == .active else {
                return
            }

            Task {
                await refreshLocalIndex()
            }
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
        isSearchPresented = false
    }

    private func deleteHistoryEntry(_ entry: SearchHistoryEntry) {
        Task {
            do {
                try await historyStore.removeEntry(id: entry.id)
                historyErrorMessage = nil
                reloadHistory()
                AuraAccessibilityAnnouncer.announce(String(localized: "Search deleted"))
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
                AuraAccessibilityAnnouncer.announce(String(localized: "Search history cleared"))
            } catch {
                handleHistoryWriteFailure(error, operation: "clear")
            }
        }
    }

    private func refreshLocalIndex() async {
        do {
            let refreshedIndex = try await SearchIndexBuilder(modelContext: modelContext).makeIndex(
                currentAccountAddress: currentAccountAddress,
                currentChain: currentChain
            )
            try Task.checkCancellation()
            localIndex = refreshedIndex
            debouncedClassification = parser.classify(query: query, index: refreshedIndex)
            try await spotlightIndexer.reconcile(scope: searchScope)
        } catch is CancellationError {
            return
        } catch {
            logger.error("Failed to rebuild local search index: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func observeModelContextSaves() async {
        await SearchIndexBuilder(modelContext: modelContext).observePersistenceChanges {
            await refreshLocalIndex()
        }
    }

    private func runAssistantSearchIfNeeded() async {
        do {
            try await Task.sleep(for: .milliseconds(500))
            try Task.checkCancellation()
        } catch {
            return
        }

        let nextClassification = classification
        guard allowsAssistantForCurrentScope else {
            assistantState = .idle
            return
        }

        guard nextClassification.kind.isAssistantEligible, !nextClassification.trimmedQuery.isEmpty else {
            assistantState = .idle
            return
        }

        guard assistantProvider.availability == .available else {
            assistantState = .unavailable(assistantProvider.availability)
            return
        }

        let request = SearchAssistantRequest(
            query: nextClassification.trimmedQuery,
            scope: searchScope,
            kind: nextClassification.kind
        )
        for await state in assistantProvider.streamAnswer(for: request) {
            guard !Task.isCancelled else { return }
            assistantState = state
        }
    }

    private func handleHistoryWriteFailure(_ error: Error, operation: String) {
        logger.error("Failed to \(operation, privacy: .public) search history: \(error.localizedDescription, privacy: .public)")
        historyErrorMessage = "Auralis could not \(operation) recent searches right now. Existing results are still shown."
        reloadHistory()
    }

    private func updateDebouncedClassificationAnnouncement() async {
        do {
            try await Task.sleep(for: .milliseconds(400))
            try Task.checkCancellation()
        } catch {
            return
        }

        let nextClassification = classification
        debouncedClassification = nextClassification

        guard !nextClassification.trimmedQuery.isEmpty else {
            announcedClassificationTitle = nil
            return
        }

        let title = nextClassification.kind.title
        guard announcedClassificationTitle != title else {
            return
        }

        announcedClassificationTitle = title
        AuraAccessibilityAnnouncer.announce(String(localized: "Detected as \(title)"))
    }

    static func makePresentation(
        classification: SearchQueryClassification,
        historyEntries: [SearchHistoryEntry],
        allowsAssistant: Bool = true
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
                content: allowsAssistant && classification.kind.isAssistantEligible ? .assistant : .noResults
            )
        }

        if allowsAssistant && classification.kind.isAssistantEligible {
            return SearchRootPresentation(
                showsDetection: true,
                content: .resultsAndAssistant
            )
        }

        return SearchRootPresentation(
            showsDetection: true,
            content: .results
        )
    }

    static func classification(
        _ classification: SearchQueryClassification,
        applying scope: SearchResultScope
    ) -> SearchQueryClassification {
        let filter = SearchFilterState(
            selectedScope: scope,
            tokens: [],
            currentAccountAddress: nil,
            currentChain: .ethMainnet
        )
        return self.classification(classification, applying: filter, index: .empty)
    }

    static func classification(
        _ classification: SearchQueryClassification,
        applying filter: SearchFilterState,
        index: SearchLocalIndex
    ) -> SearchQueryClassification {
        let localMatches: [SearchLocalMatch]
        if classification.kind == .empty, filter.hasQueryIndependentFilters {
            localMatches = index.allMatches(filter: filter)
        } else {
            localMatches = classification.localMatches.filter { filter.includes(match: $0) }
        }

        let kind: SearchQueryKind = classification.kind == .empty && filter.hasQueryIndependentFilters ? .text : classification.kind
        return SearchQueryClassification(
            rawQuery: classification.rawQuery,
            normalizedQuery: classification.normalizedQuery,
            kind: kind,
            localMatches: localMatches
        )
    }

    static func makeSuggestions(
        query: String,
        index: SearchLocalIndex,
        scope: SearchResultScope,
        limit: Int = 5
    ) -> [SearchSuggestion] {
        makeSuggestions(
            query: query,
            index: index,
            filter: SearchFilterState(
                selectedScope: scope,
                tokens: [],
                currentAccountAddress: nil,
                currentChain: .ethMainnet
            ),
            historyEntries: [],
            limit: limit
        )
    }

    static func makeSuggestions(
        query: String,
        index: SearchLocalIndex,
        filter: SearchFilterState,
        historyEntries: [SearchHistoryEntry],
        limit: Int = 5
    ) -> [SearchSuggestion] {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedQuery = trimmedQuery.lowercased()
        guard !normalizedQuery.isEmpty else {
            return []
        }

        let recentQueries = Set(historyEntries.map { $0.normalizedQuery })
        let candidates = index.suggestionCandidates
            .filter { filter.selectedScope.includes(matchKind: $0.kind) }
            .filter { suggestion in
                filter.contentScopes.isEmpty || filter.contentScopes.contains { $0.includes(matchKind: suggestion.kind) }
            }
            .compactMap { candidate -> (suggestion: SearchSuggestion, score: Int)? in
                let normalizedCompletion = candidate.completion.lowercased()
                guard normalizedCompletion != normalizedQuery else {
                    return nil
                }

                let score: Int
                if normalizedCompletion.hasPrefix(normalizedQuery) {
                    score = 300
                } else if normalizedCompletion
                    .split(separator: " ")
                    .contains(where: { $0.hasPrefix(normalizedQuery) }) {
                    score = 200
                } else if normalizedCompletion.contains(normalizedQuery) {
                    score = 100
                } else {
                    return nil
                }

                let recentBoost = recentQueries.contains(normalizedCompletion) ? 30 : 0
                let currentScopeBoost = Self.currentScopeBoost(candidate, filter: filter)
                return (candidate, score + recentBoost + currentScopeBoost)
            }

        var seen = Set<String>()
        return candidates
            .sorted { lhs, rhs in
                if lhs.score == rhs.score {
                    return lhs.suggestion.completion.localizedCaseInsensitiveCompare(rhs.suggestion.completion) == .orderedAscending
                }
                return lhs.score > rhs.score
            }
            .map(\.suggestion)
            .filter { seen.insert($0.completion.lowercased()).inserted }
            .prefix(limit)
            .map { $0 }
    }

    static func makeTokenSuggestions(
        query: String,
        index: SearchLocalIndex,
        currentAccountAddress: String?,
        currentChain: Chain,
        selectedTokens: [SearchToken],
        limit: Int = 8
    ) -> [SearchToken] {
        let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let selectedIDs = Set(selectedTokens.map(\.id))
        let contentTokens = SearchResultScope.allCases
            .filter { $0 != .all }
            .map { SearchToken(kind: .content($0)) }
        let mediaTokens = SearchToken.SearchMediaFilter.allCases.map { SearchToken(kind: .media($0)) }
        let accountTokens = index.accounts.map {
            SearchToken(kind: .account(address: $0.address, displayName: $0.displayName))
        }
        let currentAccountToken = currentAccountAddress.map {
            SearchToken(kind: .account(address: $0, displayName: $0.displayAddress))
        }
        let chainTokens = ([currentChain] + Chain.allCases.filter { $0 != currentChain })
            .map { SearchToken(kind: .chain($0)) }

        var seen = Set<String>()
        return (contentTokens + mediaTokens + [currentAccountToken].compactMap { $0 } + accountTokens + chainTokens)
            .filter { seen.insert($0.id).inserted }
            .filter { !selectedIDs.contains($0.id) }
            .filter { token in
                normalizedQuery.isEmpty || token.title.lowercased().contains(normalizedQuery)
            }
            .prefix(limit)
            .map { $0 }
    }

    private static func currentScopeBoost(_ suggestion: SearchSuggestion, filter: SearchFilterState) -> Int {
        switch suggestion.kind {
        case .tokenSymbol, .collectionName, .contract:
            return 15
        case .account, .ens:
            return filter.currentAccountAddress == nil ? 0 : 10
        case .nftName, .musicItem, .receipt:
            return 5
        }
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
        case .receipt(let id):
            router.showReceipt(id: id)
        case .musicItem(let id):
            router.showMusicNFTDetail(id: id)
        }
    }
}

private struct SearchTokenLabel: View {
    let token: SearchToken

    var body: some View {
        Text(token.title)
    }
}

private struct SearchTokenSuggestionRow: View {
    let token: SearchToken

    var body: some View {
        Label {
            VStack(alignment: .leading, spacing: 2) {
                Text(token.title)
                Text(token.suggestionDetail)
                    .font(.caption)
                    .foregroundStyle(Color.textSecondary)
            }
        } icon: {
            Image(systemName: symbolName)
                .accessibilityHidden(true)
        }
        .accessibilityElement(children: .combine)
    }

    private var symbolName: String {
        switch token.kind {
        case .content:
            return "line.3.horizontal.decrease.circle"
        case .media:
            return "play.circle"
        case .account:
            return "person.crop.circle"
        case .chain:
            return "link.circle"
        }
    }
}

private struct SearchCompletionSuggestionRow: View {
    let query: String
    let suggestion: SearchSuggestion

    var body: some View {
        Label {
            VStack(alignment: .leading, spacing: 2) {
                highlightedCompletion
                Text("\(suggestion.kind.title) • \(suggestion.detail)")
                    .font(.caption)
                    .foregroundStyle(Color.textSecondary)
            }
        } icon: {
            Image(systemName: "arrow.up.left")
                .accessibilityHidden(true)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(String(localized: "Suggestion \(suggestion.completion.accessibilitySpokenQuery)"))
        .accessibilityValue(String(localized: "\(suggestion.kind.title), \(suggestion.detail)"))
    }

    @ViewBuilder
    private var highlightedCompletion: some View {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedQuery.isEmpty,
           suggestion.completion.lowercased().hasPrefix(trimmedQuery.lowercased()),
           suggestion.completion.count > trimmedQuery.count {
            HStack(spacing: 0) {
                Text(trimmedQuery)
                    .foregroundStyle(Color.textPrimary)
                Text(String(suggestion.completion.dropFirst(trimmedQuery.count)))
                    .foregroundStyle(Color.textSecondary)
            }
        } else {
            Text(suggestion.completion)
                .foregroundStyle(Color.textPrimary)
        }
    }
}

private struct SearchScopeBar: View {
    @Binding var selectedScope: SearchResultScope

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(SearchResultScope.allCases) { scope in
                    Button {
                        selectedScope = scope
                    } label: {
                        Text(scope.title)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(selectedScope == scope ? Color(.systemBackground) : Color.textPrimary)
                            .padding(.horizontal, 12)
                            .frame(height: 36)
                            .background(
                                Capsule()
                                    .fill(selectedScope == scope ? Color.primary : Color.white.opacity(0.08))
                            )
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(selectedScope == scope ? .isSelected : [])
                    .accessibilityHint(String(localized: "Filters search results to \(scope.title)"))
                    .accessibilityIdentifier(A11yID.Search.scope(scope.rawValue))
                }
            }
            .padding(.horizontal, 2)
        }
        .accessibilityLabel(String(localized: "Search scope"))
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
                            .accessibilityAddTraits(.isHeader)

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
            .accessibilityElement(children: .combine)
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
                        .accessibilityAddTraits(.isHeader)

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
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(String(localized: "\(match.kind.title), \(match.title)"))
                    .accessibilityValue(String(localized: "\(match.subtitle)"))
                    .accessibilityHint(String(localized: "Opens this result"))
                    .accessibilityIdentifier(A11yID.Search.match(id: match.id))
                }
            }
        }
    }
}

private struct SearchNoResultsCard: View {
    let classification: SearchQueryClassification
    let selectedScope: SearchResultScope

    var body: some View {
        AuraEmptyState(
            eyebrow: "Search",
            title: "No local matches yet",
            message: "No \(selectedScope.emptyStateName) results matched \"\(classification.trimmedQuery)\". Check the spelling, switch scopes, or search all categories.",
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
                            .accessibilityAddTraits(.isHeader)

                        Spacer(minLength: 12)

                        Button(action: onClearAll) {
                            Text("Clear All")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(Color.primary)
                                .frame(minWidth: 44, minHeight: 44)
                                .padding(.horizontal, 8)
                                .background(Color(.systemBackground), in: Capsule())
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
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
                            .frame(minHeight: 44)
                            .contentShape(Rectangle())
                            .accessibilityElement(children: .ignore)
                            .accessibilityLabel(String(localized: "Recent search \(entry.query.accessibilitySpokenQuery)"))
                            .accessibilityValue(String(localized: "\(entry.recordedAt.formatted(date: .abbreviated, time: .shortened))"))
                            .accessibilityHint(String(localized: "Runs this recent search"))
                            .accessibilityAction(named: String(localized: "Delete")) {
                                onDelete(entry)
                            }
                            .accessibilityIdentifier("search.history.\(entry.normalizedQuery)")

                            Button(role: .destructive) {
                                onDelete(entry)
                            } label: {
                                Image(systemName: "trash")
                                    .foregroundStyle(Color.textSecondary)
                            }
                            .buttonStyle(.plain)
                            .frame(minWidth: 44, minHeight: 44)
                            .contentShape(Rectangle())
                            .accessibilityLabel(String(localized: "Delete \(entry.query)"))
                        }
                    }
                }
            }
        }
    }
}

private extension String {
    var accessibilitySpokenQuery: String {
        auraGroupedForSpeech
            .replacingOccurrences(of: ".", with: " dot ")
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
