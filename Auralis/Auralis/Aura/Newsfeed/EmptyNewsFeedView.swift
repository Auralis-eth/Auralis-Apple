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

    var body: some View {
        Group {
            if nftService.error != nil {
                ShellProviderFailureStateView(
                    error: nftService.error,
                    isShowingCachedContent: false,
                    retry: refresh
                )
            } else {
                ShellStatusCard(
                    eyebrow: "Collection",
                    title: "No NFTs Found",
                    message: "We could not find NFTs for this wallet on the current chain yet. Try refreshing or switch to another saved account.",
                    systemImage: "photo.artframe",
                    tone: .neutral,
                    primaryAction: ShellStatusAction(
                        title: "Refresh",
                        systemImage: "arrow.clockwise",
                        handler: refresh
                    )
                )
            }
        }
        .disabled(nftService.isLoading)
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
