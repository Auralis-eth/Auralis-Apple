@testable import Auralis
import AuraPlayMediaCore
import Foundation
import MusicFeature
import SwiftData
import Testing

@Suite(.tags(.slow))
@MainActor
struct AuraPlayPhase8PlaybackOrchestrationTests {
    @Test("queue entry identity keeps duplicate media addressable")
    func queueEntryIdentityKeepsDuplicateMediaAddressable() throws {
        let media = mediaItem(id: "duplicate", kind: .music)
        var queue = AuraPlayPlaybackQueue()

        queue.replaceQueue(with: [media, media], startAt: 0, origin: .playlist(id: "mix"))
        let first = try #require(queue.entries.first)
        let second = try #require(queue.entries.dropFirst().first)

        #expect(first.id != second.id)
        #expect(queue.currentEntryID == first.id)
        let removedSecond = queue.remove(entryID: second.id)
        let removedCurrent = queue.remove(entryID: first.id)

        #expect(removedSecond)
        #expect(queue.entries.map(\.id) == [first.id])
        #expect(queue.currentEntryID == first.id)
        #expect(removedCurrent == false)
    }

    @Test("reorder keeps current entry stable even when current entry moves")
    func reorderKeepsCurrentEntryStable() throws {
        let first = mediaItem(id: "first", kind: .music)
        let second = mediaItem(id: "second", kind: .music)
        let third = mediaItem(id: "third", kind: .music)
        var queue = AuraPlayPlaybackQueue()
        queue.replaceQueue(with: [first, second, third], startAt: 1, origin: .playlist(id: "mix"))
        let currentID = try #require(queue.currentEntryID)

        let didReorder = queue.reorder(entryID: currentID, toIndex: 0)

        #expect(didReorder)
        #expect(queue.currentEntryID == currentID)
        #expect(queue.currentIndex == 0)
        #expect(queue.currentItem?.id == "second")
    }

    @Test("advance records bounded history and stops at boundary")
    func advanceRecordsBoundedHistory() {
        var queue = AuraPlayPlaybackQueue()
        let items = (0..<60).map { mediaItem(id: "track-\($0)", kind: .music) }
        queue.replaceQueue(with: items, startAt: 0, origin: .playlist(id: "long"))

        for _ in 0..<59 {
            let advanced = queue.advance()
            #expect(advanced != nil)
        }

        let boundaryAdvance = queue.advance()
        #expect(boundaryAdvance == nil)
        #expect(queue.history.count == 50)
        #expect(queue.history.first?.item.id == "track-9")
    }

    @Test("audio to video handoff awaits audio stop before video load")
    func audioToVideoHandoffAwaitsAudioStopBeforeVideoLoad() async throws {
        let recorder = CallRecorder()
        let audio = MockPlaybackEngine(kind: .audio, recorder: recorder)
        let video = MockPlaybackEngine(kind: .video, recorder: recorder)
        let orchestrator = PlaybackOrchestrator(
            arbiter: EngineArbiter(audioController: audio, videoController: video)
        )

        _ = await orchestrator.play(item: mediaItem(id: "song", kind: .music))
        _ = await orchestrator.play(item: mediaItem(id: "clip", kind: .video))

        let events = recorder.events
        #expect(events.contains("audio.stop"))
        #expect(events.contains("video.load.clip"))
        let stopIndex = try #require(events.firstIndex(of: "audio.stop"))
        let videoLoadIndex = try #require(events.firstIndex(of: "video.load.clip"))
        #expect(stopIndex < videoLoadIndex)
    }

    @Test("generation token discards stale load under real async timing")
    func generationTokenDiscardsStaleLoad() async {
        let recorder = CallRecorder()
        let audio = MockPlaybackEngine(kind: .audio, recorder: recorder, loadDelayNanoseconds: 200_000_000)
        let video = MockPlaybackEngine(kind: .video, recorder: recorder)
        let orchestrator = PlaybackOrchestrator(
            arbiter: EngineArbiter(audioController: audio, videoController: video)
        )

        async let staleResult: Bool = orchestrator.play(item: mediaItem(id: "slow-audio", kind: .music))
        try? await Task.sleep(nanoseconds: 50_000_000)
        let freshResult = await orchestrator.play(item: mediaItem(id: "video", kind: .video))
        let stale = await staleResult

        #expect(stale == false)
        #expect(freshResult)
        #expect(audio.recordedCommands.contains("play") == false)
        #expect(orchestrator.state == .playing(mediaItem(id: "video", kind: .video)))
    }

