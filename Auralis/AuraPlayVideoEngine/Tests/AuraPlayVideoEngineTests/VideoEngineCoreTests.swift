import AVFoundation
#if canImport(AVKit) && canImport(UIKit) && !os(visionOS)
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

    @MainActor
    @Test("Controller can load the shared core playable media item")
    func controllerLoadsCorePlayableMediaItem() async throws {
        let controller = VideoPlayerController()
        defer { controller.teardown() }

        let item = AuraPlayableMediaItem(
            id: "shared-video-1",
            sourceURL: try #require(URL(string: "https://example.com/shared-video.mp4")),
            declaredFormat: "mp4",
            contentKind: .video,
            metadata: MediaMetadata(
                id: "shared-video-1",
                title: "Shared Video",
                artist: "Aura",
                artworkURL: nil
            )
        )

        try await controller.load(media: item)
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
    @Test("Teardown finishes the playback event stream")
    func teardownFinishesPlaybackEventStream() async {
        let controller = VideoPlayerController(timeObserverRegistrar: MockTimeObserverRegistrar())
        var iterator = controller.events.makeAsyncIterator()

        controller.teardown()

        let nextEvent = await iterator.next()
        #expect(nextEvent == nil)
    }

    @MainActor
    @Test("Load after teardown fails instead of reviving a finished event stream")
    func loadAfterTeardownFails() async throws {
        let registrar = MockTimeObserverRegistrar()
        let controller = VideoPlayerController(
            assetLoadPlan: VideoAssetLoadPlan(preloadKeys: []),
            timeObserverRegistrar: registrar
        )

        controller.teardown()
        controller.play()

        await #expect(throws: VideoPlaybackError.controllerTornDown) {
            try await controller.load(resolvedURL: try #require(URL(string: "https://example.com/video.mp4")))
        }
        #expect(registrar.addCount == 1)
        #expect(registrar.removeCount == 1)
        #expect(registrar.unbalancedObserverCount == 0)
    }

    @MainActor
    @Test("Pause and seek after teardown are no-ops")
    func pauseAndSeekAfterTeardownAreNoOps() async {
        let controller = VideoPlayerController(timeObserverRegistrar: MockTimeObserverRegistrar())

        controller.teardown()
        controller.pause()
        await controller.seek(to: 12, kind: .scrub)

        #expect(controller.state == .idle)
    }

    @MainActor
    @Test("Playback event stream keeps only the newest buffered events")
    func playbackEventStreamBuffersNewestEvents() async throws {
        let controller = VideoPlayerController(timeObserverRegistrar: MockTimeObserverRegistrar())
        var iterator = controller.events.makeAsyncIterator()
        for _ in 0..<200 {
            controller.play()
            controller.pause()
        }

        controller.teardown()

        var count = 0
        while await iterator.next() != nil {
            count += 1
        }

        #expect(count <= 120)
    }

    @MainActor
    @Test("Each events access provides an independent stream for concurrent observers")
    func eventsSupportMultipleConsumers() async {
        let controller = VideoPlayerController(timeObserverRegistrar: MockTimeObserverRegistrar())
        var first = controller.events.makeAsyncIterator()
        var second = controller.events.makeAsyncIterator()

        controller.play()

        let firstEvent = await first.next()
        let secondEvent = await second.next()

        #expect(firstEvent == .stateChanged(.playing))
        #expect(secondEvent == .stateChanged(.playing))
        controller.teardown()
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

@Suite("Offline download records")
struct OfflineDownloadRecordTests {
    @Test("Cancelled URLSession completions stay cancelled", arguments: [
        VideoOfflineAssetKind.progressiveFile,
        .hlsPackage,
    ])
    func cancelledCompletionMapsToCancelled(kind: VideoOfflineAssetKind) throws {
        let sourceURL = try #require(URL(string: "https://example.com/video.mp4"))
        let record = VideoOfflineDownloadCompletionRecord.record(
            for: URLError(.cancelled),
            sourceURL: sourceURL,
            kind: kind
        )

        #expect(record.sourceURL == sourceURL)
        #expect(record.kind == kind)
        #expect(record.state == .cancelled)
        #expect(record.errorDescription == nil)
    }

    @Test("NSURLErrorCancelled completions stay cancelled")
    func nsURLCancelledCompletionMapsToCancelled() throws {
        let sourceURL = try #require(URL(string: "https://example.com/video.m3u8"))
        let error = NSError(domain: NSURLErrorDomain, code: NSURLErrorCancelled)
        let record = VideoOfflineDownloadCompletionRecord.record(
            for: error,
            sourceURL: sourceURL,
            kind: .hlsPackage
        )

        #expect(record.state == .cancelled)
        #expect(record.errorDescription == nil)
    }

    @Test("Failed completion does not overwrite a cancelled manifest record")
    func failedCompletionDoesNotOverwriteCancelledRecord() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("VideoOfflineManifestStoreTests-\(UUID().uuidString)", isDirectory: true)
        let store = VideoOfflineManifestStore(directory: directory)
        defer { try? FileManager.default.removeItem(at: directory) }
        let sourceURL = try #require(URL(string: "https://example.com/video.mp4"))

        try await store.upsert(VideoOfflineAssetRecord(
            sourceURL: sourceURL,
            kind: .progressiveFile,
            state: .cancelled
        ))
        try await store.upsert(VideoOfflineAssetRecord(
            sourceURL: sourceURL,
            kind: .progressiveFile,
            state: .failed,
            errorDescription: "cancel callback raced with delegate completion"
        ))

        let record = try await store.record(for: sourceURL)
        #expect(record?.state == .cancelled)
        #expect(record?.errorDescription == nil)
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

    @MainActor
    @Test("Completion observation does not retain the queue forever")
    func completionObservationDoesNotRetainQueue() async throws {
        let controller = MockVideoController()
        weak var weakQueue: VideoPlaybackQueueController?

        do {
            let queue = VideoPlaybackQueueController(controller: controller)
            weakQueue = queue
            queue.startObservingCompletion()
        }

        try await Task.sleep(for: .milliseconds(10))
        #expect(weakQueue == nil)
    }
}

@Suite("Multiview playback coordination")
struct MultiviewPlaybackTests {
    @MainActor
    @Test("Synchronized mode connects every participant to one coordination medium")
    func synchronizedModeCoordinatesParticipants() throws {
        let playbackCoordinator = MockPlaybackCoordinator()
        let routingArbiter = MockRoutingPlaybackArbiter()
        let networkPrioritizer = MockNetworkResourcePrioritizer()
        let coordinator = VideoMultiviewCoordinator(
            playbackCoordinator: playbackCoordinator,
            routingArbiter: routingArbiter,
            networkPrioritizer: networkPrioritizer
        )
        let first = MockVideoController()
        let second = MockVideoController()

        try coordinator.register(VideoMultiviewParticipant(id: "first", controller: first))
        try coordinator.register(VideoMultiviewParticipant(id: "second", controller: second))

        #expect(playbackCoordinator.coordinatedPlayerIDs == [
            ObjectIdentifier(first.player),
            ObjectIdentifier(second.player)
        ])
        #expect(Set(playbackCoordinator.coordinationMediumIDs).count == 1)
    }

    @MainActor
    @Test("Independent mode does not coordinate playback")
    func independentModeDoesNotCoordinateParticipants() throws {
        let playbackCoordinator = MockPlaybackCoordinator()
        let coordinator = VideoMultiviewCoordinator(
            syncMode: .independent,
            playbackCoordinator: playbackCoordinator,
            routingArbiter: MockRoutingPlaybackArbiter(),
            networkPrioritizer: MockNetworkResourcePrioritizer()
        )

        try coordinator.register(VideoMultiviewParticipant(id: "first", controller: MockVideoController()))

        #expect(playbackCoordinator.coordinatedPlayerIDs.isEmpty)
    }

    @MainActor
    @Test("Duplicate participant IDs are rejected")
    func duplicateParticipantIDsAreRejected() throws {
        let controller = MockVideoController()
        let coordinator = VideoMultiviewCoordinator(
            playbackCoordinator: MockPlaybackCoordinator(),
            routingArbiter: MockRoutingPlaybackArbiter(),
            networkPrioritizer: MockNetworkResourcePrioritizer()
        )

        try coordinator.register(VideoMultiviewParticipant(id: "main", controller: controller))

        #expect(throws: VideoMultiviewError.duplicateParticipant("main")) {
            try coordinator.register(VideoMultiviewParticipant(id: "main", controller: MockVideoController()))
        }
    }

    @MainActor
    @Test("Preferred routing roles update the routing arbiter")
    func preferredRoutingRolesUpdateArbiter() throws {
        let routingArbiter = MockRoutingPlaybackArbiter()
        let coordinator = VideoMultiviewCoordinator(
            playbackCoordinator: MockPlaybackCoordinator(),
            routingArbiter: routingArbiter,
            networkPrioritizer: MockNetworkResourcePrioritizer()
        )
        let primary = MockVideoController()
        let audio = MockVideoController()

        try coordinator.register(VideoMultiviewParticipant(
            id: "primary",
            controller: primary,
            role: [.primary, .externalPlaybackPreferred]
        ))
        try coordinator.register(VideoMultiviewParticipant(
            id: "audio",
            controller: audio,
            role: [.secondary, .nonMixableAudioPreferred]
        ))

        #expect(routingArbiter.externalPlaybackPlayerID == ObjectIdentifier(primary.player))
        #expect(routingArbiter.nonMixableAudioPlayerID == ObjectIdentifier(audio.player))
    }

    @MainActor
    @Test("Unregister clears stale routing preferences")
    func unregisterClearsStaleRoutingPreferences() throws {
        let routingArbiter = MockRoutingPlaybackArbiter()
        let coordinator = VideoMultiviewCoordinator(
            playbackCoordinator: MockPlaybackCoordinator(),
            routingArbiter: routingArbiter,
            networkPrioritizer: MockNetworkResourcePrioritizer()
        )
        let controller = MockVideoController()

        try coordinator.register(VideoMultiviewParticipant(
            id: "primary",
            controller: controller,
            role: [.externalPlaybackPreferred, .nonMixableAudioPreferred]
        ))
        coordinator.unregister(id: "primary")

        #expect(routingArbiter.externalPlaybackPlayerID == nil)
        #expect(routingArbiter.nonMixableAudioPlayerID == nil)
    }

    @MainActor
    @Test("Network priority updates are applied to participant players")
    func networkPriorityUpdatesAreApplied() throws {
        let networkPrioritizer = MockNetworkResourcePrioritizer()
        let coordinator = VideoMultiviewCoordinator(
            playbackCoordinator: MockPlaybackCoordinator(),
            routingArbiter: MockRoutingPlaybackArbiter(),
            networkPrioritizer: networkPrioritizer
        )
        let controller = MockVideoController()

        try coordinator.register(VideoMultiviewParticipant(
            id: "primary",
            controller: controller,
            networkPriority: .high
        ))
        coordinator.updateNetworkPriority(.low, for: "primary")

        #expect(networkPrioritizer.appliedPriorities == [
            ObjectIdentifier(controller.player): [.high, .low]
        ])
    }

    @MainActor
    @Test("Coordination errors leave participant state unchanged")
    func coordinationErrorsLeaveParticipantStateUnchanged() throws {
        let playbackCoordinator = MockPlaybackCoordinator(error: MockMultiviewError.coordinationFailed)
        let coordinator = VideoMultiviewCoordinator(
            playbackCoordinator: playbackCoordinator,
            routingArbiter: MockRoutingPlaybackArbiter(),
            networkPrioritizer: MockNetworkResourcePrioritizer()
        )

        #expect(throws: MockMultiviewError.coordinationFailed) {
            try coordinator.register(VideoMultiviewParticipant(id: "first", controller: MockVideoController()))
        }
        #expect(coordinator.participantIDs.isEmpty)
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

