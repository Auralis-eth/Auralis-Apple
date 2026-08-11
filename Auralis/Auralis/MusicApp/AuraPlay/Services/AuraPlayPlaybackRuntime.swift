import AuraPlayAudioEngine
import AuraPlayMediaCore
import AuraPlayVideoEngine
import AuralisPrimaryModels
import AuralisPrimaryPersistence
import AVFoundation
import Foundation
import MusicFeature
import Observation
import SwiftData
import SwiftUI

@MainActor
protocol AuraPlayVideoRemoteControlling: AnyObject {
    var currentPosition: TimeInterval { get }
    var playerVideoCapabilities: AuraPlayPlayerVideoCapabilities? { get }
    var playerVideoSurface: AnyView? { get }
    var playerVideoRoutePicker: AnyView? { get }

    func play()
    func pause()
    func togglePlayPause()
    func load(_ item: AuraPlayableMediaItem) async throws
    func seek(to seconds: TimeInterval) async
    func skipToNext() async
    func skipToPrevious() async
    func stopForAudioHandoff() async
    func startPiP()
    func stopPiP()
    func restorePiP()
    func selectSubtitle(_ title: String?) async
    func setPlaybackSpeed(_ speed: Double) async
    func toggleVideoGravity() async
}

@MainActor
@Observable
public final class AuraPlayPlaybackRuntime: AuraPlayPlaybackControlling, AuraPlayPlaybackPresenting, AuraPlayPlaybackItemPresenting, AuraPlayPlaybackModePresenting, AuraPlayPlayerVideoPresenting, AuraPlayPlayerVideoSurfacePresenting, AuraPlayQueueCoordinating {
    @ObservationIgnored private let engineController: AudioEngineController
    @ObservationIgnored private let cacheManager: MediaCacheManager
    @ObservationIgnored private let scheduler: GaplessScheduler
    @ObservationIgnored private let autoMixController: AutoMixController
    @ObservationIgnored private let audioSessionManager: AudioSessionManager
    @ObservationIgnored private let recoveryCoordinator: EngineRecoveryCoordinator
    @ObservationIgnored private let nowPlayingPublisher: NowPlayingPublisher
    @ObservationIgnored private let remoteCommandPublisher: RemoteCommandPublisher
    @ObservationIgnored private let playbackOrchestrator: PlaybackOrchestrator
    @ObservationIgnored private let audioOrchestratorController: RuntimeAudioOrchestratorController
    @ObservationIgnored private let videoOrchestratorController: RuntimeVideoOrchestratorController
    @ObservationIgnored fileprivate weak var videoRemoteControls: (any AuraPlayVideoRemoteControlling)?
    @ObservationIgnored private var openVideoPlayer: (@MainActor () -> Void)?
    @ObservationIgnored private var phase8ActiveEngine: EngineKind?
    @ObservationIgnored private var lastPlaybackPositionWriteSeconds: [String: TimeInterval] = [:]
    @ObservationIgnored private var orchestratedNFTs: [String: NFT] = [:]
    @ObservationIgnored private var libraryQueueSeed: [NFT] = []
    @ObservationIgnored private var libraryQueueCursor: Int?
    @ObservationIgnored private var libraryQueueQueryContext: MediaItemQueryContext?
    @ObservationIgnored private var libraryQueueNextOffset: Int?
    @ObservationIgnored private var libraryQueueExtender: (any AuraPlayQueueExtending)?
    @ObservationIgnored private var libraryQueueNFTResolver: (@MainActor ([String]) -> [NFT])?
    @ObservationIgnored private var libraryQueueExtensionTask: Task<Void, Never>?
    @ObservationIgnored private var didAttemptSessionRestore = false
    @ObservationIgnored private var currentNFT: NFT?
    @ObservationIgnored private var currentMedia: NFTPlayableMedia?
    @ObservationIgnored private var currentLoadTask: Task<Void, Error>?
    @ObservationIgnored private var playbackGeneration = 0
    @ObservationIgnored private var displayUpdateTask: Task<Void, Never>?
    @ObservationIgnored private var cacheProgressTask: Task<Void, Never>?
    @ObservationIgnored private var loudnessMeasurementTask: Task<Void, Never>?
    @ObservationIgnored private var remoteCommandTask: Task<Void, Never>?
    @ObservationIgnored private var recoveryEventTask: Task<Void, Never>?
    @ObservationIgnored private var visualizationTask: Task<Void, Never>?
    @ObservationIgnored private var underrunRecoveryTask: Task<Void, Never>?
    @ObservationIgnored private var musicReceiptLogger: MusicReceiptEventLogger?
    @ObservationIgnored private var pendingPlaybackTriggerCause: MusicReceiptTriggerCause?
    @ObservationIgnored private var mediaResolver: GatewayFallbackChain?
    @ObservationIgnored private var mediaGatewayHosts: Set<String> = []
    @ObservationIgnored private var auraPlayModelContainer: ModelContainer?
    @ObservationIgnored private let skipInterval: TimeInterval = 15
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private var selectedEQPreset: AuraPlayEQPresetID
    @ObservationIgnored private var customEQGains: [Float]
    @ObservationIgnored private var normalizationEnabled: Bool
    @ObservationIgnored private var smartShuffleEnabled: Bool
    @ObservationIgnored private var crossfadeDuration: Double
    @ObservationIgnored private var currentApproxLoudnessLUFS: Double?
    @ObservationIgnored private var currentArtworkData: Data?
    @ObservationIgnored private var preparedTransitionNFT: NFT?
    @ObservationIgnored private var preparedTransitionMedia: NFTPlayableMedia?
    @ObservationIgnored private var preparedTransitionDuration: TimeInterval = 0
    @ObservationIgnored private var lastTransitionQuality: TransitionQuality?
    @ObservationIgnored private var lastRecoveryStatus = "Ready"
    @ObservationIgnored private var lastObservedFrame: AVAudioFramePositionValue = 0
    @ObservationIgnored private var stalledFrameObservationCount = 0
    @ObservationIgnored private var observedAutomaticTransitionCount = 0
    @ObservationIgnored private var nowPlayingElapsedTickSignature: String?
    @ObservationIgnored private let libraryQueueWindowSize = 24
    @ObservationIgnored private let libraryQueueLowWatermark = 6
    @ObservationIgnored private let maxConsecutivePlaybackFailures = 3

    public var previousAudio = Playlist(name: "Previous")
    public var nextAudio = Playlist(name: "Next")
    public var playbackState: AuraPlayPlaybackState = .stopped
    public var currentTrack: AuraPlayTrack?
    public private(set) var currentTime: TimeInterval = 0
    public private(set) var cachePresentation = AuraPlayCachePresentation(
        state: .unavailable,
        progressFraction: nil,
        message: "Load a track to see offline availability.",
        canSaveOffline: false,
        canPin: false,
        canUnpin: false
    )
    public private(set) var systemIntegrationPresentation = AuraPlaySystemIntegrationPresentation(
        routeMode: "Custom Engine",
        nowPlayingStatus: "Ready",
        remoteCommandStatus: "Ready",
        spatialAudioStatus: "System route only"
    )
    public private(set) var visualizationPresentation = AuraPlayVisualizationPresentation()
    public private(set) var audioTuningPresentation = AuraPlayAudioTuningPresentation()
    public private(set) var playbackAlert: AuraPlayPlaybackAlertPresentation?

    private var currentDuration: TimeInterval = 0
    private var pausedAt: TimeInterval = 0
    private var seekPosition: TimeInterval = 0
    private var currentTrackCompletionHandled = false

    public init(
        engineController: AudioEngineController? = nil,
        cacheManager: MediaCacheManager? = nil,
        audioSessionManager: AudioSessionManager = AudioSessionManager(),
        nowPlayingPublisher: NowPlayingPublisher = NowPlayingPublisher(),
        remoteCommandPublisher: RemoteCommandPublisher = RemoteCommandPublisher(),
        defaults: UserDefaults = .standard
    ) throws {
        let resolvedEngineController = try engineController ?? AudioEngineController()
        let resolvedCacheManager = try cacheManager ?? MediaCacheManager()
        let resolvedEQPreset = AuraPlayAudioSettings.eqPreset(from: defaults)
        let resolvedCustomEQGains = AuraPlayAudioSettings.customEQGains(from: defaults)
        let resolvedNormalizationEnabled = AuraPlayAudioSettings.normalizationEnabled(from: defaults)
        let resolvedSmartShuffleEnabled = defaults.bool(
            forKey: AuraPlayIntelligenceSettings.smartShuffleEnabledDefaultsKey
        )
        let resolvedCrossfadeDuration = AuraPlayAudioSettings.crossfadeDuration(from: defaults)
        let resolvedShuffleMode = AuraPlayPlaybackPreferenceSettings.shuffleMode(from: defaults)
        let resolvedRepeatMode = AuraPlayPlaybackPreferenceSettings.repeatMode(from: defaults)
        let audioOrchestratorController = RuntimeAudioOrchestratorController()
        let videoOrchestratorController = RuntimeVideoOrchestratorController()
        let playbackStateWriter = RuntimePlaybackStateWriter()
        let playbackOrchestrator = PlaybackOrchestrator(
            arbiter: EngineArbiter(
                audioController: audioOrchestratorController,
                videoController: videoOrchestratorController
            ),
            positionPersistence: PositionPersistenceCoordinator(store: playbackStateWriter),
            queueAdvanceCoordinator: QueueAdvanceCoordinator { item in
                await resolvedCacheManager.prefetch(item)
            }
        )
        let resolvedScheduler = GaplessScheduler(
            cacheManager: resolvedCacheManager,
            engineController: resolvedEngineController
        )
        self.engineController = resolvedEngineController
        self.cacheManager = resolvedCacheManager
        self.scheduler = resolvedScheduler
        self.autoMixController = AutoMixController(
            scheduler: resolvedScheduler,
            engineController: resolvedEngineController
        )
        self.audioSessionManager = audioSessionManager
        self.recoveryCoordinator = EngineRecoveryCoordinator(
            audioSessionManager: audioSessionManager,
            engineController: resolvedEngineController
        )
        self.nowPlayingPublisher = nowPlayingPublisher
        self.remoteCommandPublisher = remoteCommandPublisher
        self.playbackOrchestrator = playbackOrchestrator
        self.audioOrchestratorController = audioOrchestratorController
        self.videoOrchestratorController = videoOrchestratorController
        self.defaults = defaults
        self.selectedEQPreset = resolvedEQPreset
        self.customEQGains = resolvedCustomEQGains
        self.normalizationEnabled = resolvedNormalizationEnabled
        self.smartShuffleEnabled = resolvedSmartShuffleEnabled
        self.crossfadeDuration = resolvedCrossfadeDuration
        self.audioTuningPresentation = AuraPlayAudioTuningPresentation(
            eqPreset: resolvedEQPreset,
            isNormalizationEnabled: resolvedNormalizationEnabled,
            crossfadeDuration: resolvedCrossfadeDuration,
            customEQGains: resolvedCustomEQGains
        )
        playbackOrchestrator.setShuffleMode(resolvedShuffleMode)
        playbackOrchestrator.setRepeatMode(resolvedRepeatMode)
        startCacheProgressUpdates()
        startLoudnessMeasurementUpdates()
        startRecoveryUpdates()
        audioOrchestratorController.attach(runtime: self)
        videoOrchestratorController.attach(runtime: self)
        playbackStateWriter.attach(runtime: self)
        applySmartShuffleSetting()
        bindRemoteCommands()

        Task { [weak self] in
            guard let self else { return }
            try? await self.audioSessionManager.configure()
            try? await self.audioSessionManager.activate()
            self.recoveryCoordinator.start()
            await self.engineController.applyEQPreset(self.engineEQPreset)
            await self.engineController.applyNormalizationGain(
                approxLoudnessLUFS: self.normalizationEnabled ? self.currentApproxLoudnessLUFS : nil
            )
            try? await self.engineController.start()
        }
    }

