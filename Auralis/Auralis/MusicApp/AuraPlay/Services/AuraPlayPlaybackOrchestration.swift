import AuraPlayMediaCore
import Foundation
import MusicFeature
import Observation

private let auraPlayRemoteSkipInterval: TimeInterval = 15

enum EngineKind: String, Equatable, Sendable {
    case audio
    case video

    init(item: AuraPlayableMediaItem) {
        self = item.contentKind == .video ? .video : .audio
    }
}

enum OrchestratorState: Sendable {
    case idle
    case loading(AuraPlayableMediaItem)
    case playing(AuraPlayableMediaItem)
    case paused(AuraPlayableMediaItem)
    case buffering(AuraPlayableMediaItem)
    case failed(AuraPlayableMediaItem, String)
}

extension OrchestratorState: Equatable {
    static func == (lhs: OrchestratorState, rhs: OrchestratorState) -> Bool {
        switch (lhs, rhs) {
        case (.idle, .idle):
            true
        case let (.loading(lhsItem), .loading(rhsItem)),
             let (.playing(lhsItem), .playing(rhsItem)),
             let (.paused(lhsItem), .paused(rhsItem)),
             let (.buffering(lhsItem), .buffering(rhsItem)):
            lhsItem.id == rhsItem.id
        case let (.failed(lhsItem, lhsMessage), .failed(rhsItem, rhsMessage)):
            lhsItem.id == rhsItem.id && lhsMessage == rhsMessage
        default:
            false
        }
    }
}

struct PlaybackFailureNotice: Equatable, Identifiable, Sendable {
    let id: UUID
    let message: String
    let isPersistent: Bool

    init(id: UUID = UUID(), message: String, isPersistent: Bool) {
        self.id = id
        self.message = message
        self.isPersistent = isPersistent
    }
}

protocol EngineTimeSource: Sendable {
    func currentTick() async -> PlaybackTick
}

@MainActor
protocol AuraPlayEngineControlling: AnyObject {
    var kind: EngineKind { get }
    var recordedCommands: [String] { get }

    func load(_ item: AuraPlayableMediaItem) async throws
    func play() async throws
    func pause() async
    func stop() async
    func seek(to seconds: TimeInterval) async
    func currentTick() async -> PlaybackTick
}

@MainActor
final class EngineArbiter {
    private let audioController: any AuraPlayEngineControlling
    private let videoController: any AuraPlayEngineControlling
    private(set) var activeEngine: EngineKind?

    init(
        audioController: any AuraPlayEngineControlling,
        videoController: any AuraPlayEngineControlling
    ) {
        self.audioController = audioController
        self.videoController = videoController
    }

    func controller(for engine: EngineKind) -> any AuraPlayEngineControlling {
        switch engine {
        case .audio:
            audioController
        case .video:
            videoController
        }
    }

    func activate(
        engine requestedEngine: EngineKind,
        for item: AuraPlayableMediaItem,
        generation: Int,
        isCurrentGeneration: @MainActor (Int) -> Bool
    ) async throws -> Bool {
        if let activeEngine, activeEngine != requestedEngine {
            await controller(for: activeEngine).stop()
            guard isCurrentGeneration(generation) else { return false }
        }

        let controller = controller(for: requestedEngine)
        try await controller.load(item)
        guard isCurrentGeneration(generation) else { return false }
        try await controller.play()
        guard isCurrentGeneration(generation) else {
            await controller.stop()
            return false
        }

        activeEngine = requestedEngine
        return true
    }

    func pauseActiveEngine() async {
        guard let activeEngine else { return }
        await controller(for: activeEngine).pause()
    }

    func resumeActiveEngine() async throws {
        guard let activeEngine else { return }
        try await controller(for: activeEngine).play()
    }

    func stopActiveEngine() async {
        guard let activeEngine else { return }
        await controller(for: activeEngine).stop()
        self.activeEngine = nil
    }

    func seekActiveEngine(to seconds: TimeInterval) async {
        guard let activeEngine else { return }
        await controller(for: activeEngine).seek(to: seconds)
    }

    func currentTick() async -> PlaybackTick {
        guard let activeEngine else {
            return PlaybackTick(currentSeconds: 0, durationSeconds: nil)
        }
        return await controller(for: activeEngine).currentTick()
    }
}

