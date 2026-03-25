import SwiftData
import SwiftUI

struct SearchRootView: View {
    @Query private var accounts: [EOAccount]
    @Query private var nfts: [NFT]

    let currentAccountAddress: String?
    let currentChain: Chain

    @State private var query = ""
    @FocusState private var isQueryFieldFocused: Bool

    private let parser = SearchQueryParser()

    private var localIndex: SearchLocalIndex {
        SearchLocalIndex.make(
            nfts: nfts,
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

                    SearchDetectionCard(classification: classification)

                    if classification.kind == .empty {
                        EmptyView()
                    } else if classification.kind.isInvalidInput {
                        AuraEmptyState(
                            eyebrow: "Search",
                            title: classification.kind.title,
                            message: classification.kind.feedbackMessage,
                            systemImage: "exclamationmark.triangle",
                            tone: .critical
                        )
                    } else if classification.localMatches.isEmpty {
                        AuraSurfaceCard(style: .regular, cornerRadius: 24, padding: 18) {
                            VStack(alignment: .leading, spacing: 10) {
                                Text("No Local Matches Yet")
                                    .font(.headline)
                                    .foregroundStyle(Color.textPrimary)

                                Text("Classification is ready, but this query does not match the current local search index for the active scope.")
                                    .font(.subheadline)
                                    .foregroundStyle(Color.textSecondary)
                            }
                        }
                    } else {
                        SearchLocalMatchesCard(matches: classification.localMatches)
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
        }
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

    var body: some View {
        AuraSurfaceCard(style: .regular, cornerRadius: 24, padding: 18) {
            VStack(alignment: .leading, spacing: 12) {
                Text("Local Matches")
                    .font(.headline)
                    .foregroundStyle(Color.textPrimary)

                ForEach(matches) { match in
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
