import AuraUI
import SwiftUI

struct AuraPlayNowPlayingView<Player: AuraPlayPlaybackPresenting>: View {
    let player: Player
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    @State private var seekValue: Double = 0
    @State private var isDraggingSeek = false
    @ScaledMetric(relativeTo: .title) private var primaryPlaybackIconSize = 56
    @ScaledMetric(relativeTo: .title) private var artworkMaxSize = 280

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
                                    .accessibilityLabel(String(localized: "Playback position"))
                                    .accessibilityValue(
                                        String(localized: "\(timeString(from: seekValue)) of \(timeString(from: track.duration))")
                                    )
                                    .accessibilityHint(String(localized: "Swipe up or down to seek"))
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
                                    .accessibilityLabel(String(localized: "Skip backward 10 seconds"))
                                    .accessibilityHint(String(localized: "Moves playback backward by ten seconds"))

                                    Button {
                                        Task { await player.auraPlayPrevious() }
                                    } label: {
                                        Image(systemName: "backward.fill")
                                            .font(.title2)
                                            .foregroundStyle(.primary)
                                    }
                                    .frame(minWidth: 44, minHeight: 44)
                                    .accessibilityLabel(String(localized: "Previous track"))
                                    .accessibilityHint(String(localized: "Plays the previous track"))

                                    mainPlaybackButton

                                    Button {
                                        Task { await player.auraPlayNext() }
                                    } label: {
                                        Image(systemName: "forward.fill")
                                            .font(.title2)
                                            .foregroundStyle(.primary)
                                    }
                                    .frame(minWidth: 44, minHeight: 44)
                                    .accessibilityLabel(String(localized: "Next track"))
                                    .accessibilityHint(String(localized: "Plays the next track"))

                                    Button {
                                        player.auraPlaySkipForward()
                                    } label: {
                                        Image(systemName: "goforward.10")
                                            .font(.title3)
                                    }
                                    .frame(minWidth: 44, minHeight: 44)
                                    .accessibilityLabel(String(localized: "Skip forward 10 seconds"))
                                    .accessibilityHint(String(localized: "Moves playback forward by ten seconds"))
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
                                .accessibilityHidden(true)
                            Text("No track loaded")
                                .font(.title3)
                                .foregroundStyle(.secondary)
                                .accessibilityAddTraits(.isHeader)
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
        .auraSurfaceBackground(style: .soft, cornerRadius: 0)
        .ignoresSafeArea(edges: .bottom)
    }

    @ViewBuilder
    private var mainPlaybackButton: some View {
        switch player.auraPlayPlaybackState {
        case .loading:
            Button(action: player.auraPlayPause) {
                Image(systemName: "pause.fill")
                    .font(.system(size: primaryPlaybackIconSize))
            }
            .disabled(true)
            .frame(minWidth: 44, minHeight: 44)
            .overlay {
                ProgressView()
                    .progressViewStyle(.circular)
                    .scaleEffect(1.2)
            }
            .accessibilityLabel(String(localized: "Loading playback"))
            .accessibilityHint(String(localized: "Playback is loading"))
            .accessibilityShowsLargeContentViewer()

        case .playing:
            Button(action: player.auraPlayPause) {
                Image(systemName: "pause.fill")
                    .font(.system(size: primaryPlaybackIconSize))
            }
            .frame(minWidth: 44, minHeight: 44)
            .accessibilityLabel(String(localized: "Pause"))
            .accessibilityHint(String(localized: "Pauses the current track"))
            .accessibilityShowsLargeContentViewer()

        case .paused:
            Button {
                try? player.auraPlayResume()
            } label: {
                Image(systemName: "play.fill")
                    .font(.system(size: primaryPlaybackIconSize))
            }
            .frame(minWidth: 44, minHeight: 44)
            .accessibilityLabel(String(localized: "Resume"))
            .accessibilityHint(String(localized: "Resumes the current track"))
            .accessibilityShowsLargeContentViewer()

        case .stopped:
            Button {
                try? player.auraPlayPlay()
            } label: {
                Image(systemName: "play.fill")
                    .font(.system(size: primaryPlaybackIconSize))
            }
            .frame(minWidth: 44, minHeight: 44)
            .accessibilityLabel(String(localized: "Play"))
            .accessibilityHint(String(localized: "Starts playback"))
            .accessibilityShowsLargeContentViewer()

        case .error:
            Image(systemName: "exclamationmark.triangle")
                .font(.title)
                .foregroundStyle(.secondary)
                .frame(minWidth: 44, minHeight: 44)
                .accessibilityLabel(String(localized: "Playback unavailable"))
        }
    }

    @ViewBuilder
    private var artworkView: some View {
        if let imageURLString = player.auraPlayCurrentTrack?.imageURLString,
           !imageURLString.isEmpty,
            let imageURL = URL(string: imageURLString) {
            CachedAsyncImage(url: imageURL)
                .frame(maxWidth: min(artworkMaxSize, 320), maxHeight: min(artworkMaxSize, 320))
                .clipShape(RoundedRectangle(cornerRadius: 20))
                .shadow(color: .black.opacity(0.1), radius: 8, x: 0, y: 4)
                .accessibilityHidden(true)
        } else {
            RoundedRectangle(cornerRadius: 20)
                .fill(Color.gray.opacity(0.25))
                .aspectRatio(1, contentMode: .fit)
                .overlay {
                    Image(systemName: "music.note")
                        .font(.system(size: 48))
                        .foregroundStyle(.gray)
                }
                .frame(maxWidth: min(artworkMaxSize, 320), maxHeight: min(artworkMaxSize, 320))
                .shadow(color: .black.opacity(0.1), radius: 8, x: 0, y: 4)
                .accessibilityHidden(true)
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
                        .accessibilityHidden(true)
                } else {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.gray.opacity(0.25))
                        .frame(width: 48, height: 48)
                        .overlay {
                            Image(systemName: "music.note")
                                .foregroundStyle(.gray)
                                .accessibilityHidden(true)
                        }
                        .accessibilityHidden(true)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.body.weight(.semibold))
                        .lineLimit(dynamicTypeSize.isAccessibilitySize ? 3 : 1)
                        .fixedSize(horizontal: false, vertical: true)
                        .foregroundStyle(.primary)
                    if let artist, !artist.isEmpty {
                        Text(artist)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(dynamicTypeSize.isAccessibilitySize ? 2 : 1)
                            .fixedSize(horizontal: false, vertical: true)
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
        .accessibilityLabel(
            String(
                localized: "\(accessibilityPrefix): \(title.isEmpty ? "Unknown Track" : title)\(artist.map { ", by \($0)" } ?? "")"
            )
        )
        .opacity(player.auraPlayPlaybackState == .loading ? 0.85 : 1.0)
    }
}

