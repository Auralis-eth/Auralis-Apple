//
//  NewsFeedListingView.swift
//  Auralis
//
//  Created by Daniel Bell on 6/29/25.
//

import SwiftData
import SwiftUI

struct NewsFeedListingView: View {
    @Query(sort: [
        SortDescriptor(\NFT.acquiredAt?.blockTimestamp),
        SortDescriptor(\NFT.collection?.name),
        SortDescriptor(\NFT.tokenId)
    ]) private var nfts: [NFT]

    @Binding var currentAccount: EOAccount?
    @Binding var selectedNFT: NFT?
    @Binding var currentChain: Chain

    let searchString: String
    let nftService: NFTService
    let refreshAction: @MainActor () async -> Void

    var displayNFTs: [NFT] {
        var currentNFTs = nfts
        //filter search
        if !searchString.trimmingCharacters(in: .whitespaces).isEmpty {
            currentNFTs = currentNFTs.filter {
                [$0.name, $0.collection?.name, $0.nftDescription]
                    .contains { field in
                        field?.localizedStandardContains(searchString) ?? false
                    }
            }
        }

        return currentNFTs
    }

    var body: some View {
        if nfts.isEmpty {
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
                    ScrollView(.vertical, showsIndicators: false) {
                        LazyVStack(spacing: 0) {
                            ForEach(displayNFTs) { metaData in
                                Button {
                                    selectedNFT = metaData
                                } label: {
                                    NewsFeedCardView(nft: metaData)
                                        .frame(width: geometry.size.width,
                                               height: geometry.size.height)
                                        .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel(metaData.name ?? metaData.collection?.name ?? "Open NFT")
                                .accessibilityHint("Shows NFT details")
                                .accessibilityAddTraits(.isButton)
                            }
                        }
                    }
                    .scrollTargetBehavior(.paging)
                }
            }
            .background(Color.background)
            .ignoresSafeArea(.all)
        }
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
        _nfts = Query(
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

}
