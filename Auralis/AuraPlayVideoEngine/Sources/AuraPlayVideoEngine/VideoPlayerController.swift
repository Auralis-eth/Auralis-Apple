import AVFoundation
import Foundation

@MainActor
public protocol VideoPlayerControlling: AnyObject {
    var player: AVPlayer { get }
    var events: AsyncStream<VideoPlaybackEvent> { get }
    var state: VideoPlaybackState { get }
    var waitingReason: VideoWaitingReason? { get }

    func load(resolvedURL: URL) async throws
    func load(media: some VideoPlayableMedia) async throws
    func play()
    func pause()
    func seek(to seconds: Double, kind: VideoSeekKind) async
    func teardown()
}

@MainActor
public final class VideoPlayerController: VideoPlayerControlling {
    public let player: AVPlayer
    public private(set) var state: VideoPlaybackState = .idle
    public private(set) var waitingReason: VideoWaitingReason?

    /// Each access returns an independent stream, so multiple observers (integration
    /// coordinator, queue controller, UI) each receive every event emitted after the
    /// stream is created. Events are not replayed to late subscribers.
    public var events: AsyncStream<VideoPlaybackEvent> {
        eventHub.makeStream()
    }

    private let eventHub = PlaybackEventHub()
    private let validator: VideoFormatValidator
    private let bufferingPolicy: VideoBufferingPolicy
    private let assetLoader: VideoAssetLoader
    private let assetLoadPlan: VideoAssetLoadPlan
    private let resourceLoaderDelegate: VideoAssetResourceLoaderDelegate?
    private let playbackSpeedController: PlaybackSpeedController
    private let timeObserverRegistrar: any VideoTimeObserverRegistering
    private let seekCoordinator = ChaseTimeSeekCoordinator()
    private let playerObserverBag = ObserverBag()
    private let itemObserverBag = ObserverBag()
    private var periodicTimeObserver: PeriodicTimeObserver?
    private var selectedPlaybackSpeed: PlaybackSpeedOption
    private var isTornDown = false

    public convenience init(
        player: AVPlayer = AVPlayer(),
        validator: VideoFormatValidator = VideoFormatValidator(),
        bufferingPolicy: VideoBufferingPolicy = VideoBufferingPolicy(),
        assetLoader: VideoAssetLoader = VideoAssetLoader(),
        assetLoadPlan: VideoAssetLoadPlan = VideoAssetLoadPlan(preloadKeys: []),
        resourceLoaderDelegate: VideoAssetResourceLoaderDelegate? = nil,
        progressiveCachingPipeline: ProgressiveVideoCachingPipeline? = nil,
        offlineManifestStore: VideoOfflineManifestStoring? = nil,
        playbackSpeedController: PlaybackSpeedController = PlaybackSpeedController()
    ) {
        let resolvedAssetLoader: VideoAssetLoader
        if let progressiveCachingPipeline {
            resolvedAssetLoader = VideoAssetLoader(
                urlMapper: progressiveCachingPipeline,
                offlineManifestStore: offlineManifestStore
            )
        } else if let offlineManifestStore {
            resolvedAssetLoader = VideoAssetLoader(offlineManifestStore: offlineManifestStore)
        } else {
            resolvedAssetLoader = assetLoader
        }

        self.init(
            player: player,
            validator: validator,
            bufferingPolicy: bufferingPolicy,
            assetLoader: resolvedAssetLoader,
            assetLoadPlan: assetLoadPlan,
            resourceLoaderDelegate: resourceLoaderDelegate,
            playbackSpeedController: playbackSpeedController,
            timeObserverRegistrar: AVPlayerTimeObserverRegistrar(player: player)
        )
    }

    init(
        player: AVPlayer = AVPlayer(),
        validator: VideoFormatValidator = VideoFormatValidator(),
        bufferingPolicy: VideoBufferingPolicy = VideoBufferingPolicy(),
        assetLoader: VideoAssetLoader = VideoAssetLoader(),
        assetLoadPlan: VideoAssetLoadPlan = VideoAssetLoadPlan(preloadKeys: []),
        resourceLoaderDelegate: VideoAssetResourceLoaderDelegate? = nil,
        playbackSpeedController: PlaybackSpeedController = PlaybackSpeedController(),
        timeObserverRegistrar: any VideoTimeObserverRegistering
    ) {
        self.player = player
        self.validator = validator
        self.bufferingPolicy = bufferingPolicy
        self.assetLoader = assetLoader
        self.assetLoadPlan = assetLoadPlan
        self.resourceLoaderDelegate = resourceLoaderDelegate
        self.playbackSpeedController = playbackSpeedController
        self.selectedPlaybackSpeed = playbackSpeedController.storedSpeed
        self.timeObserverRegistrar = timeObserverRegistrar

        configurePlayer()
        registerPlayerObservers()
        registerPeriodicTimeObserver()
    }

    deinit {
        let eventHub = eventHub
        let periodicTimeObserver = periodicTimeObserver
        let timeObserverRegistrar = timeObserverRegistrar
        Task { @MainActor in
            eventHub.finish()
            if let periodicTimeObserver {
                timeObserverRegistrar.removeTimeObserver(periodicTimeObserver.rawValue)
            }
        }
    }

