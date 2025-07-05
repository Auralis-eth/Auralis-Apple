//
//  NewsFeedListView.swift
//  Auralis
//
//  Created by Daniel Bell on 6/29/25.
//

import SwiftData
import SwiftUI

struct NewsFeedListView: View {
    @Environment(\.modelContext) private var modelContext
    @Binding var currentAccount: EOAccount?
    @Binding var selectedNFT: NFT?
    @Binding var currentChain: Chain
    @State private var sortOrder = SortDescriptor(\NFT.acquiredAt?.blockTimestamp)
    @State private var searchText: String = ""

    let nftService: NFTService

    var body: some View {
        NewsFeedListingView(
            currentAccount: $currentAccount,
            selectedNFT: $selectedNFT,
            sort: sortOrder,
            searchString: searchText,
            nftService: nftService,
            currentChain: $currentChain
        )
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Menu {
                    // Sort options
                    Menu("Time", systemImage: "clock") {
                        NFTSortButton(title: "Last Update", sortOrder: $sortOrder, keyPath: \.timeLastUpdated)
                        NFTSortButton(title: "Acquired", sortOrder: $sortOrder, keyPath: \.acquiredAt?.blockTimestamp)
                    }

                    NFTSortButton(title: "Collection Name", sortOrder: $sortOrder, keyPath: \.collection?.name)
                    NFTSortButton(title: "Item Name", sortOrder: $sortOrder, keyPath: \.name)
                } label: {
                    SystemImage("ellipsis")
                        .padding(8)
                }
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(action: {
                    Task {
                        await nftService.refreshNFTs(
                            for: currentAccount,
                            chain: currentChain,
                            modelContext: modelContext
                        )
                    }
                }) {
                    SystemImage("arrow.clockwise")
                }
                .disabled(nftService.isLoading)
            }
        }
    }
}
