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

    var body: some View {
        VStack(spacing: 16) {
            Capsule()
                .frame(width: 40, height: 6)
                .foregroundStyle(.secondary)
                .padding(.top, 8)

//            if let track = audioEngine.currentTrack {
            if let track = AudioEngine.Track(title: "Ethereum Whitepaper", artist: "Vitalik Buterin", duration: 420) as? AudioEngine.Track {
                VStack(alignment: .leading, spacing: 8) {
                    Text(track.title)
                        .font(.title2)
                        .bold()
                        .lineLimit(2)
                    Text(track.artist)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal)

                // Album art placeholder
                RoundedRectangle(cornerRadius: 12)
                    .aspectRatio(1, contentMode: .fit)
                    .overlay(
                        Image(systemName: "music.note")
                            .font(.system(size: 64))
                            .padding()
                    )
                    .padding(.horizontal)

                // Progress + time labels
                VStack {
                    Slider(
                        value: Binding(
                            get: { audioEngine.progress },
                            set: { try? audioEngine.seek(to: $0) }
                        ),
                        in: 0...(track.duration),
                        onEditingChanged: { editing in
                            // when slider ends, ensure accurate state if needed
                        }
                    )
                    HStack {
                        Text(timeString(from: audioEngine.progress))
                        Spacer()
                        Text(timeString(from: track.duration))
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }.padding(.horizontal)

                // Playback controls
                HStack(spacing: 36) {
                    Button(action: audioEngine.playPrevious) {
                        Image(systemName: "backward.fill")
                            .font(.title2)
                    }
                    switch audioEngine.playbackState {
                    case .loading:
                        Button(action: audioEngine.pause) {
                            Image(systemName: "pause.fill")
                                .font(.system(size: 56))
                        }
                        .disabled(true) // disable the button
                        .overlay {
                            ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle())
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
                    }
                    Button(action: audioEngine.playNext) {
                        Image(systemName: "forward.fill")
                            .font(.title2)
                    }
                }
                .padding(.vertical)

                Spacer()
            } else {
                Text("No track loaded")
                    .foregroundStyle(.secondary)
                Spacer()
            }
        }
        .padding(.bottom, 20)
        .background(.ultraThinMaterial)
        .ignoresSafeArea(edges: .bottom)
    }

    private func timeString(from seconds: TimeInterval) -> String {
        guard seconds.isFinite else { return "0:00" }
        let s = Int(seconds)
        let mins = s / 60
        let secs = s % 60
        return String(format: "%d:%02d", mins, secs)
    }
}





