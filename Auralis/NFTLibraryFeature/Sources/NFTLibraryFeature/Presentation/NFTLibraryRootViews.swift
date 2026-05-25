import AuralisPrimaryModels
import AuralisPrimaryPersistence
import AuraUI
import NFTDomain
import NFTPersistence
import NFTPresentation
import NFTProviderAdapters
import SwiftUI

#if canImport(UIKit)
import UIKit
#endif

public struct NFTLibraryTokensRootView: View {
    public let nfts: [NFT]
    public let currentChain: Chain
    public let emptyTitle: String
    public let emptyMessage: String
    public let isLoading: Bool
    public let failure: NFTProviderFailurePresentation?
    public let actions: NFTLibraryActions

    public init(
        nfts: [NFT],
        currentChain: Chain,
        emptyTitle: String = "No NFTs Found",
        emptyMessage: String,
        isLoading: Bool,
        failure: NFTProviderFailurePresentation?,
        actions: NFTLibraryActions
    ) {
        self.nfts = nfts
        self.currentChain = currentChain
        self.emptyTitle = emptyTitle
        self.emptyMessage = emptyMessage
        self.isLoading = isLoading
        self.failure = failure
        self.actions = actions
    }

    public var body: some View {
        Group {
            if nfts.isEmpty {
                NFTLibraryScenicScreen(contentAlignment: Alignment.center) {
                    if let failure {
                        NFTLibraryProviderFailureStateView(failure: failure, retry: actions.refresh)
                    } else {
                        NFTLibraryEmptyStateView(
                            title: emptyTitle,
                            message: emptyMessage,
                            isLoading: isLoading,
                            refresh: actions.refresh
                        )
                    }
                }
            } else {
                VStack(spacing: 0) {
                    if let failure {
                        NFTLibraryFailureBanner(failure: failure, retry: actions.refresh)
                    }

                    List(nfts) { nft in
                        Button {
                            actions.openNFT(nft.id)
                        } label: {
                            VStack(alignment: .leading, spacing: 6) {
                                Text(NFTLibraryPresentation.displayTitle(for: nft))
                                    .foregroundStyle(Color.textPrimary)

                                Text(NFTLibraryPresentation.displaySubtitle(for: nft, chain: currentChain))
                                    .font(.caption)
                                    .foregroundStyle(Color.textSecondary)
                            }
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("nftTokens.row.\(nft.id)")
                    }
                }
            }
        }
        .navigationTitle("NFT Tokens")
        .accessibilityIdentifier("nftTokens.root")
    }
}

public struct NFTLibraryNewsFeedRootView: View {
    public let nfts: [NFT]
    public let searchResults: [NFT]
    public let searchString: String
    public let isLoading: Bool
    public let failure: NFTProviderFailurePresentation?
    public let actions: NFTLibraryActions

    public init(
        nfts: [NFT],
        searchResults: [NFT] = [],
        searchString: String = "",
        isLoading: Bool,
        failure: NFTProviderFailurePresentation?,
        actions: NFTLibraryActions
    ) {
        self.nfts = nfts
        self.searchResults = searchResults
        self.searchString = searchString
        self.isLoading = isLoading
        self.failure = failure
        self.actions = actions
    }

    private var displayNFTs: [NFT] {
        searchString.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nfts : searchResults
    }

    public var body: some View {
        Group {
            if nfts.isEmpty {
                ZStack {
                    Image("aurora-1")
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .clipped()
                        .ignoresSafeArea()
                        .accessibilityHidden(true)

                    if let failure {
                        NFTLibraryProviderFailureStateView(failure: failure, retry: actions.refresh)
                    } else {
                        NFTLibraryEmptyStateView(isLoading: isLoading, refresh: actions.refresh)
                    }
                }
            } else {
                VStack(spacing: 12) {
                    if let failure {
                        NFTLibraryFailureBanner(failure: failure, retry: actions.refresh)
                    }

                    GeometryReader { geometry in
                        ScrollView(.vertical, showsIndicators: false) {
                            LazyVStack(spacing: 0) {
                                ForEach(displayNFTs) { nft in
                                    Button {
                                        actions.openNFT(nft.id)
                                    } label: {
                                        NFTLibraryCardView(nft: nft)
                                            .frame(width: geometry.size.width)
                                            .frame(minHeight: geometry.size.height, maxHeight: geometry.size.height)
                                            .contentShape(Rectangle())
                                    }
                                    .buttonStyle(.plain)
                                    .accessibilityElement(children: .contain)
                                    .accessibilityLabel(NFTLibraryPresentation.displayTitle(for: nft))
                                    .accessibilityValue(
                                        String(localized: "Collection: \(nft.collection?.name ?? "Unknown Collection")")
                                    )
                                    .accessibilityHint(String(localized: "Shows NFT details"))
                                    .accessibilityAction(named: "Open details") {
                                        actions.openNFT(nft.id)
                                    }
                                    .accessibilityAction(named: "Copy token ID") {
                                        copyNFTIdentifier(nft.id)
                                    }
                                }
                            }
                            .scrollTargetLayout()
                        }
                        .scrollTargetBehavior(.paging)
                    }
                }
                .background(Color.background)
                .ignoresSafeArea(.all)
            }
        }
    }

    private func copyNFTIdentifier(_ id: String) {
        #if canImport(UIKit)
        UIPasteboard.general.string = id
        #endif
        AuraAccessibilityAnnouncer.announce("NFT ID copied")
    }
}
