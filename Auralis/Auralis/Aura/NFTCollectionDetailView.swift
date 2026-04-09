import SwiftData
import SwiftUI

struct NFTCollectionDetailPresentation: Equatable {
    let title: String
    let subtitle: String
    let contractAddressLine: String?
    let items: [Item]

    struct Item: Equatable, Identifiable {
        let id: String
        let title: String
        let subtitle: String
    }
}

struct NFTCollectionDetailView: View {
    @Query private var nfts: [NFT]

    let route: NFTTokensRoute
    let currentAccountAddress: String?
    let currentChain: Chain
    let onOpenItem: (String) -> Void

    init(
        route: NFTTokensRoute,
        currentAccountAddress: String?,
        currentChain: Chain,
        onOpenItem: @escaping (String) -> Void
    ) {
        self.route = route
        self.currentAccountAddress = currentAccountAddress
        self.currentChain = currentChain
        self.onOpenItem = onOpenItem

        let normalizedAccountAddress = NFT.normalizedScopeComponent(currentAccountAddress) ?? ""
        let chainRawValue = currentChain.rawValue
        _nfts = Query(
            filter: #Predicate<NFT> {
                $0.accountAddressRawValue == normalizedAccountAddress &&
                $0.networkRawValue == chainRawValue
            },
            sort: [SortDescriptor(\NFT.acquiredAt?.blockTimestamp, order: .reverse)]
        )
    }

    private var presentation: NFTCollectionDetailPresentation {
        Self.makePresentation(route: route, nfts: nfts, currentChain: currentChain)
    }

    var body: some View {
        AuraScenicScreen(horizontalPadding: 12, verticalPadding: 12) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    AuraSurfaceCard(style: .regular, cornerRadius: 24, padding: 18) {
                        VStack(alignment: .leading, spacing: 10) {
                            Text(presentation.title)
                                .font(.title2.weight(.semibold))
                                .foregroundStyle(Color.textPrimary)

                            Text(presentation.subtitle)
                                .font(.subheadline)
                                .foregroundStyle(Color.textSecondary)

                            if let contractAddressLine = presentation.contractAddressLine {
                                Text(contractAddressLine)
                                    .font(.footnote.monospaced())
                                    .foregroundStyle(Color.textSecondary)
                            }
                        }
                    }

                    if presentation.items.isEmpty {
                        AuraEmptyState(
                            eyebrow: "Collection",
                            title: "No scoped items found",
                            message: "This collection is not available in the current account and chain scope.",
                            systemImage: "square.stack.3d.up.slash",
                            tone: .neutral
                        )
                    } else {
                        AuraSurfaceCard(style: .regular, cornerRadius: 24, padding: 18) {
                            VStack(alignment: .leading, spacing: 12) {
                                ForEach(presentation.items) { item in
                                    Button {
                                        onOpenItem(item.id)
                                    } label: {
                                        VStack(alignment: .leading, spacing: 6) {
                                            Text(item.title)
                                                .font(.headline)
                                                .foregroundStyle(Color.textPrimary)

                                            Text(item.subtitle)
                                                .font(.caption)
                                                .foregroundStyle(Color.textSecondary)
                                        }
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .padding(.vertical, 4)
                                    }
                                    .buttonStyle(.plain)
                                    .accessibilityIdentifier("nft.collection.item.\(item.id)")
                                }
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .navigationTitle("Collection")
        .navigationBarTitleDisplayMode(.large)
        .accessibilityIdentifier("nft.collection.detail")
    }

    static func makePresentation(
        route: NFTTokensRoute,
        nfts: [NFT],
        currentChain: Chain
    ) -> NFTCollectionDetailPresentation {
        let title: String
        let filteredNFTs: [NFT]
        let contractAddressLine: String?

        switch route {
        case .item:
            title = "Collection"
            filteredNFTs = []
            contractAddressLine = nil
        case .collection(let contractAddress, let collectionTitle, _):
            title = collectionTitle
            let normalizedContractAddress = contractAddress.flatMap(NFT.normalizedScopeComponent)
            filteredNFTs = nfts.filter { nft in
                if let normalizedContractAddress {
                    return NFT.normalizedScopeComponent(nft.contract.address) == normalizedContractAddress
                }

                let nftCollectionName = (nft.collection?.name ?? nft.collectionName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                return nftCollectionName.caseInsensitiveCompare(collectionTitle) == .orderedSame
            }
            contractAddressLine = normalizedContractAddress?.displayAddress
        }

        let items = filteredNFTs.map { nft in
            NFTCollectionDetailPresentation.Item(
                id: nft.id,
                title: nft.name ?? "Untitled NFT",
                subtitle: nft.tokenId.isEmpty ? currentChain.routingDisplayName : "\(currentChain.routingDisplayName) • Token \(nft.tokenId)"
            )
        }

        let subtitle = items.isEmpty
            ? "No items available in the current scope"
            : "\(items.count) item\(items.count == 1 ? "" : "s") in \(currentChain.routingDisplayName)"

        return NFTCollectionDetailPresentation(
            title: title,
            subtitle: subtitle,
            contractAddressLine: contractAddressLine,
            items: items
        )
    }
}
