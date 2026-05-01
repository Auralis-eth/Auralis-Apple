import SwiftData
import SwiftUI

struct NFTMusicPlayerLibraryView: View {
    @ObservedObject var audioEngine: AudioEngine
    let currentAccount: EOAccount?
    let currentChain: Chain
    let nftService: NFTService
    let refreshAction: @MainActor () async -> Void
    let onOpenNFT: (NFT) -> Void
    let onOpenCollection: (MusicCollectionSummary) -> Void
    let musicLibraryIndexer: any MusicLibraryIndexing
    let musicLibraryReceiptLogger: ReceiptEventLogger
    @Environment(\.modelContext) private var modelContext
    @Query private var libraryItems: [MusicLibraryItem]

    @AppStorage("feature_recentlyPlayedLibrary") private var featureRecentlyPlayedLibrary: Bool = true

    @State private var errorMessage: String?
    @State private var showingError: Bool = false
    @State private var lastRebuildSignature: Int?
    @State private var musicNFTByID: [String: NFT] = [:]

    init(
        audioEngine: AudioEngine,
        currentAccount: EOAccount?,
        currentChain: Chain,
        nftService: NFTService,
        refreshAction: @escaping @MainActor () async -> Void,
        onOpenNFT: @escaping (NFT) -> Void,
        onOpenCollection: @escaping (MusicCollectionSummary) -> Void,
        musicLibraryIndexer: any MusicLibraryIndexing,
        musicLibraryReceiptLogger: ReceiptEventLogger
    ) {
        self.audioEngine = audioEngine
        self.currentAccount = currentAccount
        self.currentChain = currentChain
        self.nftService = nftService
        self.refreshAction = refreshAction
        self.onOpenNFT = onOpenNFT
        self.onOpenCollection = onOpenCollection
        self.musicLibraryIndexer = musicLibraryIndexer
        self.musicLibraryReceiptLogger = musicLibraryReceiptLogger

        let normalizedAccountAddress = NFT.normalizedScopeComponent(currentAccount?.address) ?? ""
        let chainRawValue = currentChain.rawValue
        _libraryItems = Query(
            filter: #Predicate<MusicLibraryItem> {
                $0.accountAddressRawValue == normalizedAccountAddress &&
                $0.networkRawValue == chainRawValue
            },
            sort: [
                SortDescriptor(\MusicLibraryItem.normalizedArtistKey),
                SortDescriptor(\MusicLibraryItem.normalizedTitleKey),
                SortDescriptor(\MusicLibraryItem.id)
            ]
        )
    }

    private var rebuildSignature: Int {
        var hasher = Hasher()
        hasher.combine(currentAccount?.address ?? "")
        hasher.combine(currentChain.rawValue)

        for item in libraryItems.sorted(by: { $0.id < $1.id }) {
            hasher.combine(item.id)
            hasher.combine(item.playbackURLString ?? "")
            hasher.combine(item.indexedAt.timeIntervalSince1970)
        }

        return hasher.finalize()
    }

    private var collectionSummaries: [MusicCollectionSummary] {
        MusicCollectionSummary.summaries(from: libraryItems)
    }

    var body: some View {
        NavigationStack {
            Group {
                if libraryItems.isEmpty {
                    if let failure = nftService.providerFailurePresentation(isShowingCachedContent: false) {
                        ShellProviderFailureStateView(
                            failure: failure,
                            retry: refresh
                        )
                        .padding()
                    } else {
                        ShellEmptyLibraryStateView(kind: .music)
                            .padding()
                    }
                } else {
                    ScrollView {
                        VStack(spacing: 20) {
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
                            }

                            if featureRecentlyPlayedLibrary {
                                RecentlyPlayedSection(audioEngine: audioEngine)
                                    .padding(.bottom, 8)
                            }

                            if !collectionSummaries.isEmpty {
                                VStack(alignment: .leading, spacing: 12) {
                                    Text("Collections")
                                        .font(.headline)

                                    ScrollView(.horizontal, showsIndicators: false) {
                                        HStack(spacing: 12) {
                                            ForEach(collectionSummaries, id: \.key) { summary in
                                                Button {
                                                    onOpenCollection(summary)
                                                } label: {
                                                    MusicCollectionCard(summary: summary)
                                                }
                                                .buttonStyle(.plain)
                                                .accessibilityIdentifier("music.collection.\(summary.key)")
                                            }
                                        }
                                        .padding(.horizontal, 2)
                                    }
                                }
                            }

                            VStack(alignment: .leading, spacing: 12) {
                                Text("Tracks")
                                    .font(.headline)

                                LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 3), spacing: 8) {
                                    ForEach(libraryItems) { item in
                                        Button {
                                            Task {
                                                guard let nft = musicNFTByID[item.sourceNFTID] else {
                                                    errorMessage = "The source NFT for this library item is no longer available."
                                                    showingError = true
                                                    return
                                                }

                                                do {
                                                    try await audioEngine.loadAndPlay(nft: nft)
                                                    onOpenNFT(nft)
                                                } catch {
                                                    let message = "Failed to load \(item.title): \(error.localizedDescription)"
                                                    errorMessage = message
                                                    showingError = true
                                                }
                                            }
                                        } label: {
                                            MusicLibraryCard(item: item)
                                                .padding(.horizontal)
                                        }
                                        .buttonStyle(.plain)
                                        .accessibilityIdentifier("music.libraryItem.\(item.id)")
                                    }
                                }
                            }
                        }
                    }
                    .padding()
                }
            }
            .navigationTitle("Music NFTs")
            .accessibilityIdentifier("music.library.root")
            .alert("Audio Engine Error", isPresented: $showingError) {
                Button("OK") { }
            } message: {
                Text(errorMessage ?? "Unknown error")
            }
        }
        .task(id: rebuildSignature) {
            await reconcileLibraryIndexIfNeeded()
        }
        .task(id: nftResolutionKey) {
            await refreshResolvedNFTs()
        }
    }

    private func refresh() {
        Task {
            await refreshAction()
            await reconcileLibraryIndexIfNeeded(force: true)
        }
    }

    @MainActor
    private func reconcileLibraryIndexIfNeeded(force: Bool = false) async {
        guard force || lastRebuildSignature != rebuildSignature else {
            return
        }

        do {
            let shouldRebuild: Bool
            if force {
                shouldRebuild = true
            } else {
                shouldRebuild = try await musicLibraryIndexer.needsRebuild(
                    accountAddress: currentAccount?.address,
                    chain: currentChain
                )
            }

            if shouldRebuild {
                _ = try await musicLibraryIndexer.rebuildIndex(
                    accountAddress: currentAccount?.address,
                    chain: currentChain,
                    correlationID: nil,
                    receiptEventLogger: musicLibraryReceiptLogger
                )
            }

            lastRebuildSignature = rebuildSignature
        } catch {
            errorMessage = "Failed to reconcile the music library: \(error.localizedDescription)"
            showingError = true
        }
    }
}

