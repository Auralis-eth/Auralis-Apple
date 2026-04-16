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

struct NFTMusicPlayerApp: View {
    @ObservedObject var audioEngine: AudioEngine
    let currentAccount: EOAccount?
    let currentChain: Chain
    let nftService: NFTService
    let refreshAction: @MainActor () async -> Void
    let onOpenNFT: (NFT) -> Void
    let onOpenCollection: (MusicCollectionSummary) -> Void
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
                            onOpenCollection: onOpenCollection,
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
