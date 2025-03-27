//
//  NFTMusicPlayer.swift
//  Auralis
//
//  Created by Daniel Bell on 3/24/25.
//

import SwiftUI

struct NFTMusicPlayer: View {
    @StateObject private var audioPlayer = AudioPlayerManager()
    let audioURL: String

    var body: some View {
        VStack(spacing: 20) {
            Text("Music Player")
                .font(.title)
                .fontWeight(.bold)

            if audioPlayer.isPlaying {
                Image(systemName: "waveform")
                    .font(.system(size: 100))
                    .foregroundColor(.blue)
            } else {
                Image(systemName: "waveform.slash")
                    .font(.system(size: 100))
                    .foregroundColor(.gray)
            }

            HStack(spacing: 30) {
                Button {
                    if audioPlayer.isPlaying {
                        audioPlayer.pause()
                    } else {
                        audioPlayer.play()
                    }
                } label: {
                    Image(systemName: audioPlayer.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                        .font(.system(size: 50))
                        .accessibilityLabel(audioPlayer.isPlaying ? "Pause" : "Play")
                }

                Button(action: {
                    audioPlayer.stop()
                }) {
                    Image(systemName: "stop.circle.fill")
                        .font(.system(size: 50))
                        .accessibilityLabel("Stop")
                }
            }

            if let error = audioPlayer.errorMessage {
                Text(error)
                    .foregroundColor(.red)
                    .padding()
            }
        }
        .padding()
        .task {
            await audioPlayer.setupAudio(with: audioURL)
        }
    }
}

