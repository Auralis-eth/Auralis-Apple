//
//  NewsFeedListView.swift
//  Auralis
//
//  Created by Daniel Bell on 6/29/25.
//

import AuralisPrimaryModels
import SwiftData
import SwiftUI

struct NewsFeedListView: View {
    @Binding var currentAccount: EOAccount?
    @Binding var selectedNFT: NFT?
    @Binding var currentChain: Chain
    @State private var sortOrder = SortDescriptor(\NFT.acquiredAt?.blockTimestamp)
    @State private var searchText: String = ""

    let nftService: NFTService
    let refreshAction: @MainActor () async -> Void

    private var scopeIdentity: String {
        let normalizedAddress = NFT.normalizedScopeComponent(currentAccount?.address) ?? ""
        return "\(normalizedAddress)|\(currentChain.rawValue)"
    }

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
            .id(scopeIdentity)
        }
        .toolbar {
            ToolbarItemGroup {
                Menu {
                    NFTSortButton(title: "Acquired", field: .acquired, sortOrder: $sortOrder)
                    NFTSortButton(title: "Collection Name", field: .collectionName, sortOrder: $sortOrder)
                    NFTSortButton(title: "Item Name", field: .itemName, sortOrder: $sortOrder)
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
                }, label: {
                    SystemImage("arrow.clockwise")
                })
                .disabled(nftService.isLoading)
            }
        }
    }
}
