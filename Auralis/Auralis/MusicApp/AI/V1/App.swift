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












import SwiftUI

struct DetailView: View {
    let item: String
    
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: iconForItem(item))
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
    @State private var selection: SidebarItem? = nil
    let sidebarItems = SidebarItem.allCases

    var body: some View {
        NavigationSplitView {
            // Sidebar
            ZStack(alignment: .bottom) {
                GatewayBackgroundImage()
                Color.background.opacity(0.3)
                    .ignoresSafeArea()
                    .contentShape(Rectangle())
                
                VStack {
                    List(sidebarItems, selection: $selection) { item in
                        Label(item.title, systemImage: item.systemImage)
                            .listRowBackground(Color.clear)
                            .tag(item)
                    }
                    .listStyle(.sidebar)
                    .scrollContentBackground(.hidden)
                    .background(.clear)
                    .padding()
                    .glassEffect(.regular.tint(.surface), in: .rect(cornerRadius: 30, style: .continuous))
                    Spacer()
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(sidebarItems) { item in
                            Label(item.title, systemImage: item.systemImage)
                                .padding()
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    selection = item
                                }
                        }
                    }
                    .background(.clear)
                    .padding()
                    .glassEffect(.regular.tint(.surface), in: .rect(cornerRadius: 30, style: .continuous))
                    Spacer()
                }
            }
            .navigationTitle("Browse")
            .padding(.top)
        } detail: {
            VStack {
                Group {
                    switch selection {
                    case .library:
                        NFTMusicPlayerLibraryView(audioEngine: audioEngine)
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
            .modelContainer(for: Playlist.self)
        }
    }
}





struct NFTMusicPlayerLibraryView: View {
    @ObservedObject var audioEngine: AudioEngine
    @Query private var nfts: [NFT]
    private var musicNFTs: [NFT] {
        nfts.filter { $0.isMusic() }
    }

    @State private var errorMessage: String?
    @State private var showingError: Bool = false
    
    var body: some View {
        NavigationStack {
            Group {
                if musicNFTs.isEmpty {
                    ContentUnavailableView {
                        Label("No Music NFTs", systemImage: "music.note")
                    } description: {
                        Text("Your music NFT collection will appear here.")
                    }
                } else {
                    ScrollView {
                        VStack(spacing: 20) {
                            // Format Support Testing
                            VStack(alignment: .leading) {
                                Text("Format Support Test")
                                    .font(.headline)
                                
                                LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 3), spacing: 8) {
                                    ForEach(musicNFTs) { nft in
                                        MusicNFTCard(nft: nft)
                                            .padding(.horizontal)
                                            .onTapGesture {
                                                Task {
                                                    do {
                                                        try await audioEngine.loadAndPlay(nft: nft)
                                                    } catch {
                                                        let message = "Failed to load \(nft.name): \(error.localizedDescription)"
                                                        errorMessage = message
                                                        showingError = true
                                                    }
                                                }
                                            }
                                    }
                                }
                            }
                        }
                    }
                    .padding()
                }
            }
            .navigationTitle("Music NFTs")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    AVRoutePicker()
                        .frame(width: 32, height: 32)
                        .accessibilityLabel("AirPlay and Bluetooth devices")
                }
            }
            .alert("Audio Engine Error", isPresented: $showingError) {
                Button("OK") { }
            } message: {
                Text(errorMessage ?? "Unknown error")
            }
        }
    }
}

























private struct MusicNFTCard: View {
    let nft: NFT

    var body: some View {
        HStack(spacing: 16) {
            AsyncImage(url: URL(string: nft.image?.thumbnailUrl ?? nft.image?.originalUrl ?? "")) { image in
                image.resizable().scaledToFill()
            } placeholder: {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.gray.opacity(0.25))
                    .overlay {
                        Image(systemName: "music.note").foregroundStyle(.gray)
                    }
            }
            .frame(width: 80, height: 80)
            .clipShape(RoundedRectangle(cornerRadius: 12))

            VStack(alignment: .leading, spacing: 6) {
                Text(nft.name ?? "Unknown Track")
                    .font(.headline)
                    .lineLimit(2)

                if let artist = nft.artistName, !artist.isEmpty {
                    Text(artist)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                HStack(spacing: 6) {
                    Image(systemName: (nft.isMusic()) ? "speaker.wave.2.fill" : "music.note")
                        .foregroundStyle(.blue)
                        .imageScale(.small)

                    if let ct = nft.contentType, ct.hasPrefix("audio/") {
                        Text(ct.replacingOccurrences(of: "audio/", with: "").uppercased())
                            .font(.caption2)
                            .foregroundStyle(.blue)
                    }
                }
            }

            Spacer()

            if let network = nft.network {
                VStack(spacing: 4) {
                    Image(systemName: "link")
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

