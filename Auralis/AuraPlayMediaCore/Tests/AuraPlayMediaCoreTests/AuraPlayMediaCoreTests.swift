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

    @Test("Cache keys keep a readable stub and sanitize filesystem-hostile identifiers")
    func cacheKeySanitizesMediaID() {
        let key = CacheKey(mediaID: "wallet/track id?#1").rawValue

        #expect(key.hasPrefix("media-wallet-track-id--1-"))
        #expect(key.rangeOfCharacter(from: CharacterSet(charactersIn: "/?#: ")) == nil)
        #expect(CacheKey(mediaID: "").rawValue.hasPrefix("media-"))
        #expect(CacheKey(mediaID: "///???").rawValue.hasPrefix("media-"))
    }

    @Test("Cache keys are deterministic and collision-resistant across sanitized identifiers")
    func cacheKeyIsCollisionResistant() throws {
        let url = try #require(URL(string: "track-1"))

        #expect(CacheKey(mediaID: "a/b") == CacheKey(mediaID: "a/b"))
        #expect(CacheKey(mediaID: "a/b") != CacheKey(mediaID: "a?b"))
        #expect(CacheKey(mediaID: "///???") != CacheKey(mediaID: "?/?/?/"))
        #expect(CacheKey(mediaID: "track-1") != CacheKey(url: url))
    }

    @Test("Cache keys stay within filename length limits for long URLs")
    func cacheKeyStaysWithinFilenameLimits() throws {
        let longPath = String(repeating: "a", count: 400)
        let url = try #require(URL(string: "https://gateway.example/ipfs/\(longPath)?token=abc"))
        let otherURL = try #require(URL(string: "https://gateway.example/ipfs/\(longPath)?token=abd"))

        let key = CacheKey(url: url).rawValue

        #expect(key.utf8.count <= 255)
        #expect(key.hasPrefix("url-"))
        #expect(key.rangeOfCharacter(from: CharacterSet(charactersIn: "/?=+")) == nil)
        #expect(CacheKey(url: url) == CacheKey(url: url))
        #expect(CacheKey(url: url) != CacheKey(url: otherURL))
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

    @Test("Gateway resolver passes web and file URLs through untouched")
    func gatewayResolverPassesWebURLsThrough() async throws {
        let resolver = GatewayMediaURLResolver()
        let web = try #require(URL(string: "https://example.com/track.mp3"))
        let file = try #require(URL(string: "file:///tmp/track.mp3"))

        #expect(try await resolver.resolve(web) == web)
        #expect(try await resolver.resolve(file) == file)
    }

    @Test("Gateway resolver maps IPFS URLs preserving case-sensitive CIDs")
    func gatewayResolverMapsIPFSPreservingCIDCase() async throws {
        let resolver = GatewayMediaURLResolver()
        let withPath = try #require(URL(string: "ipfs://QmYwAPJzv5CZsnA625s3Xf2nemtYgPpHdWEz79ojWnPbdG/readme.txt"))
        let bare = try #require(URL(string: "ipfs://QmYwAPJzv5CZsnA625s3Xf2nemtYgPpHdWEz79ojWnPbdG"))

        let resolvedWithPath = try await resolver.resolve(withPath)
        let resolvedBare = try await resolver.resolve(bare)

        #expect(resolvedWithPath.absoluteString == "https://ipfs.io/ipfs/QmYwAPJzv5CZsnA625s3Xf2nemtYgPpHdWEz79ojWnPbdG/readme.txt")
        #expect(resolvedBare.absoluteString == "https://ipfs.io/ipfs/QmYwAPJzv5CZsnA625s3Xf2nemtYgPpHdWEz79ojWnPbdG")
    }

    @Test("Gateway resolver maps Arweave URLs and rejects unsupported schemes")
    func gatewayResolverMapsArweaveAndRejectsUnknownSchemes() async throws {
        let resolver = GatewayMediaURLResolver()
        let arweave = try #require(URL(string: "ar://AbC123xYz"))
        let unsupported = try #require(URL(string: "magnet:?xt=urn:btih:abc"))

        let resolved = try await resolver.resolve(arweave)
        #expect(resolved.absoluteString == "https://arweave.net/AbC123xYz")

        await #expect(throws: AuraPlayError.invalidMediaURL(unsupported)) {
            _ = try await resolver.resolve(unsupported)
        }
    }

    @Test("Gateway resolver preserves query strings and fragments when mapping to gateways")
    func gatewayResolverPreservesQueryStringsAndFragments() async throws {
        let resolver = GatewayMediaURLResolver()
        let ipfs = try #require(URL(string: "ipfs://QmYwAPJzv5CZsnA625s3Xf2nemtYgPpHdWEz79ojWnPbdG/track.mp3?filename=track%20one.mp3"))
        let arweave = try #require(URL(string: "ar://AbC123xYz?ext=mp4"))
        let ipfsFragment = try #require(URL(string: "ipfs://QmYwAPJzv5CZsnA625s3Xf2nemtYgPpHdWEz79ojWnPbdG/video.mp4#t=30"))
        let arweaveQueryAndFragment = try #require(URL(string: "ar://AbC123xYz?ext=mp4#t=5,20"))

        let resolvedIPFS = try await resolver.resolve(ipfs)
        let resolvedArweave = try await resolver.resolve(arweave)
        let resolvedIPFSFragment = try await resolver.resolve(ipfsFragment)
        let resolvedArweaveQueryAndFragment = try await resolver.resolve(arweaveQueryAndFragment)

        #expect(resolvedIPFS.absoluteString == "https://ipfs.io/ipfs/QmYwAPJzv5CZsnA625s3Xf2nemtYgPpHdWEz79ojWnPbdG/track.mp3?filename=track%20one.mp3")
        #expect(resolvedArweave.absoluteString == "https://arweave.net/AbC123xYz?ext=mp4")
        #expect(resolvedIPFSFragment.absoluteString == "https://ipfs.io/ipfs/QmYwAPJzv5CZsnA625s3Xf2nemtYgPpHdWEz79ojWnPbdG/video.mp4#t=30")
        #expect(resolvedArweaveQueryAndFragment.absoluteString == "https://arweave.net/AbC123xYz?ext=mp4#t=5,20")
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

    @Test("Cached file state round-trips through Codable alongside its sibling enums")
    func cachedFileStateRoundTripsThroughCodable() throws {
        for state in AuraCachedFileState.allCases {
            let encoded = try JSONEncoder().encode(state)
            #expect(try JSONDecoder().decode(AuraCachedFileState.self, from: encoded) == state)
        }
    }

    @Test("Fixed network status provider represents online and offline fixtures")
    func fixedNetworkStatusProviderRepresentsBothStates() {
        #expect(FixedMediaNetworkStatusProvider().isOffline == false)
        #expect(FixedMediaNetworkStatusProvider(isOffline: true).isOffline)
    }

    @Test("No-op media logger accepts informational and error messages")
    func noOpMediaLoggerAcceptsMessages() {
        let logger = NoOpMediaEngineLogger()

        logger.info("loaded")
        logger.error("failed")
    }

    @Test("AuraPlay errors provide localized descriptions")
    func auraPlayErrorsProvideLocalizedDescriptions() throws {
        let url = try #require(URL(string: "https://example.com/broken.mp3"))

        #expect(AuraPlayError.mediaUnavailableOffline.errorDescription?.isEmpty == false)
        #expect(AuraPlayError.unsupportedFormat("ogg").errorDescription?.contains("ogg") == true)
        #expect(AuraPlayError.downloadFailed("HTTP 404").errorDescription?.contains("HTTP 404") == true)
        #expect(AuraPlayError.invalidMediaURL(url).errorDescription?.contains(url.absoluteString) == true)
    }

    @Test("Shared media session identity carries SharePlay coordination identity")
    func sharedMediaSessionIdentityCarriesCoordinationIdentity() throws {
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

        #expect(identity.activity.fallbackURL == fallbackURL)
        #expect(identity.queue.currentItemID == "video-1")
        #expect(identity.queue.revision == 3)
        #expect(identity.lobbyPolicy.lateJoinPolicy == .waitInLobby)
        #expect(identity.lobbyPolicy.minimumReadyParticipants == 2)
        #expect(identity.lobbyPolicy.requiresExplicitStart)
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

        #expect(activity.activityIdentifier.isReverseDNSStyle)
        #expect(SharedMediaActivityIdentifier(rawValue: "order-together").isReverseDNSStyle == false)
        #expect(SharedMediaActivityIdentifier(rawValue: "...").isReverseDNSStyle == false)
        #expect(activity.activityType == .shopTogether)
        #expect(activity.launchPayload["truckName"] == "Aura Taco Truck")
    }
}