@Suite("Immersive playback policy")
struct ImmersivePlaybackPolicyTests {
    @Test("2D content remains standard 2D on every surface")
    func twoDimensionalContentUsesStandardPresentation() {
        let policy = VideoImmersivePlaybackPolicy()

        #expect(policy.presentation(profile: .standard2D, surface: .customPlayerLayer) == .standardTwoDimensional)
        #expect(policy.presentation(profile: .standard2D, surface: .avKitExpanded) == .standardTwoDimensional)
        #expect(policy.presentation(profile: .standard2D, surface: .quickLookPreview) == .standardTwoDimensional)
    }

    @Test("Stereo and spatial content map each surface to its honest presentation")
    func stereoAndSpatialContentMapToSurfacePresentation() {
        let policy = VideoImmersivePlaybackPolicy()

        #expect(policy.presentation(profile: .spatialVideo, surface: .customPlayerLayer) == .inlineTwoDimensionalSpatialFallback)
        #expect(policy.presentation(profile: .stereo3D, surface: .avKitExpanded) == .stereoFullscreen)
        #expect(policy.presentation(profile: .spatialVideo, surface: .quickLookPreview) == .quickLookSystemPresentation)
    }

    @Test("Projected and immersive media route through immersive host surfaces")
    func projectedAndImmersiveProfilesUseImmersiveHostSurfaces() {
        let policy = VideoImmersivePlaybackPolicy()

        #expect(policy.presentation(profile: .appleProjectedMedia, surface: .avKitExpanded) == .avKitExpandedImmersivePortal)
        #expect(policy.presentation(profile: .appleImmersiveVideo, surface: .avKitImmersive) == .avKitImmersiveExperience)
        #expect(policy.presentation(profile: .appleProjectedMedia, surface: .realityKitProgressiveImmersive) == .realityKitProgressiveImmersive)
        #expect(policy.presentation(profile: .spatialVideo, surface: .realityKitFullImmersive) == .realityKitFullImmersive)
    }