    deinit {
        currentLoadTask?.cancel()
        displayUpdateTask?.cancel()
        cacheProgressTask?.cancel()
        loudnessMeasurementTask?.cancel()
        remoteCommandTask?.cancel()
        recoveryEventTask?.cancel()
        visualizationTask?.cancel()
        underrunRecoveryTask?.cancel()
        let engineController = engineController
        let audioSessionManager = audioSessionManager
        let nowPlayingPublisher = nowPlayingPublisher
        let recoveryCoordinator = recoveryCoordinator
        Task {
            recoveryCoordinator.stop()
            await engineController.stop()
            await engineController.stopVisualization()
            await nowPlayingPublisher.clear()
            try? await audioSessionManager.deactivate()
        }
    }

    public var currentTrackID: String? {
        currentTrack?.id
    }

    public var auraPlayCurrentTrack: AuraPlayTrack? {
        currentTrack
    }

    public var auraPlayPlaybackState: AuraPlayPlaybackState {
        playbackState
    }

    public var auraPlayProgress: TimeInterval {
        currentTime
    }

    public var auraPlayNextPreviewTrack: AuraPlayTrack? {
        playbackOrchestrator.queue.peekNext().map {
            AuraPlayTrack(item: $0.item)
        }
    }

    public var auraPlayPreviousPreviewTrack: AuraPlayTrack? {
        let queue = playbackOrchestrator.queue
        if let historyItem = queue.history.last?.item {
            return AuraPlayTrack(item: historyItem)
        }
        guard let currentIndex = queue.currentIndex,
              queue.entries.indices.contains(currentIndex - 1) else {
            return nil
        }
        return AuraPlayTrack(item: queue.entries[currentIndex - 1].item)
    }

    public var auraPlayCachePresentation: AuraPlayCachePresentation {
        cachePresentation
    }

    public var auraPlaySystemIntegrationPresentation: AuraPlaySystemIntegrationPresentation {
        systemIntegrationPresentation
    }

    public var auraPlayVisualizationPresentation: AuraPlayVisualizationPresentation {
        visualizationPresentation
    }

    public var auraPlayAudioTuningPresentation: AuraPlayAudioTuningPresentation {
        audioTuningPresentation
    }

    public var auraPlayPlaybackAlert: AuraPlayPlaybackAlertPresentation? {
        playbackAlert
    }

    public var auraPlayCurrentItemPresentation: AuraPlayCurrentItemPresentation? {
        if let currentItem = playbackOrchestrator.queue.currentItem {
            if let currentNFT, currentNFT.id == currentItem.id {
                return Self.currentItemPresentation(
                    nft: currentNFT,
                    track: currentTrack,
                    media: currentMedia
                )
            }
            return AuraPlayCurrentItemPresentation(
                id: currentItem.id,
                title: currentItem.metadata.title.nilIfEmpty ?? currentTrack?.title?.nilIfEmpty ?? "Unknown Title",
                creator: currentItem.metadata.artist?.nilIfEmpty ?? currentTrack?.artist?.nilIfEmpty,
                collection: nil,
                artworkURLString: currentItem.metadata.artworkURL?.absoluteString ?? currentTrack?.imageURLString,
                mediaKind: currentItem.contentKind == .video ? .video : .audio
            )
        }

        guard let currentNFT else {
            return currentTrack.map {
                AuraPlayCurrentItemPresentation(
                    id: $0.id,
                    title: $0.title?.nilIfEmpty ?? "Unknown Title",
                    creator: $0.artist?.nilIfEmpty,
                    collection: nil,
                    artworkURLString: $0.imageURLString,
                    mediaKind: .audio
                )
            }
        }

        return Self.currentItemPresentation(nft: currentNFT, track: currentTrack, media: currentMedia)
    }

    public var auraPlayShuffleEnabled: Bool {
        playbackOrchestrator.shuffleCoordinator.mode == .on
    }

    public var auraPlaySmartShuffleEnabled: Bool {
        smartShuffleEnabled
    }

    public var auraPlayRepeatModeTitle: String {
        switch playbackOrchestrator.repeatMode {
        case .off:
            "Off"
        case .one:
            "One"
        case .all:
            "All"
        }
    }

    public var auraPlayVideoCapabilities: AuraPlayPlayerVideoCapabilities? {
        videoRemoteControls?.playerVideoCapabilities
    }

    public var auraPlayPlayerVideoSurface: AnyView? {
        videoRemoteControls?.playerVideoSurface
    }

    public var auraPlayPlayerVideoRoutePicker: AnyView? {
        videoRemoteControls?.playerVideoRoutePicker
    }

    public func auraPlaySetShuffleEnabled(_ isEnabled: Bool) {
        playbackOrchestrator.setShuffleMode(isEnabled ? .on : .off)
        defaults.set(
            (isEnabled ? AuraPlayShuffleMode.on : AuraPlayShuffleMode.off).rawValue,
            forKey: AuraPlayPlaybackPreferenceSettings.shuffleModeDefaultsKey
        )
        if isEnabled {
            applySmartShuffleSetting()
        }
    }

    public func auraPlaySetSmartShuffleEnabled(_ isEnabled: Bool) {
        smartShuffleEnabled = isEnabled
        defaults.set(isEnabled, forKey: AuraPlayIntelligenceSettings.smartShuffleEnabledDefaultsKey)
        applySmartShuffleSetting()
    }

    public func auraPlayCycleRepeatMode() {
        let nextMode: AuraPlayRepeatMode
        switch playbackOrchestrator.repeatMode {
        case .off:
            nextMode = .all
        case .all:
            nextMode = .one
        case .one:
            nextMode = .off
        }
        playbackOrchestrator.setRepeatMode(nextMode)
        defaults.set(nextMode.rawValue, forKey: AuraPlayPlaybackPreferenceSettings.repeatModeDefaultsKey)
    }

    func auraPlaySetRepeatMode(_ mode: AuraPlayRepeatMode) {
        playbackOrchestrator.setRepeatMode(mode)
        defaults.set(mode.rawValue, forKey: AuraPlayPlaybackPreferenceSettings.repeatModeDefaultsKey)
    }

    func auraPlayCacheSettingsSummary() async -> AuraPlayCacheSettingsSummary {
        await cacheManager.cacheSettingsSummary()
    }

    func auraPlaySetCacheDiskCapBytes(_ bytes: Int64) async throws -> AuraPlayCacheSettingsSummary {
        try await cacheManager.updateDiskCapBytes(bytes)
    }

    func auraPlayClearUnpinnedCache() async throws -> AuraPlayCacheSettingsSummary {
        try await cacheManager.clearUnpinnedCache()
    }

    public func auraPlayStartPiP() {
        videoRemoteControls?.startPiP()
    }

    public func auraPlayStopPiP() {
        videoRemoteControls?.stopPiP()
    }

    public func auraPlayRestorePiP() {
        videoRemoteControls?.restorePiP()
    }

    public func auraPlaySelectSubtitle(_ title: String?) async {
        await videoRemoteControls?.selectSubtitle(title)
    }

    public func auraPlaySetPlaybackSpeed(_ speed: Double) async {
        await videoRemoteControls?.setPlaybackSpeed(speed)
    }

    public func auraPlayToggleVideoGravity() async {
        await videoRemoteControls?.toggleVideoGravity()
    }

    func configureMusicReceiptLogger(_ logger: MusicReceiptEventLogger?) {
        musicReceiptLogger = logger
    }

    func configureAuraPlayModelContainer(_ modelContainer: ModelContainer?) {
        auraPlayModelContainer = modelContainer
        applySmartShuffleSetting()
    }

    func configureVideoRouteOpening(_ openVideoPlayer: @escaping @MainActor () -> Void) {
        self.openVideoPlayer = openVideoPlayer
    }

    func auraPlayRegisterVideoRemoteControls(_ controls: (any AuraPlayVideoRemoteControlling)?) {
        videoRemoteControls = controls
        if controls == nil, phase8ActiveEngine == .video {
            phase8ActiveEngine = nil
        }
    }

    func auraPlayPrepareForVideoPlayback(_ media: AuraPlayableMediaItem? = nil) async {
        if currentTrack != nil || playbackState == .playing || playbackState == .loading {
            await playbackOrchestrator.stop()
        }
        phase8ActiveEngine = .video
        if let media {
            playbackOrchestrator.markExternalPlaybackActive(
                item: media,
                origin: .single(mediaItemID: media.id)
            )
        }
    }

    func auraPlayVideoPlaybackStopped() {
        if phase8ActiveEngine == .video {
            phase8ActiveEngine = nil
        }
    }

    func auraPlayStoredVideoPosition(for mediaID: String) async -> StoredVideoPlaybackPosition? {
        guard let snapshot = try? await playbackPositionStateService?
            .storedPosition(for: mediaID) else {
            return nil
        }
        return StoredVideoPlaybackPosition(
            mediaID: snapshot.mediaID,
            positionMilliseconds: snapshot.positionMilliseconds,
            durationMilliseconds: snapshot.durationMilliseconds
        )
    }

    func auraPlayPersistVideoPositionIfNeeded(
        mediaID: String,
        tick: PlaybackTick,
        isPlaying: Bool,
        force: Bool = false
    ) async {
        await writePlaybackPosition(
            mediaID: mediaID,
            tick: tick,
            isPlaying: isPlaying,
            force: force
        )
    }

    func auraPlayMarkVideoCompleted(mediaID: String) async {
        try? await positionPersistenceCoordinator?.markCompleted(mediaID: mediaID)
        lastPlaybackPositionWriteSeconds[mediaID] = nil
    }

    func configureMediaResolver(
        _ resolver: GatewayFallbackChain?,
        configuration: AuraPlayStorageResolutionConfiguration
    ) {
        mediaResolver = resolver
        mediaGatewayHosts = Set(
            (configuration.ipfsGatewayChain + configuration.arweaveGatewayChain)
                .compactMap { $0.host?.lowercased() }
        )
    }

    public func play() throws {
        pendingPlaybackTriggerCause = pendingPlaybackTriggerCause ?? .userInitiated
        Task { [weak self] in
            guard let self else { return }
            do {
                try await self.playPrepared(shouldRecordStart: true)
            } catch {
                self.playbackState = .error
                self.updateNowPlaying()
            }
        }
    }

    public func pause() {
        guard playbackState == .playing else { return }
        Task { [weak self] in
            guard let self else { return }
            await self.playbackOrchestrator.pause()
        }
    }

