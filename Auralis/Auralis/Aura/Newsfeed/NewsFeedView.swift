//
//  NewsFeedView.swift
//  Auralis
//
//  Created by Daniel Bell on 6/23/25.
//

import SwiftData
import SwiftUI

// MARK: - Updated Views

struct NewsFeedView: View {
    @Environment(\.modelContext) private var modelContext

    @Binding var currentAccount: EOAccount?
    @State private var selectedNFT: NFT?
    @Binding var nftService: NFTService
    @Binding var currentChain: Chain
    let refreshAction: @MainActor () async -> Void
    let router: AppRouter

    var body: some View {
        NewsFeedListView(
            currentAccount: $currentAccount,
            selectedNFT: $selectedNFT,
            currentChain: $currentChain,
            nftService: nftService,
            refreshAction: refreshAction
        )
        .frame(maxWidth: .infinity)
        .background(Color.background)
        .refreshable {
            await refreshAction()
        }
        .onChange(of: selectedNFT) { oldValue, newValue in
            guard let newValue else { return }
            router.showNewsNFTDetail(id: newValue.id)
            selectedNFT = nil
        }
    }
}