    @Test("Host system presentation flag excludes local-only surfaces")
    func hostSystemPresentationFlag() {
        #expect(VideoImmersivePlaybackPresentation.quickLookSystemPresentation.usesHostSystemPresentation)
        #expect(VideoImmersivePlaybackPresentation.stereoFullscreen.usesHostSystemPresentation == false)
    }
}

@Suite("Media inspection")
struct MediaInspectionTests {
    @MainActor
    @Test("Capabilities use the injected immersive profile detector")
    func capabilitiesUseImmersiveProfileDetector() async throws {
        let item = AVPlayerItem(asset: AVMutableComposition())
        let manager = VideoMediaTrackManager(immersiveProfileDetector: MockImmersiveMediaProfileDetector(profile: .appleImmersiveVideo))

        let capabilities = try await manager.capabilities(for: item)

        #expect(capabilities.immersiveMediaProfile == .appleImmersiveVideo)
        #expect(capabilities.isAppleImmersiveVideo)
        #expect(capabilities.isSpatialVideo == false)
        #expect(capabilities.supportsExternalPlayback == false)
    }

    @MainActor
    @Test("Standard 2D capabilities can advertise external playback")
    func standardCapabilitiesAdvertiseExternalPlayback() async throws {
        let item = AVPlayerItem(asset: AVMutableComposition())
        let manager = VideoMediaTrackManager(immersiveProfileDetector: MockImmersiveMediaProfileDetector(profile: .standard2D))

        let capabilities = try await manager.capabilities(for: item)

        #expect(capabilities.supportsExternalPlayback)
    }

