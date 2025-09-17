
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

@Model
class Playlist {
    var id: UUID
    var name: String
    var tracks: [NFT]
    var dateCreated: Date
    
    init(name: String) {
        self.id = UUID()
        self.name = name
        self.tracks = []
        self.dateCreated = Date()
    }
}

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
    @Binding var currentAccount: EOAccount?
    @ObservedObject var audioEngine: AudioEngine
    @State private var selection: SidebarItem? = nil
    let sidebarItems = SidebarItem.allCases

    var body: some View {
        NavigationSplitView {
            // Sidebar
            List(sidebarItems, selection: $selection) { item in
                Label(item.title, systemImage: item.systemImage)
                .tag(item)
            }
            .navigationTitle("Browse")
        } detail: {
            VStack {
                Group {
                    switch selection {
                    case .library:
                        NFTMusicPlayerLibraryView(currentAccount: $currentAccount, audioEngine: audioEngine)
                    case .playlists:
                        Text("\(selection?.title ?? "Playlists")")
                            .font(.title)
                            .padding()
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

//create a music instruments view
//make the playback be based on playlists
//* - Implement playNext() method with playlist integration
//* - Implement playPrevious() method with playlist integration
//### Recently Played Tracking
//- Add recently played tracking system
//- Show recently played items in UI
//- Build recently played tracking implementation
//- Build recently played tracking feature



//@Query private var playlists: [Playlist]
//* ### Playlist
//* - Connect to SwiftData playlist models
//    * C
//    * R
//    * U
//    * D
//- Implement Swift Data for playlist storage
//- Implement playlist management system with local storage
//- Enable local playlist creation and management
//- Create playlist management system with local storage
//- Implement local playlist creation functionality
//- Implement local playlist management functionality
//New playlist
//    title
//    description
//    image
//        from image playground



//* - Add "Add to Playlist" button to NFT card
//* When clicked, present a sheet with available playlists and allow the user to add the NFT to one of them.
//### Playlist Management


//In playlist
//    download
//    show the playlist image
//    shuffle play
//    add to
//    delete the playlist



struct NFTMusicPlayerLibraryView: View {
    @Binding var currentAccount: EOAccount?
    
    @ObservedObject var audioEngine: AudioEngine
    @Environment(\.modelContext) private var modelContext
    @Query private var playlists: [Playlist]
    @Query private var nfts: [NFT]
    
    private var musicNFTs: [NFT] {
        nfts.filter {
            $0.isMusic()
        }
    }

    @State private var selectedNFT: NFT?
    @State private var seekValue: Double = 0
    @State private var isDragging: Bool = false
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
                            // Account Header
                            Text(currentAccount?.address ?? "NO ACCOUNT")
                                .font(.headline)
                                .padding()
                            
                            // Playback State Display
                            VStack {
                                Text("Playback State")
                                    .font(.headline)
                                Text(playbackStateText)
                                    .font(.subheadline)
                                    .foregroundColor(stateColor)
                                    .padding(.horizontal)
                                    .padding(.vertical, 4)
                                    .background(stateColor.opacity(0.2))
                                    .cornerRadius(8)
                            }
                            
                            // Time Display
                            HStack {
                                Text(formatTime(audioEngine.currentTime))
                                Spacer()
                                Text("Progress: \(Int(audioEngine.progress * 100))%")
                                Spacer()
                                Text(formatTime(audioEngine.duration))
                            }
                            .font(.caption)
                            .foregroundColor(.secondary)
                            
                            // Seek Slider
                            VStack {
                                HStack {
                                    Text("Seek")
                                    Spacer()
                                    Text("Duration: \(formatTime(audioEngine.duration))")
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                }
                                
                                Slider(
                                    value: $seekValue,
                                    in: 0...max(1, audioEngine.duration),
                                    onEditingChanged: { dragging in
                                        isDragging = dragging
                                        if !dragging {
                                            seekToPosition()
                                        }
                                    }
                                )
                                .disabled(audioEngine.duration == 0)
                            }
                            .onReceive(Timer.publish(every: 0.1, on: .main, in: .common).autoconnect()) { _ in
                                if !isDragging {
                                    seekValue = audioEngine.currentTime
                                }
                            }
                            
                            // Main Playback Controls
                            HStack(spacing: 30) {
                                Button("Previous") {
                                    audioEngine.playPrevious()
                                }
                                .disabled(audioEngine.playbackState == .loading)
                                                                
                                Button("Next") {
                                    audioEngine.playNext()
                                }
                                .disabled(audioEngine.playbackState == .loading)
                            }
                            .buttonStyle(.bordered)
                            
                            Divider()
                            Divider()
                            
                            // Format Support Testing
                            VStack(alignment: .leading) {
                                Text("Format Support Test")
                                    .font(.headline)
                                
                                LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 3), spacing: 8) {
                                    ForEach(nfts) { nft in
                                        MusicNFTCard(nft: nft)
                                            .onTapGesture { selectedNFT = nft }
                                            .padding(.horizontal)
                                            .onTapGesture {
                                                Task {
                                                    do {
                                                        guard let musicURL = nft.musicURL else {
                                                            return
                                                        }
//                                                        try await audioEngine.loadAndPlay(url: musicURL, title: nft.name, artist: nft.artist)
                                                    } catch {
                                                        showError("Failed to load \(nft.name): \(error.localizedDescription)")
                                                    }
                                                }
                                            }
                                    }
                                }
                            }
                            
                            Divider()
                            
                            // Playlist Section
                            VStack(alignment: .leading) {
                                Text("Playlists (\(playlists.count))")
                                    .font(.headline)
                                
                                if playlists.isEmpty {
                                    Text("No playlists found")
                                        .foregroundColor(.secondary)
                                        .italic()
                                } else {
                                    List(playlists) { playlist in
                                        Text(playlist.name)
                                    }
                                    .frame(maxHeight: 150)
                                }
                            }
                        }
                    }
                    .padding()
                }
            }
            .navigationTitle("Music NFTs")
            .navigationBarTitleDisplayMode(.large)
            .sheet(item: $selectedNFT) { nft in
                MusicNFTDetailView(nft: nft)
            }
            .alert("Audio Engine Error", isPresented: $showingError) {
                Button("OK") { }
            } message: {
                Text(errorMessage ?? "Unknown error")
            }
        }
    }
    
    // MARK: - Computed Properties
    
    private var playbackStateText: String {
        switch audioEngine.playbackState {
        case .stopped: return "STOPPED"
        case .playing: return "PLAYING"
        case .paused: return "PAUSED"
        case .loading: return "LOADING..."
        }
    }
    
    private var stateColor: Color {
        switch audioEngine.playbackState {
        case .stopped: return .secondary
        case .playing: return .green
        case .paused: return .orange
        case .loading: return .blue
        }
    }
    
    // MARK: - Helper Methods
    
    private func formatTime(_ time: TimeInterval) -> String {
        let minutes = Int(time) / 60
        let seconds = Int(time) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
    
    private func handlePlayButtonTap() async {
        do {
            switch audioEngine.playbackState {
            case .stopped, .loading:
                // Try to load a default file if none is loaded
//                if audioEngine.duration == 0, let audioURL = Bundle.main.url(forResource: "sample", withExtension: "mp3") {
//                    try await audioEngine.loadAndPlay(url: audioURL)
//                } else {
//                    try audioEngine.play()
//                }
                print("play")
            case .playing:
                audioEngine.pause()
            case .paused:
                try audioEngine.resume()
            }
        } catch {
            showError(error.localizedDescription)
        }
    }
    
    private func seekToPosition() {
        do {
            try audioEngine.seek(to: seekValue)
        } catch {
            showError("Seek failed: \(error.localizedDescription)")
        }
    }
    
    private func showError(_ message: String) {
        errorMessage = message
        showingError = true
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
                    Image(systemName: (nft.audioUrl?.isEmpty == false) ? "speaker.wave.2.fill" : "music.note")
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

private struct MusicNFTDetailView: View {
    let nft: NFT
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Artwork
                    VStack(spacing: 12) {
                        AsyncImage(url: URL(string: nft.image?.originalUrl ?? "")) { image in
                            image.resizable().scaledToFit()
                        } placeholder: {
                            RoundedRectangle(cornerRadius: 20)
                                .fill(Color.gray.opacity(0.25))
                                .aspectRatio(1, contentMode: .fit)
                                .overlay {
                                    Image(systemName: "music.note")
                                        .font(.title)
                                        .foregroundStyle(.gray)
                                }
                        }
                        .frame(maxWidth: 260, maxHeight: 260)
                        .clipShape(RoundedRectangle(cornerRadius: 20))

                        VStack(spacing: 6) {
                            Text(nft.name ?? "Unknown Track")
                                .font(.title2).bold()
                                .multilineTextAlignment(.center)
                            if let artist = nft.artistName, !artist.isEmpty {
                                Text(artist)
                                    .font(.title3)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity)

                    // Audio controls (stub)
                    if let urlString = nft.audioUrl ?? nft.animationUrl,
                       !urlString.isEmpty,
                       URL(string: urlString) != nil {
                        VStack(spacing: 12) {
                            Text("Audio")
                                .font(.headline)
                            HStack {
                                Button {
                                    // TODO: Integrate actual audio playback
                                } label: {
                                    Label("Play", systemImage: "play.fill")
                                }
                                .buttonStyle(.borderedProminent)

                                ShareLink(item: URL(string: urlString)!) {
                                    Image(systemName: "square.and.arrow.up")
                                }
                                .buttonStyle(.bordered)
                            }
                        }
                        .padding()
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
                    }

                    // Details
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Details").font(.headline)

                        DetailRow(title: "Token ID", value: nft.tokenId)
                        DetailRow(title: "Contract", value: nft.contract.address)
                        DetailRow(title: "Network", value: nft.network?.displayName)
                        DetailRow(title: "Content Type", value: nft.contentType)
                        DetailRow(title: "Updated", value: nft.timeLastUpdated)
                    }
                    .padding()
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))

                    // Description
                    if let desc = nft.nftDescription, !desc.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Description").font(.headline)
                            Text(desc)
                        }
                    }
                }
                .padding()
            }
            .navigationTitle("Music NFT")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

private struct DetailRow: View {
    let title: String
    let value: String?

    var body: some View {
        if let value, !value.isEmpty {
            HStack {
                Text(title).foregroundStyle(.secondary)
                Spacer()
                Text(value).fontWeight(.medium)
            }
            .font(.subheadline)
        }
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