    public func resume() throws {
        guard playbackState == .paused else { return }
        pendingPlaybackTriggerCause = pendingPlaybackTriggerCause ?? .userInitiated
        Task { [weak self] in
            guard let self else { return }
            do {
                if !self.playbackOrchestrator.hasActiveEngine, let restoredNFT = self.currentNFT {
                    // Cold-launch restored session: no engine has media loaded,
                    // so resume runs the full load path and seeks back.
                    let resumePosition = self.currentTime
                    try await self.loadAndPlay(nft: restoredNFT, triggerCause: .userInitiated)
                    if resumePosition > 0 {
                        await self.playbackOrchestrator.seek(to: resumePosition)
                    }
                    return
                }
                try await self.playbackOrchestrator.resume()
            } catch {
                self.playbackState = .error
                self.updateNowPlaying()
            }
        }
    }

    public func seek(to time: TimeInterval) throws {
        guard currentMedia != nil else { return }
        let clampedTime = max(0, min(time, currentDuration))
        let wasPlaying = playbackState == .playing

        seekPosition = clampedTime
        pausedAt = clampedTime
        currentTime = clampedTime

        Task { [weak self] in
            guard let self else { return }
            await self.playbackOrchestrator.seek(to: clampedTime)
            if !wasPlaying {
                self.playbackState = .paused
            }
            self.updateNowPlaying(restartElapsedTicker: true)
        }
    }

    public func playNext() async {
        await playbackOrchestrator.skipToNext()
    }

    public func playPrevious() async {
        await playbackOrchestrator.skipToPrevious()
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
        guard currentDuration > 0 else { return }
        let targetTime = min(currentDuration, currentTime + skipInterval)
        try? seek(to: targetTime)
    }

    public func auraPlaySkipBackward() {
        guard currentDuration > 0 else {
            try? seek(to: 0)
            return
        }
        let targetTime = max(0, currentTime - skipInterval)
        try? seek(to: targetTime)
    }

    public func auraPlayNext() async {
        await playbackOrchestrator.skipToNext()
    }

    public func auraPlayPrevious() async {
        await playbackOrchestrator.skipToPrevious()
    }

    public func auraPlayQueueItems() -> [AuraPlayQueuePresentationItem] {
        let queue = playbackOrchestrator.queue
        let history = queue.history.reversed().map {
            AuraPlayQueuePresentationItem(item: $0.item, role: .history)
        }
        let current = queue.currentItem.map {
            [AuraPlayQueuePresentationItem(item: $0, role: .current)]
        } ?? []
        let upcoming: [AuraPlayQueuePresentationItem]
        if let currentIndex = queue.currentIndex {
            upcoming = queue.entries.dropFirst(currentIndex + 1).map {
                AuraPlayQueuePresentationItem(item: $0.item, role: .upcoming)
            }
        } else {
            upcoming = []
        }

        return history + current + upcoming
    }

    public func auraPlayRemoveQueueItem(id: String) {
        playbackOrchestrator.removeNonCurrentQueueItem(mediaID: id)
    }

    public func auraPlayMoveQueueItem(id: String, toUpcomingIndex: Int) {
        playbackOrchestrator.moveUpcomingQueueItem(mediaID: id, toUpcomingIndex: toUpcomingIndex)
    }

    public func auraPlayClearUpcomingQueue() {
        playbackOrchestrator.clearUpcomingQueue()
    }

    public func auraPlaySaveOffline() async {
        guard let currentMedia else { return }
        cachePresentation = AuraPlayCachePresentation(
            state: .queued,
            progressFraction: 0,
            message: "Offline save queued.",
            canSaveOffline: false,
            canPin: false,
            canUnpin: false
        )
        await cacheManager.prefetch(currentMedia)
        persistCacheState(mediaID: currentMedia.id, cachedFileState: .partial)
    }

    public func auraPlayPinOffline() async {
        guard let currentMedia else { return }
        do {
            try await cacheManager.pin(currentMedia)
            persistCacheState(mediaID: currentMedia.id, cachedFileState: .pinned)
            cachePresentation = AuraPlayCachePresentation(
                state: .pinned,
                progressFraction: 1,
                message: "Saved offline and pinned.",
                canSaveOffline: false,
                canPin: false,
                canUnpin: true
            )
        } catch {
            cachePresentation = AuraPlayCachePresentation(
                state: .error,
                progressFraction: cachePresentation.progressFraction,
                message: "Could not pin this track for offline playback.",
                canSaveOffline: true,
                canPin: true,
                canUnpin: false
            )
        }
    }

    public func auraPlayUnpinOffline() async {
        guard let currentMedia else { return }
        do {
            try await cacheManager.unpin(currentMedia)
            persistCacheState(mediaID: currentMedia.id, cachedFileState: .cached)
            cachePresentation = AuraPlayCachePresentation(
                state: .cached,
                progressFraction: 1,
                message: "Saved offline. Pin removed.",
                canSaveOffline: false,
                canPin: true,
                canUnpin: false
            )
        } catch {
            cachePresentation = AuraPlayCachePresentation(
                state: .error,
                progressFraction: cachePresentation.progressFraction,
                message: "Could not remove the offline pin.",
                canSaveOffline: false,
                canPin: false,
                canUnpin: true
            )
        }
    }

    public func auraPlaySetEQPreset(_ preset: AuraPlayEQPresetID) {
        selectedEQPreset = preset
        defaults.set(preset.rawValue, forKey: AuraPlayAudioSettings.eqPresetDefaultsKey)
        refreshAudioTuningPresentation()
        Task { [weak self] in
            guard let self else { return }
            await self.engineController.applyEQPreset(self.engineEQPreset)
        }
    }

    public func auraPlaySetCustomEQBand(index: Int, gain: Float) {
        guard customEQGains.indices.contains(index) else { return }
        customEQGains[index] = min(max(gain.rounded(), AuraPlayAudioSettings.minimumBandGain), AuraPlayAudioSettings.maximumBandGain)
        selectedEQPreset = .custom
        defaults.set(selectedEQPreset.rawValue, forKey: AuraPlayAudioSettings.eqPresetDefaultsKey)
        AuraPlayAudioSettings.writeCustomEQGains(customEQGains, to: defaults)
        refreshAudioTuningPresentation()
        Task { [weak self] in
            guard let self else { return }
            await self.engineController.applyEQPreset(self.engineEQPreset)
        }
    }

    public func auraPlaySetNormalizationEnabled(_ isEnabled: Bool) {
        normalizationEnabled = isEnabled
        defaults.set(isEnabled, forKey: AuraPlayAudioSettings.normalizationEnabledDefaultsKey)
        refreshAudioTuningPresentation()
        Task { [weak self] in
            guard let self else { return }
            await self.engineController.applyNormalizationGain(
                approxLoudnessLUFS: isEnabled ? self.currentApproxLoudnessLUFS : nil
            )
        }
    }

    public func auraPlaySetCrossfadeDuration(_ duration: Double) {
        crossfadeDuration = min(8, max(0, duration.rounded()))
        defaults.set(crossfadeDuration, forKey: AuraPlayAudioSettings.crossfadeDurationDefaultsKey)
        refreshAudioTuningPresentation()
        Task { [weak self] in
            guard let self else { return }
            await self.prepareUpcomingTransitionIfPossible()
            self.refreshAudioTuningPresentation()
        }
    }

    public func auraPlayDismissPlaybackAlert() {
        playbackAlert = nil
    }

    public func presentAuraPlayPlaybackFailure(_ error: Error) {
        playbackState = .error
        cachePresentation = playbackFailurePresentation(for: error)
        presentPlaybackAlert(for: error)
        updateNowPlaying()
    }