    @MainActor
    @Test("Playback assistant options map to immersive media profiles")
    func playbackAssistantOptionsMapToProfiles() {
        let detector = AVFoundationImmersiveMediaProfileDetector()

        #if os(visionOS)
        #expect(detector.playbackConfigurationOptionsProfile([.appleImmersiveVideo]) == .appleImmersiveVideo)
        #endif
        #expect(detector.playbackConfigurationOptionsProfile([.nonRectilinearProjection]) == .appleProjectedMedia)
        #expect(detector.playbackConfigurationOptionsProfile([.spatialVideo]) == .spatialVideo)
        #expect(detector.playbackConfigurationOptionsProfile([.stereoVideo]) == .stereo3D)
        #expect(detector.playbackConfigurationOptionsProfile([]) == .standard2D)
    }

    @Test("Legacy spatial flag resolves profile and stereo capability")
    func legacySpatialFlagResolvesDerivedCapabilities() {
        let capabilities = VideoPlaybackCapabilities(
            hasAudioVariants: false,
            hasLegibleTracks: false,
            hasChapters: false,
            isHighFrameRate: false,
            isSpatialVideo: true,
            supportsExternalPlayback: true
        )

        #expect(capabilities.immersiveMediaProfile == .spatialVideo)
        #expect(capabilities.isStereoVideo)
    }
}

