import Foundation
import MusicFeature

@MainActor
struct AuraPlayAudioEngineQueueCoordinator: AuraPlayQueueCoordinating {
    private let audioEngine: AudioEngine

    init(audioEngine: AudioEngine) {
        self.audioEngine = audioEngine
    }

    func snapshot() -> AuraPlayQueueSnapshot {
        AuraPlayQueueSnapshot(
            upcomingCount: audioEngine.nextAudio.tracks.count,
            historyCount: audioEngine.previousAudio.tracks.count
        )
    }
}
