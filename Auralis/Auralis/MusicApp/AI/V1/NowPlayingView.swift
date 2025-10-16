//
//  NowPlayingView.swift
//  Auralis
//
//  Created by Daniel Bell on 9/16/25.
//

import SwiftUI

// MARK: - Now Playing (expanded) view

struct NowPlayingView: View {
    @ObservedObject var audioEngine: AudioEngine
    @Environment(\.dismiss) var dismiss

    @State private var seekValue: Double = 0
    @State private var isDraggingSeek: Bool = false

    // Neighbor previews
    private var nextPreviewNFT: NFT? { audioEngine.queue.dequeueNextPreview() }
    private var previousPreviewNFT: NFT? { audioEngine.queue.previous.tracks.last }
    private let previousRestartThreshold: TimeInterval = 3.0

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    // Drag indicator / sheet handle
                    Capsule()
                        .frame(width: 40, height: 6)
                        .foregroundStyle(.secondary)
                        .padding(.top, 8)

                    if let track = audioEngine.currentTrack {
                        VStack(spacing: 24) {
                            // Artwork + Title / Artist
                            VStack(spacing: 16) {
                                nftArtworkView

                                VStack(spacing: 8) {
                                    if let title = (track.title), !title.isEmpty {
                                        Text(title)
                                            .font(.title2)
                                            .fontWeight(.bold)
                                            .multilineTextAlignment(.center)
                                            .lineLimit(3)
                                    }

                                    if let artist = (track.artist), !artist.isEmpty {
                                        Text(artist)
                                            .font(.title3)
                                            .foregroundStyle(.secondary)
                                            .multilineTextAlignment(.center)
                                    }
                                }
                                .frame(maxWidth: .infinity)
                            }

                            // Progress + Controls
                            VStack(spacing: 20) {
                                // Slider + times
                                VStack(spacing: 8) {
                                    Slider(
                                        value: $seekValue,
                                        in: 0...max(1, track.duration),
                                        onEditingChanged: { dragging in
                                            isDraggingSeek = dragging
                                            if !dragging {
                                                try? audioEngine.seek(to: seekValue)
                                            }
                                        }
                                    )
                                    .onChange(of: audioEngine.currentTrack) { _, _ in
                                        // Reset seek to start when track changes
                                        seekValue = 0
                                    }
                                    .onChange(of: audioEngine.progress) { _, newValue in
                                        if !isDraggingSeek {
                                            seekValue = newValue
                                        }
                                    }
                                    .onAppear {
                                        seekValue = audioEngine.progress
                                    }

                                    HStack {
                                        Text(timeString(from: seekValue))
                                        Spacer()
                                        Text(timeString(from: track.duration))
                                    }
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                }

                                // Playback controls row
                                HStack(spacing: 28) {
                                    // Coarse skip backward
                                    Button {
                                        audioEngine.skipBackward()
                                    } label: {
                                        Image(systemName: "gobackward.10")
                                            .font(.title3)
                                    }

                                    // Previous track
                                    Button {
                                        Task {
                                            await audioEngine.playPrevious()
                                        }
                                    } label: {
                                        Image(systemName: "backward.fill")
                                            .font(.title2)
                                            .foregroundStyle(.primary)
                                    }

                                    // Main play/pause handling including loading state
                                    switch audioEngine.playbackState {
                                    case .loading:
                                        Button(action: audioEngine.pause) {
                                            Image(systemName: "pause.fill")
                                                .font(.system(size: 56))
                                        }
                                        .disabled(true)
                                        .overlay {
                                            ProgressView()
                                                .progressViewStyle(CircularProgressViewStyle())
                                                .scaleEffect(1.2)
                                        }

                                    case .playing:
                                        Button(action: audioEngine.pause) {
                                            Image(systemName: "pause.fill")
                                                .font(.system(size: 56))
                                        }

                                    case .paused:
                                        Button {
                                            try? audioEngine.resume()
                                        } label: {
                                            Image(systemName: "play.fill")
                                                .font(.system(size: 56))
                                        }

                                    case .stopped:
                                        Button {
                                            try? audioEngine.play()
                                        } label: {
                                            Image(systemName: "play.fill")
                                                .font(.system(size: 56))
                                        }
                                    case .error:
                                        EmptyView()
                                    }

                                    // Next track
                                    Button {
                                        Task {
                                            await audioEngine.playNext()
                                        }
                                    } label: {
                                        Image(systemName: "forward.fill")
                                            .font(.title2)
                                            .foregroundStyle(.primary)
                                    }

                                    // Coarse skip forward
                                    Button {
                                        audioEngine.skipForward()
                                    } label: {
                                        Image(systemName: "goforward.10")
                                            .font(.title3)
                                    }
                                }
                            }
                            
                            // Neighbor previews (Previous / Next)
                            VStack(spacing: 8) {
                                if let prev = previousPreviewNFT {
                                    previewRow(title: prev.name ?? "Unknown Track",
                                               artist: prev.artistName,
                                               imageURLString: prev.image?.thumbnailUrl ?? prev.image?.originalUrl,
                                               label: "Previous",
                                               accessibilityPrefix: "Previous",
                                               action: {
                                                   if audioEngine.progress > previousRestartThreshold {
                                                       try? audioEngine.seek(to: 0)
                                                   } else {
                                                       Task { await audioEngine.playPrevious() }
                                                   }
                                               })
                                }

                                if let next = nextPreviewNFT {
                                    previewRow(title: next.name ?? "Unknown Track",
                                               artist: next.artistName,
                                               imageURLString: next.image?.thumbnailUrl ?? next.image?.originalUrl,
                                               label: "Next",
                                               accessibilityPrefix: "Next",
                                               action: {
                                                   Task { await audioEngine.playNext() }
                                               })
                                }
                            }

                            // Recently Played Section
                            RecentlyPlayedSection(audioEngine: audioEngine)

                            // Details card
                            VStack(alignment: .leading, spacing: 12) {
                                Text("Details")
                                    .font(.headline)
                                    .foregroundStyle(.primary)

//                                VStack(spacing: 8) {
//                                    if let tokenId = track.tokenId, !tokenId.isEmpty {
//                                        DetailRow(title: "Token ID", value: tokenId)
//                                    }
//                                    if let contractAddress = track.contractAddress ?? track.contract?.address, !contractAddress.isEmpty {
//                                        DetailRow(title: "Contract", value: contractAddress)
//                                    }
//                                    if let networkName = track.networkName ?? track.network?.displayName, !networkName.isEmpty {
//                                        DetailRow(title: "Network", value: networkName)
//                                    }
//                                    if let contentType = track.contentType, !contentType.isEmpty {
//                                        DetailRow(title: "Content Type", value: contentType)
//                                    }
//                                    if let updated = track.timeLastUpdated, !updated.isEmpty {
//                                        DetailRow(title: "Updated", value: updated)
//                                    }
//                                }
                            }
                            .padding()
                            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))

