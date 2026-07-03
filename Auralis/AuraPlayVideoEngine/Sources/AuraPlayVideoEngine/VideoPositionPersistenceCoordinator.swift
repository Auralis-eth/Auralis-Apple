import Foundation

public actor VideoPositionPersistenceCoordinator {
    private let mediaID: String
    private let store: VideoPlaybackStateStoring
    private let cadenceSeconds: Double
    private var lastWriteSeconds: Double?

    public init(mediaID: String, store: VideoPlaybackStateStoring, cadenceSeconds: Double = 5) {
        self.mediaID = mediaID
        self.store = store
        self.cadenceSeconds = cadenceSeconds
    }

    public func handleTick(_ tick: PlaybackTick, isPlaying: Bool) async throws {
        guard isPlaying else { return }

        if let lastWriteSeconds, tick.currentSeconds - lastWriteSeconds < cadenceSeconds {
            return
        }

        try await write(tick)
    }

    public func flush(_ tick: PlaybackTick) async throws {
        try await write(tick)
    }

    public func markCompleted() async throws {
        try await store.markCompleted(mediaID: mediaID)
        try await store.writePosition(
            StoredVideoPlaybackPosition(
                mediaID: mediaID,
                positionMilliseconds: 0,
                durationMilliseconds: nil
            )
        )
        lastWriteSeconds = nil
    }

    private func write(_ tick: PlaybackTick) async throws {
        try await store.writePosition(
            StoredVideoPlaybackPosition(
                mediaID: mediaID,
                positionMilliseconds: Int((tick.currentSeconds * 1000).rounded()),
                durationMilliseconds: tick.durationSeconds.map { Int(($0 * 1000).rounded()) }
            )
        )
        lastWriteSeconds = tick.currentSeconds
    }
}
