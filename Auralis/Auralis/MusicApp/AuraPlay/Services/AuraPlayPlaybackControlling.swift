import AuralisPrimaryModels
import Foundation

@MainActor
/// Abstracts playback controls so AuraPlay can talk to the shared engine through a testable seam.
protocol AuraPlayPlaybackControlling {
    var playbackState: AudioEngine.PlaybackState { get }
    var currentTrack: AudioEngine.Track? { get }
    var currentTrackID: String? { get }
    var currentTime: TimeInterval { get }

    func play() throws
    func pause()
    func resume() throws
    func seek(to time: TimeInterval) throws
    func playNext() async
    func playPrevious() async
}

@MainActor
/// Adapts the existing shared `AudioEngine` to the AuraPlay playback-control contract.
struct AuraPlayAudioEnginePlaybackController: AuraPlayPlaybackControlling {
    private let audioEngine: AudioEngine

    init(audioEngine: AudioEngine) {
        self.audioEngine = audioEngine
    }

    var playbackState: AudioEngine.PlaybackState {
        audioEngine.playbackState
    }

    var currentTrack: AudioEngine.Track? {
        audioEngine.currentTrack
    }

    var currentTrackID: String? {
        audioEngine.currentTrackNFTID
    }

    var currentTime: TimeInterval {
        audioEngine.currentTime
    }

    func play() throws {
        try audioEngine.play()
    }

    func pause() {
        audioEngine.pause()
    }

    func resume() throws {
        try audioEngine.resume()
    }

    func seek(to time: TimeInterval) throws {
        try audioEngine.seek(to: time)
    }

    func playNext() async {
        await audioEngine.playNext()
    }

    func playPrevious() async {
        await audioEngine.playPrevious()
    }
}
