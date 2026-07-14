import AVFoundation
import AuraPlayMediaCore
import Foundation

@MainActor
public final class VideoPlaybackIntegrationCoordinator {
    private let controller: any VideoPlayerControlling
    private let metadata: VideoMediaMetadata
    private let playbackStateStore: (any VideoPlaybackStateStoring)?
    private let nowPlayingPublisher: (any VideoNowPlayingPublishing)?
    private let remoteCommandStream: (any VideoRemoteCommandStreaming)?
    private let mediaSessionManager: (any VideoMediaSessionManaging)?
    private let gatewayResolver: (any VideoGatewayResolving)?
    public let coordinatedPlaybackConfiguration: VideoCoordinatedPlaybackConfiguration?
    private let bufferingPolicy: VideoBufferingPolicy
    private let stallFallbackCoordinator: StallFallbackCoordinator
    private let logger: VideoEngineLogging

    private var tasks: [Task<Void, Never>] = []
    private var persistenceCoordinator: VideoPositionPersistenceCoordinator?
    private var latestTick = PlaybackTick(currentSeconds: 0, durationSeconds: nil)
    private var currentResolvedURL: URL?
    private var fallbackRetried = false
    private var isObserving = false
    private var fallbackCheckTask: Task<Void, Never>?

    public init(
        controller: any VideoPlayerControlling,
        metadata: VideoMediaMetadata,
        playbackStateStore: (any VideoPlaybackStateStoring)? = nil,
        nowPlayingPublisher: (any VideoNowPlayingPublishing)? = nil,
        remoteCommandStream: (any VideoRemoteCommandStreaming)? = nil,
        mediaSessionManager: (any VideoMediaSessionManaging)? = nil,
        gatewayResolver: (any VideoGatewayResolving)? = nil,
        pictureInPictureController: (any VideoPictureInPictureControlling)? = nil,
        coordinatedPlaybackConfiguration: VideoCoordinatedPlaybackConfiguration? = nil,
        bufferingPolicy: VideoBufferingPolicy = VideoBufferingPolicy(),
        stallFallbackCoordinator: StallFallbackCoordinator = StallFallbackCoordinator(),
        logger: VideoEngineLogging = NoOpVideoEngineLogger()
    ) {
        self.controller = controller
        self.metadata = metadata
        self.playbackStateStore = playbackStateStore
        self.nowPlayingPublisher = nowPlayingPublisher
        self.remoteCommandStream = remoteCommandStream
        self.mediaSessionManager = mediaSessionManager
        self.gatewayResolver = gatewayResolver
        self.coordinatedPlaybackConfiguration = coordinatedPlaybackConfiguration
        self.bufferingPolicy = bufferingPolicy
        self.stallFallbackCoordinator = stallFallbackCoordinator
        self.logger = logger
        self.persistenceCoordinator = playbackStateStore.map {
            VideoPositionPersistenceCoordinator(mediaID: metadata.id, store: $0)
        }
    }

    deinit {
        tasks.forEach { $0.cancel() }
        fallbackCheckTask?.cancel()
    }

    @discardableResult
    public func load(media: some VideoPlayableMedia) async throws -> StoredVideoPlaybackPosition? {
        try await mediaSessionManager?.configureForPlayback()
        currentResolvedURL = media.resolvedPlaybackURL
        fallbackRetried = false
        let storedPosition = try await playbackStateStore?.storedPosition(for: media.videoMediaID)
        try await controller.load(media: media)
        return resumablePosition(from: storedPosition)
    }

    public func startObserving(observesPlaybackEvents: Bool = true) {
        guard !isObserving else { return }
        isObserving = true

        if observesPlaybackEvents {
            let events = controller.events
            tasks.append(Task { [weak self] in
                for await event in events {
                    if Task.isCancelled { return }
                    guard let self else { return }
                    await self.handlePlaybackEvent(event)
                }
            })
        }

        if let remoteCommandStream {
            let commands = remoteCommandStream.events
            tasks.append(Task { [weak self] in
                for await command in commands {
                    if Task.isCancelled { return }
                    guard let self else { return }
                    await self.handleRemoteCommand(command)
                }
            })
        }

        if let mediaSessionManager {
            let events = mediaSessionManager.events
            tasks.append(Task { [weak self] in
                for await event in events {
                    if Task.isCancelled { return }
                    guard let self else { return }
                    await self.handleMediaSessionEvent(event)
                }
            })
        }
    }

    public func stop() async {
        await flushPosition()
        if let nowPlayingPublisher {
            await nowPlayingPublisher.clear(metadataID: metadata.id)
        }
        tasks.forEach { $0.cancel() }
        tasks.removeAll()
        fallbackCheckTask?.cancel()
        fallbackCheckTask = nil
        isObserving = false
        controller.teardown()
    }

