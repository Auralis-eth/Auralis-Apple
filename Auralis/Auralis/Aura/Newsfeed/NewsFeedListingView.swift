//
//  NewsFeedListingView.swift
//  Auralis
//
//  Created by Daniel Bell on 6/29/25.
//

import SwiftData
import SwiftUI

struct NewsFeedListingView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: [
        SortDescriptor(\NFT.acquiredAt?.blockTimestamp),
        SortDescriptor(\NFT.collection?.name),
        SortDescriptor(\NFT.tokenId)
    ]) private var nfts: [NFT]

    @Binding var currentAccount: EOAccount?
    @Binding var selectedNFT: NFT?
    @Binding var currentChain: Chain

    let searchString: String
    let nftService: NFTService

    var displayNFTs: [NFT] {
        if searchString.trimmingCharacters(in: .whitespaces).isEmpty {
            nfts
        } else {
            nfts.filter {
                [$0.name, $0.collection?.name, $0.nftDescription]
                    .contains { field in
                        field?.localizedStandardContains(searchString) ?? false
                    }
            }
        }
    }

    var body: some View {
        if nftService.isLoading && nfts.isEmpty {
            // Loading state with background
            Image("aurora-1")
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipped()
                .ignoresSafeArea()
                .overlay(alignment: .center) {
                    if nftService.isLoading {
                        NFTNewsfeedLoadingView(
                            itemsLoaded: nftService.itemsLoaded,
                            total: nftService.total
                        )
                    }
                }
        } else if nfts.isEmpty {
            // No NFTs found view
            EmptyNewsFeedView(
                currentAccount: currentAccount,
                currentChain: currentChain,
                nftService: nftService
            )
//            .task { @MainActor in
//                await nftService.refreshNFTs(
//                    for: currentAccount,
//                    chain: currentChain,
//                    modelContext: modelContext
//                )
//            }
        } else {
            ScrollView {
                LazyVStack(spacing: 16) {
                    ForEach(displayNFTs) { metaData in
                        NewfeedCardView(nft: metaData)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            selectedNFT = metaData
                        }
                    }
                }
                .padding(.vertical)
            }
            .background(Color.background)
            .overlay(alignment: .topLeading) {
                if nftService.isLoading {
                    NFTNewsfeedLoadingView(
                        itemsLoaded: nftService.itemsLoaded,
                        total: nftService.total,
                        size: .small
                    )
                }
            }
            .task { @MainActor in
                await nftService.refreshNFTs(
                    for: currentAccount,
                    chain: currentChain,
                    modelContext: modelContext
                )
            }
        }
    }

    init(currentAccount: Binding<EOAccount?>, selectedNFT: Binding<NFT?>, sort: SortDescriptor<NFT>, searchString: String, nftService: NFTService, currentChain: Binding<Chain>) {
        _nfts = Query(sort: [sort])
        self.searchString = searchString
        _selectedNFT = selectedNFT
        _currentAccount = currentAccount
        self.nftService = nftService
        _currentChain = currentChain
    }

}


