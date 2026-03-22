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
        var currentNFTs = nfts
        //filter search
        if !searchString.trimmingCharacters(in: .whitespaces).isEmpty {
            currentNFTs = currentNFTs.filter {
                [$0.name, $0.collection?.name, $0.nftDescription]
                    .contains { field in
                        field?.localizedStandardContains(searchString) ?? false
                    }
            }
        }
        
        return currentNFTs
    }

    var body: some View {
        if nfts.isEmpty {
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
            VStack(spacing: 12) {
                if let error = nftService.error {
                    AuraErrorBanner(
                        title: "Showing Last Sync",
                        message: error.localizedDescription,
                        systemImage: "exclamationmark.triangle",
                        tone: .warning,
                        action: AuraFeedbackAction(
                            title: "Retry",
                            systemImage: "arrow.clockwise",
                            handler: refresh
                        )
                    )
                    .padding(.horizontal, 12)
                    .padding(.top, 8)
                }

                GeometryReader { geometry in
                    ScrollView(.vertical, showsIndicators: false) {
                        LazyVStack(spacing: 0) {
                            ForEach(displayNFTs) { metaData in
                                NewsFeedCardView(nft: metaData)
                                    .frame(width: geometry.size.width,
                                           height: geometry.size.height)
                                    .contentShape(Rectangle())
                                    .onTapGesture {
                                        selectedNFT = metaData
                                    }
                            }
                        }
                    }
                    .scrollTargetBehavior(.paging)
                }
            }
            .background(Color.background)
            .ignoresSafeArea(.all)
        }
    }


    init(
        currentAccount: Binding<EOAccount?>,
        selectedNFT: Binding<NFT?>,
        sort: SortDescriptor<NFT>,
        searchString: String,
        nftService: NFTService,
        currentChain: Binding<Chain>
    ) {
        _nfts = Query(sort: [sort])
        self.searchString = searchString
        _selectedNFT = selectedNFT
        _currentAccount = currentAccount
        self.nftService = nftService
        _currentChain = currentChain
    }

    private func refresh() {
        Task {
            let correlationID = UUID().uuidString
            await nftService.refreshNFTs(
                for: currentAccount,
                chain: currentChain,
                modelContext: modelContext,
                correlationID: correlationID
            )
        }
    }

}
