import SwiftData
import SwiftUI

struct SharedNFTDetailView: View {
    let route: NFTDetailRoute
    let currentAccountAddress: String?
    let currentChain: Chain
    @Query private var nfts: [NFT]

    init(route: NFTDetailRoute, currentAccountAddress: String?, currentChain: Chain) {
        self.route = route
        self.currentAccountAddress = currentAccountAddress
        self.currentChain = currentChain

        let normalizedAccountAddress = NFT.normalizedScopeComponent(currentAccountAddress) ?? ""
        let chainRawValue = currentChain.rawValue
        _nfts = Query(
            filter: #Predicate<NFT> {
                $0.accountAddressRawValue == normalizedAccountAddress &&
                $0.networkRawValue == chainRawValue
            }
        )
    }

    private var nft: NFT? {
        switch route {
        case .detail(let id):
            return nfts.first { $0.id == id }
        }
    }

    private var imageURL: URL? {
        guard let nft else { return nil }

        if let originalURL = nft.image?.originalUrl, let url = URL(string: originalURL) {
            return url
        }

        if let thumbnailURL = nft.image?.thumbnailUrl, let url = URL(string: thumbnailURL) {
            return url
        }

        return nil
    }

    private var titleText: String {
        nft?.name ?? "Untitled NFT"
    }

    private var collectionName: String? {
        nft?.collection?.name ?? nft?.collectionName
    }

    private var descriptionText: String? {
        guard let description = nft?.nftDescription, !description.isEmpty else {
            return nil
        }

        return description
    }

    var body: some View {
        Group {
            if let nft {
                VStack {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 20) {
                            nftImage

                            VStack(alignment: .leading, spacing: 12) {
                                AuraTrustLabel(kind: .metadata)

                                HeadlineFontText(titleText)
                                    .fontWeight(.semibold)
                                    .accessibilityIdentifier("nft.detail.title")

                                if let collectionName {
                                    SubheadlineFontText(collectionName)
                                }

                                if let description = descriptionText {
                                    SecondaryText(description)
                                }

                                badgeRow(for: nft)
                            }
                        }
                        .padding()
                    }
                }
                .navigationTitle(titleText)
                .navigationBarTitleDisplayMode(.inline)
                .background(Color.background)
                .accessibilityIdentifier("nft.detail.screen")
            } else {
                ContentUnavailableView(
                    "NFT Unavailable",
                    systemImage: "exclamationmark.triangle",
                    description: Text("The requested NFT could not be resolved for the current account.")
                )
                .navigationTitle("NFT Detail")
                .accessibilityIdentifier("nft.detail.unavailable")
            }
        }
    }

    private var nftImage: some View {
        AsyncImage(url: imageURL) { image in
            image
                .resizable()
                .scaledToFill()
        } placeholder: {
            RoundedRectangle(cornerRadius: 20)
                .fill(Color.secondary.opacity(0.2))
                .overlay {
                    SystemImage("photo")
                        .font(.largeTitle)
                        .foregroundStyle(.secondary)
                }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 280)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    @ViewBuilder
    private func badgeRow(for nft: NFT) -> some View {
        HStack(spacing: 12) {
            if let chain = nft.network {
                BadgeLabel(title: chain.routingDisplayName)
            }

            if nft.isMusic() {
                BadgeLabel(title: "Music NFT")
            }
        }
    }
}

struct NFTTokensRootView: View {
    @Query private var nfts: [NFT]
    let currentAccount: EOAccount?
    let currentChain: Chain
    let contextSnapshot: ContextSnapshot
    let nftService: NFTService
    let refreshAction: @MainActor () async -> Void
    let router: AppRouter

    init(
        currentAccount: EOAccount?,
        currentChain: Chain,
        contextSnapshot: ContextSnapshot,
        nftService: NFTService,
        refreshAction: @escaping @MainActor () async -> Void,
        router: AppRouter
    ) {
        self.currentAccount = currentAccount
        self.currentChain = currentChain
        self.contextSnapshot = contextSnapshot
        self.nftService = nftService
        self.refreshAction = refreshAction
        self.router = router

        let normalizedAccountAddress = NFT.normalizedScopeComponent(currentAccount?.address) ?? ""
        let chainRawValue = currentChain.rawValue
        _nfts = Query(
            filter: #Predicate<NFT> {
                $0.accountAddressRawValue == normalizedAccountAddress &&
                $0.networkRawValue == chainRawValue
            },
            sort: [SortDescriptor(\NFT.acquiredAt?.blockTimestamp, order: .reverse)]
        )
    }

    var body: some View {
        Group {
            if nfts.isEmpty {
                AuraScenicScreen(contentAlignment: .center) {
                    if let failure = nftService.providerFailurePresentation(isShowingCachedContent: false) {
                        ShellProviderFailureStateView(
                            failure: failure,
                            retry: refresh
                        )
                    } else {
                        ShellEmptyLibraryStateView(
                            kind: .nft,
                            snapshot: contextSnapshot
                        )
                    }
                }
            } else {
                VStack(spacing: 0) {
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

                    List(nfts) { nft in
                        Button {
                            router.showNFTTokensDetail(id: nft.id)
                        } label: {
                            VStack(alignment: .leading, spacing: 6) {
                                Text(nft.name ?? "Untitled NFT")
                                    .foregroundStyle(Color.textPrimary)

                                Text(nft.collection?.name ?? nft.collectionName ?? nft.tokenId)
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

    private func refresh() {
        Task {
            await refreshAction()
        }
    }
}