@Suite("URLSession media downloader HTTP handling", .serialized)
struct URLSessionMediaDownloaderHTTPTests {
    private func makeStubSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        return URLSession(configuration: configuration)
    }

    private func temporaryFileURL(_ prefix: String) -> URL {
        FileManager.default.temporaryDirectory
            .appending(path: "\(prefix)-\(UUID().uuidString)")
    }

    @Test("Download rejects HTTP error statuses instead of returning the error body")
    func downloadRejectsHTTPErrorStatus() async throws {
        let url = try #require(URL(string: "https://cdn.example/missing.mp3"))
        StubURLProtocol.responder = { _ in (404, [:], Data("not found".utf8)) }
        let downloader = URLSessionMediaDownloader(session: makeStubSession())

        await #expect(throws: AuraPlayError.downloadFailed("HTTP 404 for \(url.absoluteString)")) {
            _ = try await downloader.download(from: url)
        }
    }

    @Test("Download returns the payload for successful responses")
    func downloadReturnsPayloadOnSuccess() async throws {
        let url = try #require(URL(string: "https://cdn.example/track.mp3"))
        let body = Data((0..<4_096).map { UInt8($0 % 251) })
        StubURLProtocol.responder = { _ in (200, ["Content-Length": "\(body.count)"], body) }
        let downloader = URLSessionMediaDownloader(session: makeStubSession())

        let (fileURL, response) = try await downloader.download(from: url)
        defer { try? FileManager.default.removeItem(at: fileURL) }

        #expect((response as? HTTPURLResponse)?.statusCode == 200)
        #expect(try Data(contentsOf: fileURL) == body)
    }

    @Test("Resume appends partial content responses to the partial file")
    func resumeAppendsPartialContent() async throws {
        let url = try #require(URL(string: "https://cdn.example/resumable.mp3"))
        let partialFileURL = temporaryFileURL("mediacore-partial")
        let prefix = Data([1, 2, 3, 4, 5])
        let tail = Data([6, 7, 8, 9])
        try prefix.write(to: partialFileURL)
        defer { try? FileManager.default.removeItem(at: partialFileURL) }
        StubURLProtocol.responder = { _ in (206, ["Content-Range": "bytes 5-8/9"], tail) }
        let downloader = URLSessionMediaDownloader(session: makeStubSession())

        let (fileURL, _) = try await downloader.resumeDownload(
            from: url,
            to: partialFileURL,
            startingAt: Int64(prefix.count)
        )

        #expect(fileURL == partialFileURL)
        #expect(try Data(contentsOf: partialFileURL) == prefix + tail)
    }

    @Test("Resume rejects partial content whose range does not start at the resume offset")
    func resumeRejectsMismatchedContentRange() async throws {
        let url = try #require(URL(string: "https://cdn.example/mismatched.mp3"))
        let partialFileURL = temporaryFileURL("mediacore-partial")
        let existing = Data([1, 2, 3, 4, 5])
        try existing.write(to: partialFileURL)
        defer { try? FileManager.default.removeItem(at: partialFileURL) }
        StubURLProtocol.responder = { _ in (206, ["Content-Range": "bytes 0-8/9"], Data([9, 9, 9, 9])) }
        let downloader = URLSessionMediaDownloader(session: makeStubSession())

        await #expect(throws: AuraPlayError.downloadFailed("Partial content did not start at byte 5 for \(url.absoluteString)")) {
            _ = try await downloader.resumeDownload(from: url, to: partialFileURL, startingAt: 5)
        }
        #expect(try Data(contentsOf: partialFileURL) == existing)
    }

    @Test("Resume rejects partial content without a verifiable Content-Range header")
    func resumeRejectsMissingContentRange() async throws {
        let url = try #require(URL(string: "https://cdn.example/unverifiable.mp3"))
        let partialFileURL = temporaryFileURL("mediacore-partial")
        let existing = Data([1, 2, 3])
        try existing.write(to: partialFileURL)
        defer { try? FileManager.default.removeItem(at: partialFileURL) }
        StubURLProtocol.responder = { _ in (206, [:], Data([4, 5])) }
        let downloader = URLSessionMediaDownloader(session: makeStubSession())

        await #expect(throws: AuraPlayError.downloadFailed("Partial content did not start at byte 3 for \(url.absoluteString)")) {
            _ = try await downloader.resumeDownload(from: url, to: partialFileURL, startingAt: 3)
        }
        #expect(try Data(contentsOf: partialFileURL) == existing)
    }

    @Test("Resume replaces the partial file when the server sends the full payload")
    func resumeReplacesFileOnFullResponse() async throws {
        let url = try #require(URL(string: "https://cdn.example/changed.mp3"))
        let partialFileURL = temporaryFileURL("mediacore-partial")
        try Data([9, 9, 9]).write(to: partialFileURL)
        defer { try? FileManager.default.removeItem(at: partialFileURL) }
        let fullBody = Data([1, 2, 3, 4, 5, 6])
        StubURLProtocol.responder = { _ in (200, [:], fullBody) }
        let downloader = URLSessionMediaDownloader(session: makeStubSession())

        let (fileURL, _) = try await downloader.resumeDownload(
            from: url,
            to: partialFileURL,
            startingAt: 3
        )

        #expect(fileURL == partialFileURL)
        #expect(try Data(contentsOf: partialFileURL) == fullBody)
    }

    @Test("Resume surfaces HTTP errors and preserves the partial file")
    func resumeSurfacesHTTPErrorsAndPreservesPartialFile() async throws {
        let url = try #require(URL(string: "https://cdn.example/unsatisfiable.mp3"))
        let partialFileURL = temporaryFileURL("mediacore-partial")
        let existing = Data([1, 2, 3])
        try existing.write(to: partialFileURL)
        defer { try? FileManager.default.removeItem(at: partialFileURL) }
        StubURLProtocol.responder = { _ in (416, [:], Data("range not satisfiable".utf8)) }
        let downloader = URLSessionMediaDownloader(session: makeStubSession())

        await #expect(throws: AuraPlayError.downloadFailed("HTTP 416 for \(url.absoluteString)")) {
            _ = try await downloader.resumeDownload(from: url, to: partialFileURL, startingAt: 3)
        }
        #expect(try Data(contentsOf: partialFileURL) == existing)
    }

    @Test("Progressive download streams chunks to disk and completes with the full payload")
    func progressiveDownloadStreamsChunksToDisk() async throws {
        let url = try #require(URL(string: "https://cdn.example/progressive.mp3"))
        let destinationURL = temporaryFileURL("mediacore-progressive")
        defer { try? FileManager.default.removeItem(at: destinationURL) }
        let body = Data((0..<100_000).map { UInt8($0 % 249) })
        StubURLProtocol.responder = { _ in (200, ["Content-Length": "\(body.count)"], body) }
        let downloader = URLSessionMediaDownloader(session: makeStubSession())

        let handle = try await downloader.downloadUntilPlayable(
            from: url,
            to: destinationURL,
            minimumPlayableBytes: 1_024
        )

        #expect(handle.playableURL == destinationURL)
        let completedURL = try await handle.completion.value
        #expect(completedURL == destinationURL)
        #expect(try Data(contentsOf: destinationURL) == body)
    }

    @Test("Progressive download rejects HTTP error statuses before writing")
    func progressiveDownloadRejectsHTTPErrorStatus() async throws {
        let url = try #require(URL(string: "https://cdn.example/progressive-missing.mp3"))
        let destinationURL = temporaryFileURL("mediacore-progressive")
        defer { try? FileManager.default.removeItem(at: destinationURL) }
        StubURLProtocol.responder = { _ in (503, [:], Data("service unavailable".utf8)) }
        let downloader = URLSessionMediaDownloader(session: makeStubSession())

        await #expect(throws: AuraPlayError.downloadFailed("HTTP 503 for \(url.absoluteString)")) {
            _ = try await downloader.downloadUntilPlayable(
                from: url,
                to: destinationURL,
                minimumPlayableBytes: 1_024
            )
        }
        #expect(FileManager.default.fileExists(atPath: destinationURL.path) == false)
    }

    @Test("Progressive download removes the empty destination when the transport fails")
    func progressiveDownloadRemovesEmptyDestinationOnTransportFailure() async throws {
        let url = try #require(URL(string: "https://cdn.example/unreachable.mp3"))
        let destinationURL = temporaryFileURL("mediacore-progressive")
        defer { try? FileManager.default.removeItem(at: destinationURL) }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [FailingStubURLProtocol.self]
        let downloader = URLSessionMediaDownloader(session: URLSession(configuration: configuration))

        await #expect(throws: (any Error).self) {
            _ = try await downloader.downloadUntilPlayable(
                from: url,
                to: destinationURL,
                minimumPlayableBytes: 1_024
            )
        }
        #expect(FileManager.default.fileExists(atPath: destinationURL.path) == false)
    }

    @Test("Progressive download cancellation fails completion and keeps partial bytes for resume")
    func progressiveDownloadCancellationKeepsPartialBytes() async throws {
        let url = try #require(URL(string: "https://cdn.example/hanging.mp3"))
        let destinationURL = temporaryFileURL("mediacore-progressive")
        defer { try? FileManager.default.removeItem(at: destinationURL) }
        let chunk = Data((0..<4_096).map { UInt8($0 % 241) })
        HangingStubURLProtocol.initialChunk = chunk
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [HangingStubURLProtocol.self]
        let downloader = URLSessionMediaDownloader(session: URLSession(configuration: configuration))

        let handle = try await downloader.downloadUntilPlayable(
            from: url,
            to: destinationURL,
            minimumPlayableBytes: Int64(chunk.count)
        )

        handle.completion.cancel()
        await #expect(throws: (any Error).self) {
            _ = try await handle.completion.value
        }
        #expect(try Data(contentsOf: destinationURL) == chunk)
    }

    @Test("Chunk streaming delegate suspends at the high-water mark and resumes after draining")
    func chunkStreamingDelegateAppliesBackpressure() async throws {
        let url = try #require(URL(string: "https://cdn.example/backpressure.mp3"))
        HangingStubURLProtocol.initialChunk = Data()
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [HangingStubURLProtocol.self]
        let session = URLSession(configuration: configuration)
        let (chunks, continuation) = AsyncThrowingStream.makeStream(of: Data.self)
        let delegate = ChunkStreamingTaskDelegate(chunks: continuation)
        let task = session.dataTask(with: URLRequest(url: url))
        delegate.attach(to: task)
        task.resume()
        defer {
            continuation.finish()
            task.cancel()
        }
        #expect(task.state == .running)

        delegate.urlSession(session, dataTask: task, didReceive: Data(count: Int(ChunkStreamingTaskDelegate.bufferHighWaterMark)))
        #expect(task.state == .suspended)

        // Draining down to the low-water mark resumes the transfer.
        let drained = ChunkStreamingTaskDelegate.bufferHighWaterMark - ChunkStreamingTaskDelegate.bufferLowWaterMark
        delegate.consume(byteCount: Int(drained))
        #expect(task.state == .running)
        for try await _ in chunks { break }
    }
}

private final class StubURLProtocol: URLProtocol {
    nonisolated(unsafe) static var responder: (@Sendable (URLRequest) -> (Int, [String: String], Data))?

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard
            let responder = Self.responder,
            let url = request.url
        else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }
        let (status, headers, body) = responder(request)
        guard let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: "HTTP/1.1", headerFields: headers) else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

/// Fails every request at the transport layer before any response is delivered.
private final class FailingStubURLProtocol: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        client?.urlProtocol(self, didFailWithError: URLError(.cannotConnectToHost))
    }

    override func stopLoading() {}
}

/// Delivers a 200 response and one chunk, then keeps the transfer open forever
/// so tests can observe in-flight behavior like cancellation.
private final class HangingStubURLProtocol: URLProtocol {
    nonisolated(unsafe) static var initialChunk = Data()

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard
            let url = request.url,
            let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: [:])
        else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        if !Self.initialChunk.isEmpty {
            client?.urlProtocol(self, didLoad: Self.initialChunk)
        }
        // Intentionally never calls urlProtocolDidFinishLoading.
    }

    override func stopLoading() {}
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
