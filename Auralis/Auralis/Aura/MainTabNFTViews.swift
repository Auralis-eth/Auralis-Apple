import AuralisPrimaryModels
import NFTKit
import NFTLibraryFeature
import OperatorCore
import ReceiptStorage
import ReceiptsCore
import SwiftData
import SwiftUI

struct SharedNFTDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.openURL) private var openURL
    @Query private var nfts: [NFT]

    let route: NFTDetailRoute
    let currentAccountAddress: String?
    let currentChain: Chain

    init(route: NFTDetailRoute, currentAccountAddress: String?, currentChain: Chain) {
        self.route = route
        self.currentAccountAddress = currentAccountAddress
        self.currentChain = currentChain

        let normalizedAccountAddress = NFT.normalizedScopeComponent(currentAccountAddress) ?? ""
        let chainRawValue = currentChain.rawValue
        let requestedID: String
        switch route {
        case .detail(let id):
            requestedID = id
        }

        var descriptor = FetchDescriptor<NFT>(
            predicate: #Predicate<NFT> { nft in
                nft.id == requestedID &&
                nft.accountAddressRawValue == normalizedAccountAddress &&
                nft.networkRawValue == chainRawValue
            }
        )
        descriptor.fetchLimit = 1
        _nfts = Query(descriptor)
    }

    var body: some View {
        NFTLibraryDetailView(
            nft: nfts.first,
            dependencies: libraryDependencies
        )
    }

    private var libraryDependencies: NFTLibraryDependencies {
        NFTLibraryDependencies { request in
            await ExternalLinkOpenFlow(
                eventLogger: AppExternalLinkEventLogger(
                    receiptEventLogger: ReceiptEventLogger(
                        receiptStore: ReceiptStores.live(modelContext: modelContext)
                    )
                ),
                openURL: { url in
                    openURL(url)
                }
            ).confirm(request)
        }
    }
}

struct NFTTokensRootView: View {
    @Query private var nfts: [NFT]

    let currentAccount: EOAccount?
    let currentChain: Chain
    let contextSnapshot: ContextSnapshot
    let nftService: NFTService
    let refreshAction: @MainActor () async -> Void
    let router: AppRouter

    init(
        currentAccount: EOAccount?,
        currentChain: Chain,
        contextSnapshot: ContextSnapshot,
        nftService: NFTService,
        refreshAction: @escaping @MainActor () async -> Void,
        router: AppRouter
    ) {
        self.currentAccount = currentAccount
        self.currentChain = currentChain
        self.contextSnapshot = contextSnapshot
        self.nftService = nftService
        self.refreshAction = refreshAction
        self.router = router

        let normalizedAccountAddress = NFT.normalizedScopeComponent(currentAccount?.address) ?? ""
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
        NFTLibraryTokensRootView(
            nfts: nfts,
            currentChain: currentChain,
            emptyMessage: emptyMessage,
            isLoading: nftService.isLoading,
            failure: nftService.providerFailurePresentation(isShowingCachedContent: !nfts.isEmpty),
            actions: NFTLibraryActions(
                openNFT: { id in
                    router.showNFTTokensDetail(id: id)
                },
                openCollection: { contractAddress, title, chain in
                    router.showNFTCollectionDetail(contractAddress: contractAddress, title: title, chain: chain)
                },
                refresh: refreshAction
            )
        )
    }

    private var emptyMessage: String {
        let scope = contextSnapshot.scopeSummary
        return "No NFTs are available for \(scope). Try refreshing or switch to another saved account."
    }
}