#Preview("Now Playing Large Text") {
    AuraPlayNowPlayingView(player: AuraPlayPreviewPlayer())
        .environment(\.dynamicTypeSize, .accessibility5)
}

#Preview("Now Playing Dark Mode") {
    AuraPlayNowPlayingView(player: AuraPlayPreviewPlayer())
        .preferredColorScheme(.dark)
}

#Preview("Now Playing High Contrast Large Text") {
    AuraPlayNowPlayingView(player: AuraPlayPreviewPlayer())
        .environment(\.dynamicTypeSize, .accessibility5)
}

#Preview("Now Playing Reduce Transparency") {
    AuraPlayNowPlayingView(player: AuraPlayPreviewPlayer())
}

#Preview("Now Playing Reduce Motion and Transparency") {
    AuraPlayNowPlayingView(player: AuraPlayPreviewPlayer())
}

#Preview("Now Playing Light Increased Contrast") {
    AuraPlayNowPlayingView(player: AuraPlayPreviewPlayer())
        .preferredColorScheme(.light)
}

@MainActor
private final class AuraPlayPreviewPlayer: AuraPlayPlaybackPresenting {
    let auraPlayCurrentTrack: AuraPlayTrack? = AuraPlayTrack(
        id: "preview-current",
        title: "Preview Signal",
        artist: "Auralis QA",
        duration: 245,
        imageURLString: nil
    )
    let auraPlayPlaybackState: AuraPlayPlaybackState = .playing
    let auraPlayProgress: TimeInterval = 72
    let auraPlayNextPreviewTrack: AuraPlayTrack? = AuraPlayTrack(
        id: "preview-next",
        title: "Next Fixture",
        artist: "Auralis QA",
        duration: 198,
        imageURLString: nil
    )
    let auraPlayPreviousPreviewTrack: AuraPlayTrack? = AuraPlayTrack(
        id: "preview-previous",
        title: "Previous Fixture",
        artist: "Auralis QA",
        duration: 211,
        imageURLString: nil
    )

    func auraPlayPlay() throws {}
    func auraPlayPause() {}
    func auraPlayResume() throws {}
    func auraPlaySeek(to time: TimeInterval) throws {}
    func auraPlaySkipForward() {}
    func auraPlaySkipBackward() {}
    func auraPlayNext() async {}
    func auraPlayPrevious() async {}

    func auraPlayRecentlyPlayed(limit: Int) -> [AuraPlayRecentlyPlayedItem] {
        [
            AuraPlayRecentlyPlayedItem(
                id: "recent-preview",
                title: "Recently Played Fixture",
                artist: "Auralis QA",
                imageURLString: nil,
                lastPlayed: Date(timeIntervalSince1970: 1_800_000_000)
            )
        ]
    }

    func auraPlayPlayRecentlyPlayed(id: String) async throws {}
    func auraPlayRemoveRecentlyPlayed(id: String) {}
    func auraPlayClearRecentlyPlayed() {}
}