    public func auraPlayStartVisualization() async {
        visualizationTask?.cancel()

        guard playbackState == .playing else {
            visualizationPresentation = AuraPlayVisualizationPresentation(
                isLive: false,
                message: "Start playback to see live meter activity."
            )
            return
        }

        visualizationPresentation = AuraPlayVisualizationPresentation(
            levels: visualizationPresentation.levels,
            isLive: true,
            message: "Live meter activity from the custom audio engine."
        )

        let stream = engineController.startVisualization(
            configuration: AudioVisualizationConfiguration(framesPerSecond: 15)
        )
        visualizationTask = Task { [weak self] in
            for await frame in stream {
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    guard let self else { return }
                    self.visualizationPresentation = AuraPlayVisualizationPresentation(frame: frame)
                }
            }
        }
    }

    public func auraPlayStopVisualization() async {
        visualizationTask?.cancel()
        visualizationTask = nil
        await engineController.stopVisualization()
        visualizationPresentation = AuraPlayVisualizationPresentation(
            levels: visualizationPresentation.levels,
            isLive: false,
            message: "Visualizer paused."
        )
    }

    public func snapshot() -> AuraPlayQueueSnapshot {
        let queue = playbackOrchestrator.queue
        let upcomingCount = queue.currentIndex.map {
            max(0, queue.entries.count - $0 - 1)
        } ?? 0
        return AuraPlayQueueSnapshot(
            upcomingCount: upcomingCount,
            historyCount: queue.history.count
        )
    }

    func loadAndPlay(nft: NFT) async throws {
        try await loadAndPlay(nft: nft, triggerCause: .userInitiated)
    }

    /// Phase 8 orchestrator state, exposed for the app-target
    /// `AuraPlayPlaybackOrchestrating` adapter.
    var phase8OrchestratorState: OrchestratorState {
        playbackOrchestrator.state
    }

    func configureLibraryQueueExtension(
        extender: any AuraPlayQueueExtending,
        resolveNFTs: @escaping @MainActor ([String]) -> [NFT]
    ) {
        libraryQueueExtender = extender
        libraryQueueNFTResolver = resolveNFTs
    }

    /// Starts playback from a bounded Library window and captures the query
    /// context so the queue can lazily extend past the materialized window.
    public func playLibraryWindow(
        id: String,
        in orderedNFTs: [NFT],
        queryContext: MediaItemQueryContext?,
        nextOffset: Int?,
        origin: QueueOrigin? = nil
    ) async throws {
        try await playLibraryItem(id: id, in: orderedNFTs, origin: origin)
        libraryQueueQueryContext = queryContext
        libraryQueueNextOffset = nextOffset
    }

    /// Starts playback from resolved AuraPlay media rows. This path preserves the
    /// media item's canonical playback URL and audio/video classification instead
    /// of falling back to legacy `NFT.audioUrl` fields.
    public func playPlaybackWindow(
        item: AuraPlayableMediaItem,
        queue items: [AuraPlayableMediaItem],
        startAt index: Int,
        queryContext: MediaItemQueryContext?,
        nextOffset: Int?,
        origin: QueueOrigin? = nil
    ) async throws {
        libraryQueueQueryContext = queryContext
        libraryQueueNextOffset = nextOffset
        let safeIndex = items.indices.contains(index) ? index : (items.firstIndex(where: { $0.id == item.id }) ?? 0)
        let didPlay = await playbackOrchestrator.play(
            item: item,
            queue: items,
            startAt: safeIndex,
            origin: origin ?? .single(mediaItemID: item.id)
        )
        guard didPlay else {
            let error = AuraPlayError.engineStartFailed
            presentAuraPlayPlaybackFailure(error)
            throw error
        }
    }

    public func waitForVideoRemoteControls(timeoutNanoseconds: UInt64 = 1_000_000_000) async -> Bool {
        if videoRemoteControls != nil {
            return true
        }

        let clock = ContinuousClock()
        let deadline = clock.now + .nanoseconds(Int(timeoutNanoseconds))
        while clock.now < deadline {
            try? await Task.sleep(nanoseconds: 50_000_000)
            if videoRemoteControls != nil {
                return true
            }
        }
        return false
    }

    /// Restores the most recent playback session as paused after cold launch,
    /// so the mini-player shows it without starting audio (P9-006).
    @discardableResult
    public func restoreMostRecentSessionIfNeeded() async -> Bool {
        guard !didAttemptSessionRestore, case .idle = playbackOrchestrator.state else {
            return false
        }
        didAttemptSessionRestore = true
        guard let resolver = libraryQueueNFTResolver else { return false }

        let didRestore = await playbackOrchestrator.restoreMostRecent { [weak self] mediaID in
            guard let self, let nft = resolver([mediaID]).first else { return nil }
            // Skip restoration when the persisted "most recent" item has lost
            // its playback URLs; an about:blank / /dev/null placeholder would
            // silently fail to play. Returning nil leaves the session idle.
            guard let sourceURLString = nft.secureAnimationUrl ?? nft.animationUrl,
                  let sourceURL = URL(string: sourceURLString) else {
                return nil
            }
            let item = AuraPlayableMediaItem(
                id: nft.id,
                sourceURL: sourceURL,
                contentKind: self.isVideoMediaCandidate(nft: nft) ? .video : .music,
                metadata: MediaMetadata(
                    id: nft.id,
                    title: nft.name ?? "Unknown Track",
                    artist: nft.artistName,
                    artworkURL: URL(string: nft.image?.secureUrl ?? nft.image?.originalUrl ?? "")
                )
            )
            // Mirror the restored session into the presenter surface so the
            // mini-player has artwork/title/paused state on cold launch.
            self.currentNFT = nft
            self.orchestratedNFTs[nft.id] = nft
            self.currentTrack = AuraPlayTrack(nft: nft)
            self.playbackState = .paused
            return item
        }

        if didRestore,
           let candidate = try? await positionPersistenceCoordinator?.restoreCandidate(),
           candidate.mediaID == currentNFT?.id {
            let restoredSeconds = Double(candidate.positionMilliseconds) / 1000
            currentTime = restoredSeconds
            pausedAt = restoredSeconds
            seekPosition = restoredSeconds
            if let durationMilliseconds = candidate.durationMilliseconds {
                currentDuration = Double(durationMilliseconds) / 1000
            }
            updateNowPlaying()
        }
        return didRestore
    }

    private func isVideoMediaCandidate(nft: NFT) -> Bool {
        Self.isVideoMedia(nft: nft, media: nil)
    }

    public func playLibraryItem(id: String, in scopedNFTs: [NFT], origin: QueueOrigin? = nil) async throws {
        let uniqueNFTs = scopedNFTs.uniquedByID()
        guard let startIndex = uniqueNFTs.firstIndex(where: { $0.id == id }) else {
            playbackState = .error
            return
        }
        let nft = uniqueNFTs[startIndex]
        libraryQueueSeed = uniqueNFTs
        libraryQueueCursor = startIndex
        libraryQueueQueryContext = nil
        libraryQueueNextOffset = nil
        libraryQueueExtensionTask?.cancel()
        seedUpcomingQueue(after: startIndex)

        do {
            try await loadAndPlay(nft: nft, triggerCause: .userInitiated, origin: origin)
        } catch {
            if isUnsupportedFormat(error), !nextAudio.tracks.isEmpty {
                await playNext(triggerCause: .autoAdvance)
                return
            }
            throw error
        }
    }

    public func addLibraryItemToQueue(id: String, in scopedNFTs: [NFT]) {
        guard let nft = scopedNFTs.first(where: { $0.id == id }) else {
            return
        }

        guard currentNFT?.id != nft.id,
              !nextAudio.tracks.contains(where: { $0.id == nft.id }) else {
            return
        }

        nextAudio.tracks.append(nft)
    }

    private func seedUpcomingQueue(after index: Int) {
        guard libraryQueueSeed.indices.contains(index) else {
            nextAudio.tracks.removeAll()
            return
        }
        let lowerBound = libraryQueueSeed.index(after: index)
        guard lowerBound < libraryQueueSeed.endIndex else {
            nextAudio.tracks.removeAll()
            return
        }
        let upperBound = min(libraryQueueSeed.endIndex, lowerBound + libraryQueueWindowSize)
        let currentID = libraryQueueSeed[index].id
        nextAudio.tracks = Array(libraryQueueSeed[lowerBound..<upperBound])
            .filter { $0.id != currentID }
    }

    private func extendUpcomingQueueIfNeeded(after currentID: String) {
        guard let currentIndex = libraryQueueSeed.firstIndex(where: { $0.id == currentID }) else {
            return
        }
        libraryQueueCursor = currentIndex
        guard nextAudio.tracks.count <= libraryQueueLowWatermark else {
            return
        }
        let queuedIDs = Set(nextAudio.tracks.map(\.id)).union([currentID])
        let lowerBound = libraryQueueSeed.index(after: currentIndex)
        if lowerBound < libraryQueueSeed.endIndex {
            let candidates = libraryQueueSeed[lowerBound...]
                .filter { !queuedIDs.contains($0.id) }
                .prefix(libraryQueueWindowSize - nextAudio.tracks.count)
            nextAudio.tracks.append(contentsOf: candidates)
        }

        // Near the seed tail with a captured query context: fetch the next
        // window as a pure function of that context (P9-002 lazy extension).
        let remainingSeed = libraryQueueSeed.count - (currentIndex + 1)
        if remainingSeed <= libraryQueueLowWatermark {
            extendSeedFromCapturedContext(after: currentID)
        }
    }

    private func extendSeedFromCapturedContext(after currentID: String) {
        guard libraryQueueExtensionTask == nil,
              let extender = libraryQueueExtender,
              let resolver = libraryQueueNFTResolver,
              var context = libraryQueueQueryContext,
              let nextOffset = libraryQueueNextOffset else {
            return
        }
        context.offset = nextOffset

        libraryQueueExtensionTask = Task { [weak self] in
            defer { self?.libraryQueueExtensionTask = nil }
            guard let window = try? await extender.fetchNextWindow(from: context) else { return }
            guard let self, !Task.isCancelled else { return }
            // The queue may have been replaced while fetching.
            guard self.libraryQueueNextOffset == nextOffset else { return }

            let knownIDs = Set(self.libraryQueueSeed.map(\.id))
            let newIDs = window.items.map(\.id).filter { !knownIDs.contains($0) }
            let resolvedNFTs = resolver(newIDs)
            self.libraryQueueSeed.append(contentsOf: resolvedNFTs.uniquedByID().filter { !knownIDs.contains($0.id) })
            self.libraryQueueNextOffset = window.nextOffset
            self.libraryQueueQueryContext = window.queryContext ?? self.libraryQueueQueryContext
            self.extendUpcomingQueueIfNeeded(after: currentID)
        }
    }

    private func loadAndPlay(
        nft: NFT,
        triggerCause: MusicReceiptTriggerCause,
        origin: QueueOrigin? = nil
    ) async throws {
        pendingPlaybackTriggerCause = triggerCause
        let mediaItem = try await playableMediaItem(for: nft)
        orchestratedNFTs[mediaItem.id] = nft
        let didPlay = await playbackOrchestrator.play(
            item: mediaItem,
            queue: [mediaItem],
            startAt: 0,
            origin: origin ?? .single(mediaItemID: mediaItem.id)
        )
        guard didPlay else {
            let error = AuraPlayError.engineStartFailed
            playbackState = .error
            cachePresentation = playbackFailurePresentation(for: error)
            presentPlaybackAlert(for: error)
            updateNowPlaying()
            throw error
        }
    }

    private func playableMediaItem(for nft: NFT) async throws -> AuraPlayableMediaItem {
        let media = try await playableMedia(for: nft)
        return AuraPlayableMediaItem(
            media,
            metadata: MediaMetadata(
                id: nft.id,
                title: nft.name ?? "Unknown Track",
                artist: nft.artistName,
                artworkURL: URL(string: nft.image?.secureUrl ?? nft.image?.originalUrl ?? "")
            )
        )
    }

    fileprivate func loadAudioItemForOrchestrator(_ item: AuraPlayableMediaItem) async throws {
        await prepareForAudioPlayback()
        await persistCurrentAudioPosition(force: true)
        currentLoadTask?.cancel()
        underrunRecoveryTask?.cancel()
        underrunRecoveryTask = nil
        playbackState = .loading
        clearPreparedTransition()

        currentMedia = NFTPlayableMedia(item)
        currentApproxLoudnessLUFS = item.approxLoudnessLUFS
        currentArtworkData = nil
        lastRecoveryStatus = "Loading"
        refreshAudioTuningPresentation()
        cachePresentation = AuraPlayCachePresentation(
            state: .downloading,
            progressFraction: 0,
            message: "Preparing a playable local file. Playback can start before the full file is cached when the gateway supports it.",
            canSaveOffline: false,
            canPin: false,
            canUnpin: false
        )

        let localURL = try await cacheManager.localFileWhenPlayable(for: item)
        let audioFile = try AVAudioFile(forReading: localURL)
        let duration = Double(audioFile.length) / audioFile.fileFormat.sampleRate

        try Task.checkCancellation()
        await engineController.configureForContentKind(item.contentKind)
        await engineController.applyEQPreset(engineEQPreset)
        await engineController.applyNormalizationGain(
            approxLoudnessLUFS: normalizationEnabled ? currentApproxLoudnessLUFS : nil
        )
        try await scheduler.scheduleCurrent(fileURL: localURL, startingFrame: 0)

        let nft = orchestratedNFTs[item.id]
        currentNFT = nft
        currentDuration = duration
        seekPosition = 0
        pausedAt = 0
        currentTime = 0
        currentTrackCompletionHandled = false
        currentTrack = AuraPlayTrack(
            id: item.id,
            title: item.metadata.title,
            artist: item.metadata.artist,
            duration: duration,
            imageURLString: item.metadata.artworkURL?.absoluteString
        )
        currentArtworkData = await loadArtworkData(for: currentTrack)
        await refreshCachePresentation(for: NFTPlayableMedia(item))
        persistCacheState(
            mediaID: item.id,
            cachedFileState: await cacheManager.isCached(item) ? .cached : .partial
        )
        if let currentMedia {
            pinForOfflineIfPreferred(currentMedia)
        }
        refreshAudioTuningPresentation()
        updateNowPlaying()
    }

    fileprivate func startLoadedAudioItemFromOrchestrator() async throws {
        try await engineController.start()
        phase8ActiveEngine = .audio
        playbackState = .playing
        lastRecoveryStatus = "Ready"
        await prepareUpcomingTransitionIfPossible()
        startDisplayUpdates()
        recordPlaybackStartedIfPossible()
        updateNowPlaying()
    }

    fileprivate func pauseAudioFromOrchestrator() async {
        guard playbackState == .playing else { return }
        pausedAt = currentTime
        playbackState = .paused
        stopDisplayUpdates()
        underrunRecoveryTask?.cancel()
        underrunRecoveryTask = nil
        updateNowPlaying()
        await persistCurrentAudioPosition(force: true)
        await engineController.pause()
        await auraPlayStopVisualization()
    }

    fileprivate func resumeAudioFromOrchestrator() async throws {
        try await engineController.resume()
        phase8ActiveEngine = .audio
        playbackState = .playing
        startDisplayUpdates()
        recordPlaybackStartedIfPossible()
        updateNowPlaying()
    }

    fileprivate func stopAudioFromOrchestrator() async {
        await stop()
    }

    fileprivate func loadVideoItemForOrchestrator(_ item: AuraPlayableMediaItem) async throws {
        if videoRemoteControls == nil {
            openVideoPlayer?()
            guard await waitForVideoRemoteControls() else {
                throw AuraPlayError.engineStartFailed
            }
        }

        guard let videoRemoteControls else {
            throw AuraPlayError.engineStartFailed
        }

        await prepareForAudioPlayback()
        await persistCurrentAudioPosition(force: true)
        playbackState = .loading
        currentMedia = NFTPlayableMedia(item)
        currentDuration = 0
        currentTime = 0
        pausedAt = 0
        currentTrack = AuraPlayTrack(
            id: item.id,
            title: item.metadata.title,
            artist: item.metadata.artist,
            duration: 0,
            imageURLString: item.metadata.artworkURL?.absoluteString
        )
        updateNowPlaying()
        try await videoRemoteControls.load(item)
    }

    fileprivate func seekAudioFromOrchestrator(to time: TimeInterval) async {
        guard let currentMedia else { return }
        let clampedTime = max(0, min(time, currentDuration))
        let startingFrame = AVAudioFramePositionValue(clampedTime * currentMedia.sampleRate)
        let wasPlaying = playbackState == .playing

        seekPosition = clampedTime
        pausedAt = clampedTime
        currentTime = clampedTime

        do {
            let localURL = try await cacheManager.localFile(for: currentMedia)
            try await scheduler.scheduleCurrent(fileURL: localURL, startingFrame: startingFrame)
            if wasPlaying {
                try await engineController.start()
                playbackState = .playing
                startDisplayUpdates()
            } else {
                playbackState = .paused
            }
            updateNowPlaying(restartElapsedTicker: true)
        } catch {
            playbackState = .error
            updateNowPlaying()
        }
    }

    private func checkCurrentPlaybackGeneration(_ generation: Int) throws {
        guard generation == playbackGeneration else {
            throw CancellationError()
        }
    }

    private func playableMedia(for nft: NFT) async throws -> NFTPlayableMedia {
        guard let rawAudioURL = nft.audioUrl?.trimmingCharacters(in: .whitespacesAndNewlines),
              !rawAudioURL.isEmpty else {
            throw AuraPlayError.invalidMediaURL(URL(fileURLWithPath: ""))
        }

        let sourceURL: URL
        if shouldUseStorageResolver(for: rawAudioURL), let mediaResolver {
            sourceURL = try await mediaResolver.resolve(rawAudioURL)
        } else if let musicURL = nft.musicURL {
            sourceURL = musicURL
        } else if let mediaResolver {
            sourceURL = try await mediaResolver.resolve(rawAudioURL)
        } else if let url = URL(string: rawAudioURL) {
            sourceURL = url
        } else {
            throw AuraPlayError.invalidMediaURL(URL(fileURLWithPath: rawAudioURL))
        }

        return NFTPlayableMedia(
            id: nft.id,
            sourceURL: sourceURL,
            declaredFormat: sourceURL.pathExtension.nilIfEmpty,
            contentKind: .music,
            cachedFileState: .notCached,
            approxLoudnessLUFS: nil
        )
    }

    private func shouldUseStorageResolver(for rawAudioURL: String) -> Bool {
        let lowercased = rawAudioURL.lowercased()
        return lowercased.hasPrefix("ipfs://")
            || lowercased.hasPrefix("/ipfs/")
            || lowercased.hasPrefix("ipfs/")
            || lowercased.hasPrefix("ar://")
            || lowercased.hasPrefix("data:")
    }

    private func playPrepared(shouldRecordStart: Bool) async throws {
        guard currentMedia != nil else {
            await playbackOrchestrator.skipToNext()
            return
        }

        await prepareForAudioPlayback()
        try await engineController.start()
        try await engineController.resume()
        phase8ActiveEngine = .audio
        playbackState = .playing
        startDisplayUpdates()
        if shouldRecordStart {
            recordPlaybackStartedIfPossible()
        }
        updateNowPlaying()
        pendingPlaybackTriggerCause = nil
    }

    private func playNext(triggerCause: MusicReceiptTriggerCause) async {
        guard !nextAudio.tracks.isEmpty else {
            await stop()
            return
        }

        // Push the outgoing track into history once, before iterating: on a
        // failed attempt the current track is unchanged, so re-pushing per
        // attempt would accumulate duplicates.
        if let currentNFT {
            previousAudio.tracks.append(currentNFT)
        }

        // Walk the upcoming queue until a track plays or the consecutive-failure
        // limit is reached. Iterative (not recursive) so a large unplayable
        // queue cannot build an unbounded async call chain.
        var consecutiveFailures = 0
        while !nextAudio.tracks.isEmpty {
            let beforeSummary = queueStateSummary()
            let next = nextAudio.tracks.removeFirst()

            do {
                try await loadAndPlay(nft: next, triggerCause: triggerCause)
                extendUpcomingQueueIfNeeded(after: next.id)
                await recordQueueChangedIfPossible(
                    operation: "next",
                    affectedMediaIDs: [next.id],
                    beforeSummary: beforeSummary,
                    afterSummary: queueStateSummary(),
                    triggerCause: triggerCause,
                    nft: next
                )
                return
            } catch {
                if error is CancellationError { return }
                presentPlaybackAlert(for: error)
                consecutiveFailures += 1
                if consecutiveFailures >= maxConsecutivePlaybackFailures {
                    await presentRepeatedFailureAlertAndStop()
                    return
                }
            }
        }

        await stop()
    }

    private func playPrevious(triggerCause: MusicReceiptTriggerCause) async {
        guard !previousAudio.tracks.isEmpty else {
            try? seek(to: 0)
            return
        }

        // Move the outgoing track to the front of up-next once (see playNext).
        if let currentNFT {
            nextAudio.tracks.insert(currentNFT, at: 0)
        }

        var consecutiveFailures = 0
        while !previousAudio.tracks.isEmpty {
            let beforeSummary = queueStateSummary()
            let previous = previousAudio.tracks.removeLast()

            do {
                try await loadAndPlay(nft: previous, triggerCause: triggerCause)
                await recordQueueChangedIfPossible(
                    operation: "previous",
                    affectedMediaIDs: [previous.id],
                    beforeSummary: beforeSummary,
                    afterSummary: queueStateSummary(),
                    triggerCause: triggerCause,
                    nft: previous
                )
                return
            } catch {
                if error is CancellationError { return }
                presentPlaybackAlert(for: error)
                consecutiveFailures += 1
                if consecutiveFailures >= maxConsecutivePlaybackFailures {
                    await presentRepeatedFailureAlertAndStop()
                    return
                }
            }
        }

        await stop()
    }

    private func presentRepeatedFailureAlertAndStop() async {
        playbackAlert = AuraPlayPlaybackAlertPresentation(
            title: "Playback Stopped",
            message: "Several items couldn't play. Playback stopped."
        )
        await stop()
    }

    private func stop() async {
        underrunRecoveryTask?.cancel()
        underrunRecoveryTask = nil
        await persistCurrentAudioPosition(force: true)
        await engineController.stop()
        await auraPlayStopVisualization()
        playbackState = .stopped
        if phase8ActiveEngine == .audio {
            phase8ActiveEngine = nil
        }
        seekPosition = 0
        pausedAt = 0
        currentTime = 0
        stopDisplayUpdates()
        updateNowPlaying()
    }

    private func startDisplayUpdates() {
        stopDisplayUpdates()
        lastObservedFrame = 0
        stalledFrameObservationCount = 0
        displayUpdateTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                guard self.playbackState == .playing else { return }
                let frame = await self.engineController.currentFrame()
                self.observeRenderProgress(frame)
                let automaticTransitionCount = self.engineController.debugAutomaticTransitionCount()
                if automaticTransitionCount > self.observedAutomaticTransitionCount {
                    self.observedAutomaticTransitionCount = automaticTransitionCount
                    if await self.advanceUsingPreparedTransitionIfPossible(triggerCause: .autoAdvance) {
                        continue
                    }
                }
                self.currentTime = min(
                    self.currentDuration,
                    max(0, Double(frame) / (self.currentMedia?.sampleRate ?? 48_000))
                )
                await self.persistCurrentAudioPosition(force: false)
                if self.shouldCompleteCurrentTrack {
                    await self.completeCurrentTrackAndAdvance()
                    return
                }
                self.updateNowPlaying()
                try? await Task.sleep(for: .milliseconds(250))
            }
        }
    }

    private func stopDisplayUpdates() {
        displayUpdateTask?.cancel()
        displayUpdateTask = nil
    }

    private var shouldCompleteCurrentTrack: Bool {
        playbackState == .playing
            && currentTrackCompletionHandled == false
            && currentDuration > 0
            && currentTime >= max(0, currentDuration - 0.25)
    }

    private func completeCurrentTrackAndAdvance() async {
        currentTrackCompletionHandled = true
        let completedTrackID = currentTrack?.id
        let completedTitle = currentTrack?.title
        let completedArtist = currentTrack?.artist
        stopDisplayUpdates()
        await auraPlayStopVisualization()

        if let completedTrackID {
            await markCurrentAudioCompletedIfNeeded()
            await recordPlaybackCompletedIfPossible(
                mediaID: completedTrackID,
                title: completedTitle,
                artist: completedArtist,
                triggerCause: .autoAdvance
            )
        }

        if await advanceUsingPreparedTransitionIfPossible(triggerCause: .autoAdvance) {
            return
        }
        if await advanceAfterBriefGapIfPossible(triggerCause: .autoAdvance) {
            return
        }

        playbackState = .stopped
        updateNowPlaying()
        await playNext(triggerCause: .autoAdvance)
    }
}

