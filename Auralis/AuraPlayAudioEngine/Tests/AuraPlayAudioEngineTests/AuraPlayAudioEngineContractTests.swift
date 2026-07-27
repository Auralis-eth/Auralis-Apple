import AudioToolbox
import AVFoundation
import Foundation
import Testing
#if canImport(MediaPlayer)
import MediaPlayer
#endif
@testable import AuraPlayAudioEngine

private struct FixtureMedia: AuraPlayableMedia {
    let id: String
    let sourceURL: URL
    let declaredFormat: String?
    let contentKind: AuraPlayableContentKind
    let cachedFileState: AuraCachedFileState
    let approxLoudnessLUFS: Double?
}

private struct FixturePlugin: DecoderPlugin {
    let supportedExtensions: Set<String> = ["fixture"]

    func makeSource(for fileURL: URL, declaredFormat: String?) throws -> any AudioTrackSource {
        try NativeAudioTrackSource(fileURL: fileURL, declaredFormat: declaredFormat)
    }
}

private actor MockAudioSessionManager: AudioSessionManaging {
    private(set) var configureCallCount = 0
    private(set) var activateCallCount = 0
    private(set) var deactivateCallCount = 0
    private(set) var supportsMultichannelContentValues: [Bool] = []
    private var spatialAudioEnabled = false

    nonisolated let events: AsyncStream<AudioSessionEvent>
    private let continuation: AsyncStream<AudioSessionEvent>.Continuation

    init() {
        let streamPair = AsyncStream<AudioSessionEvent>.makeStream()
        self.events = streamPair.stream
        self.continuation = streamPair.continuation
    }

    deinit {
        continuation.finish()
    }

    func configure() async throws {
        configureCallCount += 1
    }

    func activate() async throws {
        activateCallCount += 1
    }

    func deactivate() async throws {
        deactivateCallCount += 1
    }

    func setSupportsMultichannelContent(_ supports: Bool) async throws {
        supportsMultichannelContentValues.append(supports)
    }

    func currentSpatialAudioEnabled() async -> Bool {
        spatialAudioEnabled
    }

    func setSpatialAudioEnabled(_ isEnabled: Bool) {
        spatialAudioEnabled = isEnabled
    }

    func send(_ event: AudioSessionEvent) {
        continuation.yield(event)
    }
}

@Test("NFT-like media can be adapted without importing an NFT model")
func mediaTypeErasurePreservesGenericFields() throws {
    let media = FixtureMedia(
        id: "42",
        sourceURL: try #require(URL(string: "ipfs://example/audio.mp3")),
        declaredFormat: "mp3",
        contentKind: .music,
        cachedFileState: .cached,
        approxLoudnessLUFS: -18
    )

    let erased = AnyAuraPlayableMedia(media)

    #expect(erased.id == "42")
    #expect(erased.sourceURL == media.sourceURL)
    #expect(erased.declaredFormat == "mp3")
    #expect(erased.contentKind == .music)
    #expect(erased.cachedFileState == .cached)
    #expect(erased.approxLoudnessLUFS == -18)
}

@Test("Cache keys remove filesystem-hostile characters")
func cacheKeySanitizesMediaID() {
    let key = CacheKey(mediaID: "wallet/track id?#1")

    #expect(key.rawValue.hasPrefix("media-wallet-track-id--1-"))
    #expect(key.rawValue.rangeOfCharacter(from: CharacterSet(charactersIn: "/?#: ")) == nil)
}

@Test("Cache keys stay distinct when sanitizing would produce an empty filename")
func cacheKeyFallsBackForEmptySanitizedID() {
    #expect(CacheKey(mediaID: "///???").rawValue.hasPrefix("media-"))
    #expect(CacheKey(mediaID: "").rawValue.hasPrefix("media-"))
    #expect(CacheKey(mediaID: "///???") != CacheKey(mediaID: ""))
}

@Test("EQ presets expose deterministic ten-band gains")
func eqPresetGainsAreDeterministic() {
    #expect(EQPreset.bassBoost.gains == [4, 4, 4, 0, 0, 0, 0, 0, 0, 0])
    #expect(EQPreset.vocalClarity.gains == [-2, 0, 0, 0, 3, 3, 3, 0, 0, 0])
    #expect(EQPreset.custom([1, 2]).gains == [1, 2, 0, 0, 0, 0, 0, 0, 0, 0])
}

@Test("Approximate loudness normalization clamps gain")
func loudnessNormalizationClampsGain() {
    #expect(LoudnessNormalization.gainDB(for: -20) == 6)
    #expect(LoudnessNormalization.gainDB(for: -40) == 12)
    #expect(LoudnessNormalization.gainDB(for: 10) == -12)
    #expect(LoudnessNormalization.gainDB(for: nil) == 0)
}

@Test("Visualization configuration clamps callback pressure")
func visualizationConfigurationClampsCallbackPressure() {
    let fast = AudioVisualizationConfiguration(framesPerSecond: 120)
    let tiny = AudioVisualizationConfiguration(preferredBufferFrameCount: 128)
    let huge = AudioVisualizationConfiguration(preferredBufferFrameCount: 20_000)

    #expect(fast.framesPerSecond == 60)
    #expect(fast.bufferFrameCount(sampleRate: 48_000) == 800)
    #expect(tiny.bufferFrameCount(sampleRate: 48_000) == 256)
    #expect(huge.bufferFrameCount(sampleRate: 48_000) == 16_384)
}

@Test("Visualization analyzer reports per-channel RMS and peak")
func visualizationAnalyzerReportsChannelLevels() throws {
    let format = try #require(AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 2))
    let buffer = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 4))
    buffer.frameLength = 4

    let firstChannel = try #require(buffer.floatChannelData?[0])
    let secondChannel = try #require(buffer.floatChannelData?[1])
    for frame in 0..<4 {
        firstChannel[frame] = frame.isMultiple(of: 2) ? 1 : -1
        secondChannel[frame] = 0.5
    }

    let frame = AudioVisualizationAnalyzer.makeFrame(
        buffer: buffer,
        time: AVAudioTime(sampleTime: 42, atRate: 48_000)
    )

    #expect(frame.renderFrame == 42)
    #expect(frame.hostTime == nil)
    #expect(frame.sampleRate == 48_000)
    #expect(frame.frameCount == 4)
    #expect(frame.channels.count == 2)
    #expect(abs(frame.channels[0].rms - 1) < 0.001)
    #expect(abs(frame.channels[0].peak - 1) < 0.001)
    #expect(abs(frame.channels[1].rms - 0.5) < 0.001)
    #expect(abs(frame.channels[1].peak - 0.5) < 0.001)
}

@Test("Visualization tap lifecycle preserves playback graph")
func visualizationTapLifecyclePreservesPlaybackGraph() async throws {
    let controller = try AudioEngineController()
    let firstStream = controller.startVisualization(configuration: AudioVisualizationConfiguration(preferredBufferFrameCount: 512))
    let secondStream = controller.startVisualization(configuration: AudioVisualizationConfiguration(preferredBufferFrameCount: 1_024))
    _ = (firstStream, secondStream)

    #expect(controller.graphDescription.connectionCount == 5)

    await controller.stopVisualization()

    #expect(controller.graphDescription.connectionCount == 5)
}

@Test("Equal-power crossfade curve has expected midpoint")
func equalPowerCrossfadeMidpoint() {
    let curve = EqualPowerCrossfadeCurve()
    let midpoint = curve.volumes(progress: 0.5)

    #expect(abs(midpoint.outgoing - 0.707) < 0.01)
    #expect(abs(midpoint.incoming - 0.707) < 0.01)
}

@Test("Native WAV opens through the native source path")
func nativeWAVUsesNativeSource() throws {
    let fileURL = try makeFixtureWAV(name: "native")
    let factory = AudioTrackSourceFactory()
    let source = try factory.makeSource(for: fileURL)

    #expect(source is NativeAudioTrackSource)
    #expect(source.frameLength > 0)
}

@Test("Declared format overrides extensionless cache files")
func declaredFormatOverridesMissingExtension() throws {
    let wavURL = try makeFixtureWAV(name: "extensionless-source")
    let extensionlessURL = FileManager.default.temporaryDirectory
        .appending(path: "extensionless-\(UUID().uuidString)")
    try FileManager.default.copyItem(at: wavURL, to: extensionlessURL)

    let factory = AudioTrackSourceFactory()
    let source = try factory.makeSource(for: extensionlessURL, declaredFormat: "wav")

    #expect(source is NativeAudioTrackSource)
}

@Test("Cache normalizes declared formats before creating local filenames")
func cacheNormalizesDeclaredFormatsBeforeCreatingLocalFilenames() async throws {
    let sourceURL = try makeFixtureWAV(name: "normalized-format-source")
    let extensionlessURL = FileManager.default.temporaryDirectory
        .appending(path: "normalized-format-\(UUID().uuidString)")
    try FileManager.default.copyItem(at: sourceURL, to: extensionlessURL)
    let cacheDirectory = FileManager.default.temporaryDirectory
        .appending(path: "AuraPlayNormalizedFormat-\(UUID().uuidString)", directoryHint: .isDirectory)
    let manager = try MediaCacheManager(cacheDirectory: cacheDirectory)
    let media = FixtureMedia(
        id: "normalized-format-item",
        sourceURL: extensionlessURL,
        declaredFormat: " .WAV ",
        contentKind: .music,
        cachedFileState: .notCached,
        approxLoudnessLUFS: nil
    )

    let cachedURL = try await manager.localFile(for: media)

    #expect(cachedURL.lastPathComponent == "\(CacheKey(mediaID: "normalized-format-item").rawValue).wav")
    #expect(await manager.isCached(media))
}

@Test("Deferred formats fail cleanly until plugins are registered")
func deferredFormatsFailCleanly() throws {
    let factory = AudioTrackSourceFactory()

    #expect(throws: AuraPlayError.unsupportedFormat("ogg")) {
        try factory.makeSource(for: URL(fileURLWithPath: "/tmp/track.ogg"))
    }
}

@Test("Decoder plugins can handle future formats without graph changes")
func decoderPluginHandlesRegisteredExtension() throws {
    let fileURL = try makeFixtureWAV(name: "plugin")
    let fixtureURL = fileURL.deletingPathExtension().appendingPathExtension("fixture")
    try FileManager.default.copyItem(at: fileURL, to: fixtureURL)

    let factory = AudioTrackSourceFactory(plugins: [FixturePlugin()])
    let source = try factory.makeSource(for: fixtureURL)

    #expect(source is NativeAudioTrackSource)
}