    @Test("remote commands map to orchestrator actions")
    func remoteCommandsMapToOrchestratorActions() async {
        let recorder = CallRecorder()
        let audio = MockPlaybackEngine(kind: .audio, recorder: recorder)
        let video = MockPlaybackEngine(kind: .video, recorder: recorder)
        let orchestrator = PlaybackOrchestrator(
            arbiter: EngineArbiter(audioController: audio, videoController: video)
        )
        let coordinator = RemoteCommandCoordinator(orchestrator: orchestrator)
        _ = await orchestrator.play(item: mediaItem(id: "song", kind: .music))

        await coordinator.dispatch(.pause)
        #expect(orchestrator.state == .paused(mediaItem(id: "song", kind: .music)))

        await coordinator.dispatch(.play)
        #expect(orchestrator.state == .playing(mediaItem(id: "song", kind: .music)))

        await coordinator.dispatch(.skipForward(15))
        #expect(audio.recordedCommands.contains("seek.15.0"))

        await coordinator.dispatch(.changePlaybackPosition(42))
        #expect(audio.recordedCommands.contains("seek.42.0"))
    }

    @Test("remote command coordinator covers every command case")
    func remoteCommandCoordinatorCoversEveryCommandCase() async throws {
        let recorder = CallRecorder()
        let audio = MockPlaybackEngine(kind: .audio, recorder: recorder)
        let video = MockPlaybackEngine(kind: .video, recorder: recorder)
        let first = mediaItem(id: "first", kind: .music)
        let second = mediaItem(id: "second", kind: .music)
        let orchestrator = PlaybackOrchestrator(
            arbiter: EngineArbiter(audioController: audio, videoController: video)
        )
        let coordinator = RemoteCommandCoordinator(orchestrator: orchestrator)

        _ = await orchestrator.play(item: first, queue: [first, second], startAt: 0, origin: .playlist(id: "remote"))
        await coordinator.dispatch(.pause)
        await coordinator.dispatch(.play)
        await coordinator.dispatch(.togglePlayPause)
        await coordinator.dispatch(.togglePlayPause)
        audio.setTick(PlaybackTick(currentSeconds: 30, durationSeconds: 120))
        await coordinator.dispatch(.skipForward(15))
        await coordinator.dispatch(.skipBackward(10))
        await coordinator.dispatch(.changePlaybackPosition(42))
        await coordinator.dispatch(.next)
        await coordinator.dispatch(.previous)

        #expect(audio.recordedCommands.contains("pause"))
        #expect(audio.recordedCommands.filter { $0 == "play" }.count >= 3)
        #expect(audio.recordedCommands.contains("seek.45.0"))
        #expect(audio.recordedCommands.contains("seek.35.0"))
        #expect(audio.recordedCommands.contains("seek.42.0"))
        #expect(orchestrator.queue.currentItem?.id == "first")
    }

    @Test("audio playback start prepares the next queue item")
    func audioPlaybackStartPreparesNextQueueItem() async {
        let recorder = CallRecorder()
        let audio = MockPlaybackEngine(kind: .audio, recorder: recorder)
        let video = MockPlaybackEngine(kind: .video, recorder: recorder)
        var preparedIDs: [String] = []
        let advanceCoordinator = QueueAdvanceCoordinator { item in
            preparedIDs.append(item.id)
        }
        let first = mediaItem(id: "first", kind: .music)
        let second = mediaItem(id: "second", kind: .music)
        let orchestrator = PlaybackOrchestrator(
            arbiter: EngineArbiter(audioController: audio, videoController: video),
            queueAdvanceCoordinator: advanceCoordinator
        )

        _ = await orchestrator.play(item: first, queue: [first, second], startAt: 0, origin: .playlist(id: "gapless"))

        #expect(preparedIDs == ["second"])
    }

    @Test("repeat all restarts an exhausted queue at first entry")
    func repeatAllRestartsExhaustedQueue() async {
        let recorder = CallRecorder()
        let audio = MockPlaybackEngine(kind: .audio, recorder: recorder)
        let video = MockPlaybackEngine(kind: .video, recorder: recorder)
        let orchestrator = PlaybackOrchestrator(
            arbiter: EngineArbiter(audioController: audio, videoController: video)
        )
        let first = mediaItem(id: "first", kind: .music)
        let second = mediaItem(id: "second", kind: .music)

        _ = await orchestrator.play(item: first, queue: [first, second], startAt: 0, origin: .playlist(id: "loop"))
        orchestrator.setRepeatMode(.all)
        await orchestrator.skipToNext()
        await orchestrator.skipToNext()

        #expect(orchestrator.queue.currentItem?.id == "first")
        #expect(orchestrator.state == .playing(first))
    }

