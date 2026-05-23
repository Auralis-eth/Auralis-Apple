import SwiftUI

private enum AuraPlayMiniPlayerAccessoryMode {
    case inline
    case expanded
    case unknown
}

public struct AuraPlayMiniPlayerView<Player: AuraPlayPlaybackPresenting>: View {
    private let player: Player

    @State private var showNowPlaying = false

    private var accessoryMode: AuraPlayMiniPlayerAccessoryMode {
        .expanded
    }

    public init(player: Player) {
        self.player = player
    }

    public var body: some View {
        Group {
            if player.auraPlayCurrentTrack != nil {
                AuraPlayMiniPlayerContentView(
                    player: player,
                    accessoryMode: accessoryMode,
                    openNowPlaying: openNowPlaying
                )
                .sheet(isPresented: $showNowPlaying) {
                    AuraPlayNowPlayingView(player: player)
                }
            }
        }
        .accessibilityElement(children: .contain)
    }

    private func openNowPlaying() {
        if accessoryMode != .unknown {
            showNowPlaying = true
        }
    }
}

private struct AuraPlayMiniPlayerContentView<Player: AuraPlayPlaybackPresenting>: View {
    let player: Player
    let accessoryMode: AuraPlayMiniPlayerAccessoryMode
    let openNowPlaying: () -> Void

    @State private var miniSeekValue: Double = 0
    @State private var miniIsDragging = false

    private var currentTrackAccessibilityValue: String {
        let title = player.auraPlayCurrentTrack?.title?.isEmpty == false
            ? player.auraPlayCurrentTrack?.title ?? "Unknown Title"
            : "Unknown Title"
        return "\(title), \(playbackStateAccessibilityValue)"
    }

    private var playbackStateAccessibilityValue: String {
        switch player.auraPlayPlaybackState {
        case .loading:
            return "loading"
        case .playing:
            return "playing"
        case .paused:
            return "paused"
        case .stopped:
            return "stopped"
        case .error:
            return "playback unavailable"
        }
    }

    var body: some View {
        VStack {
            HStack {
                if let currentTrack = player.auraPlayCurrentTrack {
                    Button(action: openNowPlaying) {
                        AuraPlayMiniPlayerTrackView(
                            currentTrack: currentTrack,
                            accessoryMode: accessoryMode
                        )
                        .id(currentTrack.id)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.plain)
                    .contentShape(Rectangle())
                    .accessibilityLabel("Now Playing")
                    .accessibilityValue(currentTrackAccessibilityValue)
                    .accessibilityHint("Opens the Now Playing screen")
                }

                HStack(spacing: 8) {
                    Button {
                        Task { await player.auraPlayPrevious() }
                    } label: {
                        Image(systemName: "backward.fill")
                            .font(.title3)
                    }
                    .frame(minWidth: 44, minHeight: 44)
                    .accessibilityLabel("Previous track")

                    AuraPlayPlaybackStateButton(
                        sourceState: player.auraPlayPlaybackState,
                        play: { try? player.auraPlayPlay() },
                        pause: player.auraPlayPause,
                        resume: { try? player.auraPlayResume() }
                    )

                    Button {
                        Task { await player.auraPlayNext() }
                    } label: {
                        Image(systemName: "forward.fill")
                            .font(.title3)
                    }
                    .frame(minWidth: 44, minHeight: 44)
                    .accessibilityLabel("Next track")
                }
                .buttonStyle(.borderless)
            }

            switch (accessoryMode, player.auraPlayCurrentTrack) {
            case (.expanded, let track?):
                Slider(
                    value: $miniSeekValue,
                    in: 0...max(1, track.duration),
                    onEditingChanged: { dragging in
                        miniIsDragging = dragging
                        if !dragging {
                            try? player.auraPlaySeek(to: miniSeekValue)
                        }
                    }
                )
                .accessibilityLabel("Playback position")
                .onChange(of: player.auraPlayCurrentTrack) { _, _ in
                    miniSeekValue = 0
                }
                .onChange(of: player.auraPlayProgress) { _, newValue in
                    if !miniIsDragging {
                        miniSeekValue = newValue
                    }
                }
                .onAppear {
                    miniSeekValue = player.auraPlayProgress
                }
            default:
                ProgressView()
            }
        }
        .padding(.top)
        .padding(.trailing)
    }
}

private struct AuraPlayMiniPlayerTrackView: View {
    let currentTrack: AuraPlayTrack
    let accessoryMode: AuraPlayMiniPlayerAccessoryMode

    var body: some View {
        Group {
            if let imageURLString = currentTrack.imageURLString,
               !imageURLString.isEmpty,
               let imageURL = URL(string: imageURLString) {
                CachedAsyncImage(url: imageURL)
                    .scaledToFill()
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .padding(.trailing)
            } else {
                RoundedRectangle(cornerRadius: 6)
                    .frame(
                        width: accessoryMode == .expanded ? 44 : 36,
                        height: accessoryMode == .expanded ? 44 : 36
                    )
                    .overlay {
                        Image(systemName: "music.note")
                            .font(.system(size: accessoryMode == .expanded ? 20 : 16))
                            .padding(6)
                    }
                    .padding(.trailing)
            }
        }

        VStack(alignment: .leading) {
            Text(currentTrack.title ?? "Unknown Title")
                .font(accessoryMode == .expanded ? .subheadline.bold() : .subheadline)
                .lineLimit(1)
            if accessoryMode == .expanded {
                Text(currentTrack.artist ?? "Unknown Artist")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

private struct AuraPlayPlaybackStateButton: View {
    let sourceState: AuraPlayPlaybackState
    let play: () -> Void
    let pause: () -> Void
    let resume: () -> Void

    var body: some View {
        Button {
            switch sourceState {
            case .loading:
                pause()
            case .playing:
                pause()
            case .paused:
                resume()
            case .stopped:
                play()
            case .error:
                break
            }
        } label: {
            switch sourceState {
            case .loading, .playing:
                Image(systemName: "pause.fill")
                    .font(.title3)
            case .paused, .stopped:
                Image(systemName: "play.fill")
                    .font(.title3)
            case .error:
                Image(systemName: "exclamationmark.triangle")
                    .font(.title3)
            }
        }
        .frame(minWidth: 44, minHeight: 44)
        .disabled(sourceState == .loading || sourceState == .error)
        .overlay {
            if sourceState == .loading {
                ProgressView()
                    .progressViewStyle(.circular)
            }
        }
        .animation(nil, value: sourceState)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityHint(accessibilityHint)
    }

    private var accessibilityLabel: String {
        switch sourceState {
        case .loading:
            return "Loading playback"
        case .playing:
            return "Pause"
        case .paused, .stopped:
            return "Play"
        case .error:
            return "Playback unavailable"
        }
    }

    private var accessibilityHint: String {
        switch sourceState {
        case .loading:
            return "Playback is loading"
        case .playing:
            return "Pauses the current track"
        case .paused:
            return "Resumes the current track"
        case .stopped:
            return "Starts playback"
        case .error:
            return "Playback controls are unavailable"
        }
    }
}
