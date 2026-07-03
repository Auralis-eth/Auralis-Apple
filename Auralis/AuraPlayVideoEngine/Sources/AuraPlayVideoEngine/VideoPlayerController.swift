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
    public let events: AsyncStream<VideoPlaybackEvent>
    public private(set) var state: VideoPlaybackState = .idle
    public private(set) var waitingReason: VideoWaitingReason?

    private let eventContinuation: AsyncStream<VideoPlaybackEvent>.Continuation
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
    private var periodicTimeObserver: Any?
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

        var continuation: AsyncStream<VideoPlaybackEvent>.Continuation!
        self.events = AsyncStream { continuation = $0 }
        self.eventContinuation = continuation

        configurePlayer()
        registerPlayerObservers()
        registerPeriodicTimeObserver()
    }

    deinit {
        MainActor.assumeIsolated {
            teardown()
            eventContinuation.finish()
        }
    }

    public func load(resolvedURL: URL) async throws {
        try validator.validateResolvedPlaybackURL(resolvedURL)
        restoreObservationIfNeeded()
        isTornDown = false
        updateState(.loading(resolvedURL))

        let item = try await assetLoader.playerItem(
            for: resolvedURL,
            plan: assetLoadPlan,
            bufferingPolicy: bufferingPolicy,
            resourceLoaderDelegate: resourceLoaderDelegate
        )
        selectedPlaybackSpeed = playbackSpeedController.storedSpeed
        item.audioTimePitchAlgorithm = selectedPlaybackSpeed.pitchAlgorithm
        replaceCurrentItem(with: item)
    }

    public func load(media: some VideoPlayableMedia) async throws {
        try await load(resolvedURL: media.resolvedPlaybackURL)
    }

    public func play() {
        isTornDown = false
        selectedPlaybackSpeed = playbackSpeedController.storedSpeed
        player.currentItem?.audioTimePitchAlgorithm = selectedPlaybackSpeed.pitchAlgorithm
        player.rate = Float(selectedPlaybackSpeed.rawValue)
        updateState(.playing)
    }

    public func pause() {
        player.pause()
        updateState(.paused)
    }

    public func seek(to seconds: Double, kind: VideoSeekKind) async {
        await seekCoordinator.requestSeek(to: seconds, tolerance: kind.tolerance) { [weak self] targetSeconds, tolerance in
            await self?.performSeek(to: targetSeconds, tolerance: tolerance) ?? false
        }
    }

    public func teardown() {
        guard !isTornDown else { return }
        isTornDown = true

        if let periodicTimeObserver {
            timeObserverRegistrar.removeTimeObserver(periodicTimeObserver)
            self.periodicTimeObserver = nil
        }

        itemObserverBag.invalidate()
        playerObserverBag.invalidate()
        player.replaceCurrentItem(with: nil)
        updateState(.idle)
    }

    private func configurePlayer() {
        player.allowsExternalPlayback = true
        player.usesExternalPlaybackWhileExternalScreenIsActive = true
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

        playerObserverBag.store(player.observe(\.isExternalPlaybackActive, options: [.initial, .new]) { [weak self] player, _ in
            Task { @MainActor [weak self] in
                self?.eventContinuation.yield(.externalPlaybackChanged(player.isExternalPlaybackActive))
            }
        })
    }

    private func registerPeriodicTimeObserver() {
        guard periodicTimeObserver == nil else { return }
        let interval = CMTime(seconds: 1.0 / 60.0, preferredTimescale: 600)
        periodicTimeObserver = timeObserverRegistrar.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            Task { @MainActor [weak self] in
                self?.publishTick(currentTime: time)
            }
        }
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
                self?.eventContinuation.yield(.didPlayToEnd)
            }
        })

        itemObserverBag.storeNotification(center.addObserver(
            forName: .AVPlayerItemFailedToPlayToEndTime,
            object: item,
            queue: .main
        ) { [weak self] notification in
            let message = (notification.userInfo?[AVPlayerItemFailedToPlayToEndTimeErrorKey] as? Error)?.localizedDescription
            Task { @MainActor [weak self] in
                self?.eventContinuation.yield(.failedToPlayToEnd(message))
            }
        })

        itemObserverBag.storeNotification(center.addObserver(
            forName: .AVPlayerItemPlaybackStalled,
            object: item,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.updateState(.buffering)
                self?.eventContinuation.yield(.playbackStalled)
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
        eventContinuation.yield(.tick(tick))
    }

    private func durationSeconds() -> Double? {
        player.currentItem?.duration.validOptionalSeconds
    }

    private func updateState(_ newState: VideoPlaybackState) {
        guard state != newState else { return }
        state = newState
        eventContinuation.yield(.stateChanged(newState))
    }

    private func updateWaitingReason(_ newReason: VideoWaitingReason?) {
        guard waitingReason != newReason else { return }
        waitingReason = newReason
        eventContinuation.yield(.waitingReasonChanged(newReason))
    }

    private func restoreObservationIfNeeded() {
        guard isTornDown else { return }
        registerPlayerObservers()
        registerPeriodicTimeObserver()
    }
}

@MainActor
protocol VideoTimeObserverRegistering: AnyObject {
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
