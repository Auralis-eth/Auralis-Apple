//
//  AudioPlayerManager.swift
//  Auralis
//
//  Created by Daniel Bell on 3/23/25.
//

import SwiftUI
import AVFoundation

@MainActor
class AudioPlayerManager: ObservableObject {
    @Published var isPlaying = false
    @Published var errorMessage: String?
    @Published var currentUrl: String?

    private var audioPlayer: AVAudioPlayer?

    func setupAudio(with urlString: String) async {
        guard let url = URL(string: urlString) else {
            self.errorMessage = "Invalid URL"
            return
        }

        do {
            // Using async/await to download the data
            let (data, _) = try await URLSession.shared.data(from: url)

            // Initialize the audio player with the downloaded data
            audioPlayer = try AVAudioPlayer(data: data)
            audioPlayer?.prepareToPlay()
            currentUrl = urlString
            errorMessage = nil
        } catch {
            errorMessage = "Error: \(error.localizedDescription)"
        }
    }

    func play() {
        audioPlayer?.play()
        isPlaying = true
    }

    func pause() {
        audioPlayer?.pause()
        isPlaying = false
    }

    func stop() {
        audioPlayer?.stop()
        audioPlayer?.currentTime = 0
        isPlaying = false
    }
}