@Test("Media cache returns local file and reuses it")
func mediaCacheCopiesLocalFileAndReusesIt() async throws {
    let sourceURL = try makeFixtureWAV(name: "cache")
    let cacheDirectory = FileManager.default.temporaryDirectory
        .appending(path: "AuraPlayCacheTests-\(UUID().uuidString)", directoryHint: .isDirectory)
    let manager = try MediaCacheManager(cacheDirectory: cacheDirectory, diskCapBytes: 10_000_000)
    let media = FixtureMedia(
        id: "cache-item",
        sourceURL: sourceURL,
        declaredFormat: "wav",
        contentKind: .music,
        cachedFileState: .notCached,
        approxLoudnessLUFS: nil
    )

    #expect(await manager.isCached(media) == false)
    let firstURL = try await manager.localFile(for: media)
    let secondURL = try await manager.localFile(for: media)

    #expect(await manager.isCached(media) == true)
    #expect(firstURL == secondURL)
    #expect(FileManager.default.fileExists(atPath: firstURL.path))
}

@Test("Corrupt complete cache hits are invalidated before reuse")
func corruptCompleteCacheHitInvalidatesAndRecaches() async throws {
    let sourceURL = try makeFixtureWAV(name: "cache-corruption-source")
    let cacheDirectory = FileManager.default.temporaryDirectory
        .appending(path: "AuraPlayCorruptCacheHit-\(UUID().uuidString)", directoryHint: .isDirectory)
    let manager = try MediaCacheManager(cacheDirectory: cacheDirectory, diskCapBytes: 10_000_000)
    let media = FixtureMedia(
        id: "cache-corruption-item",
        sourceURL: sourceURL,
        declaredFormat: "wav",
        contentKind: .music,
        cachedFileState: .notCached,
        approxLoudnessLUFS: nil
    )

    let cachedURL = try await manager.localFile(for: media)
    try Data("not audio".utf8).write(to: cachedURL)

    #expect(await manager.isCached(media) == false)
    let restoredURL = try await manager.localFile(for: media)

    #expect(restoredURL == cachedURL)
    #expect(fileSize(restoredURL) == fileSize(sourceURL))
    #expect(await manager.isCached(media) == true)
}

@Test("LRU eviction removes the oldest unpinned cached file")
func lruEvictionRemovesOldestUnpinnedFile() async throws {
    let firstSource = try makeFixtureWAV(name: "lru-first")
    let secondSource = try makeFixtureWAV(name: "lru-second")
    let cacheDirectory = FileManager.default.temporaryDirectory
        .appending(path: "AuraPlayLRU-\(UUID().uuidString)", directoryHint: .isDirectory)
    let manager = try MediaCacheManager(cacheDirectory: cacheDirectory, diskCapBytes: fileSize(firstSource) + 1)
    let first = FixtureMedia(
        id: "lru-first",
        sourceURL: firstSource,
        declaredFormat: "wav",
        contentKind: .music,
        cachedFileState: .notCached,
        approxLoudnessLUFS: nil
    )
    let second = FixtureMedia(
        id: "lru-second",
        sourceURL: secondSource,
        declaredFormat: "wav",
        contentKind: .music,
        cachedFileState: .notCached,
        approxLoudnessLUFS: nil
    )

    _ = try await manager.localFile(for: first)
    _ = try await manager.localFile(for: second)

    #expect(await manager.isCached(first) == false)
    #expect(await manager.isCached(second) == true)
}

@Test("Cache cap preference is clamped and persisted")
func cacheCapPreferenceIsClampedAndPersisted() async throws {
    let source = try makeFixtureWAV(name: "settings-cap")
    let cacheDirectory = FileManager.default.temporaryDirectory
        .appending(path: "AuraPlaySettingsCap-\(UUID().uuidString)", directoryHint: .isDirectory)
    let suiteName = "AuraPlayCacheSettings.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suiteName))
    defer { UserDefaults(suiteName: suiteName)?.removePersistentDomain(forName: suiteName) }
    let manager = try MediaCacheManager(
        cacheDirectory: cacheDirectory,
        diskCapBytes: 10_000_000,
        settingsDefaults: defaults
    )
    let media = FixtureMedia(
        id: "settings-cap",
        sourceURL: source,
        declaredFormat: "wav",
        contentKind: .music,
        cachedFileState: .notCached,
        approxLoudnessLUFS: nil
    )

    _ = try await manager.localFile(for: media)
    let summary = try await manager.updateDiskCapBytes(1)

    #expect(summary.diskCapBytes == AuraPlayCacheSettings.minimumDiskCapBytes)
    #expect(await manager.isCached(media) == true)
    let observedDefaults = try #require(UserDefaults(suiteName: suiteName))
    #expect(AuraPlayCacheSettings.diskCapBytes(from: observedDefaults) == AuraPlayCacheSettings.minimumDiskCapBytes)
}

@Test("Clearing cache preserves pinned and actively read files")
func clearUnpinnedCachePreservesPinnedAndActiveFiles() async throws {
    let pinnedSource = try makeFixtureWAV(name: "clear-pinned")
    let activeSource = try makeFixtureWAV(name: "clear-active")
    let removableSource = try makeFixtureWAV(name: "clear-removable")
    let cacheDirectory = FileManager.default.temporaryDirectory
        .appending(path: "AuraPlayClearCache-\(UUID().uuidString)", directoryHint: .isDirectory)
    let manager = try MediaCacheManager(cacheDirectory: cacheDirectory, diskCapBytes: 10_000_000)
    let pinned = FixtureMedia(
        id: "clear-pinned",
        sourceURL: pinnedSource,
        declaredFormat: "wav",
        contentKind: .music,
        cachedFileState: .notCached,
        approxLoudnessLUFS: nil
    )
    let active = FixtureMedia(
        id: "clear-active",
        sourceURL: activeSource,
        declaredFormat: "wav",
        contentKind: .music,
        cachedFileState: .notCached,
        approxLoudnessLUFS: nil
    )
    let removable = FixtureMedia(
        id: "clear-removable",
        sourceURL: removableSource,
        declaredFormat: "wav",
        contentKind: .music,
        cachedFileState: .notCached,
        approxLoudnessLUFS: nil
    )

    _ = try await manager.localFile(for: pinned)
    try await manager.pin(pinned)
    _ = try await manager.localFile(for: active)
    await manager.beginReading(active)
    _ = try await manager.localFile(for: removable)

    let summary = try await manager.clearUnpinnedCache()

    #expect(await manager.isCached(pinned) == true)
    #expect(await manager.isCached(active) == true)
    #expect(await manager.isCached(removable) == false)
    #expect(summary.cachedEntryCount == 2)
    #expect(summary.pinnedEntryCount == 1)
}

@Test("Pinned and actively-read files survive cache eviction")
func pinnedAndActivelyReadFilesSurviveEviction() async throws {
    let pinnedSource = try makeFixtureWAV(name: "pinned")
    let activeSource = try makeFixtureWAV(name: "active-reader")
    let triggerSource = try makeFixtureWAV(name: "eviction-trigger")
    let cacheDirectory = FileManager.default.temporaryDirectory
        .appending(path: "AuraPlayPinnedActive-\(UUID().uuidString)", directoryHint: .isDirectory)
    let manager = try MediaCacheManager(cacheDirectory: cacheDirectory, diskCapBytes: fileSize(pinnedSource) + fileSize(activeSource) + 1)
    let pinned = FixtureMedia(
        id: "pinned-item",
        sourceURL: pinnedSource,
        declaredFormat: "wav",
        contentKind: .music,
        cachedFileState: .notCached,
        approxLoudnessLUFS: nil
    )
    let active = FixtureMedia(
        id: "active-item",
        sourceURL: activeSource,
        declaredFormat: "wav",
        contentKind: .music,
        cachedFileState: .notCached,
        approxLoudnessLUFS: nil
    )
    let trigger = FixtureMedia(
        id: "trigger-item",
        sourceURL: triggerSource,
        declaredFormat: "wav",
        contentKind: .music,
        cachedFileState: .notCached,
        approxLoudnessLUFS: nil
    )

    _ = try await manager.localFile(for: pinned)
    try await manager.pin(pinned)
    _ = try await manager.localFile(for: active)
    await manager.beginReading(active)
    _ = try await manager.localFile(for: trigger)

    #expect(await manager.isCached(pinned) == true)
    #expect(await manager.isCached(active) == true)
    #expect(await manager.isCached(trigger) == false)

    await manager.endReading(active)
}

@Test("Approximate loudness analyzer measures finite audio")
func approximateLoudnessAnalyzerMeasuresFixture() throws {
    let sourceURL = try makeFixtureWAV(name: "loudness")
    let analyzer = ApproximateLoudnessAnalyzer()
    let value = try analyzer.measureApproxLoudnessLUFS(fileURL: sourceURL)

    #expect(value.isFinite)
    #expect(value < 0)
}

@Test("Cache emits approximate loudness when a file finishes caching")
func cacheEmitsApproximateLoudnessMeasurement() async throws {
    let sourceURL = try makeFixtureWAV(name: "cache-loudness")
    let cacheDirectory = FileManager.default.temporaryDirectory
        .appending(path: "AuraPlayCacheLoudness-\(UUID().uuidString)", directoryHint: .isDirectory)
    let manager = try MediaCacheManager(cacheDirectory: cacheDirectory, diskCapBytes: 10_000_000)
    let media = FixtureMedia(
        id: "cache-loudness-item",
        sourceURL: sourceURL,
        declaredFormat: "wav",
        contentKind: .music,
        cachedFileState: .notCached,
        approxLoudnessLUFS: nil
    )
    let measurementStream = await manager.loudnessMeasurements
    var measurements = measurementStream.makeAsyncIterator()

    _ = try await manager.localFile(for: media)
    let measurement = await measurements.next()

    #expect(measurement?.mediaID == "cache-loudness-item")
    #expect(measurement?.approxLoudnessLUFS.isFinite == true)
}