    @Test("repeat one replays the same queue entry without advancing")
    func repeatOneReplaysSameQueueEntry() async throws {
        let recorder = CallRecorder()
        let audio = MockPlaybackEngine(kind: .audio, recorder: recorder)
        let video = MockPlaybackEngine(kind: .video, recorder: recorder)
        let orchestrator = PlaybackOrchestrator(
            arbiter: EngineArbiter(audioController: audio, videoController: video)
        )
        let first = mediaItem(id: "first", kind: .music)
        let second = mediaItem(id: "second", kind: .music)

        _ = await orchestrator.play(item: first, queue: [first, second], startAt: 0, origin: .playlist(id: "loop"))
        let currentEntryID = try #require(orchestrator.queue.currentEntryID)
        orchestrator.setRepeatMode(.one)

        await orchestrator.skipToNext()
        await orchestrator.skipToNext()
        await orchestrator.skipToNext()

        #expect(orchestrator.queue.currentEntryID == currentEntryID)
        #expect(orchestrator.queue.currentItem?.id == "first")
        #expect(audio.recordedCommands.filter { $0 == "play" }.count == 4)
    }

    @Test("shuffle uses queue entry identity without mutating duplicated media order")
    func shuffleUsesQueueEntryIdentityForDuplicateMedia() throws {
        let duplicate = mediaItem(id: "duplicate", kind: .music)
        let unique = mediaItem(id: "unique", kind: .music)
        var queue = AuraPlayPlaybackQueue()
        queue.replaceQueue(with: [duplicate, unique, duplicate], startAt: 0, origin: .playlist(id: "mix"))
        var shuffle = ShuffleCoordinator()
        let originalEntryIDs = queue.entries.map(\.id)
        let duplicateEntryIDs = queue.entries.filter { $0.item.id == "duplicate" }.map(\.id)

        shuffle.setMode(.on, queue: queue)

        #expect(queue.entries.map(\.id) == originalEntryIDs)
        #expect(Set(duplicateEntryIDs).count == 2)
        #expect(shuffle.shuffledOrder.count == queue.entries.count)
        #expect(Set(shuffle.shuffledOrder) == Set(originalEntryIDs))
        #expect(shuffle.shuffledOrder.first == queue.currentEntryID)
    }

    @Test("plain shuffle keeps the existing random coordinator path when Smart Shuffle is disabled")
    func plainShuffleKeepsExistingCoordinatorPathWhenSmartShuffleDisabled() throws {
        let queueSource = try String(
            contentsOf: sourceFileURL(relativePath: "Auralis/MusicApp/AuraPlay/Services/AuraPlayPlaybackQueue.swift"),
            encoding: .utf8
        )
        let orchestratorSource = try String(
            contentsOf: sourceFileURL(relativePath: "Auralis/MusicApp/AuraPlay/Services/AuraPlayPlaybackOrchestration.swift"),
            encoding: .utf8
        )

        #expect(queueSource.contains("if smartHistory.isEmpty"))
        #expect(queueSource.contains("remainingEntries.map(\\.id).shuffled()"))
        #expect(queueSource.contains("SmartShuffleWeighting.orderedItems"))
        #expect(orchestratorSource.contains("smartHistory: isSmartShuffleEnabled ? smartShuffleHistory : [:]"))
    }

