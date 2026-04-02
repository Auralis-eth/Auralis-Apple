//
//  App.swift
//  NFTMusicPlayer
//
//  Created by Senior Swift Developer on 08/30/2025.
//  iOS 26 NFT-first music player with Liquid Glass design
//

import SwiftUI
import MediaPlayer
import AVFoundation
import SwiftData

enum SidebarItem: String, CaseIterable, Identifiable, Hashable {
    case library, playlists, downloads, settings

    var id: Self { self }
    var title: String { rawValue.capitalized }
    var systemImage: String {
        switch self {
        case .library:   return "music.note.list"
        case .playlists: return "text.badge.plus"
        case .downloads: return "arrow.down.circle"
        case .settings:  return "gearshape"
        }
    }
}

struct DetailView: View {
    let item: String
    
    var body: some View {
        VStack(spacing: 20) {
            SystemImage(iconForItem(item))
                .font(.system(size: 60))
                .foregroundColor(.blue)
            
            Text(item)
                .font(.largeTitle)
                .fontWeight(.bold)
            
            Text("This is the detail view for \(item)")
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding()
            
            Spacer()
        }
        .padding()
        .navigationTitle(item)
        .navigationBarTitleDisplayMode(.inline)
    }
    
    private func iconForItem(_ item: String) -> String {
        switch item {
        case "Home": return "house.fill"
        case "Profile": return "person.circle.fill"
        case "Settings": return "gear"
        case "About": return "info.circle.fill"
        case "Help": return "questionmark.circle.fill"
        default: return "circle.fill"
        }
    }
}

struct NFTMusicPlayerApp: View {
    @ObservedObject var audioEngine: AudioEngine
    let currentAccount: EOAccount?
    let currentChain: Chain
    let nftService: NFTService
    let refreshAction: @MainActor () async -> Void
    let onOpenNFT: (NFT) -> Void
    let musicLibraryIndexer: any MusicLibraryIndexing
    let musicLibraryReceiptLogger: ReceiptEventLogger
    @State private var selection: SidebarItem? = .library
    let sidebarItems = SidebarItem.allCases

    var body: some View {
        NavigationSplitView {
            // Sidebar
            ZStack(alignment: .bottom) {
                GatewayBackgroundImage()
                Color.background.opacity(0.3)
                    .ignoresSafeArea()
                    .contentShape(Rectangle())
                

                List(sidebarItems, selection: $selection) { item in
                    Label(item.title, systemImage: item.systemImage)
                        .foregroundStyle(Color.textSecondary)
                        .listRowBackground(Color.clear)
                        .tag(item)
                }
                .accessibilityIdentifier("music.sidebar")
                .listStyle(.sidebar)
                .scrollContentBackground(.hidden)
                .background(.clear)
                .padding()
                .glassEffect(.regular.tint(.surface), in: .rect(cornerRadius: 30, style: .continuous))
                .safeAreaPadding(.all, 30)
            }
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("")
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .padding(.vertical)
        } detail: {
            VStack {
                Group {
                    switch selection {
                    case .library:
                        NFTMusicPlayerLibraryView(
                            audioEngine: audioEngine,
                            currentAccount: currentAccount,
                            currentChain: currentChain,
                            nftService: nftService,
                            refreshAction: refreshAction,
                            onOpenNFT: onOpenNFT,
                            musicLibraryIndexer: musicLibraryIndexer,
                            musicLibraryReceiptLogger: musicLibraryReceiptLogger
                        )
                    case .playlists:
                        PlaylistListView()
                    case .none:
                        Text("Select something in the sidebar")
                            .foregroundStyle(.secondary)
                            .padding()
                    case .downloads:
                        Text("\(selection?.title ?? "downloads")")
                            .font(.title)
                            .padding()
                    case .settings:
                        Text("\(selection?.title ?? "settings")")
                            .font(.title)
                            .padding()
                    }
                }
                .navigationTitle(selection?.title ?? "Detail")
            }
        }
    }
}





struct NFTMusicPlayerLibraryView: View {
    @ObservedObject var audioEngine: AudioEngine
    let currentAccount: EOAccount?
    let currentChain: Chain
    let nftService: NFTService
    let refreshAction: @MainActor () async -> Void
    let onOpenNFT: (NFT) -> Void
    let musicLibraryIndexer: any MusicLibraryIndexing
    let musicLibraryReceiptLogger: ReceiptEventLogger
    @Query private var libraryItems: [MusicLibraryItem]
    @Query private var nfts: [NFT]

