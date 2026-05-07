//
//  NewsFeedListingView.swift
//  Auralis
//
//  Created by Daniel Bell on 6/29/25.
//

import AuralisPrimaryModels
import SwiftData
import SwiftUI

struct NewsFeedListingView: View {
    @Query private var scopedNFTs: [NFT]

    @Binding var currentAccount: EOAccount?
    @Binding var selectedNFT: NFT?
    @Binding var currentChain: Chain

    let searchString: String
    let nftService: NFTService
    let refreshAction: @MainActor () async -> Void

    @State private var searchResults: [NFT] = []

    var body: some View {
        Group {
            if scopedNFTs.isEmpty {
                ZStack {
                    Image("aurora-1")
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .clipped()
                        .ignoresSafeArea()

                    EmptyNewsFeedView(
                        currentAccount: currentAccount,
                        currentChain: currentChain,
                        nftService: nftService,
                        refreshAction: refreshAction
                    )
                }
            } else {
                VStack(spacing: 12) {
                    if let failure = nftService.providerFailurePresentation(isShowingCachedContent: true) {
                        ShellStatusBanner(
                            title: failure.title,
                            message: failure.message,
                            systemImage: failure.systemImage,
                            tone: .warning,
                            action: failure.isRetryable ? ShellStatusAction(
                                title: "Retry",
                                systemImage: "arrow.clockwise",
                                handler: refresh
                            ) : nil
                        )
                        .padding(.horizontal, 12)
                        .padding(.top, 8)
                    }

                    GeometryReader { geometry in
                        let cardWidth = geometry.size.width
                        let cardHeight = geometry.size.height

                        ScrollView(.vertical, showsIndicators: false) {
                            LazyVStack(spacing: 0) {
                                ForEach(displayNFTs) { metaData in
                                    newsFeedCardButton(for: metaData, width: cardWidth, height: cardHeight)
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
        .task(id: searchKey) {
            await refreshSearchResults()
        }
    }

    private var displayNFTs: [NFT] {
        let trimmedSearchString = searchString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedSearchString.isEmpty else {
            return scopedNFTs
        }

        return searchResults
    }

    init(
        currentAccount: Binding<EOAccount?>,
        selectedNFT: Binding<NFT?>,
        sort: SortDescriptor<NFT>,
        searchString: String,
        nftService: NFTService,
        currentChain: Binding<Chain>,
        refreshAction: @escaping @MainActor () async -> Void
    ) {
        let normalizedAccountAddress = NFT.normalizedScopeComponent(currentAccount.wrappedValue?.address) ?? ""
        let chainRawValue = currentChain.wrappedValue.rawValue

        _scopedNFTs = Query(
            filter: #Predicate<NFT> {
                $0.accountAddressRawValue == normalizedAccountAddress &&
                $0.networkRawValue == chainRawValue
            },
            sort: [sort]
        )
        self.searchString = searchString
        _selectedNFT = selectedNFT
        _currentAccount = currentAccount
        self.nftService = nftService
        _currentChain = currentChain
        self.refreshAction = refreshAction
    }

    private func refresh() {
        Task {
            await refreshAction()
        }
    }

    private var searchKey: NewsFeedSearchKey {
        NewsFeedSearchKey(
            accountID: currentAccount?.persistentModelID,
            chainRawValue: currentChain.rawValue,
            normalizedQuery: searchString
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased(),
            scopedNFTIDs: scopedNFTs.map(\.persistentModelID)
        )
    }

    @MainActor
    private func refreshSearchResults() async {
        let trimmedSearchString = searchString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedSearchString.isEmpty else {
            searchResults = []
            return
        }

        let normalizedAccountAddress = NFT.normalizedScopeComponent(currentAccount?.address) ?? ""
        let chainRawValue = currentChain.rawValue

        searchResults = scopedNFTs.filter { nft in
            nft.accountAddressRawValue == normalizedAccountAddress &&
            nft.networkRawValue == chainRawValue &&
            (
                (nft.name ?? "").localizedStandardContains(trimmedSearchString) ||
                (nft.collectionName ?? "").localizedStandardContains(trimmedSearchString) ||
                (nft.nftDescription ?? "").localizedStandardContains(trimmedSearchString)
            )
        }
    }

    private func newsFeedCardButton(for nft: NFT, width: CGFloat, height: CGFloat) -> some View {
        Button {
            selectedNFT = nft
        } label: {
            NewsFeedCardView(nft: nft)
                .frame(width: width)
                .frame(minHeight: height, maxHeight: height)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(nft.name ?? nft.collection?.name ?? "Open NFT")
        .accessibilityHint("Shows NFT details")
        .accessibilityAddTraits(.isButton)
    }

}

private struct NewsFeedSearchKey: Equatable {
    let accountID: PersistentIdentifier?
    let chainRawValue: String
    let normalizedQuery: String
    let scopedNFTIDs: [PersistentIdentifier]
}