@Test("Cache progress multicasts to multiple subscribers")
func cacheProgressMulticastsToMultipleSubscribers() async throws {
    let sourceURL = try makeFixtureWAV(name: "cache-progress-multicast")
    let cacheDirectory = FileManager.default.temporaryDirectory
        .appending(path: "AuraPlayCacheProgressMulticast-\(UUID().uuidString)", directoryHint: .isDirectory)
    let manager = try MediaCacheManager(cacheDirectory: cacheDirectory, diskCapBytes: 10_000_000)
    let media = FixtureMedia(
        id: "cache-progress-multicast-item",
        sourceURL: sourceURL,
        declaredFormat: "wav",
        contentKind: .music,
        cachedFileState: .notCached,
        approxLoudnessLUFS: nil
    )
    var firstProgress = manager.progress.makeAsyncIterator()
    var secondProgress = manager.progress.makeAsyncIterator()

    _ = try await manager.localFile(for: media)
    let firstUpdate = await firstProgress.next()
    let secondUpdate = await secondProgress.next()

    #expect(firstUpdate?.mediaID == "cache-progress-multicast-item")
    #expect(firstUpdate?.state == .cached)
    #expect(secondUpdate == firstUpdate)
}

@Test("Audio engine graph description matches Phase 6 topology")
func audioEngineGraphDescriptionMatchesTopology() throws {
    let controller = try AudioEngineController()

    #expect(controller.graphDescription.customNodeNames == [
        "primaryPlayerNode",
        "preBufferPlayerNode",
        "trackMixerNode",
        "eqNode",
        "dynamicsNode",
    ])
    #expect(controller.graphDescription.sampleRate == 48_000)
    #expect(controller.graphDescription.channelCount == 2)
    #expect(controller.graphDescription.connectionCount == 5)
    #expect(controller.graphDescription.containsEnvironmentNode == false)
}

@Test("Cached next track plans a render-frame gapless boundary")
func cachedNextTrackPlansRenderFrameBoundary() async throws {
    let cacheDirectory = FileManager.default.temporaryDirectory
        .appending(path: "AuraPlayGaplessBoundary-\(UUID().uuidString)", directoryHint: .isDirectory)
    let manager = try MediaCacheManager(cacheDirectory: cacheDirectory)
    let engineController = try AudioEngineController()
    let scheduler = GaplessScheduler(cacheManager: manager, engineController: engineController)
    let currentURL = try makeFixtureWAV(name: "gapless-current")
    let currentLength = try AVAudioFile(forReading: currentURL).length
    let next = FixtureMedia(
        id: "gapless-boundary-next",
        sourceURL: try makeFixtureWAV(name: "gapless-boundary-next"),
        declaredFormat: "wav",
        contentKind: .music,
        cachedFileState: .notCached,
        approxLoudnessLUFS: nil
    )

    try await scheduler.scheduleCurrent(fileURL: currentURL, startingFrame: 1_200)
    _ = try await manager.localFile(for: next)
    let quality = try await scheduler.prepareNext(next)

    #expect(quality == .gapless)
    #expect(engineController.debugPlannedGaplessBoundaryFrame() == currentLength - 1_200)
}

@Test("Gapless boundary converts source frames into render frames")
func gaplessBoundaryConvertsSourceFramesIntoRenderFrames() async throws {
    let cacheDirectory = FileManager.default.temporaryDirectory
        .appending(path: "AuraPlayGaplessSampleRateBoundary-\(UUID().uuidString)", directoryHint: .isDirectory)
    let manager = try MediaCacheManager(cacheDirectory: cacheDirectory)
    let engineController = try AudioEngineController()
    let scheduler = GaplessScheduler(cacheManager: manager, engineController: engineController)
    let currentURL = try makeEncodedFixtureAudioFile(
        name: "gapless-44100-current",
        extension: "m4a",
        formatID: kAudioFormatMPEG4AAC,
        frameCount: 44_100
    )
    let currentFile = try AVAudioFile(forReading: currentURL)
    let startingFrame: AVAudioFramePositionValue = 4_410
    let remainingSourceFrames = currentFile.length - startingFrame
    let expectedRenderBoundary = AVAudioFramePositionValue(
        (Double(remainingSourceFrames) * 48_000 / currentFile.fileFormat.sampleRate).rounded(.toNearestOrAwayFromZero)
    )
    let next = FixtureMedia(
        id: "gapless-sample-rate-next",
        sourceURL: try makeFixtureWAV(name: "gapless-sample-rate-next"),
        declaredFormat: "wav",
        contentKind: .music,
        cachedFileState: .notCached,
        approxLoudnessLUFS: nil
    )

    try await scheduler.scheduleCurrent(fileURL: currentURL, startingFrame: startingFrame)
    _ = try await manager.localFile(for: next)
    let quality = try await scheduler.prepareNext(next)

    #expect(quality == .gapless)
    #expect(engineController.debugPlannedGaplessBoundaryFrame() == expectedRenderBoundary)
    #expect(expectedRenderBoundary != remainingSourceFrames)
}

@Test("Gapless boundary uses scheduled stream metadata without reopening current file")
func gaplessBoundaryUsesScheduledStreamMetadata() async throws {
    let cacheDirectory = FileManager.default.temporaryDirectory
        .appending(path: "AuraPlayGaplessMetadata-\(UUID().uuidString)", directoryHint: .isDirectory)
    let manager = try MediaCacheManager(cacheDirectory: cacheDirectory)
    let engineController = try AudioEngineController()
    let scheduler = GaplessScheduler(cacheManager: manager, engineController: engineController)
    let currentURL = try makeFixtureWAV(name: "gapless-metadata-current")
    let currentLength = try AVAudioFile(forReading: currentURL).length
    let startingFrame: AVAudioFramePositionValue = 960
    let next = FixtureMedia(
        id: "gapless-metadata-next",
        sourceURL: try makeFixtureWAV(name: "gapless-metadata-next"),
        declaredFormat: "wav",
        contentKind: .music,
        cachedFileState: .notCached,
        approxLoudnessLUFS: nil
    )

    try await scheduler.scheduleCurrent(fileURL: currentURL, startingFrame: startingFrame)
    try FileManager.default.removeItem(at: currentURL)
    _ = try await manager.localFile(for: next)
    let quality = try await scheduler.prepareNext(next)

    #expect(quality == .gapless)
    #expect(engineController.debugPlannedGaplessBoundaryFrame() == currentLength - startingFrame)
}

@Test("Long-track scheduling keeps read-ahead bounded")
func longTrackSchedulingKeepsReadAheadBounded() async throws {
    let controller = try AudioEngineController()
    let fileURL = try makeLongFixtureWAV(name: "bounded-read-ahead", frameCount: AudioEngineController.scheduledChunkFrameCount * 12)

    try await controller.scheduleCurrent(fileURL: fileURL)

    #expect(controller.debugMaxObservedReadAheadBufferCount() <= AudioEngineController.maxReadAheadBufferCount)
    #expect(controller.debugMaxObservedReadAheadBufferCount() > 1)
}

@Test("Native factory recognizes all Phase 6 native formats by declared format", arguments: ["mp3", "m4a", "caf", "wav", "aif", "aiff", "flac"])
func nativeFactoryRecognizesDeclaredFormats(format: String) throws {
    let wavURL = try makeFixtureWAV(name: "native-\(format)")
    let extensionlessURL = FileManager.default.temporaryDirectory
        .appending(path: "native-\(format)-\(UUID().uuidString)")
    try FileManager.default.copyItem(at: wavURL, to: extensionlessURL)

    let factory = AudioTrackSourceFactory()
    let source = try factory.makeSource(for: extensionlessURL, declaredFormat: format)

    #expect(source is NativeAudioTrackSource)
    #expect(source.frameLength > 0)
}

@Test("Corrupted MP3 maps to corrupted-file error")
func corruptedMP3ThrowsCorruptedFile() throws {
    let url = FileManager.default.temporaryDirectory
        .appending(path: "corrupt-\(UUID().uuidString)")
        .appendingPathExtension("mp3")
    try Data("not audio".utf8).write(to: url)

    #expect(throws: AuraPlayError.corruptedFile(url)) {
        _ = try AudioTrackSourceFactory().makeSource(for: url)
    }
}

@Test("Cache rejects offline uncached media")
func cacheRejectsOfflineUncachedMedia() async throws {
    let cacheDirectory = FileManager.default.temporaryDirectory
        .appending(path: "AuraPlayOffline-\(UUID().uuidString)", directoryHint: .isDirectory)
    let manager = try MediaCacheManager(
        cacheDirectory: cacheDirectory,
        downloader: FixtureDownloader(fileURL: try makeFixtureWAV(name: "offline")),
        networkStatusProvider: FixedMediaNetworkStatusProvider(isOffline: true)
    )
    let media = FixtureMedia(
        id: "offline-item",
        sourceURL: try #require(URL(string: "https://example.com/audio.wav")),
        declaredFormat: "wav",
        contentKind: .music,
        cachedFileState: .notCached,
        approxLoudnessLUFS: nil
    )

    await #expect(throws: AuraPlayError.mediaUnavailableOffline) {
        _ = try await manager.localFile(for: media)
    }
}

@Test("Cache rejects non-audio HTTP content type")
func cacheRejectsUnexpectedHTTPContentType() async throws {
    let cacheDirectory = FileManager.default.temporaryDirectory
        .appending(path: "AuraPlayBadMime-\(UUID().uuidString)", directoryHint: .isDirectory)
    let manager = try MediaCacheManager(
        cacheDirectory: cacheDirectory,
        downloader: FixtureDownloader(
            fileURL: try makeFixtureWAV(name: "bad-mime"),
            mimeType: "text/plain"
        )
    )
    let media = FixtureMedia(
        id: "bad-mime-item",
        sourceURL: try #require(URL(string: "https://example.com/audio.wav")),
        declaredFormat: "wav",
        contentKind: .music,
        cachedFileState: .notCached,
        approxLoudnessLUFS: nil
    )

    await #expect(throws: AuraPlayError.downloadFailed("Unexpected content type text/plain for https://example.com/audio.wav")) {
        _ = try await manager.localFile(for: media)
    }
}

@Test("Cache rejects complete downloads shorter than the declared byte length")
func cacheRejectsTruncatedCompleteDownload() async throws {
    let sourceURL = try makeFixtureWAV(name: "truncated-source")
    let declaredByteCount = fileSize(sourceURL) + 1_024
    let cacheDirectory = FileManager.default.temporaryDirectory
        .appending(path: "AuraPlayTruncated-\(UUID().uuidString)", directoryHint: .isDirectory)
    let manager = try MediaCacheManager(
        cacheDirectory: cacheDirectory,
        downloader: FixtureDownloader(
            fileURL: sourceURL,
            contentLengthOverride: declaredByteCount
        )
    )
    let media = FixtureMedia(
        id: "truncated-item",
        sourceURL: try #require(URL(string: "https://example.com/truncated.wav")),
        declaredFormat: "wav",
        contentKind: .music,
        cachedFileState: .notCached,
        approxLoudnessLUFS: nil
    )

    await #expect(throws: AuraPlayError.downloadFailed("Downloaded media length \(fileSize(sourceURL)) did not match expected length \(declaredByteCount) for https://example.com/truncated.wav")) {
        _ = try await manager.localFile(for: media)
    }
    #expect(await manager.isCached(media) == false)
}

