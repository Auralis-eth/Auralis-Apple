//
//  NewsFeedView.swift
//  Auralis
//
//  Created by Daniel Bell on 6/23/25.
//

import AuralisPrimaryModels
import SwiftData
import SwiftUI
import AuraUI
import NFTKit

// MARK: - Updated Views

struct NewsFeedView: View {
    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion
    @Environment(\.modelContext) private var modelContext

    @Binding var currentAccount: EOAccount?
    @State private var selectedNFT: NFT?
    @Binding var nftService: NFTService
    @Binding var currentChain: Chain
    let refreshAction: @MainActor () async -> Void
    let router: AppRouter

    private var haptics: AuraHaptics {
        AuraHaptics(accessibilityReduceMotion: accessibilityReduceMotion)
    }

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
            haptics.impact(.light)
            await refreshAction()
        }
        .onChange(of: selectedNFT) { _, newValue in
            guard let newValue else { return }
            router.showNewsNFTDetail(id: newValue.id)
            selectedNFT = nil
        }
    }
}