    @Test("Smart Shuffle repeat all rebuilds the weighted order with a fresh seed")
    func smartShuffleRepeatAllRebuildsWeightedOrderWithFreshSeed() async {
        let recorder = CallRecorder()
        let audio = MockPlaybackEngine(kind: .audio, recorder: recorder)
        let video = MockPlaybackEngine(kind: .video, recorder: recorder)
        let orchestrator = PlaybackOrchestrator(
            arbiter: EngineArbiter(audioController: audio, videoController: video)
        )
        let items = (0..<8).map { mediaItem(id: "smart-\($0)", kind: .music) }
        let history = items.dropFirst(4).map {
            SmartShufflePlaybackHistory(
                mediaID: $0.id,
                lastPlayedAt: Date(timeIntervalSince1970: 1_800_000_000).addingTimeInterval(-60),
                playCount: 4
            )
        }

        _ = await orchestrator.play(item: items[0], queue: items, startAt: 0, origin: .playlist(id: "smart-loop"))
        orchestrator.setRepeatMode(.all)
        orchestrator.setShuffleMode(.on)
        orchestrator.setSmartShuffleEnabled(
            true,
            history: history,
            now: Date(timeIntervalSince1970: 1_800_000_000)
        )
        let firstOrder = orchestrator.shuffleCoordinator.shuffledOrder

        for _ in 0..<items.count {
            await orchestrator.skipToNext()
        }

        #expect(orchestrator.shuffleCoordinator.shuffledOrder.count == firstOrder.count)
        #expect(Set(orchestrator.shuffleCoordinator.shuffledOrder) == Set(firstOrder))
        #expect(orchestrator.shuffleCoordinator.shuffledOrder != firstOrder)
        #expect(orchestrator.state != .idle)
    }

    @Test("playback state service writes, completes, and restores most recent state")
    func playbackStateServiceWritesCompletesAndRestores() async throws {
        let container = try AuraPlayModelContainer.make(inMemory: true)
        let context = ModelContext(container)
        let service = AuraPlayPlaybackPositionStateService(modelContainer: container)
        let firstDate = Date(timeIntervalSince1970: 1_704_067_200)
        let secondDate = firstDate.addingTimeInterval(60)

        try await service.writePosition(
            mediaID: "song",
            positionMilliseconds: 12_000,
            durationMilliseconds: 120_000,
            at: firstDate
        )
        try await service.writePosition(
            mediaID: "video",
            positionMilliseconds: 30_000,
            durationMilliseconds: 180_000,
            at: secondDate
        )
        try await service.markCompleted(mediaID: "song", at: secondDate.addingTimeInterval(60))

        let rows = try context.fetch(FetchDescriptor<AuraPlayPlaybackPositionState>())
        #expect(rows.count == 2)
        let song = try #require(rows.first { $0.mediaID == "song" })
        #expect(song.positionMilliseconds == 0)
        #expect(song.completedAt != nil)

        let recent = try await service.mostRecentPlaybackState()
        #expect(recent?.mediaID == "song")
        #expect(recent?.positionMilliseconds == 0)
    }

    @Test("position persistence coordinator writes a single path for audio and video")
    func positionPersistenceCoordinatorWritesSinglePath() async throws {
        let store = InMemoryPlaybackStateStore()
        let coordinator = PositionPersistenceCoordinator(
            store: store,
            now: { Date(timeIntervalSince1970: 1_704_067_200) }
        )

        try await coordinator.writePosition(
            mediaID: "audio",
            tick: PlaybackTick(currentSeconds: 5.4, durationSeconds: 100)
        )
        try await coordinator.writePosition(
            mediaID: "video",
            tick: PlaybackTick(currentSeconds: 10.1, durationSeconds: 200)
        )
        try await coordinator.markCompleted(mediaID: "audio")

        let snapshots = await store.snapshots
        #expect(snapshots["audio"]?.positionMilliseconds == 0)
        #expect(snapshots["video"]?.positionMilliseconds == 10_100)
    }

    @Test("orchestrator writes, completes, and restores through position coordinator")
    func orchestratorWritesCompletesAndRestoresThroughPositionCoordinator() async throws {
        let store = InMemoryPlaybackStateStore()
        let coordinator = PositionPersistenceCoordinator(
            store: store,
            now: { Date(timeIntervalSince1970: 1_704_067_200) }
        )
        let recorder = CallRecorder()
        let audio = MockPlaybackEngine(kind: .audio, recorder: recorder)
        let video = MockPlaybackEngine(kind: .video, recorder: recorder)
        let item = mediaItem(id: "song", kind: .music)
        let orchestrator = PlaybackOrchestrator(
            arbiter: EngineArbiter(audioController: audio, videoController: video),
            positionPersistence: coordinator
        )

        _ = await orchestrator.play(item: item)
        audio.setTick(PlaybackTick(currentSeconds: 12.4, durationSeconds: 120))
        await orchestrator.persistPositionIfNeeded()
        await orchestrator.markCurrentItemCompleted()

        var snapshots = await store.snapshots
        #expect(snapshots["song"]?.positionMilliseconds == 0)
        #expect(snapshots["song"]?.completedAt != nil)

        try await store.writePosition(
            mediaID: "song",
            positionMilliseconds: 15_000,
            durationMilliseconds: 120_000,
            at: Date(timeIntervalSince1970: 1_704_067_260)
        )
        let restored = await orchestrator.restoreMostRecent { mediaID in
            mediaID == "song" ? item : nil
        }

        snapshots = await store.snapshots
        #expect(restored)
        #expect(snapshots["song"]?.positionMilliseconds == 15_000)
        #expect(orchestrator.state == .paused(item))
        #expect(orchestrator.queue.origin == .restored)
        #expect(orchestrator.queue.entries.count == 1)
    }

