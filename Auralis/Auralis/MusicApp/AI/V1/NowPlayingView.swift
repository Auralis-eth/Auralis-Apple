//
//  NowPlayingView.swift
//  Auralis
//
//  Created by Daniel Bell on 9/16/25.
//



import SwiftUI

// MARK: - Now Playing (expanded) view
import SwiftUI

struct NowPlayingView: View {
    @ObservedObject var audioEngine: AudioEngine
    @Environment(\.dismiss) var dismiss

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
                                        value: Binding(
                                            get: { audioEngine.progress },
                                            set: { try? audioEngine.seek(to: $0) }
                                        ),
                                        in: 0...max(1, track.duration)
                                    )

                                    HStack {
                                        Text(timeString(from: audioEngine.progress))
                                        Spacer()
                                        Text(timeString(from: track.duration))
                                    }
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                }

                                // Playback controls row
                                HStack(spacing: 40) {
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

                                    Button {
                                        Task {
                                            await audioEngine.playNext()
                                        }
                                    } label: {
                                        Image(systemName: "forward.fill")
                                            .font(.title2)
                                            .foregroundStyle(.primary)
                                    }
                                }
                            }

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
