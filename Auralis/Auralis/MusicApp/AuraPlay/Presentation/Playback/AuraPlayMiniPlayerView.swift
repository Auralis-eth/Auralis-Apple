import SwiftUI

struct AuraPlayMiniPlayerView: View {
    @ObservedObject var audioEngine: AudioEngine

    @Environment(\.tabViewBottomAccessoryPlacement) private var placement
    @State private var showNowPlaying = false

    fileprivate enum AccessoryMode {
        case inline
        case expanded
        case unknown
    }

    private var accessoryMode: AccessoryMode {
        switch placement {
        case .some(.inline):
            return .inline
        case .some(.expanded):
            return .expanded
        default:
            return .unknown
        }
    }

    var body: some View {
        Group {
            if audioEngine.currentTrack != nil {
                AuraPlayMiniPlayerContentView(
                    audioEngine: audioEngine,
                    accessoryMode: accessoryMode
                )
                .contentShape(Rectangle())
                .onTapGesture {
                    if accessoryMode != .unknown {
                        showNowPlaying = true
                    }
                }
                .accessibilityAction(named: "Open Now Playing") {
                    if accessoryMode != .unknown {
                        showNowPlaying = true
                    }
                }
                .sheet(isPresented: $showNowPlaying) {
                    AuraPlayNowPlayingView(audioEngine: audioEngine)
                }
            }
        }
        .accessibilityElement(children: .contain)
    }
}

private struct AuraPlayMiniPlayerContentView: View {
    @ObservedObject var audioEngine: AudioEngine
    fileprivate let accessoryMode: AuraPlayMiniPlayerView.AccessoryMode

    @State private var miniSeekValue: Double = 0
    @State private var miniIsDragging = false

    var body: some View {
        VStack {
            HStack {
                if let currentTrack = audioEngine.currentTrack {
                    AuraPlayMiniPlayerTrackView(
                        currentTrack: currentTrack,
                        accessoryMode: accessoryMode
                    )
                    .id(currentTrack.id)
                    Spacer()
                }

                HStack(spacing: 8) {
                    Button {
                        Task { await audioEngine.playPrevious() }
                    } label: {
                        Image(systemName: "backward.fill")
                            .font(.title3)
                    }
                    .frame(minWidth: 44, minHeight: 44)
                    .accessibilityLabel("Previous track")

                    AuraPlayPlaybackStateButton(
                        sourceState: audioEngine.playbackState,
                        play: { try? audioEngine.play() },
                        pause: audioEngine.pause,
                        resume: { try? audioEngine.resume() }
                    )

                    Button {
                        Task { await audioEngine.playNext() }
                    } label: {
                        Image(systemName: "forward.fill")
                            .font(.title3)
                    }
                    .frame(minWidth: 44, minHeight: 44)
                    .accessibilityLabel("Next track")
                }
                .buttonStyle(.glass)
            }

            switch (accessoryMode, audioEngine.currentTrack) {
            case (.expanded, let track?):
                Slider(
                    value: $miniSeekValue,
                    in: 0...max(1, track.duration),
                    onEditingChanged: { dragging in
                        miniIsDragging = dragging
                        if !dragging {
                            try? audioEngine.seek(to: miniSeekValue)
                        }
                    }
                )
                .accessibilityLabel("Playback position")
                .onChange(of: audioEngine.currentTrack) { _, _ in
                    miniSeekValue = 0
                }
                .onChange(of: audioEngine.progress) { _, newValue in
                    if !miniIsDragging {
                        miniSeekValue = newValue
                    }
                }
                .onAppear {
                    miniSeekValue = audioEngine.progress
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
    let currentTrack: AudioEngine.Track
    fileprivate let accessoryMode: AuraPlayMiniPlayerView.AccessoryMode

    var body: some View {
        Group {
            if let imageURLString = currentTrack.imageUrl,
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
    let sourceState: AudioEngine.PlaybackState
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
