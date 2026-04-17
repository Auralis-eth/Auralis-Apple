//
//  MiniPlayerView.swift
//  Auralis
//
//  Created by Daniel Bell on 9/15/25.
//

import SwiftUI

// MARK: - Mini Player (bottom accessory)
struct MiniPlayerView: View {
    @ObservedObject var audioEngine: AudioEngine

    @Environment(\.tabViewBottomAccessoryPlacement) private var placement
    @State private var showNowPlaying: Bool = false
    @State private var miniSeekValue: Double = 0
    @State private var miniIsDragging: Bool = false

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
            if audioEngine.currentTrack == nil {
                EmptyView()
            } else {
                MiniPlayerContentView(audioEngine: audioEngine, accessoryMode: accessoryMode)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        if accessoryMode != .unknown {
                            showNowPlaying = true
                        }
                    }
                    .sheet(isPresented: $showNowPlaying) {
                        NowPlayingView(audioEngine: audioEngine)
                    }
            }
        }
        .accessibilityElement(children: .contain)
    }

    private func timeString(from seconds: TimeInterval) -> String {
        guard seconds.isFinite else { return "0:00" }
        let s = Int(seconds)
        let mins = s / 60
        let secs = s % 60
        return String(format: "%d:%02d", mins, secs)
    }
}

struct MiniPlayerContentView: View {
    @ObservedObject var audioEngine: AudioEngine
    fileprivate let accessoryMode: MiniPlayerView.AccessoryMode

    @State private var miniSeekValue: Double = 0
    @State private var miniIsDragging: Bool = false

    var body: some View {
        VStack {
            HStack {
                if let currentTrack = audioEngine.currentTrack {
                    MiniPlayerPlayingView(currentTrack: currentTrack, accessoryMode: accessoryMode)
                        .id(currentTrack.id) // forces a full rebuild when the track identity changes
                    Spacer()
                }

                // playback controls
                HStack(spacing: 8) {
                    // Previous track
                    Button {
                        Task { await audioEngine.playPrevious() }
                    } label: {
                        Image(systemName: "backward.fill")
                            .font(.title3)
                    }

                    PlaybackStateButton(
                        sourceState: audioEngine.playbackState,
                        play: { try? audioEngine.play() },
                        pause: audioEngine.pause,
                        resume: { try? audioEngine.resume() }
                    )

                    // Next track
                    Button {
                        Task { await audioEngine.playNext() }
                    } label: {
                        Image(systemName: "forward.fill")
                            .font(.title3)
                    }
                }
                .buttonStyle(.glass)
            }

            // Adaptive progress/seek
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
                .onChange(of: audioEngine.currentTrack) { _, _ in
                    // Reset local slider when track changes
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
                // Compact indicator when inline or unknown placement (safe fallback)
                ProgressView()
            }

        }
        .padding(.top)
        .padding(.trailing)
    }
}

struct MiniPlayerPlayingView: View {
    let currentTrack: AudioEngine.Track
    fileprivate let accessoryMode: MiniPlayerView.AccessoryMode

    var body: some View {
        if let imageUrlString = currentTrack.imageUrl,
           !imageUrlString.isEmpty,
           let imageUrl = URL(string: imageUrlString) {
            CachedAsyncImage(url: imageUrl)
                .scaledToFill()
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .padding(.trailing)
        } else {
            RoundedRectangle(cornerRadius: 6)
                .frame(width: accessoryMode == .expanded ? 44 : 36, height: accessoryMode == .expanded ? 44 : 36)
                .overlay(
                    Image(systemName: "music.note")
                        .font(.system(size: accessoryMode == .expanded ? 20 : 16))
                        .padding(6)
                )
                .padding(.trailing)
        }

        // title / artist
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
    }
}

struct PlaybackStateButton: View {
    // Source value provided by the parent
    let sourceState: AudioEngine.PlaybackState

    // Actions
    let play: () -> Void
    let pause: () -> Void
    let resume: () -> Void

    var body: some View {
        Button {
            switch sourceState {
            case .loading:
                // No-op or pause safeguard
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
            case .loading:
                Image(systemName: "pause.fill")
                    .font(.title3)
            case .playing:
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
        .disabled(sourceState == .loading || sourceState == .error)
        .overlay {
            if sourceState == .loading {
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle())
            }
        }
        .animation(nil, value: sourceState)
    }
}