@MainActor
private extension AuraPlayPlaybackRuntime {
    func startCacheProgressUpdates() {
        cacheProgressTask?.cancel()
        let cacheManager = cacheManager
        cacheProgressTask = Task { [weak self] in
            let progressStream = cacheManager.progress
            for await progress in progressStream {
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    guard let self, progress.mediaID == self.currentMedia?.id else { return }
                    self.cachePresentation = AuraPlayCachePresentation(progress: progress)
                    self.persistCacheState(mediaID: progress.mediaID, cachedFileState: progress.state)
                    if progress.state == .partial {
                        self.lastRecoveryStatus = "Buffering"
                        self.refreshAudioTuningPresentation()
                    } else if progress.state == .cached, let currentMedia = self.currentMedia {
                        self.pinForOfflineIfPreferred(currentMedia)
                    }
                }
            }
        }
    }

    func startLoudnessMeasurementUpdates() {
        loudnessMeasurementTask?.cancel()
        let cacheManager = cacheManager
        loudnessMeasurementTask = Task { [weak self] in
            let stream = cacheManager.loudnessMeasurements
            for await measurement in stream {
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    guard let self, measurement.mediaID == self.currentMedia?.id else { return }
                    self.currentApproxLoudnessLUFS = measurement.approxLoudnessLUFS
                    self.persistCacheState(
                        mediaID: measurement.mediaID,
                        approxLoudnessLUFS: measurement.approxLoudnessLUFS
                    )
                    self.refreshAudioTuningPresentation()
                    Task { [weak self] in
                        guard let self else { return }
                        await self.engineController.applyNormalizationGain(
                            approxLoudnessLUFS: self.normalizationEnabled ? measurement.approxLoudnessLUFS : nil
                        )
                    }
                }
            }
        }
    }

    func startRecoveryUpdates() {
        recoveryEventTask?.cancel()
        let events = recoveryCoordinator.events
        recoveryEventTask = Task { [weak self] in
            for await event in events {
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    self?.handleRecoveryEvent(event)
                }
            }
        }
    }

    func bindRemoteCommands() {
        remoteCommandTask?.cancel()
        // Route system remote-command events through the runtime's handler (not
        // the orchestrator directly) so restored sessions load media before
        // playing and video commands reach the video controls.
        let events = remoteCommandPublisher.events
        remoteCommandTask = Task { [weak self] in
            for await event in events {
                guard !Task.isCancelled else { return }
                self?.handleRemoteCommand(event)
            }
        }
    }

    func handleRemoteCommand(_ event: RemoteCommandEvent) {
        if phase8ActiveEngine == .video, let videoRemoteControls {
            Task { [weak videoRemoteControls] in
                guard let videoRemoteControls else { return }
                await self.dispatchVideoRemoteCommand(event, to: videoRemoteControls)
            }
            return
        }

        switch event {
        case .play:
            // A remote/lock-screen "play" means resume. When paused — including a
            // cold-launch restored session whose engine has no media loaded — route
            // through resume so media is loaded first, rather than play() which
            // assumes prepared media and would otherwise skip to the next item.
            if playbackState == .paused {
                try? auraPlayResume()
            } else {
                try? auraPlayPlay()
            }
        case .pause:
            auraPlayPause()
        case .togglePlayPause:
            playbackState == .playing ? auraPlayPause() : try? auraPlayResume()
        case .next:
            Task { await auraPlayNext() }
        case .previous:
            Task { await auraPlayPrevious() }
        case .skipForward(let seconds):
            try? seek(to: currentTime + seconds)
        case .skipBackward(let seconds):
            try? seek(to: max(0, currentTime - seconds))
        case .changePlaybackPosition(let seconds):
            try? seek(to: seconds)
        }
    }

    func dispatchVideoRemoteCommand(
        _ event: RemoteCommandEvent,
        to controls: any AuraPlayVideoRemoteControlling
    ) async {
        switch event {
        case .play:
            controls.play()
        case .pause:
            controls.pause()
        case .togglePlayPause:
            controls.togglePlayPause()
        case .next:
            await controls.skipToNext()
        case .previous:
            await controls.skipToPrevious()
        case .skipForward(let seconds):
            await controls.seek(to: controls.currentPosition + seconds)
        case .skipBackward(let seconds):
            await controls.seek(to: max(0, controls.currentPosition - seconds))
        case .changePlaybackPosition(let seconds):
            await controls.seek(to: seconds)
        }
    }

    func prepareForAudioPlayback() async {
        if phase8ActiveEngine == .video {
            await videoRemoteControls?.stopForAudioHandoff()
            phase8ActiveEngine = nil
        }
    }

    func refreshCachePresentation(for media: NFTPlayableMedia) async {
        if await cacheManager.isCached(media) {
            cachePresentation = AuraPlayCachePresentation(
                state: .cached,
                progressFraction: 1,
                message: "Saved offline.",
                canSaveOffline: false,
                canPin: true,
                canUnpin: false
            )
            pinForOfflineIfPreferred(media)
        } else {
            cachePresentation = AuraPlayCachePresentation(
                state: .notCached,
                progressFraction: nil,
                message: "Available while online. Save offline to keep this track on device.",
                canSaveOffline: true,
                canPin: false,
                canUnpin: false
            )
        }
    }

    func pinForOfflineIfPreferred(_ media: NFTPlayableMedia) {
        guard AuraPlayAudioSettings.downloadForOfflineEnabled(from: defaults),
              cachePresentation.state != .pinned else {
            return
        }

        Task { [weak self] in
            guard let self else { return }
            do {
                try await self.cacheManager.pin(media)
                await MainActor.run {
                    guard self.currentMedia?.id == media.id else { return }
                    self.persistCacheState(mediaID: media.id, cachedFileState: .pinned)
                    self.cachePresentation = AuraPlayCachePresentation(
                        state: .pinned,
                        progressFraction: 1,
                        message: "Saved offline and pinned.",
                        canSaveOffline: false,
                        canPin: false,
                        canUnpin: true
                    )
                }
            } catch {
                await MainActor.run {
                    guard self.currentMedia?.id == media.id else { return }
                    self.cachePresentation = AuraPlayCachePresentation(
                        state: .error,
                        progressFraction: self.cachePresentation.progressFraction,
                        message: "Could not pin this track for offline playback.",
                        canSaveOffline: true,
                        canPin: true,
                        canUnpin: false
                    )
                }
            }
        }
    }

    func playbackFailurePresentation(for error: Error) -> AuraPlayCachePresentation {
        let message: String
        let canSaveOffline: Bool

        if let auraPlayError = error as? AuraPlayMediaCore.AuraPlayError {
            switch auraPlayError {
            case .unsupportedFormat(let format):
                let suffix = format.flatMap { $0.isEmpty ? nil : " (\($0))" } ?? ""
                message = "This audio format\(suffix) is not supported yet. MP3, AAC, ALAC, WAV, AIFF, and FLAC can play in AuraPlay."
                canSaveOffline = false
            case .mediaUnavailableOffline:
                message = "This track is not saved on this device. Reconnect to the network or choose a saved offline track."
                canSaveOffline = false
            case .corruptedFile:
                message = "The cached audio file could not be opened. Remove the offline copy and save the track again."
                canSaveOffline = false
            case .invalidMediaURL:
                message = "This track's audio URL could not be resolved. Choose another item or refresh the library."
                canSaveOffline = false
            case .downloadFailed(let reason):
                message = "AuraPlay could not download this track: \(reason)"
                canSaveOffline = true
            case .engineStartFailed:
                message = "The audio engine could not start. Try again after changing routes or reconnecting audio output."
                canSaveOffline = false
            case .cacheIndexCorrupted:
                message = "The offline cache index needs to be rebuilt before this track can be saved or played offline."
                canSaveOffline = false
            }
        } else {
            message = "Could not load this track. Check the connection or choose another item."
            canSaveOffline = false
        }

        return AuraPlayCachePresentation(
            state: .error,
            progressFraction: cachePresentation.progressFraction,
            message: message,
            canSaveOffline: canSaveOffline,
            canPin: false,
            canUnpin: false
        )
    }

    func presentPlaybackAlert(for error: Error) {
        guard let alert = playbackAlertPresentation(for: error) else {
            return
        }
        playbackAlert = alert
    }

    func playbackAlertPresentation(for error: Error) -> AuraPlayPlaybackAlertPresentation? {
        guard let auraPlayError = error as? AuraPlayMediaCore.AuraPlayError else {
            return nil
        }

        switch auraPlayError {
        case .unsupportedFormat(let format):
            let suffix = format.flatMap { $0.isEmpty ? nil : " (\($0))" } ?? ""
            return AuraPlayPlaybackAlertPresentation(
                title: "Unsupported Audio Format",
                message: "AuraPlay skipped an unsupported audio format\(suffix)."
            )
        case .mediaUnavailableOffline:
            return AuraPlayPlaybackAlertPresentation(
                title: "Media Unavailable Offline",
                message: "This track is not saved on this device. Reconnect to the network or choose a saved offline track."
            )
        case .corruptedFile:
            return AuraPlayPlaybackAlertPresentation(
                title: "Offline Copy Could Not Play",
                message: "The cached audio file could not be opened. Remove the offline copy and save the track again."
            )
        case .engineStartFailed:
            return AuraPlayPlaybackAlertPresentation(
                title: "Playback Could Not Start",
                message: "The audio engine could not start after recovery. Try another route or reconnect audio output."
            )
        default:
            return nil
        }
    }

    func isUnsupportedFormat(_ error: Error) -> Bool {
        guard let auraPlayError = error as? AuraPlayMediaCore.AuraPlayError,
              case .unsupportedFormat = auraPlayError else {
            return false
        }
        return true
    }

    func prepareUpcomingTransitionIfPossible() async {
        clearPreparedTransition()
        guard let next = nextAudio.tracks.first,
              let nextMedia = try? await playableMedia(for: next) else {
            lastTransitionQuality = nil
            return
        }

        do {
            lastTransitionQuality = try await autoMixController.prepareNext(
                nextMedia,
                crossfadeDuration: crossfadeDuration
            )
            if lastTransitionQuality == .gapless {
                let localURL = try await cacheManager.localFile(for: nextMedia)
                let audioFile = try AVAudioFile(forReading: localURL)
                preparedTransitionNFT = next
                preparedTransitionMedia = nextMedia
                preparedTransitionDuration = Double(audioFile.length) / audioFile.fileFormat.sampleRate
                observedAutomaticTransitionCount = engineController.debugAutomaticTransitionCount()

                if crossfadeDuration > 0 {
                    let remainingFrames = AVAudioFramePositionValue(
                        max(0, currentDuration - currentTime) * nextMedia.sampleRate
                    )
                    autoMixController.scheduleCrossfadeBeforeTrackEnd(
                        duration: crossfadeDuration,
                        remainingFrames: remainingFrames,
                        sampleRate: nextMedia.sampleRate
                    )
                }
            }
        } catch {
            lastTransitionQuality = .briefGap
        }
    }

    func clearPreparedTransition() {
        preparedTransitionNFT = nil
        preparedTransitionMedia = nil
        preparedTransitionDuration = 0
    }

    func advanceUsingPreparedTransitionIfPossible(triggerCause: MusicReceiptTriggerCause) async -> Bool {
        guard lastTransitionQuality == .gapless,
              let next = preparedTransitionNFT,
              let nextMedia = preparedTransitionMedia else {
            return false
        }

        await promotePreparedTransition(
            next: next,
            nextMedia: nextMedia,
            duration: preparedTransitionDuration,
            triggerCause: triggerCause
        )
        return true
    }

    func advanceAfterBriefGapIfPossible(triggerCause: MusicReceiptTriggerCause) async -> Bool {
        guard lastTransitionQuality == .briefGap,
              let next = nextAudio.tracks.first,
              let nextMedia = try? await playableMedia(for: next) else {
            return false
        }

        do {
            try await scheduler.startAfterBriefGap(nextMedia)
            try await engineController.start()
            let localURL = try await cacheManager.localFileWhenPlayable(for: nextMedia)
            let audioFile = try AVAudioFile(forReading: localURL)
            await promotePreparedTransition(
                next: next,
                nextMedia: nextMedia,
                duration: Double(audioFile.length) / audioFile.fileFormat.sampleRate,
                triggerCause: triggerCause
            )
            return true
        } catch {
            return false
        }
    }

    func promotePreparedTransition(
        next: NFT,
        nextMedia: NFTPlayableMedia,
        duration: TimeInterval,
        triggerCause: MusicReceiptTriggerCause
    ) async {
        let beforeSummary = queueStateSummary()
        let completedNFT = currentNFT
        if let completedNFT {
            previousAudio.tracks.append(completedNFT)
        }
        if nextAudio.tracks.first?.id == next.id {
            nextAudio.tracks.removeFirst()
        } else {
            nextAudio.tracks.removeAll { $0.id == next.id }
        }

        currentNFT = next
        currentMedia = nextMedia
        currentApproxLoudnessLUFS = nextMedia.approxLoudnessLUFS
        currentDuration = duration
        currentTime = 0
        seekPosition = 0
        pausedAt = 0
        currentTrackCompletionHandled = false
        currentTrack = AuraPlayTrack(
            id: next.id,
            title: next.name,
            artist: next.artistName,
            duration: duration,
            imageURLString: next.image?.secureUrl ?? next.image?.originalUrl
        )
        currentArtworkData = await loadArtworkData(for: currentTrack)
        playbackState = .playing
        lastRecoveryStatus = "Ready"
        await refreshCachePresentation(for: nextMedia)
        await prepareUpcomingTransitionIfPossible()
        refreshAudioTuningPresentation()
        startDisplayUpdates()
        recordPlaybackStartedIfPossible()
        updateNowPlaying()

        await recordQueueChangedIfPossible(
            operation: "autoAdvance",
            affectedMediaIDs: [next.id],
            beforeSummary: beforeSummary,
            afterSummary: queueStateSummary(),
            triggerCause: triggerCause,
            nft: next
        )
    }

    func loadArtworkData(for track: AuraPlayTrack?) async -> Data? {
        guard let imageURLString = track?.imageURLString?.nilIfEmpty,
              let url = URL(string: imageURLString) else {
            return nil
        }

        do {
            var request = URLRequest(url: url)
            request.timeoutInterval = 15
            let (data, _) = try await URLSession.shared.data(for: request)
            return data
        } catch {
            return nil
        }
    }

    func persistCacheState(mediaID: String, cachedFileState: AuraCachedFileState? = nil, approxLoudnessLUFS: Double? = nil) {
        guard let auraPlayModelContainer else {
            return
        }

        Task {
            let service = AuraPlayMediaItemService(modelContainer: auraPlayModelContainer)
            try? await service.updatePlaybackCacheState(
                sourceNFTID: mediaID,
                cachedFileStateRawValue: cachedFileState?.rawValue,
                approxLoudnessLUFS: approxLoudnessLUFS
            )
        }
    }

    var playbackPositionStateService: AuraPlayPlaybackPositionStateService? {
        guard let auraPlayModelContainer else { return nil }
        return AuraPlayPlaybackPositionStateService(modelContainer: auraPlayModelContainer)
    }

    var positionPersistenceCoordinator: PositionPersistenceCoordinator? {
        guard let playbackPositionStateService else { return nil }
        return PositionPersistenceCoordinator(store: playbackPositionStateService)
    }

    func applySmartShuffleSetting() {
        Task { [weak self] in
            guard let self else { return }
            let histories = (try? await self.playbackPositionStateService?.playbackHistories()) ?? []
            self.playbackOrchestrator.setSmartShuffleEnabled(
                self.smartShuffleEnabled,
                history: histories
            )
        }
    }

    func writePlaybackPosition(
        mediaID: String,
        tick: PlaybackTick,
        isPlaying: Bool,
        force: Bool
    ) async {
        guard force || isPlaying else { return }
        if !force,
           let lastWriteSeconds = lastPlaybackPositionWriteSeconds[mediaID],
           tick.currentSeconds - lastWriteSeconds < 5 {
            return
        }
        try? await positionPersistenceCoordinator?.writePosition(mediaID: mediaID, tick: tick)
        lastPlaybackPositionWriteSeconds[mediaID] = tick.currentSeconds
    }

    func persistCurrentAudioPosition(force: Bool) async {
        guard let mediaID = currentTrack?.id else { return }
        let duration = currentDuration > 0 ? currentDuration : nil
        await writePlaybackPosition(
            mediaID: mediaID,
            tick: PlaybackTick(currentSeconds: currentTime, durationSeconds: duration),
            isPlaying: playbackState == .playing,
            force: force
        )
    }

    func markCurrentAudioCompletedIfNeeded() async {
        guard let mediaID = currentTrack?.id else { return }
        try? await positionPersistenceCoordinator?.markCompleted(mediaID: mediaID)
        lastPlaybackPositionWriteSeconds[mediaID] = nil
    }

    func observeRenderProgress(_ frame: AVAudioFramePositionValue) {
        guard playbackState == .playing, let currentMedia else {
            stalledFrameObservationCount = 0
            lastObservedFrame = frame
            return
        }

        if frame == lastObservedFrame, currentTime < max(0, currentDuration - 1) {
            stalledFrameObservationCount += 1
        } else {
            stalledFrameObservationCount = 0
        }
        lastObservedFrame = frame

        guard stalledFrameObservationCount >= 4, underrunRecoveryTask == nil else {
            return
        }

        startProgressiveUnderrunMonitor(for: currentMedia, frame: frame)
    }

    func startProgressiveUnderrunMonitor(for media: NFTPlayableMedia, frame: AVAudioFramePositionValue? = nil) {
        guard underrunRecoveryTask == nil else {
            return
        }

        let recoveryCoordinator = recoveryCoordinator
        let cacheManager = cacheManager
        let recoveryFrame = frame ?? lastObservedFrame
        underrunRecoveryTask = Task { [weak self] in
            let progress = cacheManager.progress
            await recoveryCoordinator.recoverFromProgressiveUnderrun(
                mediaID: media.id,
                frame: recoveryFrame,
                currentBytesAvailable: 0,
                progress: progress
            )
            await MainActor.run {
                self?.underrunRecoveryTask = nil
                self?.stalledFrameObservationCount = 0
            }
        }
    }

    func refreshAudioTuningPresentation() {
        audioTuningPresentation = AuraPlayAudioTuningPresentation(
            eqPreset: selectedEQPreset,
            isNormalizationEnabled: normalizationEnabled,
            normalizationStatus: normalizationStatus,
            crossfadeDuration: crossfadeDuration,
            customEQGains: customEQGains,
            transitionStatus: transitionStatus,
            recoveryStatus: lastRecoveryStatus,
            contentProcessingStatus: contentProcessingStatus
        )
    }

    var normalizationStatus: String {
        guard normalizationEnabled else {
            return "Normalization is off."
        }
        guard let currentApproxLoudnessLUFS else {
            return "Waiting for the cache to finish measuring approximate loudness."
        }
        let gain = LoudnessNormalization.gainDB(for: currentApproxLoudnessLUFS)
        return String(format: "Approximate loudness %.1f LUFS, applying %.1f dB.", currentApproxLoudnessLUFS, gain)
    }

    var transitionStatus: String {
        if crossfadeDuration > 0 {
            return "\(Int(crossfadeDuration)) s AutoMix"
        }
        switch lastTransitionQuality {
        case .gapless:
            return "Gapless"
        case .briefGap:
            return "Brief gap"
        case nil:
            return "Hard cut"
        }
    }

    var contentProcessingStatus: String {
        currentMedia?.contentKind == .spokenWord ? "Spoken-word dynamics active" : "Music dynamics preserved"
    }

    func handleRecoveryEvent(_ event: EngineRecoveryEvent) {
        switch event {
        case .paused(let reason):
            lastRecoveryStatus = reason == .routeUnavailable ? "Paused for route change" : "Paused for interruption"
            if currentTrack != nil {
                pausedAt = currentTime
                playbackState = .paused
                stopDisplayUpdates()
            }
        case .configurationChanged:
            lastRecoveryStatus = "Route recovered"
        case .interruptionRestored(let shouldResume, _):
            lastRecoveryStatus = shouldResume ? "Interruption resumed" : "Paused after interruption"
            playbackState = shouldResume && currentTrack != nil ? .playing : .paused
            if shouldResume {
                startDisplayUpdates()
            } else {
                stopDisplayUpdates()
            }
        case .buffering:
            lastRecoveryStatus = "Buffering"
            playbackState = .loading
        case .recovered:
            lastRecoveryStatus = "Recovered"
            if currentTrack != nil {
                playbackState = .playing
                startDisplayUpdates()
            }
        case .failed(let error):
            lastRecoveryStatus = "Recovery failed"
            playbackState = .error
            presentPlaybackAlert(for: error)
        }
        refreshAudioTuningPresentation()
        updateNowPlaying()
    }

    func updateNowPlaying(restartElapsedTicker: Bool = false) {
        guard let currentTrack else {
            nowPlayingElapsedTickSignature = nil
            Task { await nowPlayingPublisher.clear() }
            return
        }

        let playbackRate = playbackState == .playing ? 1.0 : 0.0
        let state = NowPlayingState(
            title: currentTrack.title?.nilIfEmpty ?? "Unknown Track",
            artist: currentTrack.artist?.nilIfEmpty,
            artworkData: currentArtworkData,
            duration: currentDuration > 0 ? currentDuration : currentTrack.duration,
            elapsedTime: currentTime,
            playbackRate: playbackRate,
            mediaType: .audio
        )

        if playbackState == .playing {
            let tickSignature = [
                currentTrack.id,
                String(format: "%.3f", state.duration ?? 0),
                state.artworkData == nil ? "no-artwork" : "artwork"
            ].joined(separator: "|")

            if restartElapsedTicker || nowPlayingElapsedTickSignature != tickSignature {
                nowPlayingElapsedTickSignature = tickSignature
                nowPlayingPublisher.startElapsedTimeUpdates(from: state)
                Task {
                    await nowPlayingPublisher.update(state)
                }
            }
        } else {
            nowPlayingElapsedTickSignature = nil
            nowPlayingPublisher.stopElapsedTimeUpdates()
            Task {
                await nowPlayingPublisher.update(state)
            }
        }
    }

    func queueStateSummary() -> MusicReceiptStateSummary {
        MusicReceiptStateSummary(
            values: [
                "currentTrackID": currentNFT.map { .string($0.id) } ?? .null,
                "upcomingCount": .number(Double(nextAudio.tracks.count)),
                "historyCount": .number(Double(previousAudio.tracks.count))
            ]
        )
    }

    func receiptContext(for nft: NFT?, triggerCause: MusicReceiptTriggerCause) -> MusicReceiptContext {
        MusicReceiptContext(
            triggerCause: triggerCause,
            actor: .user,
            accountAddress: nft?.accountAddressRawValue.nilIfEmpty,
            chain: nft.flatMap { Chain(rawValue: $0.networkRawValue) },
            surface: "music.playback.auraPlayRuntime"
        )
    }

    func recordPlaybackStartedIfPossible() {
        guard let musicReceiptLogger, let currentNFT else {
            return
        }

        let triggerCause = pendingPlaybackTriggerCause ?? .userInitiated
        Task { @MainActor in
            _ = try? await musicReceiptLogger.recordPlaybackStarted(
                mediaID: currentNFT.id,
                title: currentNFT.name,
                artist: currentNFT.artistName,
                context: receiptContext(for: currentNFT, triggerCause: triggerCause)
            )
        }
    }

    func recordQueueChangedIfPossible(
        operation: String,
        affectedMediaIDs: [String],
        beforeSummary: MusicReceiptStateSummary,
        afterSummary: MusicReceiptStateSummary,
        triggerCause: MusicReceiptTriggerCause,
        nft: NFT
    ) async {
        guard let musicReceiptLogger else {
            return
        }

        _ = try? await musicReceiptLogger.recordQueueChanged(
            operation: operation,
            affectedMediaIDs: affectedMediaIDs,
            beforeSummary: beforeSummary,
            afterSummary: afterSummary,
            context: receiptContext(for: nft, triggerCause: triggerCause)
        )
    }

    func recordPlaybackCompletedIfPossible(
        mediaID: String,
        title: String?,
        artist: String?,
        triggerCause: MusicReceiptTriggerCause
    ) async {
        guard let musicReceiptLogger else {
            return
        }

        _ = try? await musicReceiptLogger.recordPlaybackCompleted(
            mediaID: mediaID,
            title: title,
            artist: artist,
            context: receiptContext(for: currentNFT, triggerCause: triggerCause)
        )
    }
}

