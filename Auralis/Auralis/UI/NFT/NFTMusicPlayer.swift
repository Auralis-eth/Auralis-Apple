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
            TitleFontText(text: "Music Player")

            if audioPlayer.isPlaying {
                SystemImage("waveform")
                    .font(.system(size: 100))
                    .foregroundColor(.blue)
            } else {
                SystemImage("waveform.slash")
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
                    SystemImage(audioPlayer.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                        .font(.system(size: 50))
                        .accessibilityLabel(audioPlayer.isPlaying ? "Pause" : "Play")
                }

                Button(action: {
                    audioPlayer.stop()
                }) {
                    SystemImage("stop.circle.fill")
                        .font(.system(size: 50))
                        .accessibilityLabel("Stop")
                }
            }

            if let error = audioPlayer.errorMessage {
                ErrorText(error)
                    .padding()
            }
        }
        .padding()
        .task {
            await audioPlayer.setupAudio(with: audioURL)
        }
    }
}

