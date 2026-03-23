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
    @Binding var currentAccount: EOAccount?
    @Binding var selectedNFT: NFT?
    @Binding var currentChain: Chain
    @State private var sortOrder = SortDescriptor(\NFT.acquiredAt?.blockTimestamp)
    @State private var searchText: String = ""

    let nftService: NFTService
    let refreshAction: @MainActor () async -> Void

    var body: some View {
        VStack {
            NewsFeedListingView(
                currentAccount: $currentAccount,
                selectedNFT: $selectedNFT,
                sort: sortOrder,
                searchString: searchText,
                nftService: nftService,
                currentChain: $currentChain,
                refreshAction: refreshAction
            )
        }
        .toolbar {
            ToolbarItemGroup {
                Menu {
                    NFTSortButton(title: "Acquired", sortOrder: $sortOrder, keyPath: \.acquiredAt?.blockTimestamp)
                    NFTSortButton(title: "Collection Name", sortOrder: $sortOrder, keyPath: \.collection?.name)
                    NFTSortButton(title: "Item Name", sortOrder: $sortOrder, keyPath: \.name)
                } label: {
                    SystemImage("ellipsis")
                        .padding(8)
                }
            }

            ToolbarSpacer(.flexible)

            ToolbarItem(placement: .navigationBarTrailing) {
                Button(action: {
                    Task {
                        await refreshAction()
                    }
                }) {
                    SystemImage("arrow.clockwise")
                }
                .disabled(nftService.isLoading)
            }
        }
    }
}
