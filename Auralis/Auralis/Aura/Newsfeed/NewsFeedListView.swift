//
//  NewsFeedListView.swift
//  Auralis
//
//  Created by Daniel Bell on 6/29/25.
//

import AuralisCrypto
import AuraUI
import AuralisOperators
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
                // Reviewed: the accessibility label, hint, and input labels are attached to the
                // Menu below; the rule's regex can't see modifiers that follow the label closure.
                // swiftlint:disable:next icon_only_system_image_control_requires_accessibility_label
                Menu {
                    NFTLibrarySortButton(title: "Acquired", field: .acquired, sortOrder: $sortOrder)
                    NFTLibrarySortButton(title: "Collection Name", field: .collectionName, sortOrder: $sortOrder)
                    NFTLibrarySortButton(title: "Item Name", field: .itemName, sortOrder: $sortOrder)
                } label: {
                    SystemImage("ellipsis")
                        .padding(8)
                        .frame(minWidth: 44, minHeight: 44)
                }
                .accessibilityLabel(String(localized: "Sort NFTs"))
                .accessibilityHint(String(localized: "Changes the news feed sort order"))
                .accessibilityInputLabels([
                    String(localized: "Sort"),
                    String(localized: "Sort NFTs")
                ])
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
                .frame(minWidth: 44, minHeight: 44)
                .accessibilityLabel(String(localized: "Refresh NFTs"))
                .accessibilityHint(String(localized: "Fetches the latest NFTs for this wallet"))
                .accessibilityInputLabels([
                    String(localized: "Refresh"),
                    String(localized: "Refresh NFTs")
                ])
                .disabled(nftService.isLoading)
            }
        }
    }
}