@Test("Cache rejects corrupt local files before recording them as cached")
func cacheRejectsCorruptLocalFileBeforeRecordingCacheHit() async throws {
    let sourceURL = FileManager.default.temporaryDirectory
        .appending(path: "corrupt-local-\(UUID().uuidString)")
        .appendingPathExtension("wav")
    try Data("not audio".utf8).write(to: sourceURL)
    let cacheDirectory = FileManager.default.temporaryDirectory
        .appending(path: "AuraPlayCorruptLocal-\(UUID().uuidString)", directoryHint: .isDirectory)
    let manager = try MediaCacheManager(cacheDirectory: cacheDirectory)
    let media = FixtureMedia(
        id: "corrupt-local-item",
        sourceURL: sourceURL,
        declaredFormat: "wav",
        contentKind: .music,
        cachedFileState: .notCached,
        approxLoudnessLUFS: nil
    )

    let expectedCacheURL = cacheDirectory.appending(path: "\(CacheKey(mediaID: "corrupt-local-item").rawValue).wav")

    await #expect(throws: AuraPlayError.corruptedFile(expectedCacheURL)) {
        _ = try await manager.localFile(for: media)
    }
    #expect(await manager.isCached(media) == false)
}

@Test("Cache rejects corrupt complete remote downloads before recording them as cached")
func cacheRejectsCorruptRemoteCompleteDownloadBeforeRecordingCacheHit() async throws {
    let sourceURL = FileManager.default.temporaryDirectory
        .appending(path: "corrupt-remote-\(UUID().uuidString)")
        .appendingPathExtension("wav")
    try Data("not audio".utf8).write(to: sourceURL)
    let cacheDirectory = FileManager.default.temporaryDirectory
        .appending(path: "AuraPlayCorruptRemote-\(UUID().uuidString)", directoryHint: .isDirectory)
    let manager = try MediaCacheManager(
        cacheDirectory: cacheDirectory,
        downloader: DirectFixtureDownloader(fileURL: sourceURL)
    )
    let media = FixtureMedia(
        id: "corrupt-remote-item",
        sourceURL: try #require(URL(string: "https://example.com/corrupt.wav")),
        declaredFormat: "wav",
        contentKind: .music,
        cachedFileState: .notCached,
        approxLoudnessLUFS: nil
    )

    await #expect(throws: AuraPlayError.corruptedFile(sourceURL)) {
        _ = try await manager.localFile(for: media)
    }
    #expect(await manager.isCached(media) == false)
}

@Test("Cache invalidates same-ID entries when the media source changes")
func cacheInvalidatesSameIDWhenSourceChanges() async throws {
    let firstSource = try makeFixtureAudioFile(name: "same-id-first", extension: "wav", frameCount: 2_400)
    let secondSource = try makeFixtureAudioFile(name: "same-id-second", extension: "wav", frameCount: 9_600)
    let cacheDirectory = FileManager.default.temporaryDirectory
        .appending(path: "AuraPlaySameIDInvalidation-\(UUID().uuidString)", directoryHint: .isDirectory)
    let manager = try MediaCacheManager(cacheDirectory: cacheDirectory)
    let first = FixtureMedia(
        id: "same-id-item",
        sourceURL: firstSource,
        declaredFormat: "wav",
        contentKind: .music,
        cachedFileState: .notCached,
        approxLoudnessLUFS: nil
    )
    let second = FixtureMedia(
        id: "same-id-item",
        sourceURL: secondSource,
        declaredFormat: "wav",
        contentKind: .music,
        cachedFileState: .notCached,
        approxLoudnessLUFS: nil
    )

    let firstCachedURL = try await manager.localFile(for: first)
    #expect(fileSize(firstCachedURL) == fileSize(firstSource))
    #expect(await manager.isCached(first))
    #expect(await manager.isCached(second) == false)

    let secondCachedURL = try await manager.localFile(for: second)

    #expect(secondCachedURL == firstCachedURL)
    #expect(fileSize(secondCachedURL) == fileSize(secondSource))
    #expect(await manager.isCached(first) == false)
    #expect(await manager.isCached(second))
}

@Test("localFileWhenPlayable can return before progressive completion")
func localFileWhenPlayableReturnsBeforeProgressiveCompletion() async throws {
    let cacheDirectory = FileManager.default.temporaryDirectory
        .appending(path: "AuraPlayProgressive-\(UUID().uuidString)", directoryHint: .isDirectory)
    let playablePrefix = try Data(contentsOf: makeFixtureWAV(name: "progressive-prefix"))
    let completionProbe = ProgressiveCompletionProbe()
    let downloader = ProgressiveFixtureDownloader(
        firstChunk: playablePrefix,
        tailChunk: Data(),
        tailDelayNanoseconds: 300_000_000,
        completionProbe: completionProbe
    )
    let manager = try MediaCacheManager(cacheDirectory: cacheDirectory, downloader: downloader)
    let media = FixtureMedia(
        id: "progressive-item",
        sourceURL: try #require(URL(string: "https://example.com/audio.wav")),
        declaredFormat: "wav",
        contentKind: .music,
        cachedFileState: .notCached,
        approxLoudnessLUFS: nil
    )

    let url = try await manager.localFileWhenPlayable(for: media, minimumPlayableBytes: 16)

    #expect(FileManager.default.fileExists(atPath: url.path))
    #expect(await completionProbe.isCompleted == false)
    #expect(await manager.isCached(media) == false)

    let cached = try await waitUntilCached(manager, media: media, timeoutNanoseconds: 2_000_000_000)
    #expect(cached == true)
    #expect(await completionProbe.isCompleted)
}

@Test("localFileWhenPlayable waits until a partial file is actually decodable")
func localFileWhenPlayableWaitsUntilPartialFileIsDecodable() async throws {
    let cacheDirectory = FileManager.default.temporaryDirectory
        .appending(path: "AuraPlayProgressiveDecodable-\(UUID().uuidString)", directoryHint: .isDirectory)
    let playableFile = try Data(contentsOf: makeFixtureWAV(name: "progressive-decodable"))
    let prefix = playableFile.prefix(32)
    let tail = playableFile.dropFirst(32)
    let completionProbe = ProgressiveCompletionProbe()
    let downloader = ProgressiveFixtureDownloader(
        firstChunk: Data(prefix),
        tailChunk: Data(tail),
        tailDelayNanoseconds: 80_000_000,
        completionProbe: completionProbe
    )
    let manager = try MediaCacheManager(cacheDirectory: cacheDirectory, downloader: downloader)
    let media = FixtureMedia(
        id: "progressive-decodable-item",
        sourceURL: try #require(URL(string: "https://example.com/audio.wav")),
        declaredFormat: "wav",
        contentKind: .music,
        cachedFileState: .notCached,
        approxLoudnessLUFS: nil
    )

    let url = try await manager.localFileWhenPlayable(for: media, minimumPlayableBytes: 16)

    #expect(FileManager.default.fileExists(atPath: url.path))
    #expect(await completionProbe.isCompleted)
    #expect(await manager.isCached(media))
}

@Test("Pinned progressive downloads survive eviction after completion")
func pinnedProgressiveDownloadSurvivesEvictionAfterCompletion() async throws {
    let pinnedSource = try makeFixtureWAV(name: "pinned-progressive")
    let triggerSource = try makeFixtureWAV(name: "pinned-progressive-trigger")
    let pinnedBytes = try Data(contentsOf: pinnedSource)
    let cacheDirectory = FileManager.default.temporaryDirectory
        .appending(path: "AuraPlayPinnedProgressive-\(UUID().uuidString)", directoryHint: .isDirectory)
    let downloader = ProgressiveFixtureDownloader(
        firstChunk: pinnedBytes,
        tailChunk: Data(),
        tailDelayNanoseconds: 80_000_000
    )
    let manager = try MediaCacheManager(
        cacheDirectory: cacheDirectory,
        diskCapBytes: fileSize(pinnedSource) + 1,
        downloader: downloader
    )
    let pinned = FixtureMedia(
        id: "pinned-progressive-item",
        sourceURL: try #require(URL(string: "https://example.com/pinned.wav")),
        declaredFormat: "wav",
        contentKind: .music,
        cachedFileState: .pinned,
        approxLoudnessLUFS: nil
    )
    let trigger = FixtureMedia(
        id: "pinned-progressive-trigger",
        sourceURL: triggerSource,
        declaredFormat: "wav",
        contentKind: .music,
        cachedFileState: .notCached,
        approxLoudnessLUFS: nil
    )

    let pinnedURL = try await manager.localFileWhenPlayable(for: pinned, minimumPlayableBytes: 16)
    let pinnedCached = try await waitUntilCached(manager, media: pinned, timeoutNanoseconds: 2_000_000_000)
    _ = try await manager.localFile(for: trigger)

    #expect(pinnedCached)
    #expect(FileManager.default.fileExists(atPath: pinnedURL.path))
    #expect(await manager.isCached(pinned))
    #expect(await manager.isCached(trigger) == false)
}

@Test("Pinning a playable partial waits for completion before marking it cached")
func pinningPlayablePartialWaitsForCompletionBeforeMarkingCached() async throws {
    let cacheDirectory = FileManager.default.temporaryDirectory
        .appending(path: "AuraPlayPinPartial-\(UUID().uuidString)", directoryHint: .isDirectory)
    let playablePrefix = try Data(contentsOf: makeFixtureWAV(name: "pin-partial-prefix"))
    let completionProbe = ProgressiveCompletionProbe()
    let downloader = ProgressiveFixtureDownloader(
        firstChunk: playablePrefix,
        tailChunk: Data(),
        tailDelayNanoseconds: 120_000_000,
        completionProbe: completionProbe
    )
    let manager = try MediaCacheManager(cacheDirectory: cacheDirectory, downloader: downloader)
    let media = FixtureMedia(
        id: "pin-partial-item",
        sourceURL: try #require(URL(string: "https://example.com/pin-partial.wav")),
        declaredFormat: "wav",
        contentKind: .music,
        cachedFileState: .notCached,
        approxLoudnessLUFS: nil
    )

    let partialURL = try await manager.localFileWhenPlayable(for: media, minimumPlayableBytes: 16)
    #expect(FileManager.default.fileExists(atPath: partialURL.path))
    #expect(await completionProbe.isCompleted == false)
    #expect(await manager.isCached(media) == false)

    try await manager.pin(media)

    #expect(await completionProbe.isCompleted)
    #expect(await manager.isCached(media))
}

