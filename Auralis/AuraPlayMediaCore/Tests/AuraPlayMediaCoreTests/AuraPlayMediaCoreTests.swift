import Foundation
import Testing
@testable import AuraPlayMediaCore

private struct FixtureMedia: AuraPlayableMedia {
    let id: Int
    let sourceURL: URL
    let declaredFormat: String?
    let contentKind: AuraPlayableContentKind
    let cachedFileState: AuraCachedFileState
    let approxLoudnessLUFS: Double?
}

@Suite("AuraPlay media core contracts")
struct AuraPlayMediaCoreTests {
    @Test("Playable media can be erased without losing transport metadata")
    func erasesPlayableMedia() throws {
        let media = FixtureMedia(
            id: 42,
            sourceURL: try #require(URL(string: "https://example.com/track.mp3")),
            declaredFormat: "mp3",
            contentKind: .music,
            cachedFileState: .partial,
            approxLoudnessLUFS: -14.5
        )

        let erased = AnyAuraPlayableMedia(media)

        #expect(erased.id == "42")
        #expect(erased.sourceURL == media.sourceURL)
        #expect(erased.declaredFormat == "mp3")
        #expect(erased.contentKind == .music)
        #expect(erased.cachedFileState == .partial)
        #expect(erased.approxLoudnessLUFS == -14.5)
    }

    @Test("Cache keys sanitize filesystem-hostile media identifiers")
    func cacheKeySanitizesMediaID() {
        #expect(CacheKey(mediaID: "wallet/track id?#1").rawValue == "wallet-track-id--1")
        #expect(CacheKey(mediaID: "///???").rawValue == "media-2f2f2f3f3f3f")
        #expect(CacheKey(mediaID: "").rawValue == "media-empty")
    }

    @Test("Cache keys create stable URL-safe URL identifiers")
    func cacheKeyCreatesURLIdentifier() throws {
        let url = try #require(URL(string: "https://example.com/media/video%20one.mp4?token=a+b/c"))

        let key = CacheKey(url: url).rawValue

        #expect(key == "aHR0cHM6Ly9leGFtcGxlLmNvbS9tZWRpYS92aWRlbyUyMG9uZS5tcDQ_dG9rZW49YStiL2M")
        #expect(!key.contains("/"))
        #expect(!key.contains("+"))
        #expect(!key.contains("="))
    }

    @Test("Remote command compatibility factories map video-style names to shared commands")
    func remoteCommandCompatibilityFactories() {
        #expect(RemoteCommandEvent.skipForward(seconds: 15) == .skipForward(15))
        #expect(RemoteCommandEvent.skipBackward(seconds: 10) == .skipBackward(10))
        #expect(RemoteCommandEvent.seek(seconds: 42) == .changePlaybackPosition(42))
    }

