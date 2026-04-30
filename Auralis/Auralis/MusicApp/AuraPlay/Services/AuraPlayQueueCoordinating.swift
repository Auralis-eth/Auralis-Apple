import Foundation

struct AuraPlayQueueSnapshot: Equatable, Sendable {
    let upcomingCount: Int
    let historyCount: Int
}

@MainActor
protocol AuraPlayQueueCoordinating {
    func snapshot() -> AuraPlayQueueSnapshot
}

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