@Test("Full-file requests wait for an in-flight progressive completion")
func localFileWaitsForInFlightProgressiveCompletion() async throws {
    let cacheDirectory = FileManager.default.temporaryDirectory
        .appending(path: "AuraPlayProgressiveCompletionReuse-\(UUID().uuidString)", directoryHint: .isDirectory)
    let playablePrefix = try Data(contentsOf: makeFixtureWAV(name: "progressive-completion-prefix"))
    let completionProbe = ProgressiveCompletionProbe()
    let downloader = CountedProgressiveFixtureDownloader(
        firstChunk: playablePrefix,
        tailChunk: Data(repeating: 0, count: 24),
        startDelayNanoseconds: 10_000_000,
        tailDelayNanoseconds: 120_000_000,
        completionProbe: completionProbe
    )
    let manager = try MediaCacheManager(cacheDirectory: cacheDirectory, downloader: downloader)
    let media = FixtureMedia(
        id: "progressive-completion-item",
        sourceURL: try #require(URL(string: "https://example.com/audio.wav")),
        declaredFormat: "wav",
        contentKind: .music,
        cachedFileState: .notCached,
        approxLoudnessLUFS: nil
    )

    let playableURL = try await manager.localFileWhenPlayable(for: media, minimumPlayableBytes: 16)
    #expect(await completionProbe.isCompleted == false)

    let finalURL = try await manager.localFile(for: media)

    #expect(finalURL == playableURL)
    #expect(await completionProbe.isCompleted)
    #expect(await downloader.playableDownloadCount == 1)
    #expect(await manager.isCached(media))
}

@Test("Concurrent progressive playable requests share one download")
func concurrentProgressivePlayableRequestsShareOneDownload() async throws {
    let cacheDirectory = FileManager.default.temporaryDirectory
        .appending(path: "AuraPlayProgressiveDedupe-\(UUID().uuidString)", directoryHint: .isDirectory)
    let playablePrefix = try Data(contentsOf: makeFixtureWAV(name: "progressive-dedupe-prefix"))
    let downloader = CountedProgressiveFixtureDownloader(
        firstChunk: playablePrefix,
        tailChunk: Data(),
        startDelayNanoseconds: 80_000_000,
        tailDelayNanoseconds: 500_000_000
    )
    let manager = try MediaCacheManager(cacheDirectory: cacheDirectory, downloader: downloader)
    let media = FixtureMedia(
        id: "progressive-dedupe-item",
        sourceURL: try #require(URL(string: "https://example.com/audio.wav")),
        declaredFormat: "wav",
        contentKind: .music,
        cachedFileState: .notCached,
        approxLoudnessLUFS: nil
    )

    let urls = try await withThrowingTaskGroup(of: URL.self) { group in
        for _ in 0..<4 {
            group.addTask {
                try await manager.localFileWhenPlayable(for: media, minimumPlayableBytes: 16)
            }
        }

        var values: [URL] = []
        for try await url in group {
            values.append(url)
        }
        return values
    }
    let reusedPartialURL = try await manager.localFileWhenPlayable(for: media, minimumPlayableBytes: 16)

    #expect(Set(urls).count == 1)
    #expect(reusedPartialURL == urls.first)
    #expect(await downloader.playableDownloadCount == 1)
    #expect(await manager.isCached(media) == false)

    let cached = try await waitUntilCached(manager, media: media, timeoutNanoseconds: 2_000_000_000)
    #expect(cached == true)
}

@Test("localFileWhenPlayable rejects undecodable partial files")
func localFileWhenPlayableRejectsUndecodablePartialFile() async throws {
    let cacheDirectory = FileManager.default.temporaryDirectory
        .appending(path: "AuraPlayInvalidProgressive-\(UUID().uuidString)", directoryHint: .isDirectory)
    let downloader = ProgressiveFixtureDownloader(
        firstChunk: Data(repeating: 1, count: 512),
        tailChunk: Data(),
        tailDelayNanoseconds: 80_000_000
    )
    let manager = try MediaCacheManager(cacheDirectory: cacheDirectory, downloader: downloader)
    let media = FixtureMedia(
        id: "invalid-progressive-item",
        sourceURL: try #require(URL(string: "https://example.com/audio.wav")),
        declaredFormat: "wav",
        contentKind: .music,
        cachedFileState: .notCached,
        approxLoudnessLUFS: nil
    )

    let expectedCacheURL = cacheDirectory.appending(path: "\(CacheKey(mediaID: "invalid-progressive-item").rawValue).wav")

    await #expect(throws: AuraPlayError.corruptedFile(expectedCacheURL)) {
        _ = try await manager.localFileWhenPlayable(for: media, minimumPlayableBytes: 512)
    }
    #expect(await manager.isCached(media) == false)
}

@Test("Cached next track arms automatic gapless transition")
func cachedNextTrackArmsGaplessTransition() async throws {
    let cacheDirectory = FileManager.default.temporaryDirectory
        .appending(path: "AuraPlayGaplessArm-\(UUID().uuidString)", directoryHint: .isDirectory)
    let manager = try MediaCacheManager(cacheDirectory: cacheDirectory)
    let engineController = try AudioEngineController()
    let scheduler = GaplessScheduler(cacheManager: manager, engineController: engineController)
    let media = FixtureMedia(
        id: "gapless-next",
        sourceURL: try makeFixtureWAV(name: "gapless-next"),
        declaredFormat: "wav",
        contentKind: .music,
        cachedFileState: .notCached,
        approxLoudnessLUFS: nil
    )

    _ = try await manager.localFile(for: media)
    let quality = try await scheduler.prepareNext(media)

    #expect(quality == .gapless)
    #expect(engineController.debugIsGaplessTransitionArmed())
}

@Test("Generated native containers open through AVAudioFile", arguments: ["wav", "aif", "aiff", "caf"])
func generatedNativeContainersOpen(container: String) throws {
    let url = try makeFixtureAudioFile(name: "native-container-\(container)", extension: container)
    let source = try AudioTrackSourceFactory().makeSource(for: url)

    #expect(source is NativeAudioTrackSource)
    #expect(source.frameLength > 0)
}

@Test("localFileWhenPlayable follows the cache validation path")
func localFileWhenPlayableReturnsValidatedLocalFile() async throws {
    let cacheDirectory = FileManager.default.temporaryDirectory
        .appending(path: "AuraPlayPlayable-\(UUID().uuidString)", directoryHint: .isDirectory)
    let manager = try MediaCacheManager(
        cacheDirectory: cacheDirectory,
        downloader: FixtureDownloader(fileURL: try makeFixtureWAV(name: "playable"))
    )
    let media = FixtureMedia(
        id: "playable-item",
        sourceURL: try #require(URL(string: "https://example.com/audio.wav")),
        declaredFormat: "wav",
        contentKind: .music,
        cachedFileState: .notCached,
        approxLoudnessLUFS: nil
    )

    let url = try await manager.localFileWhenPlayable(for: media, minimumPlayableBytes: 1)

    #expect(url.isFileURL)
    #expect(await manager.isCached(media))
}

@Test("Dynamics processor receives spoken-word and normalization parameters")
func dynamicsProcessorReceivesParameters() async throws {
    let controller = try AudioEngineController()

    await controller.configureForContentKind(.spokenWord)
    await controller.applyNormalizationGain(approxLoudnessLUFS: -20)

    #expect(controller.debugDynamicsParameterValue(kDynamicsProcessorParam_Threshold) == -18)
    #expect(controller.debugDynamicsParameterValue(kDynamicsProcessorParam_OverallGain) == 6)
}

@Test("Crossfade plan clamps duration and computes frame offset")
func crossfadePlanClampsDuration() throws {
    let engineController = try AudioEngineController()
    let cacheManager = try MediaCacheManager(cacheDirectory: FileManager.default.temporaryDirectory.appending(path: "AuraPlayCrossfade-\(UUID().uuidString)"))
    let scheduler = GaplessScheduler(cacheManager: cacheManager, engineController: engineController)
    let controller = AutoMixController(scheduler: scheduler, engineController: engineController)

    let plan = controller.crossfadePlan(duration: 12, sampleRate: 48_000)

    #expect(plan.duration == 8)
    #expect(plan.startsAtFrameBeforeEnd == 384_000)
}

@Test("Now Playing snapshot includes artwork and video media type")
func nowPlayingSnapshotIncludesArtworkAndMediaType() async {
    let publisher = NowPlayingPublisher(elapsedTickInterval: 0.01, publishesToSystem: false)
    await publisher.update(NowPlayingState(
        title: "Track",
        artist: "Artist",
        artworkData: Data([0, 1, 2]),
        duration: 10,
        elapsedTime: 2,
        playbackRate: 1,
        mediaType: .video
    ))

    #expect(publisher.lastSnapshot?.title == "Track")
    #expect(publisher.lastSnapshot?.hasArtwork == true)
    #expect(publisher.lastSnapshot?.mediaType == .video)
}

#if canImport(MediaPlayer)
@MainActor
@Test("MediaPlayer system publishers write global playback state")
func mediaPlayerSystemPublishersWriteGlobalPlaybackState() async {
    let nowPlayingPublisher = NowPlayingPublisher(elapsedTickInterval: 0.01)
    MPNowPlayingInfoCenter.default().nowPlayingInfo = [MPMediaItemPropertyTitle: "Probe"]
    let hostEchoesNowPlayingInfo = MPNowPlayingInfoCenter.default().nowPlayingInfo?[MPMediaItemPropertyTitle] as? String == "Probe"
    MPNowPlayingInfoCenter.default().nowPlayingInfo = nil

    await nowPlayingPublisher.update(NowPlayingState(
        title: "System Track",
        artist: "System Artist",
        duration: 42,
        elapsedTime: 7,
        playbackRate: 1,
        mediaType: .audio
    ))

    if hostEchoesNowPlayingInfo {
        let info = MPNowPlayingInfoCenter.default().nowPlayingInfo
        #expect(info?[MPMediaItemPropertyTitle] as? String == "System Track")
        #expect(info?[MPMediaItemPropertyArtist] as? String == "System Artist")
        #expect(info?[MPMediaItemPropertyPlaybackDuration] as? TimeInterval == 42)
        #expect(info?[MPNowPlayingInfoPropertyElapsedPlaybackTime] as? TimeInterval == 7)
    }
    #expect(nowPlayingPublisher.lastSnapshot?.title == "System Track")

    let remoteCommandPublisher = RemoteCommandPublisher(registerSystemCommands: true)
    _ = remoteCommandPublisher
    let commandCenter = MPRemoteCommandCenter.shared()
    #expect(commandCenter.skipForwardCommand.preferredIntervals == [15])
    #expect(commandCenter.skipBackwardCommand.preferredIntervals == [15])

    await nowPlayingPublisher.clear()
}
#endif