private extension NFTMusicPlayerLibraryView {
    struct NFTResolutionKey: Equatable {
        let accountAddress: String?
        let chain: Chain
        let sourceNFTIDs: [String]
    }

    var nftResolutionKey: NFTResolutionKey {
        NFTResolutionKey(
            accountAddress: currentAccount?.address,
            chain: currentChain,
            sourceNFTIDs: libraryItems.map(\.sourceNFTID).sorted()
        )
    }

    func refreshResolvedNFTs() async {
        let normalizedAccountAddress = NFT.normalizedScopeComponent(currentAccount?.address) ?? ""
        let chainRawValue = currentChain.rawValue

        let descriptor = FetchDescriptor<NFT>(
            predicate: #Predicate<NFT> { nft in
                nft.accountAddressRawValue == normalizedAccountAddress &&
                nft.networkRawValue == chainRawValue &&
                nft.audioUrl != nil &&
                nft.audioUrl != ""
            },
            sortBy: [SortDescriptor(\NFT.id)]
        )

        do {
            let nfts = try modelContext.fetch(descriptor)
            let nextMusicNFTByID = Dictionary(uniqueKeysWithValues: nfts.map { ($0.id, $0) })
            if musicNFTByID.keys.sorted() != nextMusicNFTByID.keys.sorted() {
                musicNFTByID = nextMusicNFTByID
                return
            }

            musicNFTByID = nextMusicNFTByID
        } catch {
            musicNFTByID = [:]
        }
    }
}