@MainActor
private final class RuntimeAudioOrchestratorController: AuraPlayEngineControlling {
    private weak var runtime: AuraPlayPlaybackRuntime?
    private(set) var recordedCommands: [String] = []

    let kind: EngineKind = .audio

    func attach(runtime: AuraPlayPlaybackRuntime) {
        self.runtime = runtime
    }

    func load(_ item: AuraPlayableMediaItem) async throws {
        recordedCommands.append("load.\(item.id)")
        try await runtime?.loadAudioItemForOrchestrator(item)
    }

    func play() async throws {
        recordedCommands.append("play")
        try await runtime?.startLoadedAudioItemFromOrchestrator()
    }

    func pause() async {
        recordedCommands.append("pause")
        await runtime?.pauseAudioFromOrchestrator()
    }

    func stop() async {
        recordedCommands.append("stop")
        await runtime?.stopAudioFromOrchestrator()
    }

    func seek(to seconds: TimeInterval) async {
        recordedCommands.append(String(format: "seek.%.1f", seconds))
        await runtime?.seekAudioFromOrchestrator(to: seconds)
    }

    func currentTick() async -> PlaybackTick {
        guard let runtime else {
            return PlaybackTick(currentSeconds: 0, durationSeconds: nil)
        }
        return PlaybackTick(
            currentSeconds: runtime.currentTime,
            durationSeconds: runtime.currentTrack?.duration
        )
    }
}