    public func flushCurrentPosition() async {
        await flushPosition()
    }

    public func flushCurrentPosition(_ tick: PlaybackTick) async {
        latestTick = tick
        await flushPosition()
    }

    public func handlePlaybackEvent(_ event: VideoPlaybackEvent) async {
        switch event {
        case .tick(let tick):
            latestTick = tick
            await persistTickIfNeeded(tick)
            await nowPlayingPublisher?.publish(
                metadata: metadata,
                tick: tick,
                isPlaying: controller.state == .playing
            )
        case .didPlayToEnd:
            await markCompleted()
        case .playbackStalled:
            await scheduleGatewayFallbackCheck()
        case .failedToPlayToEnd(let message):
            logger.error(message ?? "Video failed to play to end.")
        case .stateChanged, .externalPlaybackChanged, .waitingReasonChanged:
            break
        }
    }

    private func handleRemoteCommand(_ command: VideoRemoteCommand) async {
        await command.dispatch(to: self)
    }

    private func handleMediaSessionEvent(_ event: VideoMediaSessionEvent) async {
        switch event {
        case .shouldPause:
            controller.pause()
            await flushPosition()
        case .interruptionEndedShouldResume:
            controller.play()
        case .enteredBackground:
            await flushPosition()
        case .willStop:
            await flushPosition()
        }
    }

    private func persistTickIfNeeded(_ tick: PlaybackTick) async {
        do {
            try await persistenceCoordinator?.handleTick(tick, isPlaying: controller.state == .playing)
        } catch {
            logger.error("Failed to persist video position: \(error.localizedDescription)")
        }
    }

    private func flushPosition() async {
        do {
            try await persistenceCoordinator?.flush(latestTick)
        } catch {
            logger.error("Failed to flush video position: \(error.localizedDescription)")
        }
    }

    private func markCompleted() async {
        do {
            try await persistenceCoordinator?.markCompleted()
        } catch {
            logger.error("Failed to mark video complete: \(error.localizedDescription)")
        }
    }

    private func scheduleGatewayFallbackCheck() async {
        let stalledAt = latestTick.currentSeconds
        let threshold = stallFallbackCoordinator.thresholdSeconds

        fallbackCheckTask?.cancel()
        fallbackCheckTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(threshold))
            await self?.attemptGatewayFallback(stalledAtSeconds: stalledAt)
        }
    }

    private func attemptGatewayFallback(stalledAtSeconds: Double) async {
        defer { fallbackCheckTask = nil }
        guard controller.state == .buffering else { return }
        guard latestTick.currentSeconds <= stalledAtSeconds else { return }
        guard let currentResolvedURL else { return }

        let decision = stallFallbackCoordinator.decision(
            stalledDuration: stallFallbackCoordinator.thresholdSeconds,
            isGatewayURL: bufferingPolicy.isGatewayURL(currentResolvedURL),
            hasAlreadyRetried: fallbackRetried,
            lastKnownSeconds: stalledAtSeconds
        )
        guard decision.shouldAttemptFallback else { return }
        guard let gatewayResolver else { return }

        do {
            guard let nextURL = try await gatewayResolver.nextResolvedURL(after: currentResolvedURL) else { return }
            fallbackRetried = true
            self.currentResolvedURL = nextURL
            try await controller.load(resolvedURL: nextURL)
            await controller.seek(to: decision.resumeSeconds, kind: .resume)
            controller.play()
        } catch {
            logger.error("Gateway video fallback failed: \(error.localizedDescription)")
        }
    }

    private func resumablePosition(from storedPosition: StoredVideoPlaybackPosition?) -> StoredVideoPlaybackPosition? {
        guard let storedPosition else { return nil }
        guard storedPosition.positionMilliseconds > 5_000 else { return nil }
        if let durationMilliseconds = storedPosition.durationMilliseconds,
           durationMilliseconds - storedPosition.positionMilliseconds <= 5_000 {
            return nil
        }
        return storedPosition
    }
}

extension VideoPlaybackIntegrationCoordinator: MediaTransportControlling {
    public var isPlaying: Bool {
        controller.state == .playing
    }

    public var currentTime: TimeInterval {
        latestTick.currentSeconds
    }

    public func play() async {
        controller.play()
    }

    public func pause() async {
        controller.pause()
        await flushPosition()
    }

    public func seek(to seconds: TimeInterval) async {
        await controller.seek(to: seconds, kind: .scrub)
    }

    public func skipForward(by seconds: TimeInterval) async {
        await controller.seek(to: latestTick.currentSeconds + seconds, kind: .skip)
    }

    public func skipBackward(by seconds: TimeInterval) async {
        await controller.seek(to: max(0, latestTick.currentSeconds - seconds), kind: .skip)
    }

    public func next() async {}

    public func previous() async {}
}