@MainActor
@Observable
final class PlaybackOrchestrator {
    private let arbiter: EngineArbiter
    private let positionPersistence: PositionPersistenceCoordinator?
    private let queueAdvanceCoordinator: QueueAdvanceCoordinator?
    private let positionCadenceNanoseconds: UInt64
    private var playbackGeneration = 0
    private var positionCadenceTask: Task<Void, Never>?
    private var isSmartShuffleEnabled = false
    private var smartShuffleHistory: [String: SmartShufflePlaybackHistory] = [:]
    private var shuffleSeed: UInt64 = 0

    private(set) var state: OrchestratorState = .idle
    private(set) var queue = AuraPlayPlaybackQueue()
    private(set) var repeatMode: AuraPlayRepeatMode = .off
    private(set) var shuffleCoordinator = ShuffleCoordinator()
    var failureNotice: PlaybackFailureNotice?

    var currentEngine: EngineKind? {
        switch state {
        case .idle:
            nil
        case .loading(let item), .playing(let item), .paused(let item), .buffering(let item), .failed(let item, _):
            EngineKind(item: item)
        }
    }

    /// False after a cold-launch restore: the state is `.paused` but no engine
    /// has loaded media yet, so resume must go through the full play path.
    var hasActiveEngine: Bool {
        arbiter.activeEngine != nil
    }

    init(
        arbiter: EngineArbiter,
        positionPersistence: PositionPersistenceCoordinator? = nil,
        queueAdvanceCoordinator: QueueAdvanceCoordinator? = nil,
        positionCadenceNanoseconds: UInt64 = 5_000_000_000
    ) {
        self.arbiter = arbiter
        self.positionPersistence = positionPersistence
        self.queueAdvanceCoordinator = queueAdvanceCoordinator
        self.positionCadenceNanoseconds = positionCadenceNanoseconds
    }

    @discardableResult
    func play(
        item: AuraPlayableMediaItem,
        queue items: [AuraPlayableMediaItem]? = nil,
        startAt index: Int = 0,
        origin: QueueOrigin? = nil,
        flushExistingPosition: Bool = true
    ) async -> Bool {
        if flushExistingPosition {
            await flushPositionForCurrentItem()
        }
        stopPositionCadence()
        playbackGeneration += 1
        let generation = playbackGeneration

        if let items {
            self.queue.replaceQueue(
                with: items,
                startAt: index,
                origin: origin ?? .single(mediaItemID: item.id)
            )
        } else if self.queue.currentItem?.id != item.id {
            self.queue.replaceQueue(
                with: [item],
                startAt: 0,
                origin: origin ?? .single(mediaItemID: item.id)
            )
        }

        mutateState(.loading(item))

        do {
            let engine = EngineKind(item: item)
            let didActivate = try await arbiter.activate(
                engine: engine,
                for: item,
                generation: generation,
                isCurrentGeneration: { [weak self] capturedGeneration in
                    self?.playbackGeneration == capturedGeneration
                }
            )
            guard didActivate, generation == playbackGeneration else { return false }
            mutateState(.playing(item))
            failureNotice = nil
            await queueAdvanceCoordinator?.playbackDidStart(queue: queue, engine: engine)
            startPositionCadence(for: item.id, generation: generation)
            return true
        } catch {
            guard generation == playbackGeneration else { return false }
            mutateState(.failed(item, Self.userFacingMessage(for: error)))
            return false
        }
    }

    func togglePlayPause() async {
        switch state {
        case .playing:
            await pause()
        case .paused:
            try? await resume()
        default:
            break
        }
    }

    func pause() async {
        guard case .playing(let item) = state else { return }
        await arbiter.pauseActiveEngine()
        mutateState(.paused(item))
        stopPositionCadence()
        await flushPosition(for: item.id)
    }

    func resume() async throws {
        guard case .paused(let item) = state else { return }
        try await arbiter.resumeActiveEngine()
        mutateState(.playing(item))
        startPositionCadence(for: item.id, generation: playbackGeneration)
    }

    func stop(flushPosition: Bool = true) async {
        playbackGeneration += 1
        stopPositionCadence()
        if flushPosition {
            await flushPositionForCurrentItem()
        }
        await arbiter.stopActiveEngine()
        mutateState(.idle)
    }