@Test("Remote command publishers keep independent event streams")
func remoteCommandPublishersKeepIndependentEventStreams() async {
    let first = RemoteCommandPublisher(registerSystemCommands: false)
    let second = RemoteCommandPublisher(registerSystemCommands: false)
    var firstEvents = first.events.makeAsyncIterator()
    var secondEvents = second.events.makeAsyncIterator()

    first.simulate(.play)
    second.simulate(.skipForward(30))

    #expect(await firstEvents.next() == .play)
    #expect(await secondEvents.next() == .skipForward(30))
}

@Test("Remote command publisher multicasts events to multiple subscribers")
func remoteCommandPublisherMulticastsEventsToMultipleSubscribers() async {
    let publisher = RemoteCommandPublisher(registerSystemCommands: false)
    var firstEvents = publisher.events.makeAsyncIterator()
    var secondEvents = publisher.events.makeAsyncIterator()

    publisher.simulate(.play)

    #expect(await firstEvents.next() == .play)
    #expect(await secondEvents.next() == .play)
}

@Test("Now Playing elapsed tick advances snapshot")
func nowPlayingElapsedTickAdvancesSnapshot() async throws {
    let publisher = NowPlayingPublisher(elapsedTickInterval: 0.01, publishesToSystem: false)
    let startedAt = Date(timeIntervalSince1970: 10)
    let now = Date(timeIntervalSince1970: 10.5)

    await publisher.publishElapsedTick(
        from: NowPlayingState(title: "Timer", elapsedTime: 1, playbackRate: 1),
        startedAt: startedAt,
        now: now
    )

    #expect(publisher.lastSnapshot?.elapsedTime == 1.5)
}

@Test("Now Playing elapsed updates do not retain publisher")
func nowPlayingElapsedUpdatesDoNotRetainPublisher() async throws {
    weak var releasedPublisher: NowPlayingPublisher?
    var publisher: NowPlayingPublisher? = NowPlayingPublisher(elapsedTickInterval: 60, publishesToSystem: false)
    releasedPublisher = publisher

    publisher?.startElapsedTimeUpdates(from: NowPlayingState(title: "Timer", elapsedTime: 1, playbackRate: 1))
    try await Task.sleep(nanoseconds: 10_000_000)
    publisher = nil

    #expect(releasedPublisher == nil)
}

@Test("Now Playing publisher tolerates concurrent updates")
func nowPlayingPublisherToleratesConcurrentUpdates() async {
    let publisher = NowPlayingPublisher(elapsedTickInterval: 0.01, publishesToSystem: false)

    await withTaskGroup(of: Void.self) { group in
        for index in 0..<25 {
            group.addTask {
                await publisher.update(NowPlayingState(title: "Track \(index)", elapsedTime: TimeInterval(index)))
            }
        }
    }

    await publisher.update(NowPlayingState(title: "Final", elapsedTime: 99))

    #expect(publisher.lastSnapshot?.title == "Final")
    #expect(publisher.lastSnapshot?.elapsedTime == 99)
}

@MainActor
@Test("AirPlay optimized queue starts at requested item and publishes Now Playing")
func airPlayOptimizedQueueStartsAtRequestedItemAndPublishesNowPlaying() async throws {
    let firstURL = try makeFixtureWAV(name: "airplay-first")
    let secondURL = try makeFixtureWAV(name: "airplay-second")
    let nowPlayingPublisher = NowPlayingPublisher(elapsedTickInterval: 0.01, publishesToSystem: false)
    let controller = AirPlayQueuePlayerController(nowPlayingPublisher: nowPlayingPublisher)
    let items = [
        AirPlayQueuePlayerItem(id: "first", url: firstURL, title: "First", artist: "Aura", duration: 1),
        AirPlayQueuePlayerItem(id: "second", url: secondURL, title: "Second", artist: "Aura", duration: 2)
    ]

    await controller.loadQueue(items, startAtID: "second")

    #expect(controller.state.routeMode == .systemAirPlay)
    #expect(controller.state.queuedItemIDs == ["second"])
    #expect(controller.state.currentItemID == "second")
    #expect(nowPlayingPublisher.lastSnapshot?.title == "Second")
    #expect(nowPlayingPublisher.lastSnapshot?.artist == "Aura")
    #expect(nowPlayingPublisher.lastSnapshot?.duration == 2)
}

@MainActor
@Test("AirPlay optimized queue handles remote next commands")
func airPlayOptimizedQueueHandlesRemoteNextCommands() async throws {
    let firstURL = try makeFixtureWAV(name: "airplay-remote-first")
    let secondURL = try makeFixtureWAV(name: "airplay-remote-second")
    let remoteCommands = RemoteCommandPublisher(registerSystemCommands: false)
    let controller = AirPlayQueuePlayerController()
    let items = [
        AirPlayQueuePlayerItem(id: "first", url: firstURL, title: "First"),
        AirPlayQueuePlayerItem(id: "second", url: secondURL, title: "Second")
    ]

    await controller.loadQueue(items, startAtID: nil)
    controller.bindRemoteCommands(remoteCommands)
    remoteCommands.simulate(.next)
    for _ in 0..<20 where controller.state.currentItemID != "second" {
        try await Task.sleep(nanoseconds: 10_000_000)
    }

    #expect(controller.state.queuedItemIDs == ["second"])
    #expect(controller.state.currentItemID == "second")
}

@MainActor
@Test("AirPlay optimized queue trims naturally ended items and republishes Now Playing")
func airPlayOptimizedQueueTrimsNaturallyEndedItemsAndRepublishesNowPlaying() async throws {
    let firstURL = try makeFixtureWAV(name: "airplay-ended-first")
    let secondURL = try makeFixtureWAV(name: "airplay-ended-second")
    let player = AVQueuePlayer()
    let notificationCenter = NotificationCenter()
    let nowPlayingPublisher = NowPlayingPublisher(elapsedTickInterval: 0.01, publishesToSystem: false)
    let controller = AirPlayQueuePlayerController(
        player: player,
        nowPlayingPublisher: nowPlayingPublisher,
        notificationCenter: notificationCenter
    )
    let items = [
        AirPlayQueuePlayerItem(id: "first", url: firstURL, title: "First"),
        AirPlayQueuePlayerItem(id: "second", url: secondURL, title: "Second")
    ]

    await controller.loadQueue(items, startAtID: nil)
    let endedItem = try #require(player.currentItem)
    player.advanceToNextItem()
    notificationCenter.post(name: .AVPlayerItemDidPlayToEndTime, object: endedItem)
    for _ in 0..<20 where controller.state.queuedItemIDs != ["second"] {
        try await Task.sleep(nanoseconds: 10_000_000)
    }

    #expect(controller.state.queuedItemIDs == ["second"])
    #expect(controller.state.currentItemID == "second")
    #expect(nowPlayingPublisher.lastSnapshot?.title == "Second")
}

@MainActor
@Test("AirPlay optimized queue applies spatial audio policy to player items")
func airPlayOptimizedQueueAppliesSpatialAudioPolicyToPlayerItems() async throws {
    let url = try makeFixtureWAV(name: "airplay-spatial-policy")
    let controller = AirPlayQueuePlayerController(spatialAudioPolicy: .multichannel)
    let items = [AirPlayQueuePlayerItem(id: "spatial", url: url, title: "Spatial")]

    await controller.loadQueue(items, startAtID: nil)

    #expect(controller.state.spatialAudioPolicy == .multichannel)
    #expect(controller.debugAllowedSpatializationFormats(for: "spatial") == AVAudioSpatializationFormats.multichannel)

    controller.updateSpatialAudioPolicy(.none)

    #expect(controller.state.spatialAudioPolicy == .none)
    #expect(controller.debugAllowedSpatializationFormats(for: "spatial") == AVAudioSpatializationFormats(rawValue: 0))
}

@Test("Audio session mock records multichannel support intent and spatial capability events")
func audioSessionMockRecordsMultichannelSupportIntentAndSpatialCapabilityEvents() async throws {
    let session = MockAudioSessionManager()
    var events = session.events.makeAsyncIterator()

    try await session.setSupportsMultichannelContent(true)
    await session.setSpatialAudioEnabled(true)
    await session.send(.spatialAudioEnabledChanged(await session.currentSpatialAudioEnabled()))

    #expect(await session.supportsMultichannelContentValues == [true])
    #expect(await events.next() == .spatialAudioEnabledChanged(true))
}

@Test("Generated AAC M4A fixture opens as native decoded audio")
func generatedAACM4AFixtureOpensAsNativeAudio() throws {
    let url = try makeEncodedFixtureAudioFile(
        name: "native-aac-m4a",
        extension: "m4a",
        formatID: kAudioFormatMPEG4AAC
    )
    let source = try AudioTrackSourceFactory().makeSource(for: url)

    #expect(source is NativeAudioTrackSource)
    #expect(source.frameLength > 0)
}

@Test("Generated ALAC fixture opens as native decoded audio")
func generatedALACFixtureOpensAsNativeAudio() throws {
    let url = try makeEncodedFixtureAudioFile(
        name: "native-alac",
        extension: "m4a",
        formatID: kAudioFormatAppleLossless
    )
    let source = try AudioTrackSourceFactory().makeSource(for: url)

    #expect(source is NativeAudioTrackSource)
    #expect(source.frameLength > 0)
}

@Test("Embedded MP3 fixture opens as native decoded audio")
func embeddedMP3FixtureOpensAsNativeAudio() throws {
    let url = try makeEmbeddedBase64Fixture(resourceName: "native.mp3", extension: "mp3")
    let source = try AudioTrackSourceFactory().makeSource(for: url)

    #expect(source is NativeAudioTrackSource)
    #expect(source.frameLength > 0)
}