    public func load(resolvedURL: URL) async throws {
        guard !isTornDown else {
            throw VideoPlaybackError.controllerTornDown
        }
        try validator.validateResolvedPlaybackURL(resolvedURL)
        updateState(.loading(resolvedURL))

        let item: AVPlayerItem
        do {
            item = try await assetLoader.playerItem(
                for: resolvedURL,
                plan: assetLoadPlan,
                bufferingPolicy: bufferingPolicy,
                resourceLoaderDelegate: resourceLoaderDelegate
            )
        } catch {
            updateState(.failed(.videoLoadFailed(error.localizedDescription)))
            throw error
        }
        selectedPlaybackSpeed = playbackSpeedController.storedSpeed
        item.audioTimePitchAlgorithm = selectedPlaybackSpeed.pitchAlgorithm
        replaceCurrentItem(with: item)
    }

    public func load(media: some VideoPlayableMedia) async throws {
        try await load(resolvedURL: media.resolvedPlaybackURL)
    }

    public func play() {
        guard !isTornDown else { return }
        if state == .ended {
            // Await the restart seek so playback deterministically resumes from zero.
            Task { @MainActor [weak self] in
                guard let self else { return }
                _ = await self.performSeek(to: 0, tolerance: VideoSeekKind.resume.tolerance)
                guard !self.isTornDown, self.state == .ended else { return }
                self.beginPlayback()
            }
            return
        }
        beginPlayback()
    }

    private func beginPlayback() {
        selectedPlaybackSpeed = playbackSpeedController.storedSpeed
        player.currentItem?.audioTimePitchAlgorithm = selectedPlaybackSpeed.pitchAlgorithm
        player.rate = Float(selectedPlaybackSpeed.rawValue)
        updateState(.playing)
    }

    public func pause() {
        guard !isTornDown else { return }
        player.pause()
        updateState(.paused)
    }

    public func seek(to seconds: Double, kind: VideoSeekKind) async {
        guard !isTornDown else { return }
        await seekCoordinator.requestSeek(to: seconds, tolerance: kind.tolerance) { [weak self] targetSeconds, tolerance in
            await self?.performSeek(to: targetSeconds, tolerance: tolerance) ?? false
        }
    }

    public func teardown() {
        guard !isTornDown else { return }
        isTornDown = true

        if let periodicTimeObserver {
            timeObserverRegistrar.removeTimeObserver(periodicTimeObserver.rawValue)
            self.periodicTimeObserver = nil
        }

        itemObserverBag.invalidate()
        playerObserverBag.invalidate()
        player.replaceCurrentItem(with: nil)
        updateState(.idle)
        eventHub.finish()
    }

    private func configurePlayer() {
        #if !os(visionOS)
        player.allowsExternalPlayback = true
        #endif
        #if os(iOS) || os(tvOS)
        player.usesExternalPlaybackWhileExternalScreenIsActive = true
        #endif
        player.automaticallyWaitsToMinimizeStalling = true
    }

    private func registerPlayerObservers() {
        playerObserverBag.store(player.observe(\.timeControlStatus, options: [.initial, .new]) { [weak self] player, _ in
            Task { @MainActor [weak self] in
                self?.handleTimeControlStatus(player.timeControlStatus)
            }
        })

        playerObserverBag.store(player.observe(\.reasonForWaitingToPlay, options: [.initial, .new]) { [weak self] player, _ in
            Task { @MainActor [weak self] in
                self?.updateWaitingReason(player.reasonForWaitingToPlay.map(VideoWaitingReason.init))
            }
        })

        playerObserverBag.store(player.observe(\.rate, options: [.new]) { [weak self] player, _ in
            Task { @MainActor [weak self] in
                if player.rate == 0, self?.state == .playing {
                    self?.updateState(.paused)
                }
            }
        })

        #if !os(visionOS)
        playerObserverBag.store(player.observe(\.isExternalPlaybackActive, options: [.initial, .new]) { [weak self] player, _ in
            Task { @MainActor [weak self] in
                self?.eventHub.yield(.externalPlaybackChanged(player.isExternalPlaybackActive))
            }
        })
        #endif
    }