                            // Description
//                            if let description = track.nftDescription ?? track.description, !description.isEmpty {
//                                VStack(alignment: .leading, spacing: 8) {
//                                    Text("Description")
//                                        .font(.headline)
//                                        .foregroundStyle(.primary)
//                                    Text(description)
//                                        .font(.body)
//                                        .foregroundStyle(.secondary)
//                                        .fixedSize(horizontal: false, vertical: true)
//                                }
//                                .frame(maxWidth: .infinity, alignment: .leading)
//                            }

                            // Bottom spacer for scrollable content
                            Color.clear.frame(height: 20)
                        }
                        .padding(.horizontal)
                    } else {
                        // No track loaded view
                        VStack(spacing: 16) {
                            Image(systemName: "music.note")
                                .font(.system(size: 64))
                                .foregroundStyle(.secondary)
                            Text("No track loaded")
                                .font(.title3)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.top, 100)
                        Spacer()
                    }
                }
            }
            .navigationTitle("Now Playing")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
        .background(.ultraThinMaterial)
        .ignoresSafeArea(edges: .bottom)
    }

    // MARK: - Artwork View
    @ViewBuilder
    private var nftArtworkView: some View {
        // prefer imageUrl / fallback to nested image.originalUrl
        if let imageUrlString = audioEngine.currentTrack?.imageUrl,
           !imageUrlString.isEmpty,
           let imageUrl = URL(string: imageUrlString) {
            CachedAsyncImage(url: imageUrl)
            .frame(maxWidth: 280, maxHeight: 280)
            .clipShape(RoundedRectangle(cornerRadius: 20))
            .shadow(color: .black.opacity(0.1), radius: 8, x: 0, y: 4)
        } else {
            RoundedRectangle(cornerRadius: 20)
                .fill(Color.gray.opacity(0.25))
                .aspectRatio(1, contentMode: .fit)
                .overlay {
                    Image(systemName: "music.note")
                        .font(.system(size: 48))
                        .foregroundStyle(.gray)
                }
                .frame(maxWidth: 280, maxHeight: 280)
                .shadow(color: .black.opacity(0.1), radius: 8, x: 0, y: 4)
        }
    }

    // MARK: - Helpers
    private func timeString(from seconds: TimeInterval) -> String {
        guard seconds.isFinite else { return "0:00" }
        let s = Int(seconds)
        let mins = s / 60
        let secs = s % 60
        return String(format: "%d:%02d", mins, secs)
    }
    
    // MARK: - Compact Preview Row
    @ViewBuilder
    private func previewRow(title: String,
                            artist: String?,
                            imageURLString: String?,
                            label: String,
                            accessibilityPrefix: String,
                            action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                // Artwork 44–48pt
                if let urlStr = imageURLString, !urlStr.isEmpty, let url = URL(string: urlStr) {
                    CachedAsyncImage(url: url)
                        .frame(width: 48, height: 48)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                } else {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.gray.opacity(0.25))
                        .frame(width: 48, height: 48)
                        .overlay {
                            Image(systemName: "music.note")
                                .foregroundStyle(.gray)
                        }
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.body.weight(.semibold))
                        .lineLimit(1)
                        .foregroundStyle(.primary)
                    if let artist, !artist.isEmpty {
                        Text(artist)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                Spacer()
                Text(label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .contentShape(Rectangle())
            .padding(.vertical, 6)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(accessibilityPrefix): \(title.isEmpty ? "Unknown Track" : title)\(artist.map { ", by \($0)" } ?? "")")
        .opacity(audioEngine.playbackState == .loading ? 0.85 : 1.0)
    }
}

