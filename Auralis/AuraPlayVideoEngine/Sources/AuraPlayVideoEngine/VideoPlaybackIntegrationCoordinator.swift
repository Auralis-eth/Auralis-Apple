import AVFoundation
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
    private let bufferingPolicy: VideoBufferingPolicy
    private let stallFallbackCoordinator: StallFallbackCoordinator
    private let logger: VideoEngineLogging

    private var tasks: [Task<Void, Never>] = []
    private var persistenceCoordinator: VideoPositionPersistenceCoordinator?
    private var latestTick = PlaybackTick(currentSeconds: 0, durationSeconds: nil)
    private var currentResolvedURL: URL?
    private var fallbackRetried = false
    private var isObserving = false

    public init(
        controller: any VideoPlayerControlling,
        metadata: VideoMediaMetadata,
        playbackStateStore: (any VideoPlaybackStateStoring)? = nil,
        nowPlayingPublisher: (any VideoNowPlayingPublishing)? = nil,
        remoteCommandStream: (any VideoRemoteCommandStreaming)? = nil,
        mediaSessionManager: (any VideoMediaSessionManaging)? = nil,
        gatewayResolver: (any VideoGatewayResolving)? = nil,
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
        self.bufferingPolicy = bufferingPolicy
        self.stallFallbackCoordinator = stallFallbackCoordinator
        self.logger = logger
        self.persistenceCoordinator = playbackStateStore.map {
            VideoPositionPersistenceCoordinator(mediaID: metadata.id, store: $0)
        }
    }

    deinit {
        tasks.forEach { $0.cancel() }
    }

    @discardableResult
    public func load(media: some VideoPlayableMedia) async throws -> StoredVideoPlaybackPosition? {
        try await mediaSessionManager?.configureForVideoPlayback()
        currentResolvedURL = media.resolvedPlaybackURL
        fallbackRetried = false
        let storedPosition = try await playbackStateStore?.storedPosition(for: media.videoMediaID)
        try await controller.load(media: media)
        return resumablePosition(from: storedPosition)
    }

    public func startObserving() {
        guard !isObserving else { return }
        isObserving = true

        tasks.append(Task { [weak self] in
            await self?.observePlaybackEvents()
        })

        if let remoteCommandStream {
            tasks.append(Task { [weak self] in
                await self?.observeRemoteCommands(remoteCommandStream.commands)
            })
        }

        if let mediaSessionManager {
            tasks.append(Task { [weak self] in
                await self?.observeMediaSessionEvents(mediaSessionManager.events)
            })
        }
    }

    public func stop() async {
        await flushPosition()
        if let nowPlayingPublisher {
            await nowPlayingPublisher.clearVideo(metadataID: metadata.id)
        }
        tasks.forEach { $0.cancel() }
        tasks.removeAll()
        isObserving = false
        controller.teardown()
    }

    private func observePlaybackEvents() async {
        for await event in controller.events {
            if Task.isCancelled { return }
            await handlePlaybackEvent(event)
        }
    }

    private func observeRemoteCommands(_ commands: AsyncStream<VideoRemoteCommand>) async {
        for await command in commands {
            if Task.isCancelled { return }
            await handleRemoteCommand(command)
        }
    }

    private func observeMediaSessionEvents(_ events: AsyncStream<VideoMediaSessionEvent>) async {
        for await event in events {
            if Task.isCancelled { return }
            await handleMediaSessionEvent(event)
        }
    }

    private func handlePlaybackEvent(_ event: VideoPlaybackEvent) async {
        switch event {
        case .tick(let tick):
            latestTick = tick
            await persistTickIfNeeded(tick)
            await nowPlayingPublisher?.publishVideo(
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
        switch command {
        case .play:
            controller.play()
        case .pause:
            controller.pause()
            await flushPosition()
        case .skipForward(let seconds):
            await controller.seek(to: latestTick.currentSeconds + seconds, kind: .skip)
        case .skipBackward(let seconds):
            await controller.seek(to: max(0, latestTick.currentSeconds - seconds), kind: .skip)
        case .seek(let seconds):
            await controller.seek(to: seconds, kind: .scrub)
        }
    }

    private func handleMediaSessionEvent(_ event: VideoMediaSessionEvent) async {
        switch event {
        case .shouldPause:
            controller.pause()
            await flushPosition()
        case .interruptionEndedShouldResume:
            controller.play()
        case .enteredBackground, .willStop:
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

        tasks.append(Task { [weak self] in
            try? await Task.sleep(for: .seconds(threshold))
            await self?.attemptGatewayFallback(stalledAtSeconds: stalledAt)
        })
    }

    private func attemptGatewayFallback(stalledAtSeconds: Double) async {
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
