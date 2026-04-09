import SwiftData
import SwiftUI

struct SearchRootView: View {
    @Query private var accounts: [EOAccount]
    @Query private var nfts: [NFT]
    @Query private var holdings: [TokenHolding]

    let router: AppRouter
    let currentAccountAddress: String?
    let currentChain: Chain

    @State private var query = ""
    @State private var historyEntries: [SearchHistoryEntry] = []
    @FocusState private var isQueryFieldFocused: Bool

    private let parser = SearchQueryParser()
    private let historyStore = SearchHistoryStore()

    private var localIndex: SearchLocalIndex {
        SearchLocalIndex.make(
            nfts: nfts,
            holdings: holdings,
            accounts: accounts,
            currentAccountAddress: currentAccountAddress,
            currentChain: currentChain
        )
    }

    private var classification: SearchQueryClassification {
        parser.classify(query: query, index: localIndex)
    }

    var body: some View {
        AuraScenicScreen(horizontalPadding: 12, verticalPadding: 12) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    SearchInputCard(
                        query: $query,
                        isFocused: _isQueryFieldFocused
                    )

                    if classification.kind == .empty {
                        SearchHistoryCard(
                            historyEntries: historyEntries,
                            onSelect: recallHistory,
                            onDelete: deleteHistoryEntry,
                            onClearAll: clearHistory
                        )
                    } else if classification.kind.isInvalidInput {
                        SearchDetectionCard(classification: classification)
                        AuraEmptyState(
                            eyebrow: "Search",
                            title: classification.kind.title,
                            message: classification.kind.feedbackMessage,
                            systemImage: "exclamationmark.triangle",
                            tone: .critical
                        )
                    } else if classification.localMatches.isEmpty {
                        SearchDetectionCard(classification: classification)
                        SearchNoResultsCard(classification: classification)
                    } else {
                        SearchDetectionCard(classification: classification)
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
    }

    private func openMatch(_ match: SearchLocalMatch) {
        commitQuery()

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

    private func commitQuery() {
        historyStore.recordCommittedQuery(query, accountAddress: currentAccountAddress)
        reloadHistory()
    }

    private func reloadHistory() {
        historyEntries = historyStore.entries(for: currentAccountAddress)
    }

    private func recallHistory(_ entry: SearchHistoryEntry) {
        query = entry.query
        isQueryFieldFocused = false
    }

    private func deleteHistoryEntry(_ entry: SearchHistoryEntry) {
        historyStore.removeEntry(id: entry.id)
        reloadHistory()
    }

    private func clearHistory() {
        historyStore.clear(accountAddress: currentAccountAddress)
        reloadHistory()
    }
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
                Text("Local Matches")
                    .font(.headline)
                    .foregroundStyle(Color.textPrimary)

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
