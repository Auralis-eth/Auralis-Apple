import AuralisPrimaryModels
import AuralisPrimaryPersistence
import NFTLibraryFeature
import SwiftData
import SwiftUI

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

    var body: some View {
        NFTLibraryCollectionDetailView(
            route: libraryRoute,
            nfts: nfts,
            currentChain: currentChain,
            onOpenItem: onOpenItem
        )
    }

    static func makePresentation(
        route: NFTTokensRoute,
        nfts: [NFT],
        currentChain: Chain
    ) -> NFTCollectionDetailPresentation {
        NFTLibraryPresentation.collectionDetail(
            route: route.libraryRoute,
            nfts: nfts,
            currentChain: currentChain
        )
    }

    private var libraryRoute: NFTLibraryRoute {
        route.libraryRoute
    }
}

private extension NFTTokensRoute {
    var libraryRoute: NFTLibraryRoute {
        switch self {
        case .item(let id):
            .item(id: id)
        case .collection(let contractAddress, let title, let chain):
            .collection(contractAddress: contractAddress, title: title, chain: chain)
        }
    }
}
