//
//  NewsFeedListView.swift
//  Auralis
//
//  Created by Daniel Bell on 6/29/25.
//

import SwiftData
import SwiftUI
import SwiftUI

struct NewsFeedListView: View {
    @Query private var collections: [NFT.Collection]
    @Environment(\.modelContext) private var modelContext
    @Binding var currentAccount: EOAccount?
    @Binding var selectedNFT: NFT?
    @Binding var currentChain: Chain
    @State private var sortOrder = SortDescriptor(\NFT.acquiredAt?.blockTimestamp)
    @State private var searchText: String = ""

    let nftService: NFTService

    var body: some View {
        VStack {
            //    * [#11] Filter by Collection: Optional dropdown or search bar
            //    * [#12] Filter by Tag: Filter by user-added tags

            //    * AURA-13 [BE]: Implement filtering logic in the data layer.

//            * Date range filtering
//            * Multiple filter combinations
//            * Clear filters option
//            * Filter state persistence

//=================================




//            ForEach(collections) { collection in
//                Text(collection.name ?? "NO NAME")
//                    .foregroundStyle(Color.textPrimary)
//            }
//            if collections.isEmpty {
//                Text("No collections found")
//            }
            NewsFeedListingView(
                currentAccount: $currentAccount,
                selectedNFT: $selectedNFT,
                sort: sortOrder,
                searchString: searchText,
                nftService: nftService,
                currentChain: $currentChain
            )
        }
        .toolbar {
            ToolbarItemGroup {
//                ToolbarItem(placement: .navigationBarTrailing) {
                    Menu {
                        // Sort options
                        Menu("Time", systemImage: "clock") {
                            NFTSortButton(title: "Last Update", sortOrder: $sortOrder, keyPath: \.timeLastUpdated)
                            NFTSortButton(title: "Acquired", sortOrder: $sortOrder, keyPath: \.acquiredAt?.blockTimestamp)
                        }

                        NFTSortButton(title: "Collection Name", sortOrder: $sortOrder, keyPath: \.collection?.name)
                        NFTSortButton(title: "Item Name", sortOrder: $sortOrder, keyPath: \.name)
                    } label: {
                        SystemImage("line.3.horizontal.decrease")
                            .padding(8)
                    }
//                }
//                ToolbarItem(placement: .navigationBarTrailing) {
                    Menu {
                        // Sort options
                        //                    Menu("Time", systemImage: "clock") {
                        //                        NFTSortButton(title: "Last Update", sortOrder: $sortOrder, keyPath: \.timeLastUpdated)
                        NFTSortButton(title: "Acquired", sortOrder: $sortOrder, keyPath: \.acquiredAt?.blockTimestamp)
                        //                    }

                        NFTSortButton(title: "Collection Name", sortOrder: $sortOrder, keyPath: \.collection?.name)
                        NFTSortButton(title: "Item Name", sortOrder: $sortOrder, keyPath: \.name)
                    } label: {
                        SystemImage("ellipsis")
                            .padding(8)
                    }
//                }
            }

            ToolbarSpacer(.flexible)

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