    @Test("More Like This Play All tags the resulting queue with the moreLikeThis origin")
    func moreLikeThisPlayAllTagsQueueOrigin() async {
        let recorder = CallRecorder()
        let audio = MockPlaybackEngine(kind: .audio, recorder: recorder)
        let video = MockPlaybackEngine(kind: .video, recorder: recorder)
        let source = mediaItem(id: "source", kind: .music)
        let similarFirst = mediaItem(id: "similar-1", kind: .music)
        let similarSecond = mediaItem(id: "similar-2", kind: .music)
        let orchestrator = PlaybackOrchestrator(
            arbiter: EngineArbiter(audioController: audio, videoController: video)
        )

        _ = await orchestrator.play(
            item: similarFirst,
            queue: [similarFirst, similarSecond],
            startAt: 0,
            origin: .moreLikeThis(sourceID: source.id)
        )

        #expect(orchestrator.queue.origin == .moreLikeThis(sourceID: "source"))
        #expect(orchestrator.queue.entries.map(\.item.id) == ["similar-1", "similar-2"])
    }

    @Test("library window playback threads the caller origin instead of hardcoding single")
    func libraryWindowThreadsCallerOrigin() throws {
        let runtimeSource = try String(
            contentsOf: sourceFileURL(relativePath: "Auralis/MusicApp/AuraPlay/Services/AuraPlayPlaybackRuntime.swift"),
            encoding: .utf8
        )
        let adapterSource = try String(
            contentsOf: sourceFileURL(relativePath: "Auralis/MusicApp/AuraPlay/Player/AuraPlayOrchestratorAdapter.swift"),
            encoding: .utf8
        )

        // The runtime must accept and forward the queue origin down to the
        // orchestrator rather than always tagging library playback as `.single`.
        #expect(runtimeSource.contains("origin: origin ?? .single(mediaItemID: mediaItem.id)"))
        #expect(runtimeSource.contains("try await playLibraryItem(id: id, in: orderedNFTs, origin: origin)"))
        #expect(runtimeSource.contains("try await loadAndPlay(nft: nft, triggerCause: .userInitiated, origin: origin)"))

        // The adapter must map the presentation origin (including `.moreLikeThis`)
        // and pass it into the runtime window call.
        #expect(adapterSource.contains("origin: mapOrigin(origin, fallbackMediaID: item.id)"))
        #expect(adapterSource.contains("case .moreLikeThis(let sourceID):"))
        #expect(adapterSource.contains("return .moreLikeThis(sourceID: sourceID)"))
    }

    @Test("position cadence writes during playback and pause flushes")
    func positionCadenceWritesDuringPlaybackAndPauseFlushes() async throws {
        let store = InMemoryPlaybackStateStore()
        let coordinator = PositionPersistenceCoordinator(
            store: store,
            now: { Date(timeIntervalSince1970: 1_704_067_200) }
        )
        let recorder = CallRecorder()
        let audio = MockPlaybackEngine(kind: .audio, recorder: recorder)
        let video = MockPlaybackEngine(kind: .video, recorder: recorder)
        let item = mediaItem(id: "cadence", kind: .music)
        let orchestrator = PlaybackOrchestrator(
            arbiter: EngineArbiter(audioController: audio, videoController: video),
            positionPersistence: coordinator,
            positionCadenceNanoseconds: 10_000_000
        )

        _ = await orchestrator.play(item: item)
        audio.setTick(PlaybackTick(currentSeconds: 6, durationSeconds: 120))
        let cadenceWriteArrived = await waitForWrite(
            in: store,
            mediaID: "cadence",
            positionMilliseconds: 6_000
        )
        #expect(cadenceWriteArrived)

        audio.setTick(PlaybackTick(currentSeconds: 12, durationSeconds: 120))
        await orchestrator.pause()

        let pauseWriteArrived = await store.containsWrite(
            mediaID: "cadence",
            positionMilliseconds: 12_000
        )
        #expect(pauseWriteArrived)
    }

