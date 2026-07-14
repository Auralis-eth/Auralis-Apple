import AuraUI
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
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var currentTrackAccessibilityValue: String {
        guard let track = player.auraPlayCurrentTrack else {
            return playbackStateAccessibilityValue
        }

        let title = track.title?.isEmpty == false
            ? track.title ?? String(localized: "Unknown Title")
            : String(localized: "Unknown Title")
        let artist = track.artist?.isEmpty == false
            ? track.artist ?? String(localized: "Unknown Artist")
            : String(localized: "Unknown Artist")
        return String(localized: "\(title), by \(artist). Artwork for \(title) by \(artist). \(playbackStateAccessibilityValue)")
    }

    private var playbackStateAccessibilityValue: String {
        switch player.auraPlayPlaybackState {
        case .loading:
            return String(localized: "loading")
        case .playing:
            return String(localized: "playing")
        case .paused:
            return String(localized: "paused")
        case .stopped:
            return String(localized: "stopped")
        case .error:
            return String(localized: "playback unavailable")
        }
    }

    private var cachePresentation: AuraPlayCachePresentation {
        player.auraPlayCachePresentation
    }

    private var shouldShowCacheStatus: Bool {
        player.auraPlayPlaybackState == .loading
            || cachePresentation.progressFraction != nil
            || cachePresentation.state == .queued
            || cachePresentation.state == .downloading
            || cachePresentation.state == .partial
            || cachePresentation.state == .cached
            || cachePresentation.state == .pinned
            || cachePresentation.state == .error
    }

    private var cacheStatusTitle: String {
        if player.auraPlayPlaybackState == .loading, cachePresentation.state == .partial {
            return String(localized: "Buffering")
        }

        switch cachePresentation.state {
        case .unavailable:
            return String(localized: "Preparing")
        case .notCached:
            return String(localized: "Online only")
        case .queued:
            return String(localized: "Queued")
        case .downloading, .partial:
            return String(localized: "Downloading")
        case .cached:
            return String(localized: "Saved offline")
        case .pinned:
            return String(localized: "Pinned offline")
        case .error:
            return String(localized: "Offline error")
        }
    }

    private var cacheStatusValue: String {
        guard let progressFraction = cachePresentation.progressFraction else {
            return cachePresentation.message
        }

        return String(localized: "\(Int((progressFraction * 100).rounded())) percent. \(cachePresentation.message)")
    }

    var body: some View {
        VStack {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 8) {
                    currentTrackButton
                    transportControls
                        .frame(maxWidth: .infinity, alignment: .center)
                }
            } else {
                HStack {
                    currentTrackButton
                    transportControls
                }
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
                .accessibilityLabel(String(localized: "Playback position"))
                .accessibilityValue(
                    String(localized: "\(timeString(from: miniSeekValue)) of \(timeString(from: track.duration))")
                )
                .accessibilityHint(String(localized: "Swipe up or down to seek"))
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

            if shouldShowCacheStatus {
                miniCacheStatus
            }
        }
        .padding(.top)
        .padding(.trailing)
    }

    @ViewBuilder
    private var currentTrackButton: some View {
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
            .accessibilityLabel(String(localized: "Now Playing"))
            .accessibilityValue(currentTrackAccessibilityValue)
            .accessibilityHint(String(localized: "Opens the Now Playing screen"))
        }
    }

    private var miniCacheStatus: some View {
        HStack(spacing: 8) {
            if let progressFraction = cachePresentation.progressFraction {
                ProgressView(value: progressFraction)
                    .frame(width: 56)
                    .accessibilityHidden(true)
            } else if player.auraPlayPlaybackState == .loading || cachePresentation.state == .queued {
                ProgressView()
                    .controlSize(.small)
                    .accessibilityHidden(true)
            } else {
                Image(systemName: cacheStatusSystemImage)
                    .font(.caption)
                    .foregroundStyle(cachePresentation.state == .error ? Color.red : Color.secondary)
                    .accessibilityHidden(true)
            }

            Text(cacheStatusTitle)
                .font(.caption.weight(.semibold))
                .foregroundStyle(cachePresentation.state == .error ? Color.red : Color.secondary)
                .lineLimit(1)

            Spacer(minLength: 8)

            if let progressFraction = cachePresentation.progressFraction {
                Text("\(Int((progressFraction * 100).rounded()))%")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(String(localized: "AuraPlay offline status"))
        .accessibilityValue(cacheStatusValue)
        .accessibilityIdentifier(A11yID.AuraPlay.miniPlayerCacheStatus)
    }

    private var cacheStatusSystemImage: String {
        switch cachePresentation.state {
        case .cached:
            return "checkmark.circle"
        case .pinned:
            return "pin.fill"
        case .error:
            return "exclamationmark.triangle"
        default:
            return "arrow.down.circle"
        }
    }

    private var transportControls: some View {
        HStack(spacing: 8) {
            Button {
                Task { await player.auraPlayPrevious() }
            } label: {
                Image(systemName: "backward.fill")
                    .font(.title3)
            }
            .frame(minWidth: 44, minHeight: 44)
            .accessibilityLabel(String(localized: "Previous track"))

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
            .accessibilityLabel(String(localized: "Next track"))
        }
        .buttonStyle(.borderless)
    }

    private func timeString(from seconds: TimeInterval) -> String {
        guard seconds.isFinite else { return "0:00" }
        let totalSeconds = Int(seconds)
        let minutes = totalSeconds / 60
        let secondsComponent = totalSeconds % 60
        return String(format: "%d:%02d", minutes, secondsComponent)
    }
}

private struct AuraPlayMiniPlayerTrackView: View {
    let currentTrack: AuraPlayTrack
    let accessoryMode: AuraPlayMiniPlayerAccessoryMode
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        Group {
            if let imageURLString = currentTrack.imageURLString,
               !imageURLString.isEmpty,
               let imageURL = URL(string: imageURLString) {
                CachedAsyncImage(url: imageURL, mediaAccessibility: .decorative)
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
                            .accessibilityHidden(true)
                    }
                    .padding(.trailing)
                    .accessibilityHidden(true)
            }
        }

        VStack(alignment: .leading) {
            Text(currentTrack.title ?? "Unknown Title")
                .font(accessoryMode == .expanded ? .subheadline.bold() : .subheadline)
                .lineLimit(dynamicTypeSize.isAccessibilitySize ? 3 : 1)
                .fixedSize(horizontal: false, vertical: true)
            if accessoryMode == .expanded {
                Text(currentTrack.artist ?? "Unknown Artist")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(dynamicTypeSize.isAccessibilitySize ? 2 : 1)
                    .fixedSize(horizontal: false, vertical: true)
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
            return String(localized: "Loading playback")
        case .playing:
            return String(localized: "Pause")
        case .paused, .stopped:
            return String(localized: "Play")
        case .error:
            return String(localized: "Playback unavailable")
        }
    }

    private var accessibilityHint: String {
        switch sourceState {
        case .loading:
            return String(localized: "Playback is loading")
        case .playing:
            return String(localized: "Pauses the current track")
        case .paused:
            return String(localized: "Resumes the current track")
        case .stopped:
            return String(localized: "Starts playback")
        case .error:
            return String(localized: "Playback controls are unavailable")
        }
    }
}
