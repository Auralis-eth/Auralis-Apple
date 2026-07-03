import AVFoundation
#if canImport(AVKit) && canImport(UIKit)
import AVKit
import UIKit
#endif
import CoreGraphics
import CoreMedia
import Foundation
import Testing
@testable import AuraPlayVideoEngine

@Suite("Video format validation")
struct VideoFormatValidationTests {
    @Test("Rejects unresolved and WebM URLs")
    func rejectsUnsupportedURLs() throws {
        let validator = VideoFormatValidator()

        #expect(throws: VideoPlaybackError.unresolvedURL) {
            try validator.validateResolvedPlaybackURL(try #require(URL(string: "ipfs://example/video.mp4")))
        }

        #expect(throws: VideoPlaybackError.unsupportedVideoFormat) {
            try validator.validateResolvedPlaybackURL(try #require(URL(string: "https://example.com/video.webm")))
        }
    }

    @Test("Accepts resolved HTTPS non-WebM URLs")
    func acceptsResolvedHTTPSURL() throws {
        try VideoFormatValidator().validateResolvedPlaybackURL(
            try #require(URL(string: "https://example.com/video.mp4"))
        )
    }
}

@Suite("Playable media adapter")
struct PlayableMediaAdapterTests {
    @Test("Metadata can be created from any conforming host media object")
    func metadataFromPlayableMedia() throws {
        let artworkURL = URL(string: "https://example.com/art.png")
        let media = HostVideoMedia(
            videoMediaID: "nft-42",
            videoTitle: "Token Gate",
            videoArtist: "Aura",
            videoArtworkURL: artworkURL,
            resolvedPlaybackURL: try #require(URL(string: "https://example.com/video.mp4"))
        )

        #expect(VideoMediaMetadata(media: media) == VideoMediaMetadata(
            id: "nft-42",
            title: "Token Gate",
            artist: "Aura",
            artworkURL: artworkURL
        ))
    }

    @MainActor
    @Test("Controller can load through the playable media protocol")
    func controllerLoadsPlayableMedia() async throws {
        let controller = VideoPlayerController()
        defer { controller.teardown() }

        let media = HostVideoMedia(
            videoMediaID: "queue-row-1",
            videoTitle: "Queue Row",
            videoArtist: nil,
            videoArtworkURL: nil,
            resolvedPlaybackURL: try #require(URL(string: "https://example.com/video.mp4"))
        )

        try await controller.load(media: media)
        #expect(controller.player.currentItem != nil)
    }
}

@Suite("Video player lifecycle")
struct VideoPlayerLifecycleTests {
    @MainActor
    @Test("Teardown removes the periodic time observer exactly once")
    func teardownBalancesPeriodicTimeObserver() {
        let registrar = MockTimeObserverRegistrar()
        let controller = VideoPlayerController(timeObserverRegistrar: registrar)

        #expect(registrar.addCount == 1)
        controller.teardown()
        controller.teardown()

        #expect(registrar.removeCount == 1)
        #expect(registrar.unbalancedObserverCount == 0)
    }

    @MainActor
    @Test("Periodic observer is registered at 60fps")
    func periodicObserverUsesSmoothProgressInterval() {
        let registrar = MockTimeObserverRegistrar()
        let controller = VideoPlayerController(timeObserverRegistrar: registrar)
        defer { controller.teardown() }

        #expect(registrar.intervals.first == CMTime(seconds: 1.0 / 60.0, preferredTimescale: 600))
    }

    @MainActor
    @Test("Create-destroy stress leaves no periodic observers registered")
    func createDestroyStressBalancesPeriodicTimeObservers() {
        let registrar = MockTimeObserverRegistrar()

        for _ in 0..<100 {
            let controller = VideoPlayerController(timeObserverRegistrar: registrar)
            controller.teardown()
        }

        #expect(registrar.addCount == 100)
        #expect(registrar.removeCount == 100)
        #expect(registrar.unbalancedObserverCount == 0)
    }

    @MainActor
    @Test("Waiting reason changes are exposed as events")
    func waitingReasonEventsArePublished() async throws {
        let controller = MockVideoController()
        var iterator = controller.events.makeAsyncIterator()

        controller.emit(.waitingReasonChanged(.minimizingStalls))
        let event = await iterator.next()

        #expect(event == .waitingReasonChanged(.minimizingStalls))
        #expect(controller.waitingReason == .minimizingStalls)
    }
}

