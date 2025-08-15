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
        if nfts.isEmpty {
            // No NFTs found view
            ZStack {
                Image("aurora-1")
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipped()
                    .ignoresSafeArea()

                EmptyNewsFeedView(
                    currentAccount: currentAccount,
                    currentChain: currentChain,
                    nftService: nftService
                )
            }
        } else {
            ScrollView {
                LazyVStack(spacing: 16) {
                    ForEach(displayNFTs) { metaData in
                        NewsFeedCardView(nft: metaData)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            selectedNFT = metaData
                        }
                    }
                }
                .padding(.vertical)
            }
            .background(Color.background)
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