    func skipToNext() async {
        await flushPositionForCurrentItem()
        let nextEntry = nextEntryForAdvance()
        guard let nextEntry else {
            await stop()
            return
        }
        await play(item: nextEntry.item, flushExistingPosition: false)
    }

    func skipToPrevious(restartThreshold: TimeInterval = 3) async {
        let tick = await arbiter.currentTick()
        if tick.currentSeconds > restartThreshold {
            await seek(to: 0)
            return
        }
        await flushPositionForCurrentItem()
        guard let previous = queue.retreat() else {
            await seek(to: 0)
            return
        }
        await play(item: previous.item, flushExistingPosition: false)
    }

    func seek(to seconds: TimeInterval) async {
        await arbiter.seekActiveEngine(to: max(0, seconds))
    }

    func currentPosition() async -> TimeInterval {
        await arbiter.currentTick().currentSeconds
    }

    func setRepeatMode(_ mode: AuraPlayRepeatMode) {
        repeatMode = mode
    }

    func setShuffleMode(_ mode: AuraPlayShuffleMode) {
        shuffleCoordinator.setMode(mode, queue: queue)
        rebuildShuffleOrderIfNeeded()
    }

    func setSmartShuffleEnabled(
        _ isEnabled: Bool,
        history: [SmartShufflePlaybackHistory],
        now: Date = .now
    ) {
        isSmartShuffleEnabled = isEnabled
        smartShuffleHistory = Dictionary(
            history.map { ($0.mediaID, $0) },
            uniquingKeysWith: { current, _ in current }
        )
        rebuildShuffleOrderIfNeeded(now: now)
    }

    func restorePaused(item: AuraPlayableMediaItem, position: AuraPlayPlaybackPositionStateSnapshot) {
        queue.replaceQueue(with: [item], startAt: 0, origin: .restored)
        mutateState(.paused(item))
        failureNotice = position.isResumable ? nil : failureNotice
    }

    func markExternalPlaybackActive(
        item: AuraPlayableMediaItem,
        origin: QueueOrigin
    ) {
        playbackGeneration += 1
        stopPositionCadence()
        queue.replaceQueue(with: [item], startAt: 0, origin: origin)
        mutateState(.playing(item))
    }

    @discardableResult
    func restoreMostRecent(
        resolveMedia: @MainActor @Sendable (String) async -> AuraPlayableMediaItem?
    ) async -> Bool {
        guard let candidate = try? await positionPersistence?.restoreCandidate(),
              let item = await resolveMedia(candidate.mediaID) else {
            mutateState(.idle)
            return false
        }
        restorePaused(item: item, position: candidate)
        return true
    }

    func markCurrentItemCompleted() async {
        guard let item = queue.currentItem else { return }
        stopPositionCadence()
        try? await positionPersistence?.markCompleted(mediaID: item.id)
    }

    func flushPositionForCurrentItem() async {
        guard let item = queue.currentItem else { return }
        await flushPosition(for: item.id)
    }

    func persistPositionIfNeeded() async {
        guard case .playing(let item) = state else { return }
        await flushPosition(for: item.id)
    }

    private func mutateState(_ nextState: OrchestratorState) {
        MainActor.assertIsolated()
        state = nextState
    }

    private func startPositionCadence(for mediaID: String, generation: Int) {
        guard positionPersistence != nil else { return }
        stopPositionCadence()
        positionCadenceTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: self?.positionCadenceNanoseconds ?? 5_000_000_000)
                guard !Task.isCancelled else { return }
                guard let self, self.playbackGeneration == generation else { return }
                await self.flushPosition(for: mediaID)
            }
        }
    }

    private func stopPositionCadence() {
        positionCadenceTask?.cancel()
        positionCadenceTask = nil
    }

    private func flushPosition(for mediaID: String) async {
        guard let positionPersistence else { return }
        let tick = await arbiter.currentTick()
        try? await positionPersistence.writePosition(mediaID: mediaID, tick: tick)
    }

    private func nextEntryForAdvance() -> QueueEntry? {
        if repeatMode == .one {
            return queue.currentEntry
        }
        if shuffleCoordinator.mode == .on {
            if let currentEntryID = queue.currentEntryID,
               let shuffledNext = shuffleCoordinator.nextEntry(after: currentEntryID, queue: queue) {
                return queue.moveTo(entryID: shuffledNext.id)
            }
            if repeatMode == .all {
                queue.restartFromBeginning()
                rebuildShuffleOrderIfNeeded(advanceSeed: true)
                return queue.currentEntry
            }
            return nil
        }

        let nextEntry = queue.advance()
        if nextEntry == nil, repeatMode == .all {
            queue.restartFromBeginning()
            return queue.currentEntry
        }
        return nextEntry
    }

    private func rebuildShuffleOrderIfNeeded(now: Date = .now, advanceSeed: Bool = false) {
        guard shuffleCoordinator.mode == .on else { return }
        if advanceSeed {
            shuffleSeed &+= 1
        }
        shuffleCoordinator.rebuildOrder(
            queue: queue,
            smartHistory: isSmartShuffleEnabled ? smartShuffleHistory : [:],
            now: now,
            seed: shuffleSeed
        )
    }

    private static func userFacingMessage(for error: Error) -> String {
        if let auraPlayError = error as? MusicFeature.AuraPlayError {
            return auraPlayError.localizedDescription
        }
        return "Could not play this item. Choose another track or try again."
    }
}