// MARK: - Recently Played Section (session-scoped via QueueManager.previous)
struct RecentlyPlayedSection: View {
    @ObservedObject var audioEngine: AudioEngine
    private let initialLimit: Int = 20
    @State private var isClearing = false

    private var items: [NFT] {
        audioEngine.queue.getRecentlyPlayed(limit: initialLimit)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(NSLocalizedString("Recently Played", comment: "Recently Played section header"))
                    .font(.headline)
                Spacer()
                if !items.isEmpty {
                    Button(NSLocalizedString("Clear All", comment: "Clear all recently played")) { isClearing = true }
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .accessibilityLabel("Clear all recently played")
                }
            }

            if items.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.system(size: 36))
                        .foregroundStyle(.secondary)
                    Text(NSLocalizedString("Nothing here yet—play something and it’ll show up.", comment: "Empty state for Recently Played"))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(12)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(items, id: \.id) { nft in
                            RecentlyPlayedMiniCard(nft: nft,
                                                   lastPlayed: audioEngine.queue.lastPlayedDate(for: nft.id)) {
                                playTapped(nft: nft)
                            }
                            .frame(width: 160)
                            .contextMenu {
                                Button {
                                    playTapped(nft: nft)
                                } label: {
                                    Label(NSLocalizedString("Play", comment: "Play recently played item"), systemImage: "play.fill")
                                }

                                Button {
                                    startOverTapped(nft: nft)
                                } label: {
                                    Label(NSLocalizedString("Start Over", comment: "Start recently played item from beginning"), systemImage: "arrow.counterclockwise")
                                }

                                Button(role: .destructive) {
                                    audioEngine.queue.removeFromPrevious(id: nft.id)
                                } label: {
                                    Label(NSLocalizedString("Remove from Recently Played", comment: "Remove item from recently played"), systemImage: "trash")
                                }
                            }
                        }
                    }
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text(String(format: NSLocalizedString("Recently Played, %d items", comment: "VoiceOver label for Recently Played section with count"), items.count)))
        .confirmationDialog(NSLocalizedString("Clear all recently played items?", comment: "Confirm clear recently played"),
                            isPresented: $isClearing,
                            titleVisibility: .visible) {
            Button(NSLocalizedString("Clear All", comment: "Confirm clear all"), role: .destructive) {
                audioEngine.queue.clearPreviousHistory()
                impact()
            }
            Button(NSLocalizedString("Cancel", comment: "Cancel"), role: .cancel) { }
        }
    }

    private func startOverTapped(nft: NFT) {
        impact()
        Task {
            if let currentId = audioEngine.queue.current?.id, currentId == nft.id {
                // If it's the current track, seek to 0 and play
                try? audioEngine.seek(to: 0)
                try? audioEngine.play()
            } else {
                // Load and play from the beginning
                await audioEngine.loadAndPlay(nft: nft)
            }
        }
    }

    private func playTapped(nft: NFT) {
        impact()
        Task {
            if let currentId = audioEngine.queue.current?.id, currentId == nft.id {
                try? audioEngine.resume()
            } else {
                await audioEngine.loadAndPlay(nft: nft)
            }
        }
    }

    private func impact() {
        #if canImport(UIKit)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        #endif
    }
}

