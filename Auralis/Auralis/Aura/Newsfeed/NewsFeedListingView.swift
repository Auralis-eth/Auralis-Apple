//
//  NewsFeedListingView.swift
//  Auralis
//
//  Created by Daniel Bell on 6/29/25.
//

import AuralisPrimaryModels
import NFTLibraryFeature
import SwiftData
import SwiftUI
import NFTKit

struct NewsFeedListingView: View {
    @Query private var scopedNFTs: [NFT]

    @Binding var currentAccount: EOAccount?
    @Binding var selectedNFT: NFT?
    @Binding var currentChain: Chain

    let searchString: String
    let nftService: NFTService
    let refreshAction: @MainActor () async -> Void

    @State private var searchResults: [NFT] = []

    var body: some View {
        NFTLibraryNewsFeedRootView(
            nfts: scopedNFTs,
            searchResults: searchResults,
            searchString: searchString,
            isLoading: nftService.isLoading,
            failure: nftService.providerFailurePresentation(isShowingCachedContent: !scopedNFTs.isEmpty),
            actions: NFTLibraryActions(
                openNFT: { id in
                    selectedNFT = scopedNFTs.first { $0.id == id } ?? searchResults.first { $0.id == id }
                },
                refresh: refreshAction
            )
        )
        .task(id: searchKey) {
            await refreshSearchResults()
        }
    }

    init(
        currentAccount: Binding<EOAccount?>,
        selectedNFT: Binding<NFT?>,
        sort: SortDescriptor<NFT>,
        searchString: String,
        nftService: NFTService,
        currentChain: Binding<Chain>,
        refreshAction: @escaping @MainActor () async -> Void
    ) {
        let normalizedAccountAddress = NFT.normalizedScopeComponent(currentAccount.wrappedValue?.address) ?? ""
        let chainRawValue = currentChain.wrappedValue.rawValue

        _scopedNFTs = Query(
            filter: #Predicate<NFT> {
                $0.accountAddressRawValue == normalizedAccountAddress &&
                $0.networkRawValue == chainRawValue
            },
            sort: [sort]
        )
        self.searchString = searchString
        _selectedNFT = selectedNFT
        _currentAccount = currentAccount
        self.nftService = nftService
        _currentChain = currentChain
        self.refreshAction = refreshAction
    }

    private var searchKey: NewsFeedSearchKey {
        NewsFeedSearchKey(
            accountID: currentAccount?.persistentModelID,
            chainRawValue: currentChain.rawValue,
            normalizedQuery: searchString
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased(),
            scopedNFTIDs: scopedNFTs.map(\.persistentModelID)
        )
    }

    @MainActor
    private func refreshSearchResults() async {
        let trimmedSearchString = searchString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedSearchString.isEmpty else {
            searchResults = []
            return
        }

        let normalizedAccountAddress = NFT.normalizedScopeComponent(currentAccount?.address) ?? ""
        let chainRawValue = currentChain.rawValue

        searchResults = scopedNFTs.filter { nft in
            nft.accountAddressRawValue == normalizedAccountAddress &&
            nft.networkRawValue == chainRawValue &&
            (
                (nft.name ?? "").localizedStandardContains(trimmedSearchString) ||
                (nft.collectionName ?? "").localizedStandardContains(trimmedSearchString) ||
                (nft.nftDescription ?? "").localizedStandardContains(trimmedSearchString)
            )
        }
    }

}

private struct NewsFeedSearchKey: Equatable {
    let accountID: PersistentIdentifier?
    let chainRawValue: String
    let normalizedQuery: String
    let scopedNFTIDs: [PersistentIdentifier]
}