    @Test("video wireframe does not write playback state directly")
    func videoWireframeDoesNotWritePlaybackStateDirectly() throws {
        let sourceURL = try sourceFileURL(
            relativePath: "Auralis/MusicApp/AuraPlay/Presentation/AuraPlayVideoWireframeView.swift"
        )
        let source = try String(contentsOf: sourceURL, encoding: .utf8)

        #expect(!source.contains("UserDefaultsMediaPlaybackStateStore"))
        #expect(!source.contains("positionStore.writePosition"))
        #expect(!source.contains("SwiftDataMediaPlaybackStateStore"))
        #expect(!source.contains("VideoRemoteCommandStreamAdapter"))
        #expect(source.contains("auraPlayPersistVideoPositionIfNeeded"))
        #expect(source.contains("auraPlayMarkVideoCompleted"))
    }

    @Test("production AuraPlay video route is wired through the shared runtime")
    func productionAuraPlayVideoRouteUsesSharedRuntime() throws {
        let mainTabSource = try String(
            contentsOf: sourceFileURL(relativePath: "Auralis/Aura/MainTabView.swift"),
            encoding: .utf8
        )
        let videoSource = try String(
            contentsOf: sourceFileURL(relativePath: "Auralis/MusicApp/AuraPlay/Presentation/AuraPlayVideoWireframeView.swift"),
            encoding: .utf8
        )
        let runtimeSource = try String(
            contentsOf: sourceFileURL(relativePath: "Auralis/MusicApp/AuraPlay/Services/AuraPlayPlaybackRuntime.swift"),
            encoding: .utf8
        )

        #expect(mainTabSource.contains("playbackRuntime: playbackRuntime"))
        #expect(videoSource.contains("let playbackRuntime: AuraPlayPlaybackRuntime?"))
        #expect(videoSource.contains("auraPlayPrepareForVideoPlayback(media)"))
        #expect(videoSource.contains("auraPlayRegisterVideoRemoteControls"))
        #expect(videoSource.contains("playbackStateStore: nil"))
        #expect(videoSource.contains("remoteCommandStream: nil"))
        #expect(runtimeSource.contains("protocol AuraPlayVideoRemoteControlling"))
        #expect(runtimeSource.contains("markExternalPlaybackActive"))
        #expect(runtimeSource.contains("dispatchVideoRemoteCommand"))
        #expect(runtimeSource.contains("phase8ActiveEngine"))
        #expect(runtimeSource.contains("configureVideoRouteOpening"))
        #expect(runtimeSource.contains("openVideoPlayer?()"))
    }

    @Test("production AuraPlay audio playback routes through the playback orchestrator")
    func productionAuraPlayAudioRouteUsesPlaybackOrchestrator() throws {
        let runtimeSource = try String(
            contentsOf: sourceFileURL(relativePath: "Auralis/MusicApp/AuraPlay/Services/AuraPlayPlaybackRuntime.swift"),
            encoding: .utf8
        )

        #expect(runtimeSource.contains("private let playbackOrchestrator: PlaybackOrchestrator"))
        #expect(runtimeSource.contains("RuntimeAudioOrchestratorController"))
        #expect(runtimeSource.contains("await playbackOrchestrator.play("))
        // Remote commands must flow through the runtime's richer handler so that
        // cold-launch restored sessions load media before playing and video
        // commands reach the video controls — not straight to the orchestrator.
        #expect(runtimeSource.contains("let events = remoteCommandPublisher.events"))
        #expect(runtimeSource.contains("self?.handleRemoteCommand(event)"))
        #expect(!runtimeSource.contains("remoteCommandCoordinator.bind(to: remoteCommandPublisher)"))
    }
}

@MainActor
private final class MockPlaybackEngine: AuraPlayEngineControlling {
    let kind: EngineKind
    private let recorder: CallRecorder
    private let loadDelayNanoseconds: UInt64
    private(set) var recordedCommands: [String] = []
    private var tick = PlaybackTick(currentSeconds: 0, durationSeconds: nil)

    init(kind: EngineKind, recorder: CallRecorder, loadDelayNanoseconds: UInt64 = 0) {
        self.kind = kind
        self.recorder = recorder
        self.loadDelayNanoseconds = loadDelayNanoseconds
    }

