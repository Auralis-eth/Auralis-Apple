//
//  EmptyNewsFeedView.swift
//  Auralis
//
//  Created by Daniel Bell on 7/5/25.
//

import SwiftUI

struct EmptyNewsFeedView: View {
    @Environment(\.modelContext) private var modelContext
    let currentAccount: EOAccount?
    let currentChain: Chain

    let nftService: NFTService

    var content: some View {
        VStack(spacing: 20) {
            AccentTextSystemImage("photo.artframe")
                .font(.system(size: 60))

            Title2FontText("No NFTs Found")

            SecondaryText("We couldn't find any NFTs in this wallet address")
                .multilineTextAlignment(.center)

            Button {
                Task {
                    await nftService.refreshNFTs(
                        for: currentAccount,
                        chain: currentChain,
                        modelContext: modelContext
                    )
                }
            } label: {
                PrimaryText("Refresh")
                    .fontWeight(.medium)
                    .padding(.vertical, 12)
                    .padding(.horizontal, 24)
                    .background(Color.secondary)
                    .cornerRadius(12)
            }
            .disabled(nftService.isLoading)
        }
    }

    var body: some View {
        content
        .padding()
        .glassEffect(.regular.tint(.surface), in: .rect(cornerRadius: 30, style: .continuous))
    }
}
