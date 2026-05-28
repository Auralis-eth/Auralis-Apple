import AuralisPrimaryModels
import AuralisPrimaryPersistence
import AuraUI
import SwiftUI

public struct NFTLibraryDetailView: View {
    public let nft: NFT?
    public let dependencies: NFTLibraryDependencies

    public init(nft: NFT?, dependencies: NFTLibraryDependencies) {
        self.nft = nft
        self.dependencies = dependencies
    }

    private var titleText: String {
        nft.map(NFTLibraryPresentation.displayTitle) ?? "Untitled NFT"
    }

    private var collectionName: String? {
        nft?.collection?.name ?? nft?.collectionName
    }

    private var descriptionText: String? {
        guard let description = nft?.nftDescription, !description.isEmpty else {
            return nil
        }

        return description
    }

    public var body: some View {
        Group {
            if let nft {
                detailContent(for: nft)
            } else {
                ContentUnavailableView(
                    "NFT Unavailable",
                    systemImage: "exclamationmark.triangle",
                    description: Text("The requested NFT could not be resolved for the current account.")
                )
                .navigationTitle("NFT Detail")
                .accessibilityIdentifier("nft.detail.unavailable")
            }
        }
    }

    private func detailContent(for nft: NFT) -> some View {
        VStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    nftImage(for: nft)

                    VStack(alignment: .leading, spacing: 12) {
                        AuraTrustLabel(kind: .metadata)

                        HeadlineFontText(titleText)
                            .fontWeight(.semibold)
                            .accessibilityAddTraits(.isHeader)
                            .accessibilityIdentifier("nft.detail.title")

                        if let collectionName {
                            SubheadlineFontText(collectionName)
                        }

                        if let description = descriptionText {
                            SecondaryText(description)
                        }

                        badgeRow(for: nft)

                        NFTMarketplaceLink(nft: nft, dependencies: dependencies)
                        NFTExplorerLink(nft: nft, dependencies: dependencies)
                    }
                }
                .padding()
            }
        }
        .navigationTitle(titleText)
        .navigationBarTitleDisplayMode(.inline)
        .background(Color.background)
        .accessibilityIdentifier("nft.detail.screen")
    }

    private func nftImage(for nft: NFT) -> some View {
        Group {
            if let imageURL = NFTLibraryPresentation.imageURL(for: nft) {
                AsyncImage(url: imageURL) { image in
                    image
                        .resizable()
                        .scaledToFill()
                } placeholder: {
                    imagePlaceholder
                }
            } else {
                imagePlaceholder
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 280)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .accessibilityLabel(String(localized: "NFT artwork for \(titleText)"))
    }

    private var imagePlaceholder: some View {
        RoundedRectangle(cornerRadius: 20)
            .fill(Color.secondary.opacity(0.2))
            .overlay {
                SystemImage("photo")
                    .font(.largeTitle)
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
            }
    }

    @ViewBuilder
    private func badgeRow(for nft: NFT) -> some View {
        HStack(spacing: 12) {
            if let chain = nft.network {
                NFTLibraryBadgeLabel(title: chain.routingDisplayName)
            }

            if nft.isMusic() {
                NFTLibraryBadgeLabel(title: "Music NFT")
            }
        }
    }
}