@Suite("Asset loading")
struct AssetLoadingTests {
    @MainActor
    @Test("Asset loader creates player items with buffering policy")
    func playerItemAppliesBufferingPolicy() async throws {
        let loader = VideoAssetLoader()
        let policy = VideoBufferingPolicy(gatewayHosts: ["gateway.example"])

        let item = try await loader.playerItem(
            for: try #require(URL(string: "https://gateway.example/video.mp4")),
            plan: VideoAssetLoadPlan(preloadKeys: []),
            bufferingPolicy: policy
        )

        #expect(item.preferredForwardBufferDuration == 10)
    }

    @Test("Load plans preserve requested preload keys")
    func loadPlanStoresPreloadKeys() {
        let plan = VideoAssetLoadPlan(preloadKeys: [.tracks, .duration, .commonMetadata])

        #expect(plan.preloadKeys == [.tracks, .duration, .commonMetadata])
    }
}

@Suite("Queue playback")
struct QueuePlaybackTests {
    @MainActor
    @Test("Queue advances to the next item when playback completes")
    func queueAdvancesOnCompletion() async throws {
        let controller = MockVideoController()
        let queue = VideoPlaybackQueueController(controller: controller)
        queue.startObservingCompletion()

        try await queue.replaceQueue(with: [
            HostVideoMedia(
                videoMediaID: "one",
                videoTitle: "One",
                videoArtist: nil,
                videoArtworkURL: nil,
                resolvedPlaybackURL: try #require(URL(string: "https://example.com/one.mp4"))
            ),
            HostVideoMedia(
                videoMediaID: "two",
                videoTitle: "Two",
                videoArtist: nil,
                videoArtworkURL: nil,
                resolvedPlaybackURL: try #require(URL(string: "https://example.com/two.mp4"))
            ),
        ])

        controller.emit(.didPlayToEnd)
        try await expectEventually {
            controller.loadedURLs.last == URL(string: "https://example.com/two.mp4")
        }

        #expect(queue.snapshot.currentMediaID == "two")
    }
}

@Suite("Buffering and fallback policy")
struct BufferingPolicyTests {
    @Test("Gateway hosts get a larger forward buffer")
    func gatewayBufferDuration() throws {
        let policy = VideoBufferingPolicy(gatewayHosts: ["gateway.example"])

        #expect(policy.preferredForwardBufferDuration(for: try #require(URL(string: "https://gateway.example/video.mp4"))) == 10)
        #expect(policy.preferredForwardBufferDuration(for: try #require(URL(string: "https://cdn.example/video.mp4"))) == 0)
    }

    @Test("Fallback only fires after threshold for gateway URLs once")
    func stallFallbackDecision() {
        let coordinator = StallFallbackCoordinator(thresholdSeconds: 8)

        #expect(coordinator.decision(
            stalledDuration: 8,
            isGatewayURL: true,
            hasAlreadyRetried: false,
            lastKnownSeconds: 42
        ) == StallFallbackDecision(shouldAttemptFallback: true, resumeSeconds: 42))

        #expect(coordinator.decision(
            stalledDuration: 8,
            isGatewayURL: false,
            hasAlreadyRetried: false,
            lastKnownSeconds: 42
        ).shouldAttemptFallback == false)

        #expect(coordinator.decision(
            stalledDuration: 8,
            isGatewayURL: true,
            hasAlreadyRetried: true,
            lastKnownSeconds: 42
        ).shouldAttemptFallback == false)
    }
}

@Suite("Playback speed")
struct PlaybackSpeedTests {
    @Test("Every option has the expected display label", arguments: [
        (PlaybackSpeedOption.half, "0.5x"),
        (.threeQuarter, "0.75x"),
        (.normal, "1x"),
        (.oneQuarter, "1.25x"),
        (.oneHalf, "1.5x"),
        (.double, "2x"),
    ])
    func labels(option: PlaybackSpeedOption, label: String) {
        #expect(option.displayLabel == label)
    }

