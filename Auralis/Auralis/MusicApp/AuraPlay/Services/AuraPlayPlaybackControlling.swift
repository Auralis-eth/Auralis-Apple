import AuralisPrimaryModels
import AuralisPrimaryPersistence
import Foundation
import MusicFeature

@MainActor
/// Adapts the existing shared `AudioEngine` to the AuraPlay playback-control contract.
struct AuraPlayAudioEnginePlaybackController: AuraPlayPlaybackControlling {
    private let audioEngine: AudioEngine

    init(audioEngine: AudioEngine) {
        self.audioEngine = audioEngine
    }

    var playbackState: AuraPlayPlaybackState {
        switch audioEngine.playbackState {
        case .stopped:
            .stopped
        case .playing:
            .playing
        case .paused:
            .paused
        case .loading:
            .loading
        case .error:
            .error
        }
    }

    var currentTrack: AuraPlayTrack? {
        guard let track = audioEngine.currentTrack else {
            return nil
        }
        return AuraPlayTrack(
            id: track.id,
            title: track.title,
            artist: track.artist,
            duration: track.duration,
            imageURLString: track.imageUrl
        )
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

extension AudioEngine: AuraPlayPlaybackPresenting {
    public var auraPlayCurrentTrack: AuraPlayTrack? {
        guard let currentTrack else {
            return nil
        }
        return AuraPlayTrack(track: currentTrack)
    }

    public var auraPlayPlaybackState: AuraPlayPlaybackState {
        switch playbackState {
        case .stopped:
            .stopped
        case .playing:
            .playing
        case .paused:
            .paused
        case .loading:
            .loading
        case .error:
            .error
        }
    }

    public var auraPlayProgress: TimeInterval {
        progress
    }

    public var auraPlayNextPreviewTrack: AuraPlayTrack? {
        nextAudio.tracks.first.map(AuraPlayTrack.init(nft:))
    }

    public var auraPlayPreviousPreviewTrack: AuraPlayTrack? {
        previousAudio.tracks.last.map(AuraPlayTrack.init(nft:))
    }

    public func auraPlayPlay() throws {
        try play()
    }

    public func auraPlayPause() {
        pause()
    }

    public func auraPlayResume() throws {
        try resume()
    }

    public func auraPlaySeek(to time: TimeInterval) throws {
        try seek(to: time)
    }

    public func auraPlaySkipForward() {
        skipForward()
    }

    public func auraPlaySkipBackward() {
        skipBackward()
    }

    public func auraPlayNext() async {
        await playNext()
    }

    public func auraPlayPrevious() async {
        await playPrevious()
    }

    public func auraPlayRecentlyPlayed(limit: Int) -> [AuraPlayRecentlyPlayedItem] {
        getRecentlyPlayed(limit: limit).map { nft in
            AuraPlayRecentlyPlayedItem(
                id: nft.id,
                title: nft.name ?? "Unknown Track",
                artist: nft.artistName,
                imageURLString: nft.image?.thumbnailUrl ?? nft.image?.originalUrl,
                lastPlayed: lastPlayedDate(for: nft.id)
            )
        }
    }

    public func auraPlayPlayRecentlyPlayed(id: String) async throws {
        guard let nft = getRecentlyPlayed(limit: 100).first(where: { $0.id == id }) else {
            return
        }
        try await loadAndPlay(nft: nft)
    }

    public func auraPlayRemoveRecentlyPlayed(id: String) {
        removeFromPrevious(id: id)
    }

    public func auraPlayClearRecentlyPlayed() {
        clearPreviousHistory()
    }
}

private extension AuraPlayTrack {
    init(track: AudioEngine.Track) {
        self.init(
            id: track.id,
            title: track.title,
            artist: track.artist,
            duration: track.duration,
            imageURLString: track.imageUrl
        )
    }

    init(nft: NFT) {
        self.init(
            id: nft.id,
            title: nft.name,
            artist: nft.artistName,
            duration: 0,
            imageURLString: nft.image?.thumbnailUrl ?? nft.image?.originalUrl
        )
    }
}