    @MainActor
    @Test("Remote command dispatcher maps shared commands onto transport primitives")
    func remoteCommandDispatcherMapsToTransport() async {
        let transport = MockMediaTransport()

        await RemoteCommandEvent.play.dispatch(to: transport)
        await RemoteCommandEvent.skipForward(15).dispatch(to: transport)
        await RemoteCommandEvent.skipBackward(5).dispatch(to: transport)
        await RemoteCommandEvent.changePlaybackPosition(42).dispatch(to: transport)
        await RemoteCommandEvent.togglePlayPause.dispatch(to: transport)
        await RemoteCommandEvent.togglePlayPause.dispatch(to: transport)
        await RemoteCommandEvent.next.dispatch(to: transport)
        await RemoteCommandEvent.previous.dispatch(to: transport)

        #expect(transport.events == [
            "play",
            "seek:25.0",
            "seek:20.0",
            "seek:42.0",
            "pause",
            "play",
            "next",
            "previous",
        ])
    }

    @Test("URLSession downloader appends temporary file contents in bounded chunks")
    func urlSessionDownloaderAppendsTemporaryFileContents() throws {
        let destination = FileManager.default.temporaryDirectory
            .appending(path: "mediacore-resume-destination-\(UUID().uuidString)")
        let source = FileManager.default.temporaryDirectory
            .appending(path: "mediacore-resume-source-\(UUID().uuidString)")
        let prefix = Data([0, 1, 2, 3, 4])
        let tail = Data((0..<97).map { UInt8($0 % 31) })

        try prefix.write(to: destination)
        try tail.write(to: source)
        try URLSessionMediaDownloader.appendFileContents(from: source, to: destination, bufferSize: 7)

        #expect(try Data(contentsOf: destination) == prefix + tail)

        try? FileManager.default.removeItem(at: destination)
        try? FileManager.default.removeItem(at: source)
    }

    @Test("Ordered gateway fallback resolver advances through candidate URLs")
    func orderedGatewayFallbackResolverAdvancesThroughCandidates() async throws {
        let first = try #require(URL(string: "https://gateway-one.example/media.mp3"))
        let second = try #require(URL(string: "https://gateway-two.example/media.mp3"))
        let third = try #require(URL(string: "https://gateway-three.example/media.mp3"))
        let unknown = try #require(URL(string: "https://other.example/media.mp3"))
        let resolver = OrderedMediaGatewayFallbackResolver(resolvedURLs: [first, second, third])

        #expect(try await resolver.nextResolvedURL(after: first) == second)
        #expect(try await resolver.nextResolvedURL(after: second) == third)
        #expect(try await resolver.nextResolvedURL(after: third) == nil)
        #expect(try await resolver.nextResolvedURL(after: unknown) == first)
    }

    @Test("Media metadata stores neutral now-playing descriptors")
    func mediaMetadataStoresDescriptors() {
        let artworkURL = URL(string: "https://example.com/art.png")

        let metadata = MediaMetadata(
            id: "video-1",
            title: "Signal",
            artist: "Aura",
            artworkURL: artworkURL
        )

        #expect(metadata.id == "video-1")
        #expect(metadata.title == "Signal")
        #expect(metadata.artist == "Aura")
        #expect(metadata.artworkURL == artworkURL)
    }

    @Test("Playable media item combines shared transport fields with metadata")
    func playableMediaItemCombinesTransportAndMetadata() throws {
        let sourceURL = try #require(URL(string: "https://example.com/video.mp4"))
        let metadata = MediaMetadata(id: "video-1", title: "Signal", artist: "Aura", artworkURL: nil)

        let item = AuraPlayableMediaItem(
            id: "video-1",
            sourceURL: sourceURL,
            declaredFormat: "mp4",
            contentKind: .video,
            cachedFileState: .cached,
            metadata: metadata
        )

        #expect(item.id == "video-1")
        #expect(item.sourceURL == sourceURL)
        #expect(item.declaredFormat == "mp4")
        #expect(item.contentKind == .video)
        #expect(item.cachedFileState == .cached)
        #expect(item.metadata == metadata)
    }

    @Test("Offline state is shared across media engines")
    func offlineStateIsSharedAcrossMediaEngines() {
        #expect(MediaOfflineState.queued.rawValue == "queued")
        #expect(MediaOfflineState.downloading.rawValue == "downloading")
        #expect(MediaOfflineState.available.rawValue == "available")
        #expect(MediaOfflineState.failed.rawValue == "failed")
        #expect(MediaOfflineState.cancelled.rawValue == "cancelled")
    }

    @Test("Always online network status can represent offline fixtures")
    func alwaysOnlineNetworkStatusProviderCanRepresentOfflineFixtures() {
        #expect(AlwaysOnlineMediaNetworkStatusProvider().isOffline == false)
        #expect(AlwaysOnlineMediaNetworkStatusProvider(isOffline: true).isOffline)
    }

    @Test("No-op media logger accepts informational and error messages")
    func noOpMediaLoggerAcceptsMessages() {
        let logger = NoOpMediaEngineLogger()

        logger.info("loaded")
        logger.error("failed")
    }

    @Test("Shared media session snapshot carries SharePlay coordination identity")
    func sharedMediaSessionSnapshotCarriesCoordinationIdentity() throws {
        let fallbackURL = try #require(URL(string: "https://auralis.example/share/video-1"))
        let activity = SharedMediaActivityIdentity(
            id: "activity.video-1",
            title: "Watch Signal",
            subtitle: "Aura shared video",
            fallbackURL: fallbackURL,
            contentKind: .video
        )
        let queue = SharedMediaQueueIdentity(
            id: "queue.wallet-1",
            itemIDs: ["video-1", "video-2"],
            currentItemID: "video-1",
            revision: 3
        )
        let identity = SharedMediaSessionIdentity(
            id: "session-1",
            activity: activity,
            queue: queue,
            lobbyPolicy: SharedMediaLobbyPolicy(
                lateJoinPolicy: .waitInLobby,
                minimumReadyParticipants: 2,
                requiresExplicitStart: true
            )
        )
        let participant = MediaParticipantPresence(
            id: "participant-1",
            displayName: "Alex",
            isLocalParticipant: false,
            state: .ready
        )
        let attribution = MediaSessionChangeAttribution(
            origin: .remoteParticipant("participant-1"),
            action: .selectedItem(id: "video-2")
        )

        let snapshot = SharedMediaSessionSnapshot(
            identity: identity,
            participants: [participant],
            lastChange: attribution
        )

        #expect(snapshot.identity.activity.fallbackURL == fallbackURL)
        #expect(snapshot.identity.queue.currentItemID == "video-1")
        #expect(snapshot.identity.queue.revision == 3)
        #expect(snapshot.identity.lobbyPolicy.lateJoinPolicy == .waitInLobby)
        #expect(snapshot.participants.first?.displayName == "Alex")
        #expect(snapshot.lastChange == attribution)
    }

    @Test("Lobby policy clamps impossible ready participant counts")
    func lobbyPolicyClampsMinimumReadyParticipants() {
        let policy = SharedMediaLobbyPolicy(minimumReadyParticipants: 0)

        #expect(policy.minimumReadyParticipants == 1)
    }

    @Test("Launch policy models share sheet and in-app SharePlay affordances")
    func launchPolicyModelsSharePlayAffordances() {
        let prominent = SharedMediaActivityLaunchPolicy(
            supportedSurfaces: [.shareSheet, .inAppButton, .contextualMenu, .airDrop],
            supportedGroupContexts: [.faceTime, .messages, .airDrop],
            supportedPlatforms: [.iOS],
            shareSheetProminence: .prominent,
            requiresExistingGroupSession: false
        )
        let excluded = SharedMediaActivityLaunchPolicy(
            supportedSurfaces: [.shareSheet],
            shareSheetProminence: .excluded
        )

        #expect(prominent.shouldRegisterGroupActivityWithShareSheet)
        #expect(prominent.shouldPresentInAppSharingController)
        #expect(prominent.requiresExistingGroupSession == false)
        #expect(prominent.supports(.airDrop, on: .iOS))
        #expect(prominent.supports(.messages, on: .tvOS) == false)
        #expect(excluded.shouldRegisterGroupActivityWithShareSheet == false)
        #expect(excluded.shouldPresentInAppSharingController == false)
    }

    @Test("Activity identity maps GroupActivity metadata and payload")
    func activityIdentityMapsGroupActivityMetadataAndPayload() throws {
        let fallbackURL = try #require(URL(string: "https://auralis.example/share/order-1"))
        let activity = SharedMediaActivityIdentity(
            id: "order-together",
            activityIdentifier: "com.auralis.shareplay.order-together",
            title: "Order Tacos Together",
            subtitle: "Aura Taco Truck",
            previewImageID: "activity.order-tacos",
            fallbackURL: fallbackURL,
            contentKind: .unknown,
            activityType: .shopTogether,
            launchPayload: [
                "orderUUID": "order-1",
                "truckName": "Aura Taco Truck",
            ]
        )
        let quality = SharedMediaActivityMetadataQuality(activity: activity)

        #expect(activity.activityIdentifier.isReverseDNSStyle)
        #expect(activity.activityType == .shopTogether)
        #expect(activity.launchPayload["truckName"] == "Aura Taco Truck")
        #expect(quality.hasSpecificTitle)
        #expect(quality.hasPreviewImage)
        #expect(quality.hasFallbackURL)
    }

    @Test("Message policy separates reliable state from low-latency transient updates")
    func messagePolicySeparatesReliableAndUnreliableTraffic() {
        #expect(SharedMediaMessagePolicy.maximumPayloadBytes == 262_144)
        #expect(SharedMediaMessagePolicy.initialStateContribution.deliveryMode == .reliable)
        #expect(SharedMediaMessagePolicy.authoritativeState.deliveryMode == .reliable)
        #expect(SharedMediaMessagePolicy.controlAction.deliveryMode == .reliable)
        #expect(SharedMediaMessagePolicy.transientPlaybackHint.deliveryMode == .unreliable)
        #expect(SharedMediaMessagePolicy.realtimeGesture.deliveryMode == .unreliable)
    }

    @Test("Staged sessions carry ownerless initial playback contributions")
    func stagedSessionsCarryOwnerlessInitialPlaybackContributions() {
        let queue = SharedMediaQueueIdentity(
            id: "queue.video",
            itemIDs: ["video-1"],
            currentItemID: "video-1",
            revision: 4
        )
        let contribution = SharedMediaInitialPlaybackStateContribution(
            participantID: "participant-adam",
            sessionID: "session-video",
            queue: queue,
            playbackTick: PlaybackTick(currentSeconds: 23, durationSeconds: 120),
            isPlaying: true
        )
        let snapshot = SharedMediaSessionSnapshot(
            identity: SharedMediaSessionIdentity(
                id: "session-video",
                activity: SharedMediaActivityIdentity(
                    id: "activity-video",
                    title: "Watch Signal",
                    contentKind: .video
                ),
                queue: queue
            ),
            activationState: .staged
        )

        #expect(snapshot.activationState == .staged)
        #expect(contribution.sessionID == snapshot.identity.id)
        #expect(contribution.queue.currentItemID == "video-1")
        #expect(contribution.playbackTick.currentSeconds == 23)
        #expect(contribution.isPlaying)
    }

    @Test("Attachment policy captures GroupSessionJournal transfer limits")
    func attachmentPolicyCapturesJournalTransferLimits() {
        let policy = SharedMediaAttachmentPolicy()

        #expect(SharedMediaAttachmentPolicy.maximumPayloadBytes == 104_857_600)
        #expect(policy.permitsPayload(byteCount: 104_857_600))
        #expect(policy.permitsPayload(byteCount: 104_857_601) == false)
        #expect(policy.permitsPayload(byteCount: -1) == false)
        #expect(policy.supportsLateJoinerCatchUpWithoutReupload)
        #expect(policy.requiresEndToEndEncryption)
        #expect(policy.lifecycle == .availableWhileSessionHasParticipants)
    }

    @Test("Attachment manifests track user-generated journal content")
    func attachmentManifestsTrackJournalContent() {
        let attachment = SharedMediaAttachmentMetadata(
            id: "image-1",
            kind: .image,
            displayName: "Canvas Photo",
            byteCount: 32_000,
            contentType: "image/jpeg",
            sourceParticipantID: "participant-brian"
        )
        let manifest = SharedMediaAttachmentManifest(
            sessionID: "session-drawing",
            attachments: [attachment]
        )

        #expect(manifest.sessionID == "session-drawing")
        #expect(manifest.totalByteCount == 32_000)
        #expect(manifest.isAttachmentAllowed(attachment))
        #expect(manifest.attachments.first?.sourceParticipantID == "participant-brian")
    }

    @Test("Attachment mutations describe journal add and remove events")
    func attachmentMutationsDescribeJournalEvents() {
        let attachment = SharedMediaAttachmentMetadata(
            id: "annotation-1",
            kind: .annotation,
            byteCount: 512
        )

        #expect(SharedMediaAttachmentMutation.added(attachment) == .added(attachment))
        #expect(SharedMediaAttachmentMutation.removed("annotation-1") == .removed("annotation-1"))
    }
}

@MainActor
private final class MockMediaTransport: MediaTransportControlling, @unchecked Sendable {
    var isPlaying = false
    var currentTime: TimeInterval = 10
    private(set) var events: [String] = []

    func play() async {
        isPlaying = true
        events.append("play")
    }

    func pause() async {
        isPlaying = false
        events.append("pause")
    }

    func seek(to seconds: TimeInterval) async {
        currentTime = seconds
        events.append("seek:\(seconds)")
    }

    func next() async {
        events.append("next")
    }

    func previous() async {
        events.append("previous")
    }
}
