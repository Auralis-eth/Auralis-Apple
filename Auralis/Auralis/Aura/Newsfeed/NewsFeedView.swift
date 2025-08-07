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
    @State private var nftService = NFTService()
    @Binding var currentChain: Chain

    var body: some View {
        NavigationStack {
            // Main content - NFT list
            NewsFeedListView(
                currentAccount: $currentAccount,
                selectedNFT: $selectedNFT,
                currentChain: $currentChain,
                nftService: nftService
            )
            .frame(maxWidth: .infinity)
            .background(Color.background)
        }
        .background(Color.background)
        .task { @MainActor in
            await nftService.refreshNFTs(
                for: currentAccount,
                chain: currentChain,
                modelContext: modelContext
            )
        }
//        .scrollEdgeEffectStyle(.soft, for: .vertical)
//        .backgroundExtensionEffect()

        .refreshable {
            await nftService.refreshNFTs(
                for: currentAccount,
                chain: currentChain,
                modelContext: modelContext
            )
        }
    }
}