private struct RecentlyPlayedMiniCard: View {
    let nft: NFT
    let lastPlayed: Date?
    let onTap: () -> Void

    private func relativeDescription(for date: Date?) -> String {
        guard let date else { return NSLocalizedString("Recently played", comment: "Fallback relative time") }
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .full
        return f.localizedString(for: date, relativeTo: Date())
    }

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 8) {
                ZStack(alignment: .bottomTrailing) {
                    if let s = (nft.image?.thumbnailUrl ?? nft.image?.originalUrl), let url = URL(string: s) {
                        CachedAsyncImage(url: url)
                            .aspectRatio(1, contentMode: .fill)
                            .frame(height: 120)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    } else {
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color.gray.opacity(0.25))
                            .frame(height: 120)
                            .overlay {
                                Image(systemName: "music.note").foregroundStyle(.gray)
                            }
                    }
                    Image(systemName: "play.circle.fill")
                        .symbolRenderingMode(.hierarchical)
                        .font(.system(size: 22))
                        .foregroundStyle(.white.opacity(0.95))
                        .shadow(radius: 2)
                        .padding(8)
                        .accessibilityHidden(true)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(nft.name ?? NSLocalizedString("Unknown Track", comment: "Unknown track title"))
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(2)
                        .foregroundStyle(.primary)
                    if let artist = nft.artistName, !artist.isEmpty {
                        Text(artist)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    if let lastPlayed {
                        Text(lastPlayed, style: .relative)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    } else {
                        Text(NSLocalizedString("Recently played", comment: "Fallback relative time"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .frame(minWidth: 44, minHeight: 44)
        .contentShape(Rectangle())
        .accessibilityLabel({ () -> Text in
            let title = nft.name ?? NSLocalizedString("Unknown Track", comment: "Unknown track title")
            let artist = nft.artistName
            let played = relativeDescription(for: lastPlayed)
            if let artist, !artist.isEmpty {
                return Text("\(title), \(artist), \(played)")
            } else {
                return Text("\(title), \(played)")
            }
        }())
        .accessibilityHint(Text(NSLocalizedString("Double-tap to play", comment: "Hint to play recently played item")))
    }
}

private struct DetailRow: View {
    let title: String
    let value: String?

    var body: some View {
        if let value, !value.isEmpty {
            HStack {
                Text(title)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(value)
                    .fontWeight(.medium)
                    .multilineTextAlignment(.trailing)
            }
            .font(.subheadline)
        }
    }
}

