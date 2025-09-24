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

    private enum AccessoryMode {
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

    private var progressFraction: Double {
        guard let t = audioEngine.currentTrack, t.duration > 0 else { return 0 }
        let raw = audioEngine.progress / t.duration
        if !raw.isFinite || raw.isNaN { return 0 }
        return min(max(raw, 0), 1)
    }
    
    @ViewBuilder
    private var nftThumbnailView: some View {
        if let imageUrlString = audioEngine.currentTrack?.imageUrl,
           !imageUrlString.isEmpty,
           let imageUrl = URL(string: imageUrlString) {
            CachedAsyncImage(url: imageUrl)
                .scaledToFill()
                .clipShape(RoundedRectangle(cornerRadius: 6))
        } else {
            RoundedRectangle(cornerRadius: 6)
                .frame(width: accessoryMode == .expanded ? 44 : 36, height: accessoryMode == .expanded ? 44 : 36)
                .overlay(
                    Image(systemName: "music.note")
                        .font(.system(size: accessoryMode == .expanded ? 20 : 16))
                        .padding(6)
                )
        }
    }

    var body: some View {
        Group {
            if audioEngine.currentTrack == nil {
                EmptyView()
            } else {
                content
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

    private var content: some View {
        VStack {
            HStack {
                nftThumbnailView
                    .padding(.trailing)
                
                // title / artist
                VStack(alignment: .leading) {
                    Text(audioEngine.currentTrack?.title ?? "Unknown Title")
                        .font(accessoryMode == .expanded ? .subheadline.bold() : .subheadline)
                        .lineLimit(1)
                    if accessoryMode == .expanded {
                        Text(audioEngine.currentTrack?.artist ?? "Unknown Artist")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                
                Spacer()
                
                // playback controls
                HStack(spacing: 8) {
                    switch audioEngine.playbackState {
                    case .loading:
                        Button(action: audioEngine.pause) {
                            Image(systemName: "pause.fill")
                                .font(.title3)
                        }
                        .disabled(true) // disable the button
                        .overlay {
                            ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle())
                        }
                    case .playing:
                        Button(action: audioEngine.pause) {
                            Image(systemName: "pause.fill")
                                .font(.title3)
                        }
                    case .paused:
                        Button {
                            try? audioEngine.resume()
                        } label: {
                            Image(systemName: "play.fill")
                                .font(.title3)
                        }
                    case .stopped:
                        Button {
                            try? audioEngine.play()
                        } label: {
                            Image(systemName: "play.fill")
                                .font(.title3)
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
                            .font(.title3)
                    }
                }
                .buttonStyle(.glass)
            }
            
            // Adaptive progress/seek
            switch (accessoryMode, audioEngine.currentTrack) {
            case (.expanded, let track?):
                Slider(
                    value: Binding(
                        get: { miniIsDragging ? miniSeekValue : audioEngine.progress },
                        set: { newValue in
                            miniSeekValue = newValue
                        }
                    ),
                    in: 0...max(1, track.duration),
                    onEditingChanged: { dragging in
                        miniIsDragging = dragging
                        if !dragging {
                            // Only seek when we are in a supported context
                            try? audioEngine.seek(to: miniSeekValue)
                        }
                    }
                )
            default:
                // Compact indicator when inline or unknown placement (safe fallback)
                ProgressView(value: progressFraction, total: 1)
                    .frame(maxWidth: .infinity)
            }

        }
        .padding(.top)
        .padding(.trailing)
    }
    
    private func timeString(from seconds: TimeInterval) -> String {
        guard seconds.isFinite else { return "0:00" }
        let s = Int(seconds)
        let mins = s / 60
        let secs = s % 60
        return String(format: "%d:%02d", mins, secs)
    }
}