@Test("Embedded FLAC fixture opens as native decoded audio")
func embeddedFLACFixtureOpensAsNativeAudio() throws {
    let url = try makeEmbeddedFLACFixture()
    let source = try AudioTrackSourceFactory().makeSource(for: url)

    #expect(source is NativeAudioTrackSource)
    #expect(source.frameLength > 0)
}

@Test("Cache resumes a persisted ranged partial file")
func cacheResumesPersistedPartialFile() async throws {
    let cacheDirectory = FileManager.default.temporaryDirectory
        .appending(path: "AuraPlayResume-\(UUID().uuidString)", directoryHint: .isDirectory)
    let resumablePrefix = try Data(contentsOf: makeFixtureWAV(name: "resume-prefix"))
    let resumableTail = Data(repeating: 3, count: 24)
    let progressiveDownloader = ProgressiveFixtureDownloader(
        firstChunk: resumablePrefix,
        tailChunk: Data(),
        tailDelayNanoseconds: 1_000_000_000
    )
    let media = FixtureMedia(
        id: "resume-item",
        sourceURL: try #require(URL(string: "https://example.com/audio.wav")),
        declaredFormat: "wav",
        contentKind: .music,
        cachedFileState: .notCached,
        approxLoudnessLUFS: nil
    )

    let firstManager = try MediaCacheManager(cacheDirectory: cacheDirectory, downloader: progressiveDownloader)
    let partialURL = try await firstManager.localFileWhenPlayable(for: media, minimumPlayableBytes: 1)
    #expect(fileSize(partialURL) == Int64(resumablePrefix.count))

    let resumableDownloader = ResumableFixtureDownloader(tailChunk: resumableTail)
    let resumedManager = try MediaCacheManager(cacheDirectory: cacheDirectory, downloader: resumableDownloader)
    let completedURL = try await resumedManager.localFile(for: media)

    #expect(completedURL == partialURL)
    #expect(fileSize(completedURL) == Int64(resumablePrefix.count + resumableTail.count))
    #expect(await resumedManager.isCached(media))
    #expect(await resumableDownloader.startingOffsets == [Int64(resumablePrefix.count)])
}

@Test("Resumable downloader appends temporary file contents in bounded chunks")
func resumableDownloaderAppendsTemporaryFileContentsInBoundedChunks() throws {
    let destination = FileManager.default.temporaryDirectory
        .appending(path: "resume-destination-\(UUID().uuidString)")
    let source = FileManager.default.temporaryDirectory
        .appending(path: "resume-source-\(UUID().uuidString)")
    let prefix = Data([0, 1, 2, 3, 4])
    let tail = Data((0..<97).map { UInt8($0 % 31) })

    try prefix.write(to: destination)
    try tail.write(to: source)
    try URLSessionMediaDownloader.appendFileContents(from: source, to: destination, bufferSize: 7)

    #expect(try Data(contentsOf: destination) == prefix + tail)
}

@Test("Interruption end from session events restarts and publishes recovery")
func interruptionEndFromSessionEventsRestartsAndPublishesRecovery() async throws {
    let session = MockAudioSessionManager()
    let controller = try AudioEngineController()
    let coordinator = EngineRecoveryCoordinator(audioSessionManager: session, engineController: controller)
    var events = coordinator.events.makeAsyncIterator()

    coordinator.start()
    await session.send(.interruptionEnded(shouldResume: true))
    let event = await events.next()

    #expect(event == .interruptionRestored(shouldResume: true, resumeFrame: 0))
    coordinator.stop()
}

@Test("Pause session events publish recovery pause state")
func pauseSessionEventsPublishRecoveryPauseState() async throws {
    let session = MockAudioSessionManager()
    let controller = try AudioEngineController()
    let coordinator = EngineRecoveryCoordinator(audioSessionManager: session, engineController: controller)
    var events = coordinator.events.makeAsyncIterator()

    coordinator.start()
    await session.send(.shouldPause)
    let routeEvent = await events.next()
    await session.send(.interruptionBegan)
    let interruptionEvent = await events.next()

    #expect(routeEvent == .paused(reason: .routeUnavailable))
    #expect(interruptionEvent == .paused(reason: .interruptionBegan))
    coordinator.stop()
}

@Test("Progressive underrun recovery pauses, reschedules, then publishes recovered at the same frame")
func progressiveUnderrunRecoveryReschedulesBeforePublishingRecovered() async throws {
    let session = MockAudioSessionManager()
    let controller = try AudioEngineController()
    let coordinator = EngineRecoveryCoordinator(audioSessionManager: session, engineController: controller)
    let progressPair = AsyncStream<CacheProgress>.makeStream()
    let rescheduledFrames = FrameRecorder()
    var events = coordinator.events.makeAsyncIterator()

    let recoveryTask = Task {
        await coordinator.recoverFromProgressiveUnderrun(
            mediaID: "stalling-track",
            frame: 12_345,
            currentBytesAvailable: 512,
            progress: progressPair.stream
        ) { frame in
            await rescheduledFrames.append(frame)
        }
    }

    let first = await events.next()
    #expect(first == .buffering(mediaID: "stalling-track", frame: 12_345))

    progressPair.continuation.yield(CacheProgress(mediaID: "stalling-track", bytesWritten: 1_024, expectedBytes: 2_048, state: .partial))
    let second = await events.next()
    #expect(await rescheduledFrames.values == [12_345])
    #expect(second == .recovered(mediaID: "stalling-track", frame: 12_345))

    progressPair.continuation.finish()
    await recoveryTask.value
}

@Test("Crossfade progress overlaps volumes and swaps roles at completion")
func crossfadeProgressOverlapsVolumesAndSwapsRoles() async throws {
    let engineController = try AudioEngineController()
    let cacheManager = try MediaCacheManager(cacheDirectory: FileManager.default.temporaryDirectory.appending(path: "AuraPlayCrossfadeProgress-\(UUID().uuidString)"))
    let scheduler = GaplessScheduler(cacheManager: cacheManager, engineController: engineController)
    let controller = AutoMixController(scheduler: scheduler, engineController: engineController)

    await controller.applyCrossfadeProgress(0.5)
    let midpoint = engineController.debugPlayerVolumes()
    #expect(abs(midpoint.active - 0.707) < 0.01)
    #expect(abs(midpoint.inactive - 0.707) < 0.01)

    await controller.applyCrossfadeProgress(1)
    let complete = engineController.debugPlayerVolumes()
    #expect(complete.active == 1)
    #expect(engineController.debugAutomaticTransitionCount() == 1)
}

@Test("Scheduled AutoMix ramps do not retain controller while waiting")
func scheduledAutoMixRampDoesNotRetainControllerWhileWaiting() async throws {
    let engineController = try AudioEngineController()
    let cacheManager = try MediaCacheManager(cacheDirectory: FileManager.default.temporaryDirectory.appending(path: "AuraPlayCrossfadeRetention-\(UUID().uuidString)"))
    let scheduler = GaplessScheduler(cacheManager: cacheManager, engineController: engineController)
    weak var releasedController: AutoMixController?
    var controller: AutoMixController? = AutoMixController(scheduler: scheduler, engineController: engineController)
    releasedController = controller

    controller?.scheduleCrossfadeBeforeTrackEnd(
        duration: 1,
        remainingFrames: 48_000 * 60,
        stepsPerSecond: 1
    )
    try await Task.sleep(nanoseconds: 10_000_000)
    controller = nil

    #expect(releasedController == nil)
}

@Test("AutoMix controller tolerates concurrent state updates")
func autoMixControllerToleratesConcurrentStateUpdates() async throws {
    let engineController = try AudioEngineController()
    let cacheManager = try MediaCacheManager(cacheDirectory: FileManager.default.temporaryDirectory.appending(path: "AuraPlayCrossfadeConcurrent-\(UUID().uuidString)"))
    let scheduler = GaplessScheduler(cacheManager: cacheManager, engineController: engineController)
    let controller = AutoMixController(scheduler: scheduler, engineController: engineController)

    await withTaskGroup(of: Void.self) { group in
        for index in 0..<25 {
            group.addTask {
                controller.updateNextTransitionDuration(TimeInterval(index % 12))
                await controller.applyCrossfadeProgress(Double(index) / 24)
            }
        }
    }

    await controller.applyCrossfadeProgress(0.25)
    let volumes = engineController.debugPlayerVolumes()
    #expect(volumes.active.isFinite)
    #expect(volumes.inactive.isFinite)
}

private actor FrameRecorder {
    private(set) var values: [AVAudioFramePositionValue] = []

    func append(_ value: AVAudioFramePositionValue) {
        values.append(value)
    }
}

private actor ResumableFixtureDownloader: ResumableMediaDownloading {
    let tailChunk: Data
    private(set) var startingOffsets: [Int64] = []

    init(tailChunk: Data) {
        self.tailChunk = tailChunk
    }

    func download(from url: URL, progress: (@Sendable (Int64, Int64?) -> Void)?) async throws -> (URL, URLResponse) {
        Issue.record("Full download should not be used when a resumable partial exists")
        throw AuraPlayError.downloadFailed("Unexpected full download")
    }

    func resumeDownload(
        from url: URL,
        to partialFileURL: URL,
        startingAt byteOffset: Int64,
        eTag: String?,
        progress: (@Sendable (Int64, Int64?) -> Void)?
    ) async throws -> (URL, URLResponse) {
        startingOffsets.append(byteOffset)
        let handle = try FileHandle(forWritingTo: partialFileURL)
        try handle.seekToEnd()
        try handle.write(contentsOf: tailChunk)
        try handle.close()
        let byteCount = byteOffset + Int64(tailChunk.count)
        progress?(byteCount, byteCount)
        return (partialFileURL, HTTPURLResponse(
            url: url,
            statusCode: 206,
            httpVersion: "HTTP/1.1",
            headerFields: [
                "Content-Type": "audio/wav",
                "Accept-Ranges": "bytes",
                "ETag": eTag ?? "fixture"
            ]
        )!)
    }
}

