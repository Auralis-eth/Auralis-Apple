import AuralisPrimaryModels
import AuralisPrimaryPersistence
import AuraUI
import SwiftUI

public struct NFTLibraryCollectionDetailView: View {
    public let route: NFTLibraryRoute
    public let nfts: [NFT]
    public let currentChain: Chain
    public let onOpenItem: @MainActor (String) -> Void

    public init(
        route: NFTLibraryRoute,
        nfts: [NFT],
        currentChain: Chain,
        onOpenItem: @escaping @MainActor (String) -> Void
    ) {
        self.route = route
        self.nfts = nfts
        self.currentChain = currentChain
        self.onOpenItem = onOpenItem
    }

    private var presentation: NFTCollectionDetailPresentation {
        NFTLibraryPresentation.collectionDetail(route: route, nfts: nfts, currentChain: currentChain)
    }

    public var body: some View {
        NFTLibraryScenicScreen(horizontalPadding: 12, verticalPadding: 12) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    header

                    if presentation.items.isEmpty {
                        AuraEmptyState(
                            eyebrow: "Collection",
                            title: "No scoped items found",
                            message: "This collection is not available in the current account and chain scope.",
                            systemImage: "square.stack.3d.up.slash",
                            tone: .neutral
                        )
                    } else {
                        itemsList
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .navigationTitle("Collection")
        .navigationBarTitleDisplayMode(NavigationBarItem.TitleDisplayMode.large)
        .accessibilityIdentifier("nft.collection.detail")
    }

    private var header: some View {
        AuraSurfaceCard(style: .regular, cornerRadius: 24, padding: 18) {
            VStack(alignment: .leading, spacing: 10) {
                AuraTrustLabel(kind: .metadata)

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
            .accessibilityElement(children: .combine)
        }
    }

    private var itemsList: some View {
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
