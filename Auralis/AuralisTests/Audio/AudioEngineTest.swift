////
////  AudioEngineTest.swift
////  AuralisTests
////
////  Created by Daniel Bell on 9/29/25.
////
//
//import Testing
//@testable import Auralis
//import Foundation
//import AVFoundation
//import MediaPlayer
//import UIKit
//
//@Suite("AudioEngine test plan and pragmatic coverage")
//struct AudioEngineTest {
//
//    /*
//     Test Plan for AudioEngine.swift
//     --------------------------------
//     (unchanged commentary omitted for brevity)
//     */
//
//    @Test("coarseSkipSeconds loads from UserDefaults on init and persists on change")
//    @MainActor
//    func testCoarseSkipPersistence() async throws {
//        // Arrange
//        let defaultsKey = "AudioEngine.coarseSkipSeconds"
//        let original = UserDefaults.standard.object(forKey: defaultsKey)
//        UserDefaults.standard.set(42.0, forKey: defaultsKey)
//        defer {
//            // Restore original value to avoid test pollution
//            if let original {
//                UserDefaults.standard.set(original, forKey: defaultsKey)
//            } else {
//                UserDefaults.standard.removeObject(forKey: defaultsKey)
//            }
//        }
//
//        // Act
//        let engine = try AudioEngine(testing: true)
//
//        // Assert load from defaults
//        #expect(engine.coarseSkipSeconds == 42.0, "AudioEngine should load persisted coarseSkipSeconds on init")
//
//        // Act: change value and ensure it writes back
//        engine.coarseSkipSeconds = 15.0
//        let persisted = UserDefaults.standard.double(forKey: defaultsKey)
//        #expect(persisted == 15.0, "Setting coarseSkipSeconds should persist to UserDefaults")
//    }
//
//    @Test("isPlaying reflects playbackState")
//    @MainActor
//    func testIsPlayingComputed() async throws {
//        let engine = try AudioEngine(testing: true)
//        #expect(engine.isPlaying == false)
//
//        // play() with no audioFile should set .loading, not .playing
//        try engine.play()
//        #expect(engine.isPlaying == false)
//
//        // pause() from non-playing should remain non-playing
//        engine.pause()
//        #expect(engine.isPlaying == false)
//    }
//
//    @Test("play with no audio file enters loading state and is safe")
//    @MainActor
//    func testPlayWithoutFile() async throws {
//        let engine = try AudioEngine(testing: true)
//        #expect(engine.isPlaying == false)
//        #expect(engine.playbackState == .stopped)
//
//        try engine.play()
//
//        // We expect the engine to transition into .loading and schedule playNext asynchronously
//        #expect(engine.playbackState == .loading)
//    }
//
//    @Test("pause and resume are safe when not in corresponding states")
//    @MainActor
//    func testPauseResumeNoops() async throws {
//        let engine = try AudioEngine(testing: true)
//
//        // From .stopped, pause should be a no-op
//        engine.pause()
//        #expect(engine.playbackState == .stopped)
//
//        // From .stopped, resume should be a no-op
//        try engine.resume()
//        #expect(engine.playbackState == .stopped)
//    }
//
//    @Test("seek clamps and is safe when no audio file is loaded")
//    @MainActor
//    func testSeekNoFile() async throws {
//        let engine = try AudioEngine(testing: true)
//        // Should not throw or crash even with extreme values
//        try engine.seek(to: -100)
//        try engine.seek(to: 0)
//        try engine.seek(to: .infinity)
//
//        // Progress should remain 0 with no file
//        #expect(engine.progress == 0)
//    }
//
//    @Test("skip forward/backward safely route to seek without a file")
//    @MainActor
//    func testCoarseSkipNoFile() async throws {
//        let engine = try AudioEngine(testing: true)
//        engine.coarseSkipSeconds = 7
//        // Should not crash
//        engine.skipForward()
//        engine.skipBackward()
//        // Still no file; progress remains 0
//        #expect(engine.progress == 0)
//    }
//
//    @Test("playNext and playPrevious are safe with empty queues")
//    @MainActor
//    func testNextPreviousEmptyQueues() async throws {
//        let engine = try AudioEngine(testing: true)
//        // Ensure both queues are empty
//        engine.nextAudio.tracks.removeAll()
//        engine.previousAudio.tracks.removeAll()
//
//        // These calls should not crash and should leave engine in a consistent state
//        await engine.playNext()
//        await engine.playPrevious()
//
//        // With nothing to play, engine should not be .playing
//        #expect(engine.isPlaying == false)
//    }
//
//    @Test("RepeatMode.track triggers restart behavior on playNext() even without a file")
//    @MainActor
//    func testRepeatTrackModePlayNext() async throws {
//        let engine = try AudioEngine(testing: true)
//        engine.repeatMode = .track
//
//        // With no file, this should be safe and not transition to playing
//        await engine.playNext()
//        #expect(engine.isPlaying == false)
//    }
//
//    // MARK: - Extra tests unlocked by small adjustments already applied
//    @Test("Format support helpers are testable")
//    func testFormatSupportHelpers() async throws {
//        // Nonisolated static can be used directly
//        #expect(AudioEngine.shouldTreatAsRemote(URL(string: "https://example.com/audio.mp3")!))
//        #expect(!AudioEngine.shouldTreatAsRemote(URL(string: "file:///local.mp3")!))
//    }
//
//    @Test("canPlayFormat covers known extensions and audio-serving domains")
//    @MainActor
//    func testCanPlayFormat() async throws {
//        let engine = try AudioEngine(testing: true)
//
//        // Known extensions
//        #expect(engine.canPlayFormat(URL(string: "file:///test.wav")!))
//        #expect(engine.canPlayFormat(URL(string: "file:///test.aiff")!))
//        #expect(engine.canPlayFormat(URL(string: "file:///test.caf")!))
//        #expect(engine.canPlayFormat(URL(string: "file:///test.mp3")!))
//        #expect(engine.canPlayFormat(URL(string: "file:///test.m4a")!))
//        #expect(engine.canPlayFormat(URL(string: "file:///test.flac")!))
//
//        // Unsupported extension
//        #expect(!engine.canPlayFormat(URL(string: "file:///test.txt")!))
//        #expect(!engine.canPlayFormat(URL(string: "file:///test.png")!))
//
//        // Audio-serving domains without extension
//        #expect(engine.canPlayFormat(URL(string: "https://ipfs.io/ipfs/abcdef")!))
//        #expect(engine.canPlayFormat(URL(string: "https://arweave.net/abcdef")!))
//        #expect(engine.canPlayFormat(URL(string: "https://gateway.pinata.cloud/ipfs/abcdef")!))
//    }
//
//    @Test("shouldTreatAsRemote detects http/https and ignores file URLs")
//    func testShouldTreatAsRemote() async throws {
//        #expect(AudioEngine.shouldTreatAsRemote(URL(string: "https://example.com/a.mp3")!))
//        #expect(AudioEngine.shouldTreatAsRemote(URL(string: "http://example.com/a.mp3")!))
//        #expect(!AudioEngine.shouldTreatAsRemote(URL(string: "file:///local/a.mp3")!))
//    }
//
//    @Test("peekNextTrack respects repeat=track and returns current without queue mutation")
//    @MainActor
//    func testPeekRepeatTrackMode() async throws {
//        let engine = try AudioEngine(testing: true)
//        let current = NFTExamples.musicNFT
//        // Simulate currently playing NFT via test helper file injection
//        // We don't need a real file for peek logic; just set currentNFT indirectly via injection
//        engine.injectAudioFileForTesting(try dummyAudioFile(durationSeconds: 1.0), nft: current)
//        engine.repeatMode = .track
//
//        let peeked = engine.peekNextTrackRespectingModes()
//        #expect(peeked?.id == current.id)
//        // Ensure next/previous queues remain untouched
//        #expect(engine.nextAudio.tracks.isEmpty)
//        #expect(engine.previousAudio.tracks.isEmpty)
//    }
//
//    @Test("dequeueNextTrack respects repeat=track and does not mutate queues")
//    @MainActor
//    func testDequeueRepeatTrackMode() async throws {
//        let engine = try AudioEngine(testing: true)
//        let current = NFTExamples.musicNFT2
//        engine.injectAudioFileForTesting(try dummyAudioFile(durationSeconds: 1.0), nft: current)
//        engine.repeatMode = .track
//
//        let dequeued = engine.dequeueNextTrackRespectingModes()
//        #expect(dequeued?.id == current.id)
//        #expect(engine.nextAudio.tracks.isEmpty)
//        #expect(engine.previousAudio.tracks.isEmpty)
//    }
//
//    @Test("peek/dequeue with ordered next queue (no shuffle)")
//    @MainActor
//    func testQueueOrderedNoShuffle() async throws {
//        let engine = try AudioEngine(testing: true)
//        engine.isShuffleEnabled = false
//        let n1 = NFTExamples.musicNFT
//        let n2 = NFTExamples.musicNFT2
//        engine.nextAudio.tracks = [n1, n2]
//
//        // Peek should return first without removing
//        let peeked = engine.peekNextTrackRespectingModes()
//        #expect(peeked?.id == n1.id)
//        #expect(engine.nextAudio.tracks.count == 2)
//
//        // Dequeue should remove first
//        let first = engine.dequeueNextTrackRespectingModes()
//        #expect(first?.id == n1.id)
//        #expect(engine.nextAudio.tracks.count == 1)
//        #expect(engine.nextAudio.tracks.first?.id == n2.id)
//    }
//
//    @Test("peek/dequeue with shuffle enabled returns one element and mutates size by 1 on dequeue")
//    @MainActor
//    func testQueueShuffle() async throws {
//        let engine = try AudioEngine(testing: true)
//        engine.isShuffleEnabled = true
//        let n1 = NFTExamples.musicNFT
//        let n2 = NFTExamples.musicNFT2
//        engine.nextAudio.tracks = [n1, n2]
//
//        // Peek returns one of the elements but does not mutate
//        let peeked = engine.peekNextTrackRespectingModes()
//        #expect(peeked != nil)
//        #expect([n1.id, n2.id].contains(peeked!.id))
//        #expect(engine.nextAudio.tracks.count == 2)
//
//        // Dequeue removes one
//        let removed = engine.dequeueNextTrackRespectingModes()
//        #expect(removed != nil)
//        #expect([n1.id, n2.id].contains(removed!.id))
//        #expect(engine.nextAudio.tracks.count == 1)
//    }
//
//    @Test("repeat playlist rebuilds next queue from history + current when empty")
//    @MainActor
//    func testRepeatPlaylistRebuild() async throws {
//        let engine = try AudioEngine(testing: true)
//        engine.isShuffleEnabled = false
//        engine.repeatMode = .playlist
//
//        // Set a current and a previous history, empty next
//        let current = NFTExamples.musicNFT
//        let prev1 = NFTExamples.musicNFT2
//        engine.injectAudioFileForTesting(try dummyAudioFile(durationSeconds: 1.0), nft: current)
//        engine.previousAudio.tracks = [prev1]
//        engine.nextAudio.tracks = []
//
//        // Peek should derive a virtual next from [current] + previous
//        let peeked = engine.peekNextTrackRespectingModes()
//        #expect(peeked != nil)
//        #expect([current.id, prev1.id].contains(peeked!.id))
//
//        // Dequeue should rebuild and then remove first
//        let dequeued = engine.dequeueNextTrackRespectingModes()
//        #expect(dequeued != nil)
//        #expect([current.id, prev1.id].contains(dequeued!.id))
//        // After rebuild, next should have one remaining
//        #expect(engine.nextAudio.tracks.count == 1)
//    }
//
//    // MARK: - Helpers
//    private func dummyAudioFile(durationSeconds: Double, sampleRate: Double = 44100.0) throws -> AVAudioFile {
//        let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 2)!
//        let frameCount = AVAudioFrameCount(durationSeconds * sampleRate)
//        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount)!
//        buffer.frameLength = frameCount
//        // buffer is silent by default
//
//        let tmpURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathExtension("caf")
//        let file = try AVAudioFile(forWriting: tmpURL, settings: format.settings)
//        try file.write(from: buffer)
//        return try AVAudioFile(forReading: tmpURL)
//    }
//
//    // MARK: - Initialization & DI: constructor wiring and session setup
//    private class FakeAudioSession: AudioSessioning {
//        var setCategoryCalls: [(AVAudioSession.Category, AVAudioSession.Mode, AVAudioSession.CategoryOptions)] = []
//        var setActiveCalls: [Bool] = []
//        var setActiveWithOptionsCalls: [(Bool, AVAudioSession.SetActiveOptions)] = []
//        var prefersOnRouteDisconnectSet: Bool = false
//        var currentRoute: AVAudioSessionRouteDescription = AVAudioSession.sharedInstance().currentRoute
//
//        func setCategory(_ category: AVAudioSession.Category, mode: AVAudioSession.Mode, options: AVAudioSession.CategoryOptions) throws {
//            setCategoryCalls.append((category, mode, options))
//        }
//        func setActive(_ active: Bool) throws { setActiveCalls.append(active) }
//        func setActive(_ active: Bool, options: AVAudioSession.SetActiveOptions) throws { setActiveWithOptionsCalls.append((active, options)) }
//        @available(iOS 26.0, *)
//        func setPrefersInterruptionOnRouteDisconnect(_ flag: Bool) throws { prefersOnRouteDisconnectSet = flag }
//    }
//
//    @Test("engine initializes to .stopped and wires session setup calls")
//    @MainActor
//    func testInitializationAndSessionSetup() async throws {
//        let fakeSession = FakeAudioSession()
//        let engine = try AudioEngine(testing: true, session: fakeSession)
//        // playback state
//        #expect(engine.playbackState == .stopped)
//        #expect(engine.isPlaying == false)
//
//        // session wiring
//        #expect(fakeSession.setCategoryCalls.count == 1)
//        if let call = fakeSession.setCategoryCalls.first {
//            #expect(call.0 == .playback)
//            #expect(call.1 == .default)
//            #expect(call.2.contains(.allowAirPlay))
//            #expect(call.2.contains(.allowBluetoothA2DP))
//        }
//        #expect(fakeSession.setActiveCalls == [true])
//
//        // availability-specific preference
//        if #available(iOS 26.0, *) {
//            #expect(fakeSession.prefersOnRouteDisconnectSet == true)
//        }
//        _ = engine // keep reference
//    }
//
//    @Test("remote command intervals update only when enabled")
//    @MainActor
//    func testRemoteSkipIntervalsUpdate() async throws {
//        // Take a snapshot of global command center intervals to compare changes
//        let center = MPRemoteCommandCenter.shared()
//        let beforeFwd = center.skipForwardCommand.preferredIntervals
//        let beforeBack = center.skipBackwardCommand.preferredIntervals
//
//        // Disabled: changing coarseSkipSeconds should not modify command center
//        let engineDisabled = try AudioEngine(testing: true, disableRemoteCommands: true)
//        engineDisabled.coarseSkipSeconds = 17
//        let afterDisabledFwd = center.skipForwardCommand.preferredIntervals
//        let afterDisabledBack = center.skipBackwardCommand.preferredIntervals
//        #expect(afterDisabledFwd == beforeFwd)
//        #expect(afterDisabledBack == beforeBack)
//
//        // Enabled: changing coarseSkipSeconds should set both preferred intervals
//        let engineEnabled = try AudioEngine(testing: true, disableRemoteCommands: false)
//        engineEnabled.coarseSkipSeconds = 23
//        let afterEnabledFwd = center.skipForwardCommand.preferredIntervals
//        let afterEnabledBack = center.skipBackwardCommand.preferredIntervals
//        #expect(afterEnabledFwd == [23])
//        #expect(afterEnabledBack == [23])
//        _ = (engineDisabled, engineEnabled) // silence unused warnings in some runners
//    }
//
//    @Test("UserDefaults restore and session category/options on init")
//    @MainActor
//    func testDefaultsRestoreAndSessionOptions() async throws {
//        let defaultsKey = "AudioEngine.coarseSkipSeconds"
//        let original = UserDefaults.standard.object(forKey: defaultsKey)
//        UserDefaults.standard.set(8.0, forKey: defaultsKey)
//        defer {
//            if let original { UserDefaults.standard.set(original, forKey: defaultsKey) } else { UserDefaults.standard.removeObject(forKey: defaultsKey) }
//        }
//        let fakeSession = FakeAudioSession()
//        let engine = try AudioEngine(testing: true, session: fakeSession)
//        #expect(engine.coarseSkipSeconds == 8.0)
//        // Verify session category/options captured
//        #expect(fakeSession.setCategoryCalls.count == 1)
//        if let call = fakeSession.setCategoryCalls.first {
//            #expect(call.0 == .playback)
//            #expect(call.1 == .default)
//            #expect(call.2.contains(.allowAirPlay))
//            #expect(call.2.contains(.allowBluetoothA2DP))
//        }
//    }
//
//    // MARK: - Added High-Value Tests
//
//    // MARK: - Test Doubles for new tests
//    private final class FakeNowPlayingCenter: NowPlayingCentering {
//        var nowPlayingInfo: [String : Any]? = nil
//    }
//
//    private final class SlowThenFastAudioCache: AudioFileCaching {
//        // First call is slow (to simulate cancellation), second is fast
//        private var callCount = 0
//        private let urlToReturn: URL
//        private let slowDelayNanos: UInt64
//        init(urlToReturn: URL, slowDelaySeconds: Double = 0.25) {
//            self.urlToReturn = urlToReturn
//            self.slowDelayNanos = UInt64(slowDelaySeconds * 1_000_000_000)
//        }
//        func cachedURL(forRemote url: URL) async throws -> URL { urlToReturn }
//        func localURL(forRemote url: URL) async throws -> URL {
//            callCount += 1
//            if callCount == 1 {
//                try await Task.sleep(nanoseconds: slowDelayNanos)
//            }
//            return urlToReturn
//        }
//    }
//
//    // MARK: - 1) Crossfade and handoff (partial)
//    @Test("performCrossfade sets volumes immediately when timers are disabled")
//    @MainActor
//    func testPerformCrossfadeWithTimersDisabled() async throws {
//        // Arrange: create an engine with timers disabled so ramp happens instantly
//        let engine = try AudioEngine(testing: true, disableRemoteCommands: true, disableTimers: true)
//        let from = AVAudioMixerNode()
//        let to = AVAudioMixerNode()
//        from.volume = 1.0
//        to.volume = 0.0
//
//        // Act
//        engine.performCrossfade(duration: 1.0, from: from, to: to)
//
//        // Assert: target volumes applied immediately
//        #expect(abs(to.volume - 0.9) < 0.0001, "Destination mixer should jump to crossfadePeakGain when timers are disabled")
//        #expect(abs(from.volume - 0.0) < 0.0001, "Source mixer should be muted when timers are disabled")
//        _ = engine // keep alive
//    }
//
//    // MARK: - 2) Single-flight loading and cancellation
//    @Test("loadAndPlay single-flight: second request cancels the first and becomes current")
//    @MainActor
//    func testSingleFlightLoadCancelsFirst() async throws {
//        // Prepare a short dummy file to act as the audio payload
//        let file = try dummyAudioFile(durationSeconds: 0.2)
//        let localURL = file.url
//
//        // Use two distinct NFTs from examples to differentiate titles
//        let firstNFT = NFTExamples.musicNFT
//        let secondNFT = NFTExamples.musicNFT2
//
//        // Inject a cache that is slow on the first call and fast on the second
//        let cache = SlowThenFastAudioCache(urlToReturn: localURL, slowDelaySeconds: 0.3)
//
//        let engine = try AudioEngine(
//            testing: true,
//            disableRemoteCommands: true,
//            disableTimers: true,
//            audioCache: cache
//        )
//
//        // Act: kick off two loads back-to-back
//        Task { try await engine.loadAndPlay(nft: firstNFT) }
//        // Very short delay to ensure first starts, then fire second
//        try await Task.sleep(nanoseconds: 50_000_000) // 50ms
//        Task { try await engine.loadAndPlay(nft: secondNFT) }
//
//        // Wait for the second to win and start playback
//        // Poll for up to 1s
//        let deadline = Date().addingTimeInterval(1.0)
//        while Date() < deadline {
//            if engine.currentTrack?.title == secondNFT.name, engine.playbackState == .playing {
//                break
//            }
//            try await Task.sleep(nanoseconds: 50_000_000)
//        }
//
//        // Assert: second is current and playing; no error
//        #expect(engine.currentTrack?.title == secondNFT.name)
//        #expect(engine.playbackState == .playing)
//        #expect(engine.lastError == nil)
//        _ = (file, engine)
//    }
//
//    // MARK: - 3) Now Playing metadata and artwork
//    @Test("Now Playing metadata updates for finite and live tracks; artwork loader populates artwork")
//    @MainActor
//    func testNowPlayingMetadataAndArtwork() async throws {
//        let fakeCenter = FakeNowPlayingCenter()
//        let engine = try AudioEngine(
//            testing: true,
//            disableRemoteCommands: true,
//            disableTimers: true,
//            nowPlayingCenter: fakeCenter
//        )
//
//        // Finite duration: set a track and transition through playing->pause to trigger updates
//        engine.currentTrack = AudioEngine.Track(title: "Finite", artist: "Artist", duration: 10, imageUrl: nil)
//        engine.playbackState = .playing
//        engine.pause() // triggers metadata/progress update
//
//        // Assert finite metadata
//        let finiteInfo = fakeCenter.nowPlayingInfo
//        #expect(finiteInfo != nil)
//        if let info = finiteInfo {
//            #expect((info[MPMediaItemPropertyPlaybackDuration] as? Double) == 10)
//            #expect((info[MPNowPlayingInfoPropertyIsLiveStream] as? Bool) == false)
//            #expect((info[MPNowPlayingInfoPropertyPlaybackRate] as? Double) == 0.0)
//        }
//
//        // Live track (duration <= 0)
//        engine.currentTrack = AudioEngine.Track(title: "Live", artist: "DJ", duration: 0, imageUrl: nil)
//        engine.playbackState = .playing
//        engine.pause()
//
//        let liveInfo = fakeCenter.nowPlayingInfo
//        #expect(liveInfo != nil)
//        if let info = liveInfo {
//            #expect((info[MPNowPlayingInfoPropertyIsLiveStream] as? Bool) == true)
//        }
//
//        // Artwork via injected loader
//        engine.artworkLoader = { _ in
//            // 1x1 pixel image
//            UIGraphicsBeginImageContext(CGSize(width: 1, height: 1))
//            UIColor.red.setFill()
//            UIRectFill(CGRect(x: 0, y: 0, width: 1, height: 1))
//            let img = UIGraphicsGetImageFromCurrentImageContext()
//            UIGraphicsEndImageContext()
//            return img
//        }
//        engine.currentTrack = AudioEngine.Track(title: "Art", artist: "Painter", duration: 5, imageUrl: "https://example.com/art.png")
//        engine.playbackState = .paused
//        // Trigger metadata update that kicks off artwork loader
//        engine.pause()
//
//        // Poll a bit for async artwork loader to complete
//        var foundArtwork = false
//        let artDeadline = Date().addingTimeInterval(1.0)
//        while Date() < artDeadline {
//            if let info = fakeCenter.nowPlayingInfo, info[MPMediaItemPropertyArtwork] != nil {
//                foundArtwork = true
//                break
//            }
//            try await Task.sleep(nanoseconds: 50_000_000)
//        }
//        #expect(foundArtwork, "Expected artwork to be populated in now playing info")
//        _ = engine
//    }
//
//    // MARK: - 1b) Crossfade handoff while playing (uses next queue)
//    @Test("playNext while playing performs handoff and updates state")
//    @MainActor
//    func testCrossfadeHandoffWhilePlaying() async throws {
//        // Arrange: short file and two NFTs
//        let file = try dummyAudioFile(durationSeconds: 0.8)
//        let localURL = file.url
//        let currentNFT = NFTExamples.musicNFT
//        let nextNFT = NFTExamples.musicNFT2
//
//        // Cache that returns our local file for any remote URL
//        let cache = SlowThenFastAudioCache(urlToReturn: localURL, slowDelaySeconds: 0.0)
//
//        let engine = try AudioEngine(
//            testing: true,
//            disableRemoteCommands: true,
//            disableTimers: true,
//            audioCache: cache
//        )
//
//        // Inject current file + NFT and queue next
//        engine.injectAudioFileForTesting(file, nft: currentNFT)
//        engine.nextAudio.tracks = [nextNFT]
//
//        // Start playing then request next
//        try engine.play()
//        await engine.playNext()
//
//        // Wait for handoff to complete (poll up to 1s)
//        let deadline = Date().addingTimeInterval(1.0)
//        while Date() < deadline {
//            if engine.currentTrack?.title == nextNFT.name, engine.playbackState == .playing {
//                break
//            }
//            try await Task.sleep(nanoseconds: 50_000_000)
//        }
//
//        // Assert: we flipped to next, previous contains old, and still playing
//        #expect(engine.currentTrack?.title == nextNFT.name)
//        #expect(engine.playbackState == .playing)
//        #expect(engine.previousAudio.tracks.contains { $0.id == currentNFT.id })
//        _ = (engine, file)
//    }
//
//    // MARK: - 5) Seek while playing
//    @Test("seek while playing restarts from new position and remains playing")
//    @MainActor
//    func testSeekWhilePlaying() async throws {
//        let duration: Double = 1.0
//        let file = try dummyAudioFile(durationSeconds: duration)
//        
//        // Use fake audio session to prevent system notifications from interfering
//        let fakeSession = FakeAudioSession()
//        let engine = try AudioEngine(
//            testing: true,
//            disableRemoteCommands: true,
//            disableTimers: true,
//            session: fakeSession
//        )
//        engine.injectAudioFileForTesting(file)
//        
//        // Start playback
//        try engine.play()
//        #expect(engine.playbackState == .playing, "Should be playing after initial play()")
//        
//        // Let playback run briefly
//        try await Task.sleep(nanoseconds: 100_000_000) // 100ms
//        
//        // Seek to middle
//        let target = duration / 2
//        try engine.seek(to: target)
//        
//        // Poll for playing state (handles any async state transitions gracefully)
//        let deadline = Date().addingTimeInterval(0.3)
//        while Date() < deadline && engine.playbackState != .playing {
//            try await Task.sleep(nanoseconds: 20_000_000) // 20ms
//        }
//        
//        // Verify final state
//        #expect(engine.playbackState == .playing, "Should remain playing after seek")
//        #expect(engine.audioFile != nil, "Audio file should still be loaded after seek")
//        
//        // Verify progress is near target
//        let p = engine.progress
//        #expect(abs(p - target) < 0.25, "Expected progress near target after seek while playing (got: \(p), expected: \(target))")
//        _ = (engine, file)
//    }
//
//    // MARK: - 4) Interruption handling: pause on began, resume on ended+shouldResume
//    @Test("interruption began pauses; ended with shouldResume resumes")
//    @MainActor
//    func testInterruptionPauseAndResume() async throws {
//        let file = try dummyAudioFile(durationSeconds: 1.0)
//        let engine = try AudioEngine(testing: true, disableRemoteCommands: true, disableTimers: true)
//        engine.injectAudioFileForTesting(file)
//
//        try engine.play()
//        #expect(engine.playbackState == .playing)
//
//        // Post interruption began
//        let beganUserInfo: [AnyHashable: Any] = [
//            AVAudioSessionInterruptionTypeKey: AVAudioSession.InterruptionType.began.rawValue
//        ]
//        NotificationCenter.default.post(name: AVAudioSession.interruptionNotification, object: nil, userInfo: beganUserInfo)
//
//        // Allow handler to process
//        try await Task.sleep(nanoseconds: 50_000_000)
//        #expect(engine.playbackState == .paused)
//
//        // Post interruption ended with shouldResume
//        let endedUserInfo: [AnyHashable: Any] = [
//            AVAudioSessionInterruptionTypeKey: AVAudioSession.InterruptionType.ended.rawValue,
//            AVAudioSessionInterruptionOptionKey: AVAudioSession.InterruptionOptions.shouldResume.rawValue
//        ]
//        NotificationCenter.default.post(name: AVAudioSession.interruptionNotification, object: nil, userInfo: endedUserInfo)
//
//        // Allow handler to process and attempt resume
//        let deadline = Date().addingTimeInterval(1.0)
//        while Date() < deadline {
//            if engine.playbackState == .playing { break }
//            try await Task.sleep(nanoseconds: 50_000_000)
//        }
//        #expect(engine.playbackState == .playing)
//        _ = (engine, file)
//    }
//
//    // MARK: - 4b) Route change handling
//    @Test("route configuration change re-activates session and reconfigures engine")
//    @MainActor
//    func testRouteConfigurationChangeReactivatesSession() async throws {
//        // Use fake session so we can observe setActive calls
//        let fakeSession = FakeAudioSession()
//        let engine = try AudioEngine(
//            testing: true,
//            disableRemoteCommands: true,
//            disableTimers: true,
//            session: fakeSession
//        )
//
//        // Post route change notification with reason .routeConfigurationChange
//        let userInfo: [AnyHashable: Any] = [
//            AVAudioSessionRouteChangeReasonKey: AVAudioSession.RouteChangeReason.routeConfigurationChange.rawValue
//        ]
//        NotificationCenter.default.post(name: AVAudioSession.routeChangeNotification, object: nil, userInfo: userInfo)
//
//        // Allow handler to process and call ensureSessionActive
//        let deadline = Date().addingTimeInterval(1.0)
//        while Date() < deadline {
//            if fakeSession.setActiveCalls.contains(true) { break }
//            try await Task.sleep(nanoseconds: 50_000_000)
//        }
//
//        // We expect at least one additional activation attempt beyond initial init call
//        #expect(fakeSession.setActiveCalls.contains(true))
//        _ = engine
//    }
//
//    @Test("noSuitableRouteForCategory falls back to speaker and pauses if playing")
//    @MainActor
//    func testNoSuitableRoutePausesAndReaffirmsCategory() async throws {
//        let fakeSession = FakeAudioSession()
//        let engine = try AudioEngine(
//            testing: true,
//            disableRemoteCommands: true,
//            disableTimers: true,
//            session: fakeSession
//        )
//
//        // Start playing a short file
//        let file = try dummyAudioFile(durationSeconds: 0.5)
//        engine.injectAudioFileForTesting(file)
//        try engine.play()
//        #expect(engine.playbackState == .playing)
//
//        // Post route change with reason .noSuitableRouteForCategory
//        let userInfo: [AnyHashable: Any] = [
//            AVAudioSessionRouteChangeReasonKey: AVAudioSession.RouteChangeReason.noSuitableRouteForCategory.rawValue
//        ]
//        NotificationCenter.default.post(name: AVAudioSession.routeChangeNotification, object: nil, userInfo: userInfo)
//
//        // Allow handler to process
//        try await Task.sleep(nanoseconds: 100_000_000)
//
//        // Expect a reaffirm of category + active, and paused state for safety
//        #expect(fakeSession.setCategoryCalls.contains { $0.0 == .playback && $0.1 == .default })
//        #expect(fakeSession.setActiveCalls.contains(true))
//        #expect(engine.playbackState != .playing)
//        _ = (engine, file)
//    }
//
//    // MARK: - 6) Remote command availability (behavioral, without invoking handlers)
//    @Test("remote command availability toggles based on duration and queues")
//    @MainActor
//    func testRemoteCommandAvailability() async throws {
//        // Enable remote commands to let engine configure them
//        let engine = try AudioEngine(testing: true, disableRemoteCommands: false, disableTimers: true)
//
//        // With no track (duration 0), scrubbing/skip should be disabled
//        engine.injectAudioFileForTesting(try dummyAudioFile(durationSeconds: 0.0))
//        engine.pause()
//        let center = MPRemoteCommandCenter.shared()
//        #expect(center.changePlaybackPositionCommand.isEnabled == false)
//        #expect(center.skipForwardCommand.isEnabled == false)
//        #expect(center.skipBackwardCommand.isEnabled == false)
//
//        // With finite duration, enable these
//        engine.injectAudioFileForTesting(try dummyAudioFile(durationSeconds: 1.0))
//        engine.pause()
//        #expect(center.changePlaybackPositionCommand.isEnabled == true)
//        #expect(center.skipForwardCommand.isEnabled == true)
//        #expect(center.skipBackwardCommand.isEnabled == true)
//
//        // Next/Previous availability based on queues
//        engine.nextAudio.tracks.removeAll()
//        engine.previousAudio.tracks.removeAll()
//        engine.repeatMode = .none
//        engine.pause()
//        #expect(center.nextTrackCommand.isEnabled == false)
//        #expect(center.previousTrackCommand.isEnabled == false)
//
//        engine.nextAudio.tracks = [NFTExamples.musicNFT]
//        engine.pause()
//        #expect(center.nextTrackCommand.isEnabled == true)
//
//        engine.previousAudio.tracks = [NFTExamples.musicNFT2]
//        engine.pause()
//        #expect(center.previousTrackCommand.isEnabled == true)
//        _ = engine
//    }
//
//    // MARK: - 7) Deinit cleanup
//    @Test("deinit clears nowPlayingInfo and deactivates session")
//    @MainActor
//    func testDeinitCleanup() async throws {
//        // Use fakes to observe cleanup side effects
//        let fakeCenter = FakeNowPlayingCenter()
//        let fakeSession = FakeAudioSession()
//        weak var weakEngine: AudioEngine?
//        do {
//            let engine = try AudioEngine(
//                testing: true,
//                disableRemoteCommands: true,
//                disableTimers: true,
//                session: fakeSession,
//                nowPlayingCenter: fakeCenter
//            )
//            // Simulate active now playing info
//            engine.currentTrack = AudioEngine.Track(title: "X", artist: "Y", duration: 1, imageUrl: nil)
//            engine.pause()
//            #expect(fakeCenter.nowPlayingInfo != nil)
//            weakEngine = engine
//        }
//        // Drop strong references and allow deinit to run
//        // deinit posts cleanup on main queue; give it a moment
//        let deadline = Date().addingTimeInterval(1.0)
//        while Date() < deadline {
//            if weakEngine == nil { break }
//            try await Task.sleep(nanoseconds: 50_000_000)
//        }
//        // After deinit, nowPlayingInfo should be cleared asynchronously
//        try await Task.sleep(nanoseconds: 100_000_000)
//        #expect(fakeCenter.nowPlayingInfo == nil)
//        // Session deactivated at least once with false
//        #expect(fakeSession.setActiveCalls.contains(false))
//    }
//
//    @Test("Track equatable and hashable conformance")
//    func testTrackEquatableAndHashable() async throws {
//        // Assuming synthesized Equatable/Hashable on Track
//        let t1 = AudioEngine.Track(title: "A", artist: "B", duration: 10, imageUrl: "https://example.com/a.png")
//        let t1dup = AudioEngine.Track(title: "A", artist: "B", duration: 10, imageUrl: "https://example.com/a.png")
//        let t2 = AudioEngine.Track(title: "A", artist: "B", duration: 11, imageUrl: "https://example.com/a.png")
//        let t3 = AudioEngine.Track(title: "X", artist: "Y", duration: 0, imageUrl: nil)
//
//        #expect(t1 == t1dup)
//        #expect(t1 != t2)
//        #expect(t1 != t3)
//
//        var set: Set<AudioEngine.Track> = []
//        set.insert(t1)
//        set.insert(t1dup) // should be considered the same
//        set.insert(t2)
//        set.insert(t3)
//        #expect(set.count == 3)
//    }
//
//    @Test("Track codable round-trip")
//    func testTrackCodable() async throws {
//        // Assuming Codable conformance on Track
//        let original = AudioEngine.Track(title: "Title", artist: "Artist", duration: 42.5, imageUrl: "https://example.com/art.png")
//        let data = try JSONEncoder().encode(original)
//        let decoded = try JSONDecoder().decode(AudioEngine.Track.self, from: data)
//        #expect(decoded == original)
//    }
//
//    @Test("Track live vs finite duration reflected in Now Playing")
//    @MainActor
//    func testTrackLiveVsFiniteDuration() async throws {
//        let center = FakeNowPlayingCenter()
//        let engine = try AudioEngine(testing: true, disableRemoteCommands: true, disableTimers: true, nowPlayingCenter: center)
//
//        // Finite
//        engine.currentTrack = AudioEngine.Track(title: "Finite", artist: "Artist", duration: 12, imageUrl: nil)
//        engine.playbackState = .playing
//        engine.pause()
//        if let info = center.nowPlayingInfo {
//            #expect((info[MPMediaItemPropertyPlaybackDuration] as? Double) == 12)
//            #expect((info[MPNowPlayingInfoPropertyIsLiveStream] as? Bool) == false)
//        } else {
//            #expect(false, "Expected nowPlayingInfo for finite track")
//        }
//
//        // Live (<= 0 duration)
//        engine.currentTrack = AudioEngine.Track(title: "Live", artist: "DJ", duration: 0, imageUrl: nil)
//        engine.playbackState = .playing
//        engine.pause()
//        if let info = center.nowPlayingInfo {
//            #expect((info[MPNowPlayingInfoPropertyIsLiveStream] as? Bool) == true)
//            // Some implementations omit duration for live; if present ensure it's 0
//            if let d = info[MPMediaItemPropertyPlaybackDuration] as? Double { #expect(d == 0) }
//        } else {
//            #expect(false, "Expected nowPlayingInfo for live track")
//        }
//        _ = engine
//    }
//
//    @Test("Title and artist propagate to Now Playing metadata")
//    @MainActor
//    func testTrackTitleArtistInNowPlaying() async throws {
//        let center = FakeNowPlayingCenter()
//        let engine = try AudioEngine(testing: true, disableRemoteCommands: true, disableTimers: true, nowPlayingCenter: center)
//
//        let title = "Song"
//        let artist = "Performer"
//        engine.currentTrack = AudioEngine.Track(title: title, artist: artist, duration: 5, imageUrl: nil)
//        engine.playbackState = .paused
//        engine.pause() // trigger metadata update path
//
//        if let info = center.nowPlayingInfo {
//            #expect((info[MPMediaItemPropertyTitle] as? String) == title)
//            #expect((info[MPMediaItemPropertyArtist] as? String) == artist)
//        } else {
//            #expect(false, "Expected nowPlayingInfo with title/artist")
//        }
//        _ = engine
//    }
//
//    @Test("Artwork loader failure falls back gracefully")
//    @MainActor
//    func testTrackInvalidImageUrlFallback() async throws {
//        let center = FakeNowPlayingCenter()
//        let engine = try AudioEngine(testing: true, disableRemoteCommands: true, disableTimers: true, nowPlayingCenter: center)
//
//        // Loader returns nil to simulate failure
//        engine.artworkLoader = { _ in return nil }
//
//        engine.currentTrack = AudioEngine.Track(title: "ArtFail", artist: "Painter", duration: 5, imageUrl: "ht!tp://bad url")
//        engine.playbackState = .paused
//        engine.pause()
//
//        // Give async artwork attempt a moment
//        let deadline = Date().addingTimeInterval(0.5)
//        while Date() < deadline {
//            if let info = center.nowPlayingInfo, info[MPMediaItemPropertyArtwork] != nil { break }
//            try await Task.sleep(nanoseconds: 50_000_000)
//        }
//
//        // Either no artwork key or nil is acceptable; most importantly, no crash and info exists
//        #expect(center.nowPlayingInfo != nil)
//        if let info = center.nowPlayingInfo {
//            #expect(info[MPMediaItemPropertyArtwork] == nil)
//        }
//        _ = engine
//    }
//
//    // Helper failing cache to induce an error path
//    private final class AlwaysFailingAudioCache: AudioFileCaching {
//        func cachedURL(forRemote url: URL) async throws -> URL { throw URLError(.badURL) }
//        func localURL(forRemote url: URL) async throws -> URL { throw URLError(.badURL) }
//    }
//
//    @Test("Playback state reflects error when cache fails")
//    @MainActor
//    func testPlaybackStateOnErrorUsingFailingCache() async throws {
//        let engine = try AudioEngine(testing: true, disableRemoteCommands: true, disableTimers: true, audioCache: AlwaysFailingAudioCache())
//
//        // Use an example NFT presumed to load remotely; the cache will throw
//        do {
//            try await engine.loadAndPlay(nft: NFTExamples.musicNFT)
//            #expect(false, "Expected loadAndPlay to throw with failing cache")
//        } catch {
//            // Expected error path
//        }
//
//        // Engine should not be playing and should record an error
//        #expect(engine.isPlaying == false)
//        #expect(engine.playbackState != .playing)
//        #expect(engine.lastError != nil)
//        _ = engine
//    }
//
//    @Test("Repeat mode .none with non-empty queues behaves as FIFO and enables commands")
//    @MainActor
//    func testRepeatNoneWithQueues() async throws {
//        let engine = try AudioEngine(testing: true, disableRemoteCommands: false, disableTimers: true)
//        engine.repeatMode = .none
//        engine.isShuffleEnabled = false
//        let n1 = NFTExamples.musicNFT
//        let n2 = NFTExamples.musicNFT2
//        engine.nextAudio.tracks = [n1, n2]
//        engine.previousAudio.tracks.removeAll()
//
//        let peeked = engine.peekNextTrackRespectingModes()
//        #expect(peeked?.id == n1.id)
//
//        let first = engine.dequeueNextTrackRespectingModes()
//        #expect(first?.id == n1.id)
//        #expect(engine.nextAudio.tracks.first?.id == n2.id)
//
//        // Remote command availability should reflect non-empty next queue
//        let center = MPRemoteCommandCenter.shared()
//        engine.pause() // trigger a metadata/command update pass
//        #expect(center.nextTrackCommand.isEnabled == true)
//    }
//
//    @Test("Repeat .playlist with shuffle rebuilds from history + current")
//    @MainActor
//    func testRepeatPlaylistWithShuffle() async throws {
//        let engine = try AudioEngine(testing: true, disableRemoteCommands: true, disableTimers: true)
//        engine.repeatMode = .playlist
//        engine.isShuffleEnabled = true
//
//        let current = NFTExamples.musicNFT
//        let prev = NFTExamples.musicNFT2
//        engine.injectAudioFileForTesting(try dummyAudioFile(durationSeconds: 0.2), nft: current)
//        engine.previousAudio.tracks = [prev]
//        engine.nextAudio.tracks = []
//
//        // Peek should come from {current, prev}
//        let peeked = engine.peekNextTrackRespectingModes()
//        #expect(peeked != nil)
//        #expect([current.id, prev.id].contains(peeked!.id))
//
//        // Dequeue should rebuild then remove one, leaving one remaining in next
//        let dequeued = engine.dequeueNextTrackRespectingModes()
//        #expect(dequeued != nil)
//        #expect([current.id, prev.id].contains(dequeued!.id))
//        #expect(engine.nextAudio.tracks.count == 1)
//    }
//
//    @Test("Repeat .playlist with no current and empty history returns nil and is safe")
//    @MainActor
//    func testRepeatPlaylistNoCurrentEmptyHistory() async throws {
//        let engine = try AudioEngine(testing: true, disableRemoteCommands: true, disableTimers: true)
//        engine.repeatMode = .playlist
//        engine.isShuffleEnabled = false
//        engine.nextAudio.tracks.removeAll()
//        engine.previousAudio.tracks.removeAll()
//        engine.currentTrack = nil
//
//        let peeked = engine.peekNextTrackRespectingModes()
//        #expect(peeked == nil)
//
//        await engine.playNext() // should not crash
//        #expect(engine.isPlaying == false)
//    }
//
//}