    @Test("Pitch algorithm preserves natural audio")
    func pitchAlgorithms() {
        #expect(PlaybackSpeedOption.half.pitchAlgorithm == .timeDomain)
        #expect(PlaybackSpeedOption.oneHalf.pitchAlgorithm == .spectral)
        #expect(PlaybackSpeedOption.double.pitchAlgorithm == .spectral)
    }
}

@Suite("Presentation analysis")
struct PresentationAnalysisTests {
    @Test("Applies preferred transform before classifying aspect")
    func appliesPreferredTransform() {
        let analyzer = VideoPresentationAnalyzer()
        let info = analyzer.analyze(
            naturalSize: CGSize(width: 1080, height: 1920),
            preferredTransform: CGAffineTransform(rotationAngle: .pi / 2)
        )

        #expect(info.isLandscape)
        #expect(info.aspectRatio > 1.2)
    }

    @Test("Classifies square and portrait videos")
    func classifiesSquareAndPortrait() {
        let analyzer = VideoPresentationAnalyzer()

        let square = analyzer.analyze(naturalSize: CGSize(width: 1000, height: 1000), preferredTransform: .identity)
        #expect(square.isSquare)
        #expect(square.isLandscape == false)

        let portrait = analyzer.analyze(naturalSize: CGSize(width: 1080, height: 1920), preferredTransform: .identity)
        #expect(portrait.isSquare == false)
        #expect(portrait.isLandscape == false)
    }

    @Test("HDR badge requires HDR content and capable display")
    func hdrBadgeGate() {
        let detector = HDRDetector()

        #expect(detector.shouldShowHDRBadge(isHDRContent: true, deviceSupportsHDR: true))
        #expect(detector.shouldShowHDRBadge(isHDRContent: true, deviceSupportsHDR: false) == false)
        #expect(detector.shouldShowHDRBadge(isHDRContent: false, deviceSupportsHDR: true) == false)
    }
}

@Suite("Position persistence")
struct PositionPersistenceTests {
    @Test("Writes on cadence and flush")
    func writesOnCadence() async throws {
        let store = InMemoryPlaybackStateStore()
        let coordinator = VideoPositionPersistenceCoordinator(mediaID: "video-1", store: store, cadenceSeconds: 5)

        try await coordinator.handleTick(PlaybackTick(currentSeconds: 1, durationSeconds: 10), isPlaying: true)
        try await coordinator.handleTick(PlaybackTick(currentSeconds: 3, durationSeconds: 10), isPlaying: true)
        try await coordinator.handleTick(PlaybackTick(currentSeconds: 6, durationSeconds: 10), isPlaying: true)
        try await coordinator.flush(PlaybackTick(currentSeconds: 7, durationSeconds: 10))

        let writes = await store.writes
        #expect(writes.map(\.positionMilliseconds) == [1000, 6000, 7000])
    }

    @Test("Completion marks complete and resets position")
    func completionResetsPosition() async throws {
        let store = InMemoryPlaybackStateStore()
        let coordinator = VideoPositionPersistenceCoordinator(mediaID: "video-1", store: store)

        try await coordinator.markCompleted()

        #expect(await store.completedIDs == ["video-1"])
        #expect(await store.writes.last?.positionMilliseconds == 0)
    }
}

@Suite("Smooth seeking")
struct SmoothSeekingTests {
    @Test("Rapid requests coalesce and land on the newest target")
    func coalescesRapidRequests() async {
        let coordinator = ChaseTimeSeekCoordinator()
        let recorder = SeekRecorder()
        let tolerance = VideoSeekKind.scrub.tolerance

        await withTaskGroup(of: Void.self) { group in
            for target in 1...20 {
                group.addTask {
                    await coordinator.requestSeek(to: Double(target), tolerance: tolerance) { target, _ in
                        await recorder.record(target)
                        try? await Task.sleep(for: .milliseconds(1))
                        return true
                    }
                }
            }
        }

        let targets = await recorder.targets
        #expect(targets.last == 20)
        #expect(targets.count < 20)
    }
}

