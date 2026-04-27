//
//  EmptyNewsFeedView.swift
//  Auralis
//
//  Created by Daniel Bell on 7/5/25.
//

import SwiftUI

struct EmptyNewsFeedView: View {
    let currentAccount: EOAccount?
    let currentChain: Chain

    let nftService: NFTService
    let refreshAction: @MainActor () async -> Void

    var body: some View {
        Group {
            if let failure = nftService.providerFailurePresentation(isShowingCachedContent: false) {
                ShellProviderFailureStateView(
                    failure: failure,
                    retry: refresh
                )
            } else {
                AuraEmptyState(
                    eyebrow: "Collection",
                    title: "No NFTs Found",
                    message: "We could not find NFTs for this wallet on the current chain yet. Try refreshing or switch to another saved account.",
                    systemImage: "photo.artframe",
                    tone: .neutral,
                    primaryAction: AuraFeedbackAction(
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
            await refreshAction()
        }
    }
}