@Suite("AVKit immersive handoff")
struct AVKitImmersiveHandoffTests {
    @Test("Handoff request carries URL, metadata, capabilities, and requested experience")
    func requestCarriesSystemPlayerHandoffInputs() throws {
        let url = try requiredURL("https://cdn.example/video.m3u8")
        let metadata = VideoMediaMetadata(id: "video-1", title: "Immersive", artist: "Aura", artworkURL: nil)
        let capabilities = VideoPlaybackCapabilities(
            hasAudioVariants: false,
            hasLegibleTracks: false,
            hasChapters: false,
            isHighFrameRate: false,
            immersiveMediaProfile: .appleProjectedMedia,
            isSpatialVideo: false,
            supportsExternalPlayback: true
        )

        let request = VideoAVKitImmersiveHandoffRequest(
            playbackURL: url,
            metadata: metadata,
            capabilities: capabilities,
            requestedExperience: .expanded(disableAutomaticImmersiveTransition: true)
        )

        #expect(request.playbackURL == url)
        #expect(request.metadata == metadata)
        #expect(request.capabilities.isProjectedMedia)
        #expect(request.requestedExperience == .expanded(disableAutomaticImmersiveTransition: true))
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

    @Test("Coalesced requests keep the newest tolerance")
    func coalescedRequestsKeepNewestTolerance() async {
        let coordinator = ChaseTimeSeekCoordinator()
        let recorder = SeekRecorder()

        let firstSeek = Task {
            await coordinator.requestSeek(to: 1, tolerance: VideoSeekKind.scrub.tolerance) { target, tolerance in
                await recorder.record(target, tolerance: tolerance)
                try? await Task.sleep(for: .milliseconds(10))
                return true
            }
        }
        try? await Task.sleep(for: .milliseconds(1))
        await coordinator.requestSeek(to: 20, tolerance: VideoSeekKind.skip.tolerance) { target, tolerance in
            await recorder.record(target, tolerance: tolerance)
            return true
        }
        await firstSeek.value

        let requests = await recorder.requests
        #expect(requests.last?.target == 20)
        #expect(requests.last?.tolerance == VideoSeekKind.skip.tolerance)
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
    @Test("Changing speed while paused persists without starting playback")
    func setSpeedWhilePausedDoesNotStartPlayback() throws {
        let defaults = try #require(UserDefaults(suiteName: "PausedSpeedPreferenceTests"))
        defaults.removePersistentDomain(forName: "PausedSpeedPreferenceTests")
        let player = AVPlayer(playerItem: AVPlayerItem(url: try #require(URL(string: "https://example.com/video.mp4"))))
        let controller = PlaybackSpeedController(userDefaults: defaults)

        try controller.setSpeed(.double, on: player)

        #expect(player.rate == 0)
        #expect(controller.storedSpeed == .double)
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

#if canImport(AVKit) && canImport(UIKit) && !os(visionOS)
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

    @MainActor
    @Test("System media session emits app lifecycle events")
    func systemMediaSessionEmitsLifecycleEvents() async {
        let notificationCenter = NotificationCenter()
        let manager = SystemVideoMediaSessionManager(notificationCenter: notificationCenter)
        var iterator = manager.events.makeAsyncIterator()

        notificationCenter.post(name: UIApplication.didEnterBackgroundNotification, object: nil)
        let backgroundEvent = await iterator.next()
        notificationCenter.post(name: UIApplication.willTerminateNotification, object: nil)
        let terminationEvent = await iterator.next()

        #expect(backgroundEvent == .enteredBackground)
        #expect(terminationEvent == .willStop)
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
    @Test("Progressive cache mapper rewrites only known progressive file extensions")
    func mapperRewritesProgressiveURLs() throws {
        let mapper = ProgressiveVideoCacheURLMapper(configuration: ProgressiveVideoCacheConfiguration(customScheme: "cache-video"))
        let mp4 = try requiredURL("https://cdn.example/video.mp4")
        let mov = try requiredURL("https://cdn.example/video.MOV")
        let hls = try requiredURL("https://cdn.example/master.m3u8")
        let extensionless = try requiredURL("https://ipfs.example/ipfs/QmExampleHash")

        let assetURL = mapper.assetURL(for: mp4)

        #expect(assetURL.scheme == "cache-video")
        #expect(mapper.originalURL(for: assetURL) == mp4)
        #expect(mapper.assetURL(for: mov).scheme == "cache-video")
        #expect(mapper.assetURL(for: hls) == hls)
        #expect(mapper.assetURL(for: extensionless) == extensionless)
    }

    @Test("Purged cache files degrade to a miss instead of an error")
    func cacheStoreTreatsPurgedFilesAsMiss() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ProgressiveCachePurgeTests-\(UUID().uuidString)", isDirectory: true)
        let store = ProgressiveVideoCacheStore(configuration: ProgressiveVideoCacheConfiguration(cacheDirectory: directory))
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = try requiredURL("https://cdn.example/video.mp4")

        _ = try await store.store(data: Data([0, 1, 2, 3]), for: url, offset: 0, contentLength: 4, contentType: "video/mp4")
        let dataFiles = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "media" }
        for file in dataFiles {
            try FileManager.default.removeItem(at: file)
        }

        #expect(try await store.cachedData(for: url, offset: 0, length: 4) == nil)
        #expect(await store.localFileURL(for: url) == nil)
    }

    @Test("Asset loading falls back to the remote URL when an offline file is missing")
    func assetLoaderFallsBackWhenOfflineFileMissing() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("OfflineFallbackTests-\(UUID().uuidString)", isDirectory: true)
        let store = VideoOfflineManifestStore(directory: directory)
        defer { try? FileManager.default.removeItem(at: directory) }
        let sourceURL = try requiredURL("https://cdn.example/video.mp4")
        try await store.upsert(VideoOfflineAssetRecord(
            sourceURL: sourceURL,
            localFileURL: directory.appendingPathComponent("missing.mp4"),
            kind: .progressiveFile,
            state: .available,
            progress: 1
        ))
        let loader = VideoAssetLoader(offlineManifestStore: store)

        let asset = try await loader.asset(for: sourceURL, plan: VideoAssetLoadPlan(preloadKeys: []))

        #expect(asset.url == sourceURL)
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

    @Test("Cached prefix serves the start of a partially cached window")
    func cacheStoreServesCachedPrefix() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ProgressiveCachePrefixTests-\(UUID().uuidString)", isDirectory: true)
        let store = ProgressiveVideoCacheStore(configuration: ProgressiveVideoCacheConfiguration(cacheDirectory: directory))
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = try requiredURL("https://cdn.example/video.mp4")

        _ = try await store.store(data: Data([0, 1, 2, 3]), for: url, offset: 0, contentLength: 8, contentType: "video/mp4")

        #expect(try await store.cachedData(for: url, offset: 1, length: 6) == nil)
        #expect(try await store.cachedPrefixData(for: url, offset: 1, maxLength: 6) == Data([1, 2, 3]))
        #expect(try await store.cachedPrefixData(for: url, offset: 1, maxLength: 2) == Data([1, 2]))
        #expect(try await store.cachedPrefixData(for: url, offset: 4, maxLength: 4) == nil)
    }

    @Test("Progressive cache evicts older entries when over budget")
    func cacheStoreEvictsOlderEntriesWhenOverBudget() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ProgressiveCacheEvictionTests-\(UUID().uuidString)", isDirectory: true)
        let configuration = ProgressiveVideoCacheConfiguration(cacheDirectory: directory, maxCacheBytes: 1)
        let store = ProgressiveVideoCacheStore(configuration: configuration)
        defer { try? FileManager.default.removeItem(at: directory) }
        let firstURL = try requiredURL("https://cdn.example/a.mp4")
        let secondURL = try requiredURL("https://cdn.example/b.mp4")

        _ = try await store.store(data: Data([0, 1, 2, 3]), for: firstURL, offset: 0, contentLength: 4, contentType: "video/mp4")
        _ = try await store.store(data: Data([4, 5, 6, 7]), for: secondURL, offset: 0, contentLength: 4, contentType: "video/mp4")

        #expect(await store.record(for: firstURL) == nil)
        #expect(await store.record(for: secondURL) != nil)
        #expect(await store.localFileURL(for: firstURL) == nil)
        #expect(await store.localFileURL(for: secondURL) != nil)
    }

    @Test("Progressive cache rejects failed HTTP responses and tolerates ignored byte ranges")
    func progressiveCacheValidatesHTTPResponses() throws {
        let loader = ProgressiveVideoResourceLoader(
            store: ProgressiveVideoCacheStore(),
            mapper: ProgressiveVideoCacheURLMapper()
        )
        let url = try requiredURL("https://cdn.example/video.mp4")
        let notFound = try #require(HTTPURLResponse(url: url, statusCode: 404, httpVersion: nil, headerFields: nil))
        let ignoredRange = try #require(HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil))
        let partialContent = try #require(HTTPURLResponse(url: url, statusCode: 206, httpVersion: nil, headerFields: nil))

        #expect(throws: VideoPlaybackError.self) {
            try loader.validateRemoteResponse(notFound)
        }
        #expect(throws: Never.self) {
            try loader.validateRemoteResponse(ignoredRange)
        }
        #expect(throws: Never.self) {
            try loader.validateRemoteResponse(partialContent)
        }
    }

    @Test("Byte-range containment is overflow-safe for requests-to-end lengths")
    func byteRangeContainmentIsOverflowSafe() {
        let range = CachedByteRange(offset: 0, length: 10)

        #expect(range.contains(offset: 2, length: 4))
        #expect(range.contains(offset: 5, length: Int.max) == false)
    }

    @Test("Range-ignoring 200 streams forward only the requested window")
    func windowedSliceServesOnlyRequestedWindow() throws {
        let loader = ProgressiveVideoResourceLoader(
            store: ProgressiveVideoCacheStore(),
            mapper: ProgressiveVideoCacheURLMapper()
        )
        let data = Data([0, 1, 2, 3, 4, 5, 6, 7])

        // Stream from byte zero, window is bytes 2..<6.
        #expect(loader.windowedSlice(of: data, at: 0, windowOffset: 2, windowLength: 4) == Data([2, 3, 4, 5]))
        // Chunk entirely before the window is cached but not forwarded.
        #expect(loader.windowedSlice(of: Data([0, 1]), at: 0, windowOffset: 2, windowLength: 4) == nil)
        // Chunk inside an open-ended window passes through whole.
        #expect(loader.windowedSlice(of: data, at: 4, windowOffset: 2, windowLength: nil) == data)
        // An overflowing window length degrades to open-ended instead of trapping.
        #expect(loader.windowedSlice(of: data, at: 0, windowOffset: 2, windowLength: Int.max) == Data([2, 3, 4, 5, 6, 7]))
    }

    @Test("Registered content information persists across store instances")
    func cacheStoreRegistersContentInformation() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ProgressiveCacheContentInfoTests-\(UUID().uuidString)", isDirectory: true)
        let configuration = ProgressiveVideoCacheConfiguration(cacheDirectory: directory)
        let store = ProgressiveVideoCacheStore(configuration: configuration)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = try requiredURL("https://cdn.example/video.mp4")

        try await store.registerContentInformation(for: url, contentLength: 100, contentType: "video/mp4")

        #expect(await store.record(for: url)?.contentLength == 100)
        let restored = ProgressiveVideoCacheStore(configuration: configuration)
        #expect(await restored.record(for: url)?.contentLength == 100)
        #expect(await restored.record(for: url)?.contentType == "video/mp4")
    }

    @Test("Progressive resource loader maps MIME content types to UTI identifiers")
    func progressiveResourceLoaderMapsMIMEContentTypesToUTIs() throws {
        let loader = ProgressiveVideoResourceLoader(
            store: ProgressiveVideoCacheStore(),
            mapper: ProgressiveVideoCacheURLMapper()
        )
        let mp4 = ProgressiveVideoCacheRecord(
            sourceURL: try requiredURL("https://cdn.example/video.mp4"),
            contentType: "video/mp4"
        )
        let unknown = ProgressiveVideoCacheRecord(
            sourceURL: try requiredURL("https://cdn.example/video.mov"),
            contentType: "not a mime type"
        )

        #expect(loader.contentTypeIdentifier(for: mp4) == AVFileType.mp4.rawValue)
        #expect(loader.contentTypeIdentifier(for: unknown) == AVFileType.mov.rawValue)
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
        let manifestData = try Data(contentsOf: directory.appendingPathComponent("offline-manifest.json"))
        let manifestJSON = String(decoding: manifestData, as: UTF8.self)

        #expect(restored == record)
        #expect(!manifestJSON.contains(directory.path))
    }

    @Test("Offline manifest persists external local package locations without raw absolute paths")
    func offlineManifestPersistsExternalPackageLocationAsBookmark() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("OfflineManifestBookmarkTests-\(UUID().uuidString)", isDirectory: true)
        let externalDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("OfflineManifestExternalPackage-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: externalDirectory, withIntermediateDirectories: true)
        let packageURL = externalDirectory.appendingPathComponent("video.movpkg")
        try Data([1, 2, 3]).write(to: packageURL)

        let store = VideoOfflineManifestStore(directory: directory)
        let sourceURL = try requiredURL("https://cdn.example/master.m3u8")
        let record = VideoOfflineAssetRecord(
            sourceURL: sourceURL,
            localFileURL: packageURL,
            kind: .hlsPackage,
            state: .available,
            progress: 1
        )

        try await store.upsert(record)
        let restored = try #require(try await VideoOfflineManifestStore(directory: directory).record(for: sourceURL))
        let manifestData = try Data(contentsOf: directory.appendingPathComponent("offline-manifest.json"))
        let manifestJSON = String(decoding: manifestData, as: UTF8.self)

        // Bookmark resolution yields the real path (/private/var/…) while the test
        // built the record through the symlinked temporary directory (/var/…), so
        // compare symlink-resolved file URLs instead of raw URL equality.
        #expect(restored.localFileURL?.resolvingSymlinksInPath() == packageURL.resolvingSymlinksInPath())
        #expect(restored.sourceURL == record.sourceURL)
        #expect(restored.kind == record.kind)
        #expect(restored.state == record.state)
        #expect(restored.progress == record.progress)
        #expect(restored.errorDescription == record.errorDescription)
        #expect(!manifestJSON.contains(packageURL.path))
    }

    @Test("Offline manifest allows redownload start but ignores stale progress after availability")
    func offlineManifestHandlesRedownloadAndStaleProgress() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("OfflineManifestOrderingTests-\(UUID().uuidString)", isDirectory: true)
        let store = VideoOfflineManifestStore(directory: directory)
        let sourceURL = try requiredURL("https://cdn.example/video.mp4")
        let available = VideoOfflineAssetRecord(
            sourceURL: sourceURL,
            localFileURL: directory.appendingPathComponent("video.mp4"),
            kind: .progressiveFile,
            state: .available,
            progress: 1
        )
        let redownloadStart = VideoOfflineAssetRecord(
            sourceURL: sourceURL,
            kind: .progressiveFile,
            state: .downloading,
            progress: 0
        )
        let staleProgress = VideoOfflineAssetRecord(
            sourceURL: sourceURL,
            kind: .progressiveFile,
            state: .downloading,
            progress: 0.25
        )

        try await store.upsert(available)
        try await store.upsert(redownloadStart)
        #expect(try await store.record(for: sourceURL) == redownloadStart)
        try await store.upsert(available)
        try await store.upsert(staleProgress)

        let restored = try await store.record(for: sourceURL)
        #expect(restored == available)
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
    @Test("Observation tasks do not retain the integration coordinator forever")
    func observationTasksDoNotRetainCoordinator() async throws {
        let controller = MockVideoController()
        let remoteCommands = MockRemoteCommandStream()
        weak var weakCoordinator: VideoPlaybackIntegrationCoordinator?

        do {
            let coordinator = VideoPlaybackIntegrationCoordinator(
                controller: controller,
                metadata: VideoMediaMetadata(id: "video-1", title: "Video", artist: nil, artworkURL: nil),
                remoteCommandStream: remoteCommands
            )
            weakCoordinator = coordinator
            coordinator.startObserving()
        }

        try await Task.sleep(for: .milliseconds(10))
        #expect(weakCoordinator == nil)
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
    @Test("Coordinated playback does not manually start Picture in Picture after backgrounding")
    func coordinatedPlaybackDoesNotManuallyStartPictureInPictureOnBackground() async throws {
        let controller = MockVideoController()
        let session = MockMediaSessionManager()
        let pictureInPicture = MockPictureInPictureController()
        let coordinator = VideoPlaybackIntegrationCoordinator(
            controller: controller,
            metadata: VideoMediaMetadata(id: "video-1", title: "Video", artist: nil, artworkURL: nil),
            mediaSessionManager: session,
            pictureInPictureController: pictureInPicture,
            coordinatedPlaybackConfiguration: makeCoordinatedPlaybackConfiguration()
        )
        coordinator.startObserving()

        session.emit(.enteredBackground)
        try await Task.sleep(for: .milliseconds(25))

        #expect(pictureInPicture.startCount == 0)
        await coordinator.stop()
    }

    @MainActor
    @Test("Local playback does not start Picture in Picture when backgrounded")
    func localPlaybackDoesNotStartPictureInPictureOnBackground() async throws {
        let controller = MockVideoController()
        let session = MockMediaSessionManager()
        let pictureInPicture = MockPictureInPictureController()
        let coordinator = VideoPlaybackIntegrationCoordinator(
            controller: controller,
            metadata: VideoMediaMetadata(id: "video-1", title: "Video", artist: nil, artworkURL: nil),
            mediaSessionManager: session,
            pictureInPictureController: pictureInPicture
        )
        coordinator.startObserving()

        session.emit(.enteredBackground)
        try await Task.sleep(for: .milliseconds(25))

        #expect(pictureInPicture.startCount == 0)
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

enum MockMultiviewError: Error, Equatable {
    case coordinationFailed
}

@MainActor
final class MockPlaybackCoordinator: VideoPlaybackCoordinating {
    private let error: Error?
    private(set) var coordinatedPlayerIDs: [ObjectIdentifier] = []
    private(set) var coordinationMediumIDs: [ObjectIdentifier] = []

    init(error: Error? = nil) {
        self.error = error
    }

    func coordinate(player: AVPlayer, using medium: AVPlaybackCoordinationMedium) throws {
        if let error {
            throw error
        }
        coordinatedPlayerIDs.append(ObjectIdentifier(player))
        coordinationMediumIDs.append(ObjectIdentifier(medium))
    }
}

@MainActor
final class MockRoutingPlaybackArbiter: VideoRoutingPlaybackArbitrating {
    private(set) var externalPlaybackPlayerID: ObjectIdentifier?
    private(set) var nonMixableAudioPlayerID: ObjectIdentifier?

    func preferExternalPlaybackParticipant(_ player: AVPlayer?) {
        externalPlaybackPlayerID = player.map(ObjectIdentifier.init)
    }

    func preferNonMixableAudioParticipant(_ player: AVPlayer?) {
        nonMixableAudioPlayerID = player.map(ObjectIdentifier.init)
    }
}

@MainActor
final class MockNetworkResourcePrioritizer: VideoNetworkResourcePrioritizing {
    private(set) var appliedPriorities: [ObjectIdentifier: [VideoNetworkResourcePriority]] = [:]

    func apply(_ priority: VideoNetworkResourcePriority, to player: AVPlayer) {
        appliedPriorities[ObjectIdentifier(player), default: []].append(priority)
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
    private(set) var requests: [(target: Double, tolerance: VideoSeekTolerance)] = []

    func record(_ target: Double) {
        targets.append(target)
    }

    func record(_ target: Double, tolerance: VideoSeekTolerance) {
        targets.append(target)
        requests.append((target, tolerance))
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

    func publish(metadata: VideoMediaMetadata, tick: PlaybackTick, isPlaying: Bool) async {
        publishedTicks.append(tick)
    }

    func clear(metadataID: String) async {
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

    func configureForPlayback() async throws {
        configureCallCount += 1
    }

    func emit(_ event: VideoMediaSessionEvent) {
        continuation.yield(event)
    }
}

@MainActor
final class MockPictureInPictureController: VideoPictureInPictureControlling {
    private(set) var state: PiPState = .inactive
    private(set) var startCount = 0
    private(set) var stopCount = 0

    func start() {
        startCount += 1
        state = .active
    }

    func stop() {
        stopCount += 1
        state = .inactive
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

struct MockSpatialVideoDetector: VideoSpatialVideoDetecting {
    let result: Bool

    func isSpatialVideo(asset: AVAsset) async throws -> Bool {
        result
    }
}

struct MockImmersiveMediaProfileDetector: VideoImmersiveMediaProfileDetecting {
    let profile: VideoImmersiveMediaProfile

    func immersiveMediaProfile(asset: AVAsset) async throws -> VideoImmersiveMediaProfile {
        profile
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

func makeCoordinatedPlaybackConfiguration() -> VideoCoordinatedPlaybackConfiguration {
    VideoCoordinatedPlaybackConfiguration(
        sessionIdentity: SharedMediaSessionIdentity(
            id: "session.video-1",
            activity: SharedMediaActivityIdentity(
                id: "activity.video-1",
                title: "Watch Video",
                contentKind: .video
            ),
            queue: SharedMediaQueueIdentity(
                id: "queue.video",
                itemIDs: ["video-1"],
                currentItemID: "video-1",
                revision: 1
            )
        )
    )
}

// Generous deadline because parallel suites on a cold simulator can starve the
// polled task; the helper returns as soon as the condition holds.
@MainActor
func expectEventually(
    timeoutNanoseconds: UInt64 = 5_000_000_000,
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
    let id: String
    let sourceURL: URL
    let declaredFormat: String?
    let contentKind: AuraPlayableContentKind
    let cachedFileState: AuraCachedFileState
    let approxLoudnessLUFS: Double?
    let mediaMetadata: MediaMetadata

    init(
        videoMediaID: String,
        videoTitle: String,
        videoArtist: String?,
        videoArtworkURL: URL?,
        resolvedPlaybackURL: URL,
        declaredFormat: String? = nil,
        cachedFileState: AuraCachedFileState = .notCached
    ) {
        self.id = videoMediaID
        self.sourceURL = resolvedPlaybackURL
        self.declaredFormat = declaredFormat
        self.contentKind = .video
        self.cachedFileState = cachedFileState
        self.approxLoudnessLUFS = nil
        self.mediaMetadata = MediaMetadata(
            id: videoMediaID,
            title: videoTitle,
            artist: videoArtist,
            artworkURL: videoArtworkURL
        )
    }
}
