import AuralisPrimaryModels
import AuralisPrimaryPersistence
import Foundation

public struct NFTCollectionDetailPresentation: Equatable, Sendable {
    public let title: String
    public let subtitle: String
    public let contractAddressLine: String?
    public let items: [Item]

    public init(title: String, subtitle: String, contractAddressLine: String?, items: [Item]) {
        self.title = title
        self.subtitle = subtitle
        self.contractAddressLine = contractAddressLine
        self.items = items
    }

    public struct Item: Equatable, Identifiable, Sendable {
        public let id: String
        public let title: String
        public let subtitle: String

        public init(id: String, title: String, subtitle: String) {
            self.id = id
            self.title = title
            self.subtitle = subtitle
        }
    }
}

public enum NFTLibraryPresentation {
    public static func collectionDetail(
        route: NFTLibraryRoute,
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
        case .collection(let contractAddress, let collectionTitle, let routeChain):
            title = collectionTitle
            let normalizedContractAddress = contractAddress.flatMap(NFT.normalizedScopeComponent)
            filteredNFTs = nfts.filter { nft in
                guard nft.network == routeChain else {
                    return false
                }

                if let normalizedContractAddress {
                    return normalizedContractAddresses(for: nft).contains(normalizedContractAddress)
                }

                let nftCollectionName = (nft.collection?.name ?? nft.collectionName ?? "")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                return nftCollectionName.caseInsensitiveCompare(collectionTitle) == .orderedSame
            }
            contractAddressLine = normalizedContractAddress.map(displayAddress)
        }

        let items = filteredNFTs.map { nft in
            NFTCollectionDetailPresentation.Item(
                id: nft.id,
                title: nft.name ?? "Untitled NFT",
                subtitle: nft.tokenId.isEmpty ? currentChain.routingDisplayName : "\(currentChain.routingDisplayName) - Token \(nft.tokenId)"
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

    public static func displayTitle(for nft: NFT) -> String {
        nft.name ?? "Untitled NFT"
    }

    public static func displaySubtitle(for nft: NFT, chain: Chain) -> String {
        let collection = nft.collection?.name ?? nft.collectionName
        if let collection, !collection.isEmpty {
            return collection
        }

        return nft.tokenId.isEmpty ? chain.routingDisplayName : "\(chain.routingDisplayName) - Token \(nft.tokenId)"
    }

    public static func imageURL(for nft: NFT) -> URL? {
        if let originalURL = nft.image?.originalUrl, let url = URL(string: originalURL) {
            return url
        }

        if let thumbnailURL = nft.image?.thumbnailUrl, let url = URL(string: thumbnailURL) {
            return url
        }

        return nil
    }

    public static func displayAddress(_ value: String) -> String {
        if value.count > 10 {
            return "\(value.prefix(6))...\(value.suffix(4))"
        }

        return value
    }

    private static func normalizedContractAddresses(for nft: NFT) -> Set<String> {
        [nft.contract.address, nft.collection?.contractAddress]
            .compactMap(NFT.normalizedScopeComponent)
            .reduce(into: Set<String>()) { addresses, address in
                addresses.insert(address)
            }
    }
}