@MainActor
final class QueueAdvanceCoordinator {
    private let prepareNext: @MainActor (AuraPlayableMediaItem) async -> Void

    init(prepareNext: @escaping @MainActor (AuraPlayableMediaItem) async -> Void) {
        self.prepareNext = prepareNext
    }

    func playbackDidStart(queue: AuraPlayPlaybackQueue, engine: EngineKind) async {
        guard engine == .audio, let nextEntry = queue.peekNext() else {
            return
        }
        await prepareNext(nextEntry.item)
    }
}

@MainActor
final class RemoteCommandCoordinator {
    private let orchestrator: PlaybackOrchestrator
    private var task: Task<Void, Never>?

    init(orchestrator: PlaybackOrchestrator) {
        self.orchestrator = orchestrator
    }

    deinit {
        task?.cancel()
    }

    func bind(to publisher: any RemoteCommandPublishing) {
        guard task == nil else { return }
        let events = publisher.events
        task = Task { [weak self] in
            for await event in events {
                guard !Task.isCancelled else { return }
                await self?.dispatch(event)
            }
        }
    }

    func dispatch(_ event: RemoteCommandEvent) async {
        switch event {
        case .play:
            try? await orchestrator.resume()
        case .pause:
            await orchestrator.pause()
        case .togglePlayPause:
            await orchestrator.togglePlayPause()
        case .next:
            await orchestrator.skipToNext()
        case .previous:
            await orchestrator.skipToPrevious()
        case .skipForward(let seconds):
            await seekRelative(by: seconds)
        case .skipBackward(let seconds):
            await seekRelative(by: -seconds)
        case .changePlaybackPosition(let seconds):
            await orchestrator.seek(to: seconds)
        }
    }

    private func seekRelative(by delta: TimeInterval) async {
        await orchestrator.seek(to: max(0, await currentPosition() + delta))
    }

    private func currentPosition() async -> TimeInterval {
        await orchestrator.currentPosition()
    }
}

protocol AuraPlayPlaybackStateWriting: Sendable {
    func writePosition(
        mediaID: String,
        positionMilliseconds: Int,
        durationMilliseconds: Int?,
        at date: Date
    ) async throws
    func markCompleted(mediaID: String, at date: Date) async throws
    func mostRecentPlaybackState() async throws -> AuraPlayPlaybackPositionStateSnapshot?
}

extension AuraPlayPlaybackPositionStateService: AuraPlayPlaybackStateWriting {}

struct PositionPersistenceCoordinator: Sendable {
    let store: any AuraPlayPlaybackStateWriting
    var now: @Sendable () -> Date = Date.init

    func writePosition(mediaID: String, tick: PlaybackTick) async throws {
        try await store.writePosition(
            mediaID: mediaID,
            positionMilliseconds: Int((tick.currentSeconds * 1000).rounded()),
            durationMilliseconds: tick.durationSeconds.map { Int(($0 * 1000).rounded()) },
            at: now()
        )
    }

    func markCompleted(mediaID: String) async throws {
        try await store.markCompleted(mediaID: mediaID, at: now())
    }

    func restoreCandidate() async throws -> AuraPlayPlaybackPositionStateSnapshot? {
        try await store.mostRecentPlaybackState()
    }
}