    func load(_ item: AuraPlayableMediaItem) async throws {
        recordedCommands.append("load.\(item.id)")
        recorder.record("\(kind.rawValue).load.\(item.id)")
        if loadDelayNanoseconds > 0 {
            try await Task.sleep(nanoseconds: loadDelayNanoseconds)
        }
        tick = PlaybackTick(currentSeconds: 0, durationSeconds: nil)
    }

    func play() async throws {
        recordedCommands.append("play")
        recorder.record("\(kind.rawValue).play")
    }

    func pause() async {
        recordedCommands.append("pause")
        recorder.record("\(kind.rawValue).pause")
    }

    func stop() async {
        recordedCommands.append("stop")
        recorder.record("\(kind.rawValue).stop")
    }

    func seek(to seconds: TimeInterval) async {
        recordedCommands.append(String(format: "seek.%.1f", seconds))
        recorder.record("\(kind.rawValue).seek")
        tick = PlaybackTick(currentSeconds: seconds, durationSeconds: tick.durationSeconds)
    }

    func currentTick() async -> PlaybackTick {
        tick
    }

    func setTick(_ tick: PlaybackTick) {
        self.tick = tick
    }
}

@MainActor
private final class CallRecorder {
    private(set) var events: [String] = []

    func record(_ event: String) {
        events.append(event)
    }
}

private actor InMemoryPlaybackStateStore: AuraPlayPlaybackStateWriting {
    private(set) var snapshots: [String: AuraPlayPlaybackPositionStateSnapshot] = [:]
    private(set) var writeEvents: [AuraPlayPlaybackPositionStateSnapshot] = []

    func writePosition(
        mediaID: String,
        positionMilliseconds: Int,
        durationMilliseconds: Int?,
        at date: Date
    ) async throws {
        let snapshot = AuraPlayPlaybackPositionStateSnapshot(
            mediaID: mediaID,
            positionMilliseconds: positionMilliseconds,
            durationMilliseconds: durationMilliseconds,
            lastPlayedAt: date,
            completedAt: nil
        )
        snapshots[mediaID] = snapshot
        writeEvents.append(snapshot)
    }

    func markCompleted(mediaID: String, at date: Date) async throws {
        let duration = snapshots[mediaID]?.durationMilliseconds
        let snapshot = AuraPlayPlaybackPositionStateSnapshot(
            mediaID: mediaID,
            positionMilliseconds: 0,
            durationMilliseconds: duration,
            lastPlayedAt: date,
            completedAt: date
        )
        snapshots[mediaID] = snapshot
    }

    func mostRecentPlaybackState() async throws -> AuraPlayPlaybackPositionStateSnapshot? {
        snapshots.values.sorted { $0.lastPlayedAt > $1.lastPlayedAt }.first
    }

    func containsWrite(mediaID: String, positionMilliseconds: Int) -> Bool {
        writeEvents.contains {
            $0.mediaID == mediaID && $0.positionMilliseconds == positionMilliseconds
        }
    }
}

private func mediaItem(id: String, kind: AuraPlayableContentKind) -> AuraPlayableMediaItem {
    AuraPlayableMediaItem(
        id: id,
        sourceURL: URL(fileURLWithPath: "/tmp/\(id).\(kind == .video ? "mp4" : "mp3")"),
        declaredFormat: kind == .video ? "mp4" : "mp3",
        contentKind: kind,
        metadata: MediaMetadata(
            id: id,
            title: id,
            artist: "Aura",
            artworkURL: nil
        )
    )
}

private func sourceFileURL(relativePath: String) throws -> URL {
    var candidate = URL(fileURLWithPath: #filePath)
    while candidate.path != "/" {
        candidate.deleteLastPathComponent()
        let sourceURL = candidate.appendingPathComponent(relativePath)
        if FileManager.default.fileExists(atPath: sourceURL.path) {
            return sourceURL
        }
    }
    throw CocoaError(.fileNoSuchFile)
}

private func waitForWrite(
    in store: InMemoryPlaybackStateStore,
    mediaID: String,
    positionMilliseconds: Int
) async -> Bool {
    for _ in 0..<50 {
        if await store.containsWrite(mediaID: mediaID, positionMilliseconds: positionMilliseconds) {
            return true
        }
        try? await Task.sleep(nanoseconds: 10_000_000)
    }
    return false
}
