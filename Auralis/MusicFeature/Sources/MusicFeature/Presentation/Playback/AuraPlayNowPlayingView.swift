import SwiftUI

struct AuraPlayNowPlayingView<Player: AuraPlayPlaybackPresenting>: View {
    let player: Player
    @Environment(\.dismiss) private var dismiss

    @State private var seekValue: Double = 0
    @State private var isDraggingSeek = false

    private var nextPreviewTrack: AuraPlayTrack? { player.auraPlayNextPreviewTrack }
    private var previousPreviewTrack: AuraPlayTrack? { player.auraPlayPreviousPreviewTrack }
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

                    if let track = player.auraPlayCurrentTrack {
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
                                                try? player.auraPlaySeek(to: seekValue)
                                            }
                                        }
                                    )
                                    .accessibilityLabel("Playback position")
                                    .onChange(of: player.auraPlayCurrentTrack) { _, _ in
                                        seekValue = 0
                                    }
                                    .onChange(of: player.auraPlayProgress) { _, newValue in
                                        if !isDraggingSeek {
                                            seekValue = newValue
                                        }
                                    }
                                    .onAppear {
                                        seekValue = player.auraPlayProgress
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
                                        player.auraPlaySkipBackward()
                                    } label: {
                                        Image(systemName: "gobackward.10")
                                            .font(.title3)
                                    }
                                    .frame(minWidth: 44, minHeight: 44)
                                    .accessibilityLabel("Skip backward 10 seconds")
                                    .accessibilityHint("Moves playback backward by ten seconds")

                                    Button {
                                        Task { await player.auraPlayPrevious() }
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
                                        Task { await player.auraPlayNext() }
                                    } label: {
                                        Image(systemName: "forward.fill")
                                            .font(.title2)
                                            .foregroundStyle(.primary)
                                    }
                                    .frame(minWidth: 44, minHeight: 44)
                                    .accessibilityLabel("Next track")
                                    .accessibilityHint("Plays the next track")

                                    Button {
                                        player.auraPlaySkipForward()
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
                                if let prev = previousPreviewTrack {
                                    previewRow(
                                        title: prev.title ?? "Unknown Track",
                                        artist: prev.artist,
                                        imageURLString: prev.imageURLString,
                                        label: "Previous",
                                        accessibilityPrefix: "Previous",
                                        action: {
                                            if player.auraPlayProgress > previousRestartThreshold {
                                                try? player.auraPlaySeek(to: 0)
                                            } else {
                                                Task { await player.auraPlayPrevious() }
                                            }
                                        }
                                    )
                                }

                                if let next = nextPreviewTrack {
                                    previewRow(
                                        title: next.title ?? "Unknown Track",
                                        artist: next.artist,
                                        imageURLString: next.imageURLString,
                                        label: "Next",
                                        accessibilityPrefix: "Next",
                                        action: {
                                            Task { await player.auraPlayNext() }
                                        }
                                    )
                                }
                            }

                            AuraPlayRecentlyPlayedSection(player: player)

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
        switch player.auraPlayPlaybackState {
        case .loading:
            Button(action: player.auraPlayPause) {
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
            Button(action: player.auraPlayPause) {
                Image(systemName: "pause.fill")
                    .font(.system(size: 56))
            }
            .frame(minWidth: 44, minHeight: 44)
            .accessibilityLabel("Pause")
            .accessibilityHint("Pauses the current track")

        case .paused:
            Button {
                try? player.auraPlayResume()
            } label: {
                Image(systemName: "play.fill")
                    .font(.system(size: 56))
            }
            .frame(minWidth: 44, minHeight: 44)
            .accessibilityLabel("Resume")
            .accessibilityHint("Resumes the current track")

        case .stopped:
            Button {
                try? player.auraPlayPlay()
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
        if let imageURLString = player.auraPlayCurrentTrack?.imageURLString,
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
        .opacity(player.auraPlayPlaybackState == .loading ? 0.85 : 1.0)
    }
}
