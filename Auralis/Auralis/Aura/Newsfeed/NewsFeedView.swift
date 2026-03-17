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
    let router: AppRouter

    var body: some View {
        NewsFeedListView(
            currentAccount: $currentAccount,
            selectedNFT: $selectedNFT,
            currentChain: $currentChain,
            nftService: nftService
        )
        .frame(maxWidth: .infinity)
        .background(Color.background)
        .refreshable {
            let correlationID = UUID().uuidString
            await nftService.refreshNFTs(
                for: currentAccount,
                chain: currentChain,
                modelContext: modelContext,
                correlationID: correlationID
            )
        }
        .onChange(of: selectedNFT) { oldValue, newValue in
            guard let newValue else { return }
            router.showNewsNFTDetail(id: newValue.id)
            selectedNFT = nil
        }
    }
}