@MainActor
private final class RuntimeVideoOrchestratorController: AuraPlayEngineControlling {
    private weak var runtime: AuraPlayPlaybackRuntime?
    private(set) var recordedCommands: [String] = []

    let kind: EngineKind = .video

    func attach(runtime: AuraPlayPlaybackRuntime) {
        self.runtime = runtime
    }

    func load(_ item: AuraPlayableMediaItem) async throws {
        recordedCommands.append("load.\(item.id)")
        guard let runtime else {
            throw AuraPlayError.engineStartFailed
        }
        try await runtime.loadVideoItemForOrchestrator(item)
    }

    func play() async throws {
        recordedCommands.append("play")
        runtime?.videoRemoteControls?.play()
    }

    func pause() async {
        recordedCommands.append("pause")
        runtime?.videoRemoteControls?.pause()
    }

    func stop() async {
        recordedCommands.append("stop")
        await runtime?.videoRemoteControls?.stopForAudioHandoff()
    }

    func seek(to seconds: TimeInterval) async {
        recordedCommands.append(String(format: "seek.%.1f", seconds))
        await runtime?.videoRemoteControls?.seek(to: seconds)
    }

    func currentTick() async -> PlaybackTick {
        PlaybackTick(
            currentSeconds: runtime?.videoRemoteControls?.currentPosition ?? 0,
            durationSeconds: nil
        )
    }
}