    @AppStorage("feature_recentlyPlayedLibrary") private var featureRecentlyPlayedLibrary: Bool = true

    @State private var errorMessage: String?
    @State private var showingError: Bool = false
    @State private var lastRebuildSignature: Int?

    init(
        audioEngine: AudioEngine,
        currentAccount: EOAccount?,
        currentChain: Chain,
        nftService: NFTService,
        refreshAction: @escaping @MainActor () async -> Void,
        onOpenNFT: @escaping (NFT) -> Void,
        musicLibraryIndexer: any MusicLibraryIndexing,
        musicLibraryReceiptLogger: ReceiptEventLogger
    ) {
        self.audioEngine = audioEngine
        self.currentAccount = currentAccount
        self.currentChain = currentChain
        self.nftService = nftService
        self.refreshAction = refreshAction
        self.onOpenNFT = onOpenNFT
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
        _nfts = Query(
            filter: #Predicate<NFT> {
                $0.accountAddressRawValue == normalizedAccountAddress &&
                $0.networkRawValue == chainRawValue
            }
        )
    }

    private var musicNFTByID: [String: NFT] {
        Dictionary(uniqueKeysWithValues: nfts.map { ($0.id, $0) })
    }

    private var rebuildSignature: Int {
        var hasher = Hasher()
        hasher.combine(currentAccount?.address ?? "")
        hasher.combine(currentChain.rawValue)

        for nft in nfts.sorted(by: { $0.id < $1.id }) {
            hasher.combine(nft.id)
            hasher.combine(nft.audioUrl ?? "")
            hasher.combine(nft.name ?? "")
            hasher.combine(nft.artistName ?? "")
            hasher.combine(nft.collectionName ?? "")
            hasher.combine(nft.contentType ?? "")
        }

        for item in libraryItems.sorted(by: { $0.id < $1.id }) {
            hasher.combine(item.id)
            hasher.combine(item.playbackURLString ?? "")
            hasher.combine(item.indexedAt.timeIntervalSince1970)
        }

        return hasher.finalize()
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
                            // Format Support Testing
                            VStack(alignment: .leading) {
                                Text("Format Support Test")
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
                shouldRebuild = try musicLibraryIndexer.needsRebuild(
                    accountAddress: currentAccount?.address,
                    chain: currentChain
                )
            }

            if shouldRebuild {
                _ = try musicLibraryIndexer.rebuildIndex(
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

























private struct MusicLibraryCard: View {
    let item: MusicLibraryItem

    var body: some View {
        HStack(spacing: 16) {
            AsyncImage(url: item.artworkURL) { image in
                image.resizable().scaledToFill()
            } placeholder: {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.gray.opacity(0.25))
                    .overlay {
                        SystemImage("music.note").foregroundStyle(.gray)
                    }
            }
            .frame(width: 80, height: 80)
            .clipShape(RoundedRectangle(cornerRadius: 12))

            VStack(alignment: .leading, spacing: 6) {
                Text(item.title)
                    .font(.headline)
                    .lineLimit(2)

                if let artist = item.artistName, !artist.isEmpty {
                    Text(artist)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                HStack(spacing: 6) {
                    SystemImage(item.availability == .ready ? "speaker.wave.2.fill" : "music.note")
                        .foregroundStyle(.blue)
                        .imageScale(.small)

                    if let ct = item.contentType, ct.hasPrefix("audio/") {
                        Text(ct.replacingOccurrences(of: "audio/", with: "").uppercased())
                            .font(.caption2)
                            .foregroundStyle(.blue)
                    }

                    if item.availability == .unavailable {
                        Text("UNAVAILABLE")
                            .font(.caption2)
                            .foregroundStyle(.orange)
                    }
                }
            }

            Spacer()

            if let network = Chain(rawValue: item.networkRawValue) {
                VStack(spacing: 4) {
                    SystemImage("link")
                        .foregroundStyle(.secondary)
                        .imageScale(.small)
                    Text(network.displayName)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(12)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("music.card.\(item.id)")
    }
}

// Display name helper for your Chain enum
extension Chain {
    var displayName: String {
        switch self {
        case .ethMainnet:       return "Ethereum"
        case .polygonMainnet:   return "Polygon"
        case .arbMainnet:       return "Arbitrum"
        case .optMainnet:   return "Optimism"
        case .baseMainnet:       return "Base"
        default:          return rawValue.capitalized
        }
    }
}