    private func registerPeriodicTimeObserver() {
        guard periodicTimeObserver == nil else { return }
        let interval = CMTime(seconds: 1.0 / 60.0, preferredTimescale: 600)
        let observer = timeObserverRegistrar.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            MainActor.assumeIsolated {
                self?.publishTick(currentTime: time)
            }
        }
        periodicTimeObserver = PeriodicTimeObserver(rawValue: observer)
    }

    private func replaceCurrentItem(with item: AVPlayerItem) {
        itemObserverBag.invalidate()
        player.replaceCurrentItem(with: item)
        registerObservers(for: item)
    }

    private func registerObservers(for item: AVPlayerItem) {
        itemObserverBag.store(item.observe(\.status, options: [.initial, .new]) { [weak self] item, _ in
            Task { @MainActor [weak self] in
                self?.handleItemStatus(item.status, error: item.error)
            }
        })

        let center = NotificationCenter.default
        itemObserverBag.storeNotification(center.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: item,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.updateState(.ended)
                self?.eventHub.yield(.didPlayToEnd)
            }
        })

        itemObserverBag.storeNotification(center.addObserver(
            forName: .AVPlayerItemFailedToPlayToEndTime,
            object: item,
            queue: .main
        ) { [weak self] notification in
            let message = (notification.userInfo?[AVPlayerItemFailedToPlayToEndTimeErrorKey] as? Error)?.localizedDescription
            Task { @MainActor [weak self] in
                self?.eventHub.yield(.failedToPlayToEnd(message))
            }
        })

        itemObserverBag.storeNotification(center.addObserver(
            forName: .AVPlayerItemPlaybackStalled,
            object: item,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.updateState(.buffering)
                self?.eventHub.yield(.playbackStalled)
            }
        })
    }

    private func handleItemStatus(_ status: AVPlayerItem.Status, error: Error?) {
        switch status {
        case .readyToPlay:
            updateState(.ready(durationSeconds: durationSeconds()))
        case .failed:
            updateState(.failed(.videoLoadFailed(error?.localizedDescription)))
        case .unknown:
            break
        @unknown default:
            break
        }
    }

    private func handleTimeControlStatus(_ status: AVPlayer.TimeControlStatus) {
        switch status {
        case .waitingToPlayAtSpecifiedRate:
            updateState(.buffering)
        case .playing:
            updateState(.playing)
        case .paused:
            if state == .playing || state == .buffering {
                updateState(.paused)
            }
        @unknown default:
            break
        }
    }

    private func performSeek(to seconds: Double, tolerance: VideoSeekTolerance) async -> Bool {
        guard player.currentItem != nil else { return false }
        let target = CMTime(seconds: seconds, preferredTimescale: 600)

        return await withCheckedContinuation { continuation in
            player.seek(
                to: target,
                toleranceBefore: tolerance.beforeTime,
                toleranceAfter: tolerance.afterTime
            ) { finished in
                continuation.resume(returning: finished)
            }
        }
    }

    private func publishTick(currentTime: CMTime) {
        let tick = PlaybackTick(
            currentSeconds: currentTime.validSeconds,
            durationSeconds: durationSeconds()
        )
        eventHub.yield(.tick(tick))
    }

    private func durationSeconds() -> Double? {
        player.currentItem?.duration.validOptionalSeconds
    }

    private func updateState(_ newState: VideoPlaybackState) {
        guard state != newState else { return }
        state = newState
        eventHub.yield(.stateChanged(newState))
    }

    private func updateWaitingReason(_ newReason: VideoWaitingReason?) {
        guard waitingReason != newReason else { return }
        waitingReason = newReason
        eventHub.yield(.waitingReasonChanged(newReason))
    }
}

@MainActor
protocol VideoTimeObserverRegistering: AnyObject, Sendable {
    func addPeriodicTimeObserver(
        forInterval interval: CMTime,
        queue: DispatchQueue?,
        using block: @escaping @Sendable (CMTime) -> Void
    ) -> Any

    func removeTimeObserver(_ observer: Any)
}

@MainActor
private final class AVPlayerTimeObserverRegistrar: VideoTimeObserverRegistering {
    private let player: AVPlayer

    init(player: AVPlayer) {
        self.player = player
    }

    func addPeriodicTimeObserver(
        forInterval interval: CMTime,
        queue: DispatchQueue?,
        using block: @escaping @Sendable (CMTime) -> Void
    ) -> Any {
        player.addPeriodicTimeObserver(forInterval: interval, queue: queue, using: block)
    }

    func removeTimeObserver(_ observer: Any) {
        player.removeTimeObserver(observer)
    }
}

private struct PeriodicTimeObserver: @unchecked Sendable {
    let rawValue: Any
}

/// Multicasts playback events so any number of observers can consume
/// `VideoPlayerController.events` concurrently. Each stream keeps only
/// the newest 120 events so unconsumed 60fps ticks cannot grow unbounded.
@MainActor
final class PlaybackEventHub {
    private var continuations: [UUID: AsyncStream<VideoPlaybackEvent>.Continuation] = [:]
    private var isFinished = false

    func makeStream() -> AsyncStream<VideoPlaybackEvent> {
        AsyncStream(bufferingPolicy: .bufferingNewest(120)) { continuation in
            guard !isFinished else {
                continuation.finish()
                return
            }
            let id = UUID()
            continuations[id] = continuation
            continuation.onTermination = { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.continuations[id] = nil
                }
            }
        }
    }

    func yield(_ event: VideoPlaybackEvent) {
        for continuation in continuations.values {
            continuation.yield(event)
        }
    }

    func finish() {
        isFinished = true
        let active = continuations.values
        continuations.removeAll()
        for continuation in active {
            continuation.finish()
        }
    }
}

private extension CMTime {
    var validSeconds: Double {
        guard isNumeric, seconds.isFinite else { return 0 }
        return seconds
    }

    var validOptionalSeconds: Double? {
        guard isNumeric, seconds.isFinite else { return nil }
        return seconds
    }
}