private final class RuntimePlaybackStateWriter: AuraPlayPlaybackStateWriting, @unchecked Sendable {
    private weak var runtime: AuraPlayPlaybackRuntime?

    func attach(runtime: AuraPlayPlaybackRuntime) {
        self.runtime = runtime
    }

    func writePosition(
        mediaID: String,
        positionMilliseconds: Int,
        durationMilliseconds: Int?,
        at date: Date
    ) async throws {
        guard let service = await runtime?.playbackPositionStateService else { return }
        try await service.writePosition(
            mediaID: mediaID,
            positionMilliseconds: positionMilliseconds,
            durationMilliseconds: durationMilliseconds,
            at: date
        )
    }

    func markCompleted(mediaID: String, at date: Date) async throws {
        guard let service = await runtime?.playbackPositionStateService else { return }
        try await service.markCompleted(mediaID: mediaID, at: date)
    }

    func mostRecentPlaybackState() async throws -> AuraPlayPlaybackPositionStateSnapshot? {
        guard let service = await runtime?.playbackPositionStateService else { return nil }
        return try await service.mostRecentPlaybackState()
    }
}

private struct NFTPlayableMedia: AuraPlayableMedia {
    let id: String
    let sourceURL: URL
    let declaredFormat: String?
    let contentKind: AuraPlayableContentKind
    let cachedFileState: AuraCachedFileState
    let approxLoudnessLUFS: Double?

    var sampleRate: Double {
        48_000
    }

    init(
        id: String,
        sourceURL: URL,
        declaredFormat: String?,
        contentKind: AuraPlayableContentKind,
        cachedFileState: AuraCachedFileState,
        approxLoudnessLUFS: Double?
    ) {
        self.id = id
        self.sourceURL = sourceURL
        self.declaredFormat = declaredFormat
        self.contentKind = contentKind
        self.cachedFileState = cachedFileState
        self.approxLoudnessLUFS = approxLoudnessLUFS
    }

    init(_ item: AuraPlayableMediaItem) {
        self.init(
            id: item.id,
            sourceURL: item.sourceURL,
            declaredFormat: item.declaredFormat,
            contentKind: item.contentKind,
            cachedFileState: item.cachedFileState,
            approxLoudnessLUFS: item.approxLoudnessLUFS
        )
    }
}

private extension AuraPlayTrack {
    init(nft: NFT) {
        self.init(
            id: nft.id,
            title: nft.name,
            artist: nft.artistName,
            duration: 0,
            imageURLString: nft.image?.thumbnailUrl ?? nft.image?.originalUrl
        )
    }

    init(item: AuraPlayableMediaItem) {
        self.init(
            id: item.id,
            title: item.metadata.title,
            artist: item.metadata.artist,
            duration: 0,
            imageURLString: item.metadata.artworkURL?.absoluteString
        )
    }
}

private extension AuraPlayQueuePresentationItem {
    init(nft: NFT, role: AuraPlayQueueItemRole) {
        self.init(
            id: nft.id,
            title: nft.name ?? "Unknown Track",
            artist: nft.artistName,
            imageURLString: nft.image?.thumbnailUrl ?? nft.image?.originalUrl,
            role: role
        )
    }

    init(item: AuraPlayableMediaItem, role: AuraPlayQueueItemRole) {
        self.init(
            id: item.id,
            title: item.metadata.title.nilIfEmpty ?? "Unknown Track",
            artist: item.metadata.artist,
            imageURLString: item.metadata.artworkURL?.absoluteString,
            role: role
        )
    }
}

private extension AuraPlayPlaybackRuntime {
    static func currentItemPresentation(
        nft: NFT,
        track: AuraPlayTrack?,
        media: NFTPlayableMedia?
    ) -> AuraPlayCurrentItemPresentation {
        let chain = nft.network ?? .ethMainnet
        let contractAddress = nft.contract.address?.nilIfEmpty
        let tokenID = nft.tokenId.nilIfEmpty
        let explorerURL = explorerURL(
            chain: chain,
            contractAddress: contractAddress,
            tokenID: tokenID
        )
        return AuraPlayCurrentItemPresentation(
            id: nft.id,
            title: nft.name?.nilIfEmpty ?? track?.title?.nilIfEmpty ?? "Unknown Title",
            creator: nft.artistName?.nilIfEmpty ?? track?.artist?.nilIfEmpty,
            collection: nft.collectionName?.nilIfEmpty ?? nft.collection?.name?.nilIfEmpty,
            artworkURLString: nft.image?.thumbnailUrl ?? nft.image?.originalUrl ?? track?.imageURLString,
            mediaKind: isVideoMedia(nft: nft, media: media) ? .video : .audio,
            chainDisplayName: chain.routingDisplayName,
            contractAddress: contractAddress,
            tokenID: tokenID,
            shareURL: explorerURL,
            explorerURL: explorerURL
        )
    }

    static func isVideoMedia(nft: NFT, media: NFTPlayableMedia?) -> Bool {
        if let media {
            let pathExtension = media.sourceURL.pathExtension.lowercased()
            if ["mp4", "m4v", "mov", "m3u8"].contains(pathExtension) {
                return true
            }
        }
        if let contentType = nft.contentType?.lowercased(), contentType.hasPrefix("video/") {
            return true
        }
        let candidates = [
            nft.securePrimaryAssetUrl,
            nft.primaryAssetUrl,
            nft.secureAnimationUrl,
            nft.animationUrl
        ]
        return candidates.compactMap { $0?.lowercased() }.contains { value in
            ["mp4", "m4v", "mov", "m3u8"].contains { value.hasSuffix(".\($0)") }
        }
    }

    static func explorerURL(chain: Chain, contractAddress: String?, tokenID: String?) -> URL? {
        // Single explorer policy: the tested ExplorerAdapter catalog (P10-007).
        AuraPlayExplorerURLBuilder.nftURL(
            chain: chain,
            contractAddress: contractAddress,
            tokenID: tokenID
        )
    }

    var engineEQPreset: EQPreset {
        switch selectedEQPreset {
        case .flat:
            .flat
        case .bassBoost:
            .bassBoost
        case .vocalClarity:
            .vocalClarity
        case .custom:
            .custom(customEQGains)
        }
    }
}

private extension AuraPlayVisualizationPresentation {
    init(frame: AudioVisualizationFrame) {
        let channelLevels = frame.channels.flatMap { channel -> [Double] in
            [
                Double(channel.rms).squareRoot(),
                Double(channel.peak)
            ]
        }
        let levels = Self.expandedLevels(from: channelLevels, targetCount: 18)
        self.init(
            levels: levels,
            isLive: true,
            message: "Live meter activity from the custom audio engine."
        )
    }

    static func expandedLevels(from source: [Double], targetCount: Int) -> [Double] {
        guard !source.isEmpty else {
            return Array(repeating: 0.08, count: targetCount)
        }

        return (0..<targetCount).map { index in
            let base = source[index % source.count]
            let wave = 0.72 + (Double((index * 37) % 9) * 0.035)
            return min(1, max(0.04, base * wave))
        }
    }
}

private extension AuraPlayCachePresentation {
    init(progress: CacheProgress) {
        let fraction = progress.expectedBytes.map { expectedBytes in
            guard expectedBytes > 0 else { return 0.0 }
            return min(1, max(0, Double(progress.bytesWritten) / Double(expectedBytes)))
        }

        switch progress.state {
        case .notCached:
            self.init(
                state: .notCached,
                progressFraction: nil,
                message: "Available while online. Save offline to keep this track on device.",
                canSaveOffline: true,
                canPin: false,
                canUnpin: false
            )
        case .partial:
            self.init(
                state: .partial,
                progressFraction: fraction,
                message: "Playable while the remaining media continues downloading.",
                canSaveOffline: false,
                canPin: false,
                canUnpin: false
            )
        case .cached:
            self.init(
                state: .cached,
                progressFraction: 1,
                message: "Saved offline.",
                canSaveOffline: false,
                canPin: true,
                canUnpin: false
            )
        case .pinned:
            self.init(
                state: .pinned,
                progressFraction: 1,
                message: "Saved offline and pinned.",
                canSaveOffline: false,
                canPin: false,
                canUnpin: true
            )
        }
    }
}

private extension Array where Element == NFT {
    func uniquedByID() -> [NFT] {
        var seen = Set<String>()
        return filter { nft in
            seen.insert(nft.id).inserted
        }
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
