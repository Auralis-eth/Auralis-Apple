import SwiftUI

struct AuraPlayNowPlayingView: View {
    @ObservedObject var audioEngine: AudioEngine
    @Environment(\.dismiss) private var dismiss

    @State private var seekValue: Double = 0
    @State private var isDraggingSeek = false

    private var nextPreviewNFT: NFT? { audioEngine.nextAudio.tracks.first }
    private var previousPreviewNFT: NFT? { audioEngine.previousAudio.tracks.last }
    private let previousRestartThreshold: TimeInterval = 3.0

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    Capsule()
                        .frame(width: 40, height: 6)
                        .foregroundStyle(.secondary)
                        .padding(.top, 8)
                        .accessibilityHidden(true)

                    if let track = audioEngine.currentTrack {
                        VStack(spacing: 24) {
                            VStack(spacing: 16) {
                                artworkView

                                VStack(spacing: 8) {
                                    if let title = track.title, !title.isEmpty {
                                        Text(title)
                                            .font(.title2)
                                            .fontWeight(.bold)
                                            .multilineTextAlignment(.center)
                                            .lineLimit(3)
                                    }

                                    if let artist = track.artist, !artist.isEmpty {
                                        Text(artist)
                                            .font(.title3)
                                            .foregroundStyle(.secondary)
                                            .multilineTextAlignment(.center)
                                    }
                                }
                                .frame(maxWidth: .infinity)
                            }

                            VStack(spacing: 20) {
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
                                    .accessibilityLabel("Playback position")
                                    .onChange(of: audioEngine.currentTrack) { _, _ in
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

                                HStack(spacing: 28) {
                                    Button {
                                        audioEngine.skipBackward()
                                    } label: {
                                        Image(systemName: "gobackward.10")
                                            .font(.title3)
                                    }
                                    .frame(minWidth: 44, minHeight: 44)
                                    .accessibilityLabel("Skip backward 10 seconds")
                                    .accessibilityHint("Moves playback backward by ten seconds")

                                    Button {
                                        Task { await audioEngine.playPrevious() }
                                    } label: {
                                        Image(systemName: "backward.fill")
                                            .font(.title2)
                                            .foregroundStyle(.primary)
                                    }
                                    .frame(minWidth: 44, minHeight: 44)
                                    .accessibilityLabel("Previous track")
                                    .accessibilityHint("Plays the previous track")

                                    mainPlaybackButton

                                    Button {
                                        Task { await audioEngine.playNext() }
                                    } label: {
                                        Image(systemName: "forward.fill")
                                            .font(.title2)
                                            .foregroundStyle(.primary)
                                    }
                                    .frame(minWidth: 44, minHeight: 44)
                                    .accessibilityLabel("Next track")
                                    .accessibilityHint("Plays the next track")

                                    Button {
                                        audioEngine.skipForward()
                                    } label: {
                                        Image(systemName: "goforward.10")
                                            .font(.title3)
                                    }
                                    .frame(minWidth: 44, minHeight: 44)
                                    .accessibilityLabel("Skip forward 10 seconds")
                                    .accessibilityHint("Moves playback forward by ten seconds")
                                }
                            }

                            VStack(spacing: 8) {
                                if let prev = previousPreviewNFT {
                                    previewRow(
                                        title: prev.name ?? "Unknown Track",
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
                                        }
                                    )
                                }

                                if let next = nextPreviewNFT {
                                    previewRow(
                                        title: next.name ?? "Unknown Track",
                                        artist: next.artistName,
                                        imageURLString: next.image?.thumbnailUrl ?? next.image?.originalUrl,
                                        label: "Next",
                                        accessibilityPrefix: "Next",
                                        action: {
                                            Task { await audioEngine.playNext() }
                                        }
                                    )
                                }
                            }

                            AuraPlayRecentlyPlayedSection(audioEngine: audioEngine)

                            Color.clear.frame(height: 20)
                        }
                        .padding(.horizontal)
                    } else {
                        VStack(spacing: 16) {
                            Image(systemName: "music.note")
                                .font(.system(size: 64))
                                .foregroundStyle(.secondary)
                            Text("No track loaded")
                                .font(.title3)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.top, 100)
                        .frame(maxWidth: .infinity)
                    }
                }
            }
            .navigationTitle("Now Playing")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
        .background(.ultraThinMaterial)
        .ignoresSafeArea(edges: .bottom)
    }

    @ViewBuilder
    private var mainPlaybackButton: some View {
        switch audioEngine.playbackState {
        case .loading:
            Button(action: audioEngine.pause) {
                Image(systemName: "pause.fill")
                    .font(.system(size: 56))
            }
            .disabled(true)
            .frame(minWidth: 44, minHeight: 44)
            .overlay {
                ProgressView()
                    .progressViewStyle(.circular)
                    .scaleEffect(1.2)
            }
            .accessibilityLabel("Loading playback")
            .accessibilityHint("Playback is loading")

        case .playing:
            Button(action: audioEngine.pause) {
                Image(systemName: "pause.fill")
                    .font(.system(size: 56))
            }
            .frame(minWidth: 44, minHeight: 44)
            .accessibilityLabel("Pause")
            .accessibilityHint("Pauses the current track")

        case .paused:
            Button {
                try? audioEngine.resume()
            } label: {
                Image(systemName: "play.fill")
                    .font(.system(size: 56))
            }
            .frame(minWidth: 44, minHeight: 44)
            .accessibilityLabel("Resume")
            .accessibilityHint("Resumes the current track")

        case .stopped:
            Button {
                try? audioEngine.play()
            } label: {
                Image(systemName: "play.fill")
                    .font(.system(size: 56))
            }
            .frame(minWidth: 44, minHeight: 44)
            .accessibilityLabel("Play")
            .accessibilityHint("Starts playback")

        case .error:
            Image(systemName: "exclamationmark.triangle")
                .font(.title)
                .foregroundStyle(.secondary)
                .frame(minWidth: 44, minHeight: 44)
                .accessibilityLabel("Playback unavailable")
        }
    }

    @ViewBuilder
    private var artworkView: some View {
        if let imageURLString = audioEngine.currentTrack?.imageUrl,
           !imageURLString.isEmpty,
           let imageURL = URL(string: imageURLString) {
            CachedAsyncImage(url: imageURL)
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

    private func timeString(from seconds: TimeInterval) -> String {
        guard seconds.isFinite else { return "0:00" }
        let totalSeconds = Int(seconds)
        let minutes = totalSeconds / 60
        let secondsComponent = totalSeconds % 60
        return String(format: "%d:%02d", minutes, secondsComponent)
    }

    @ViewBuilder
    private func previewRow(
        title: String,
        artist: String?,
        imageURLString: String?,
        label: String,
        accessibilityPrefix: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                if let urlString = imageURLString,
                   !urlString.isEmpty,
                   let url = URL(string: urlString) {
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
        .frame(minHeight: 44)
        .accessibilityLabel("\(accessibilityPrefix): \(title.isEmpty ? "Unknown Track" : title)\(artist.map { ", by \($0)" } ?? "")")
        .opacity(audioEngine.playbackState == .loading ? 0.85 : 1.0)
    }
}