private actor CountedProgressiveFixtureDownloader: ProgressiveMediaDownloading {
    let firstChunk: Data
    let tailChunk: Data
    let startDelayNanoseconds: UInt64
    let tailDelayNanoseconds: UInt64
    let completionProbe: ProgressiveCompletionProbe?
    private(set) var playableDownloadCount = 0

    init(
        firstChunk: Data,
        tailChunk: Data,
        startDelayNanoseconds: UInt64,
        tailDelayNanoseconds: UInt64,
        completionProbe: ProgressiveCompletionProbe? = nil
    ) {
        self.firstChunk = firstChunk
        self.tailChunk = tailChunk
        self.startDelayNanoseconds = startDelayNanoseconds
        self.tailDelayNanoseconds = tailDelayNanoseconds
        self.completionProbe = completionProbe
    }

    func download(from url: URL, progress: (@Sendable (Int64, Int64?) -> Void)?) async throws -> (URL, URLResponse) {
        Issue.record("Full download should not be used for progressive playable requests")
        throw AuraPlayError.downloadFailed("Unexpected full download")
    }

    func downloadUntilPlayable(
        from url: URL,
        to destinationURL: URL,
        minimumPlayableBytes: Int64,
        progress: (@Sendable (Int64, Int64?) -> Void)?
    ) async throws -> ProgressiveMediaDownloadHandle {
        playableDownloadCount += 1
        try await Task.sleep(nanoseconds: startDelayNanoseconds)
        try? FileManager.default.removeItem(at: destinationURL)
        try firstChunk.write(to: destinationURL)
        progress?(Int64(firstChunk.count), Int64(firstChunk.count + tailChunk.count))
        let response = response(for: url)
        let completion = Task<URL, Error> {
            try await Task.sleep(nanoseconds: tailDelayNanoseconds)
            let handle = try FileHandle(forWritingTo: destinationURL)
            try handle.seekToEnd()
            try handle.write(contentsOf: tailChunk)
            try handle.close()
            progress?(Int64(firstChunk.count + tailChunk.count), Int64(firstChunk.count + tailChunk.count))
            await completionProbe?.markCompleted()
            return destinationURL
        }
        return ProgressiveMediaDownloadHandle(playableURL: destinationURL, response: response, completion: completion)
    }

    private func response(for url: URL) -> URLResponse {
        HTTPURLResponse(
            url: url,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: [
                "Content-Type": "audio/wav",
                "Content-Length": "\(firstChunk.count + tailChunk.count)",
                "Accept-Ranges": "bytes",
                "ETag": "counted-progressive-fixture"
            ]
        )!
    }
}

private actor ProgressiveCompletionProbe {
    private var completed = false

    var isCompleted: Bool {
        completed
    }

    func markCompleted() {
        completed = true
    }
}

private struct ProgressiveFixtureDownloader: ProgressiveMediaDownloading {
    let firstChunk: Data
    let tailChunk: Data
    let tailDelayNanoseconds: UInt64
    var completionProbe: ProgressiveCompletionProbe?

    func download(from url: URL, progress: (@Sendable (Int64, Int64?) -> Void)?) async throws -> (URL, URLResponse) {
        let destination = FileManager.default.temporaryDirectory
            .appending(path: "progressive-full-\(UUID().uuidString)")
            .appendingPathExtension("wav")
        try (firstChunk + tailChunk).write(to: destination)
        let byteCount = Int64(firstChunk.count + tailChunk.count)
        progress?(byteCount, byteCount)
        return (destination, response(for: url))
    }

    func downloadUntilPlayable(
        from url: URL,
        to destinationURL: URL,
        minimumPlayableBytes: Int64,
        progress: (@Sendable (Int64, Int64?) -> Void)?
    ) async throws -> ProgressiveMediaDownloadHandle {
        try? FileManager.default.removeItem(at: destinationURL)
        try firstChunk.write(to: destinationURL)
        progress?(Int64(firstChunk.count), Int64(firstChunk.count + tailChunk.count))
        let response = response(for: url)
        let completion = Task<URL, Error> {
            try await Task.sleep(nanoseconds: tailDelayNanoseconds)
            let handle = try FileHandle(forWritingTo: destinationURL)
            try handle.seekToEnd()
            try handle.write(contentsOf: tailChunk)
            try handle.close()
            progress?(Int64(firstChunk.count + tailChunk.count), Int64(firstChunk.count + tailChunk.count))
            await completionProbe?.markCompleted()
            return destinationURL
        }
        return ProgressiveMediaDownloadHandle(playableURL: destinationURL, response: response, completion: completion)
    }

    private func response(for url: URL) -> URLResponse {
        HTTPURLResponse(
            url: url,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: [
                "Content-Type": "audio/wav",
                "Content-Length": "\(firstChunk.count + tailChunk.count)",
                "Accept-Ranges": "bytes",
                "ETag": "progressive-fixture"
            ]
        )!
    }
}

private struct DirectFixtureDownloader: MediaDownloading {
    let fileURL: URL
    var mimeType: String = "audio/wav"

    func download(from url: URL, progress: (@Sendable (Int64, Int64?) -> Void)?) async throws -> (URL, URLResponse) {
        let byteCount = fileSize(fileURL)
        progress?(byteCount, byteCount)
        return (fileURL, HTTPURLResponse(
            url: url,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: [
                "Content-Type": mimeType,
                "Content-Length": "\(byteCount)",
                "Accept-Ranges": "bytes",
                "ETag": "direct-fixture"
            ]
        )!)
    }
}

private struct FixtureDownloader: MediaDownloading {
    let fileURL: URL
    var mimeType: String = "audio/wav"
    var statusCode: Int = 200
    var contentLengthOverride: Int64?

    func download(from url: URL, progress: (@Sendable (Int64, Int64?) -> Void)?) async throws -> (URL, URLResponse) {
        let destination = FileManager.default.temporaryDirectory
            .appending(path: "download-\(UUID().uuidString)")
            .appendingPathExtension(fileURL.pathExtension)
        try FileManager.default.copyItem(at: fileURL, to: destination)
        let byteCount = (try? FileManager.default.attributesOfItem(atPath: destination.path)[.size] as? Int64) ?? 0
        let expectedByteCount = contentLengthOverride ?? byteCount
        progress?(byteCount, expectedByteCount)
        let response = HTTPURLResponse(
            url: url,
            statusCode: statusCode,
            httpVersion: "HTTP/1.1",
            headerFields: [
                "Content-Type": mimeType,
                "Content-Length": "\(expectedByteCount)",
                "Accept-Ranges": "bytes",
                "ETag": "fixture"
            ]
        )!
        return (destination, response)
    }
}

private func waitUntilCached<M: AuraPlayableMedia>(_ manager: MediaCacheManager, media: M, timeoutNanoseconds: UInt64) async throws -> Bool {
    let deadline = ContinuousClock.now.advanced(by: .nanoseconds(Int(timeoutNanoseconds)))
    while ContinuousClock.now < deadline {
        if await manager.isCached(media) {
            return true
        }
        try await Task.sleep(nanoseconds: 10_000_000)
    }
    return await manager.isCached(media)
}

private func makeEmbeddedBase64Fixture(resourceName: String, extension pathExtension: String) throws -> URL {
    let resourceURL = try #require(Bundle.module.url(forResource: resourceName, withExtension: "b64"))
    let base64 = try String(contentsOf: resourceURL, encoding: .utf8)
        .components(separatedBy: .whitespacesAndNewlines)
        .joined()
    let data = try #require(Data(base64Encoded: base64))
    let destination = FileManager.default.temporaryDirectory
        .appending(path: "\(resourceName)-\(UUID().uuidString)")
        .appendingPathExtension(pathExtension)
    try data.write(to: destination)
    return destination
}

private func makeEmbeddedFLACFixture() throws -> URL {
    var encoded = ""
    for part in 1...22 {
        let name = String(format: "native.flac.part%02d", part)
        let partURL = try #require(Bundle.module.url(forResource: name, withExtension: "b64"))
        encoded += try String(contentsOf: partURL, encoding: .utf8)
    }
    let data = try #require(Data(base64Encoded: encoded.components(separatedBy: .whitespacesAndNewlines).joined()))
    let destination = FileManager.default.temporaryDirectory
        .appending(path: "native-flac-\(UUID().uuidString)")
        .appendingPathExtension("flac")
    try data.write(to: destination)
    return destination
}

private func fileSize(_ url: URL) -> Int64 {
    let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
    return attributes?[.size] as? Int64 ?? 0
}

private func makeFixtureWAV(name: String) throws -> URL {
    try makeFixtureAudioFile(name: name, extension: "wav")
}

private func makeLongFixtureWAV(name: String, frameCount: AVAudioFrameCount) throws -> URL {
    try makeFixtureAudioFile(name: name, extension: "wav", frameCount: frameCount)
}

private func makeEncodedFixtureAudioFile(
    name: String,
    extension pathExtension: String,
    formatID: AudioFormatID,
    frameCount: AVAudioFrameCount = 48_000
) throws -> URL {
    let url = FileManager.default.temporaryDirectory
        .appending(path: "\(name)-\(UUID().uuidString)")
        .appendingPathExtension(pathExtension)
    let inputFormat = try #require(AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 2))
    var settings: [String: Any] = [
        AVFormatIDKey: formatID,
        AVSampleRateKey: 44_100,
        AVNumberOfChannelsKey: 2
    ]
    if formatID == kAudioFormatMPEG4AAC {
        settings[AVEncoderBitRateKey] = 128_000
    }
    let file = try AVAudioFile(forWriting: url, settings: settings)
    let buffer = try #require(AVAudioPCMBuffer(pcmFormat: inputFormat, frameCapacity: frameCount))
    buffer.frameLength = frameCount

    for channel in 0..<Int(inputFormat.channelCount) {
        let samples = try #require(buffer.floatChannelData?[channel])
        for frame in 0..<Int(frameCount) {
            samples[frame] = sin(Float(frame) * 0.01) * 0.2
        }
    }

    try file.write(from: buffer)
    return url
}

private func makeFixtureAudioFile(name: String, extension pathExtension: String, frameCount: AVAudioFrameCount = 4_800) throws -> URL {
    let url = FileManager.default.temporaryDirectory
        .appending(path: "\(name)-\(UUID().uuidString)")
        .appendingPathExtension(pathExtension)
    let format = try #require(AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 1))
    let settings: [String: Any]
    switch pathExtension.lowercased() {
    case "aif", "aiff":
        settings = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: 48_000,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: true
        ]
    case "caf":
        settings = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: 48_000,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 32,
            AVLinearPCMIsFloatKey: true,
            AVLinearPCMIsBigEndianKey: false
        ]
    default:
        settings = format.settings
    }
    let file = try AVAudioFile(forWriting: url, settings: settings)
    let buffer = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount))
    buffer.frameLength = frameCount

    let samples = try #require(buffer.floatChannelData?[0])
    for frame in 0..<Int(frameCount) {
        samples[frame] = sin(Float(frame) * 0.01) * 0.25
    }

    try file.write(from: buffer)
    return url
}