@Suite("Preferences")
struct VideoPreferenceTests {
    @MainActor
    @Test("Playback speed stores and restores the selected option")
    func playbackSpeedPreference() throws {
        let defaults = try #require(UserDefaults(suiteName: "PlaybackSpeedPreferenceTests"))
        defaults.removePersistentDomain(forName: "PlaybackSpeedPreferenceTests")
        let player = AVPlayer(playerItem: AVPlayerItem(url: try #require(URL(string: "https://example.com/video.mp4"))))
        let controller = PlaybackSpeedController(userDefaults: defaults)

        try controller.setSpeed(.oneHalf, on: player)

        #expect(defaults.double(forKey: PlaybackSpeedController.preferenceKey) == 1.5)
        #expect(PlaybackSpeedController(userDefaults: defaults).storedSpeed == .oneHalf)
    }

    @MainActor
    @Test("VideoPlayerController resumes with the stored playback speed")
    func controllerUsesStoredSpeedOnPlay() async throws {
        let defaults = try #require(UserDefaults(suiteName: "ControllerPlaybackSpeedPreferenceTests"))
        defaults.removePersistentDomain(forName: "ControllerPlaybackSpeedPreferenceTests")
        defaults.set(PlaybackSpeedOption.oneHalf.rawValue, forKey: PlaybackSpeedController.preferenceKey)
        let player = AVPlayer()
        let controller = VideoPlayerController(
            player: player,
            playbackSpeedController: PlaybackSpeedController(userDefaults: defaults),
            timeObserverRegistrar: MockTimeObserverRegistrar()
        )
        defer { controller.teardown() }

        try await controller.load(resolvedURL: try #require(URL(string: "https://example.com/video.mp4")))
        #expect(player.currentItem?.audioTimePitchAlgorithm == .spectral)

        controller.pause()
        controller.play()

        #expect(player.currentItem?.audioTimePitchAlgorithm == .spectral)
        #expect(player.rate == Float(PlaybackSpeedOption.oneHalf.rawValue))
    }

    @MainActor
    @Test("Subtitle preference helpers expose stored language")
    func subtitlePreference() throws {
        let defaults = try #require(UserDefaults(suiteName: "SubtitlePreferenceTests"))
        defaults.removePersistentDomain(forName: "SubtitlePreferenceTests")
        defaults.set("es", forKey: SubtitleTrackManager.preferredLanguageKey)

        #expect(SubtitleTrackManager(userDefaults: defaults).preferredLanguageCode == "es")
    }
}

@Suite("Subtitle and audio description tracks")
struct SubtitleAndAudioDescriptionTests {
    @MainActor
    @Test("Items without legible or accessibility-audio groups return empty arrays")
    func emptyMediaSelectionGroupsReturnEmptyArrays() async throws {
        let item = AVPlayerItem(asset: AVMutableComposition())
        let manager = SubtitleTrackManager()

        #expect(try await manager.availableTracks(for: item).isEmpty)
        #expect(try await manager.availableAudioDescriptionTracks(for: item).isEmpty)
    }
}

#if canImport(AVKit) && canImport(UIKit)
@Suite("System video integrations")
struct SystemVideoIntegrationTests {
    @MainActor
    @Test("Video route picker prioritizes video devices")
    func routePickerPrioritizesVideoDevices() {
        let picker = AVRoutePickerView()

        VideoRoutePickerView.configure(picker)

        #expect(picker.prioritizesVideoDevices)
    }

    @MainActor
    @Test("PiP delegate callbacks publish state and restoration")
    func pictureInPictureDelegateCallbacks() throws {
        let layer = AVPlayerLayer(player: AVPlayer())
        let controller = PictureInPictureController(playerLayer: layer)
        var states: [PiPState] = []
        var restoreRequested = false
        controller.onStateChanged = { states.append($0) }
        controller.onRestoreRequested = {
            restoreRequested = true
            return true
        }
        controller.handleDidStartPictureInPicture()
        controller.handleDidStopPictureInPicture()
        let restoreResult = controller.handleRestoreUserInterfaceForPictureInPictureStop()

        #expect(states.contains(.active))
        #expect(states.last == .inactive)
        #expect(restoreRequested)
        #expect(restoreResult)
    }
}
#endif

@Suite("HDR metadata fallback")
struct HDRMetadataFallbackTests {
    @Test("Detects HDR from wide-color primaries and HDR transfer metadata")
    func detectsHDRFromFormatDescriptionExtensions() throws {
        var formatDescription: CMFormatDescription?
        let extensions: [CFString: Any] = [
            kCMFormatDescriptionExtension_ColorPrimaries: kCMFormatDescriptionColorPrimaries_ITU_R_2020,
            kCMFormatDescriptionExtension_TransferFunction: kCMFormatDescriptionTransferFunction_SMPTE_ST_2084_PQ,
        ]
        let status = CMVideoFormatDescriptionCreate(
            allocator: kCFAllocatorDefault,
            codecType: kCMVideoCodecType_HEVC,
            width: 1920,
            height: 1080,
            extensions: extensions as CFDictionary,
            formatDescriptionOut: &formatDescription
        )

        #expect(status == noErr)
        #expect(HDRDetector().isHDR(formatDescriptions: [try #require(formatDescription)]))
    }
}

@Suite("Poster cache")
struct PosterCacheTests {
    @Test("Cached poster returns without writing a duplicate")
    func cachedPosterHit() async throws {
        #if canImport(UIKit) || canImport(AppKit)
        let image = makePlatformImage()
        let cache = InMemoryVideoArtworkCache(initial: ["video-1": image])
        let generator = CachedPosterFrameGenerator(cache: cache)
        let poster = await generator.poster(
            for: AVURLAsset(url: try #require(URL(string: "https://example.com/video.mp4"))),
            mediaID: "video-1"
        )

        #expect(poster != nil)
        #expect(await cache.storeCount == 0)
        #endif
    }
}

@Suite("Progressive caching and offline downloads")
struct ProgressiveCachingAndOfflineDownloadTests {
    @Test("Progressive cache mapper rewrites only progressive HTTPS URLs")
    func mapperRewritesProgressiveURLs() throws {
        let mapper = ProgressiveVideoCacheURLMapper(configuration: ProgressiveVideoCacheConfiguration(customScheme: "cache-video"))
        let mp4 = try requiredURL("https://cdn.example/video.mp4")
        let hls = try requiredURL("https://cdn.example/master.m3u8")

        let assetURL = mapper.assetURL(for: mp4)

        #expect(assetURL.scheme == "cache-video")
        #expect(mapper.originalURL(for: assetURL) == mp4)
        #expect(mapper.assetURL(for: hls) == hls)
    }

    @Test("Progressive cache stores sparse ranges and marks complete when contiguous")
    func cacheStoreMergesRanges() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ProgressiveCacheTests-\(UUID().uuidString)", isDirectory: true)
        let store = ProgressiveVideoCacheStore(configuration: ProgressiveVideoCacheConfiguration(cacheDirectory: directory))
        let url = try requiredURL("https://cdn.example/video.mp4")

        _ = try await store.store(data: Data([0, 1]), for: url, offset: 0, contentLength: 4, contentType: "video/mp4")
        let finalRecord = try await store.store(data: Data([2, 3]), for: url, offset: 2, contentLength: 4, contentType: "video/mp4")
        let cached = try await store.cachedData(for: url, offset: 1, length: 2)

        #expect(finalRecord.cachedRanges == [CachedByteRange(offset: 0, length: 4)])
        #expect(finalRecord.isComplete)
        #expect(cached == Data([1, 2]))
        #expect(await store.localFileURL(for: url) != nil)
    }

    @Test("Offline manifest persists available local playback records")
    func offlineManifestPersistsRecords() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("OfflineManifestTests-\(UUID().uuidString)", isDirectory: true)
        let store = VideoOfflineManifestStore(directory: directory)
        let sourceURL = try requiredURL("https://cdn.example/video.mp4")
        let localURL = directory.appendingPathComponent("video.mp4")
        let record = VideoOfflineAssetRecord(
            sourceURL: sourceURL,
            localFileURL: localURL,
            kind: .progressiveFile,
            state: .available,
            progress: 1
        )

        try await store.upsert(record)
        let restored = try await VideoOfflineManifestStore(directory: directory).record(for: sourceURL)

        #expect(restored == record)
    }
}

@Suite("Integration coordinator")
struct VideoPlaybackIntegrationCoordinatorTests {
    @MainActor
    @Test("Remote skip commands use the video seek path")
    func remoteSkipUsesSeekPath() async throws {
        let controller = MockVideoController()
        let remoteCommands = MockRemoteCommandStream()
        let nowPlaying = MockNowPlayingPublisher()
        let coordinator = VideoPlaybackIntegrationCoordinator(
            controller: controller,
            metadata: VideoMediaMetadata(id: "video-1", title: "Video", artist: nil, artworkURL: nil),
            nowPlayingPublisher: nowPlaying,
            remoteCommandStream: remoteCommands
        )
        coordinator.startObserving()
        controller.emit(.tick(PlaybackTick(currentSeconds: 30, durationSeconds: 100)))
        try await expectEventually { await nowPlaying.publishedTicks.last?.currentSeconds == 30 }
        remoteCommands.emit(.skipForward(seconds: 15))

        try await expectEventually {
            controller.seekRequests.last?.seconds == 45 && controller.seekRequests.last?.kind == .skip
        }
        await coordinator.stop()
    }

    @MainActor
    @Test("Session pause flushes position and interruption resume plays")
    func sessionEventsControlPlayback() async throws {
        let controller = MockVideoController()
        let session = MockMediaSessionManager()
        let store = InMemoryPlaybackStateStore()
        let coordinator = VideoPlaybackIntegrationCoordinator(
            controller: controller,
            metadata: VideoMediaMetadata(id: "video-1", title: "Video", artist: nil, artworkURL: nil),
            playbackStateStore: store,
            mediaSessionManager: session
        )
        coordinator.startObserving()
        controller.play()
        controller.emit(.tick(PlaybackTick(currentSeconds: 12, durationSeconds: 100)))
        try await expectEventually { await store.writes.last?.positionMilliseconds == 12_000 }
        session.emit(.shouldPause)
        session.emit(.interruptionEndedShouldResume)

        try await expectEventually { controller.pauseCount == 1 && controller.playCount == 2 }
        let writes = await store.writes
        #expect(writes.last?.positionMilliseconds == 12_000)
        await coordinator.stop()
    }

    @MainActor
    @Test("Gateway stall resolves the next URL and resumes at last tick")
    func gatewayFallbackSwapsItem() async throws {
        let controller = MockVideoController()
        let fallbackURL = try #require(URL(string: String("https://gateway-two.example/video.mp4")))
        let resolver = MockGatewayResolver(nextURL: fallbackURL)
        let coordinator = VideoPlaybackIntegrationCoordinator(
            controller: controller,
            metadata: VideoMediaMetadata(id: "video-1", title: "Video", artist: nil, artworkURL: nil),
            gatewayResolver: resolver,
            bufferingPolicy: VideoBufferingPolicy(gatewayHosts: ["gateway-one.example"]),
            stallFallbackCoordinator: StallFallbackCoordinator(thresholdSeconds: 0.01)
        )
        coordinator.startObserving()
        try await coordinator.load(media: HostVideoMedia(
            videoMediaID: "video-1",
            videoTitle: "Video",
            videoArtist: nil,
            videoArtworkURL: nil,
            resolvedPlaybackURL: try #require(URL(string: "https://gateway-one.example/video.mp4"))
        ))
        controller.emit(.tick(PlaybackTick(currentSeconds: 42, durationSeconds: 100)))
        controller.emit(.stateChanged(.buffering))
        controller.emit(.playbackStalled)

        try await expectEventually {
            controller.loadedURLs.last == URL(string: "https://gateway-two.example/video.mp4")
                && controller.seekRequests.last?.seconds == 42
        }
        #expect(await resolver.requestedURLs == [URL(string: "https://gateway-one.example/video.mp4")])
        await coordinator.stop()
    }

    @MainActor
    @Test("Gateway stall fallback is skipped when playback makes progress")
    func gatewayFallbackSkipsWhenTickAdvances() async throws {
        let controller = MockVideoController()
        let resolver = MockGatewayResolver(nextURL: try requiredURL("https://gateway-two.example/video.mp4"))
        let coordinator = VideoPlaybackIntegrationCoordinator(
            controller: controller,
            metadata: VideoMediaMetadata(id: "video-1", title: "Video", artist: nil, artworkURL: nil),
            gatewayResolver: resolver,
            bufferingPolicy: VideoBufferingPolicy(gatewayHosts: ["gateway-one.example"]),
            stallFallbackCoordinator: StallFallbackCoordinator(thresholdSeconds: 0.02)
        )
        coordinator.startObserving()
        try await coordinator.load(media: HostVideoMedia(
            videoMediaID: "video-1",
            videoTitle: "Video",
            videoArtist: nil,
            videoArtworkURL: nil,
            resolvedPlaybackURL: try #require(URL(string: "https://gateway-one.example/video.mp4"))
        ))
        controller.emit(.tick(PlaybackTick(currentSeconds: 42, durationSeconds: 100)))
        controller.emit(.stateChanged(.buffering))
        controller.emit(.playbackStalled)
        controller.emit(.tick(PlaybackTick(currentSeconds: 43, durationSeconds: 100)))
        try await Task.sleep(for: .milliseconds(50))

        #expect(await resolver.requestedURLs.isEmpty)
        #expect(controller.loadedURLs == [URL(string: "https://gateway-one.example/video.mp4")])
        await coordinator.stop()
    }

    @MainActor
    @Test("End event marks playback complete")
    func endEventMarksComplete() async throws {
        let controller = MockVideoController()
        let store = InMemoryPlaybackStateStore()
        let coordinator = VideoPlaybackIntegrationCoordinator(
            controller: controller,
            metadata: VideoMediaMetadata(id: "video-1", title: "Video", artist: nil, artworkURL: nil),
            playbackStateStore: store
        )
        coordinator.startObserving()
        controller.emit(.didPlayToEnd)

        try await expectEventually { await store.completedIDs == ["video-1"] }
        #expect(await store.writes.last?.positionMilliseconds == 0)
        await coordinator.stop()
    }
}

actor InMemoryPlaybackStateStore: VideoPlaybackStateStoring {
    private(set) var writes: [StoredVideoPlaybackPosition] = []
    private(set) var completedIDs: [String] = []

    func storedPosition(for mediaID: String) async throws -> StoredVideoPlaybackPosition? {
        writes.last { $0.mediaID == mediaID }
    }

    func writePosition(_ position: StoredVideoPlaybackPosition) async throws {
        writes.append(position)
    }

    func markCompleted(mediaID: String) async throws {
        completedIDs.append(mediaID)
    }
}

actor SeekRecorder {
    private(set) var targets: [Double] = []

    func record(_ target: Double) {
        targets.append(target)
    }
}

@MainActor
final class MockVideoController: VideoPlayerControlling {
    let player = AVPlayer()
    let events: AsyncStream<VideoPlaybackEvent>
    private let continuation: AsyncStream<VideoPlaybackEvent>.Continuation
    private(set) var state: VideoPlaybackState = .idle
    private(set) var waitingReason: VideoWaitingReason?
    private(set) var loadedURLs: [URL] = []
    private(set) var seekRequests: [(seconds: Double, kind: VideoSeekKind)] = []
    private(set) var playCount = 0
    private(set) var pauseCount = 0

    init() {
        var continuation: AsyncStream<VideoPlaybackEvent>.Continuation!
        self.events = AsyncStream { continuation = $0 }
        self.continuation = continuation
    }

    func load(resolvedURL: URL) async throws {
        loadedURLs.append(resolvedURL)
        state = .ready(durationSeconds: nil)
    }

    func load(media: some VideoPlayableMedia) async throws {
        try await load(resolvedURL: media.resolvedPlaybackURL)
    }

    func play() {
        playCount += 1
        state = .playing
    }

    func pause() {
        pauseCount += 1
        state = .paused
    }

    func seek(to seconds: Double, kind: VideoSeekKind) async {
        seekRequests.append((seconds, kind))
    }

    func teardown() {
        state = .idle
        continuation.finish()
    }

    func emit(_ event: VideoPlaybackEvent) {
        if case .stateChanged(let state) = event {
            self.state = state
        }
        if case .waitingReasonChanged(let waitingReason) = event {
            self.waitingReason = waitingReason
        }
        continuation.yield(event)
    }
}

actor MockNowPlayingPublisher: VideoNowPlayingPublishing {
    private(set) var publishedTicks: [PlaybackTick] = []
    private(set) var clearedMetadataIDs: [String] = []

    func publishVideo(metadata: VideoMediaMetadata, tick: PlaybackTick, isPlaying: Bool) async {
        publishedTicks.append(tick)
    }

    func clearVideo(metadataID: String) async {
        clearedMetadataIDs.append(metadataID)
    }
}

@MainActor
final class MockTimeObserverRegistrar: VideoTimeObserverRegistering {
    private var activeTokens: Set<ObjectIdentifier> = []
    private(set) var addCount = 0
    private(set) var removeCount = 0
    private(set) var intervals: [CMTime] = []

    var unbalancedObserverCount: Int {
        activeTokens.count
    }

    func addPeriodicTimeObserver(
        forInterval interval: CMTime,
        queue: DispatchQueue?,
        using block: @escaping @Sendable (CMTime) -> Void
    ) -> Any {
        let token = MockTimeObserverToken()
        activeTokens.insert(ObjectIdentifier(token))
        addCount += 1
        intervals.append(interval)
        return token
    }

    func removeTimeObserver(_ observer: Any) {
        guard let token = observer as? MockTimeObserverToken else { return }
        if activeTokens.remove(ObjectIdentifier(token)) != nil {
            removeCount += 1
        }
    }
}

private final class MockTimeObserverToken {}

final class MockRemoteCommandStream: VideoRemoteCommandStreaming, @unchecked Sendable {
    let commands: AsyncStream<VideoRemoteCommand>
    private let continuation: AsyncStream<VideoRemoteCommand>.Continuation

    init() {
        var continuation: AsyncStream<VideoRemoteCommand>.Continuation!
        self.commands = AsyncStream { continuation = $0 }
        self.continuation = continuation
    }

    func emit(_ command: VideoRemoteCommand) {
        continuation.yield(command)
    }
}

final class MockMediaSessionManager: VideoMediaSessionManaging, @unchecked Sendable {
    let events: AsyncStream<VideoMediaSessionEvent>
    private let continuation: AsyncStream<VideoMediaSessionEvent>.Continuation
    private(set) var configureCallCount = 0

    init() {
        var continuation: AsyncStream<VideoMediaSessionEvent>.Continuation!
        self.events = AsyncStream { continuation = $0 }
        self.continuation = continuation
    }

    func configureForVideoPlayback() async throws {
        configureCallCount += 1
    }

    func emit(_ event: VideoMediaSessionEvent) {
        continuation.yield(event)
    }
}

actor MockGatewayResolver: VideoGatewayResolving {
    private let nextURL: URL?
    private(set) var requestedURLs: [URL] = []

    init(nextURL: URL?) {
        self.nextURL = nextURL
    }

    func nextResolvedURL(after failedURL: URL) async throws -> URL? {
        requestedURLs.append(failedURL)
        return nextURL
    }
}

actor InMemoryVideoArtworkCache: VideoArtworkCaching {
    private var posters: [String: PlatformImage]
    private(set) var storeCount = 0

    init(initial: [String: PlatformImage] = [:]) {
        self.posters = initial
    }

    func cachedPoster(for mediaID: String) async -> PlatformImage? {
        posters[mediaID]
    }

    func storePoster(_ image: PlatformImage, for mediaID: String) async {
        storeCount += 1
        posters[mediaID] = image
    }
}

func makePlatformImage() -> PlatformImage {
    #if canImport(UIKit)
    PlatformImage()
    #elseif canImport(AppKit)
    PlatformImage(size: CGSize(width: 1, height: 1))
    #endif
}

func requiredURL(_ value: String) throws -> URL {
    try #require(URL(string: value))
}

@MainActor
func expectEventually(
    timeoutNanoseconds: UInt64 = 1_000_000_000,
    condition: @MainActor @escaping () async -> Bool
) async throws {
    let deadline = ContinuousClock.now + .nanoseconds(Int(timeoutNanoseconds))
    while ContinuousClock.now < deadline {
        if await condition() {
            return
        }
        try await Task.sleep(for: .milliseconds(10))
    }
    #expect(await condition())
}

private struct HostVideoMedia: VideoPlayableMedia {
    let videoMediaID: String
    let videoTitle: String
    let videoArtist: String?
    let videoArtworkURL: URL?
    let resolvedPlaybackURL: URL
}
