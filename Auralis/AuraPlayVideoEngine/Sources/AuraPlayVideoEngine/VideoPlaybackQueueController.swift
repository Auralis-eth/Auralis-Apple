import Foundation

public struct VideoQueueSnapshot: Equatable, Sendable {
    public let currentIndex: Int?
    public let count: Int
    public let currentMediaID: String?

    public init(currentIndex: Int?, count: Int, currentMediaID: String?) {
        self.currentIndex = currentIndex
        self.count = count
        self.currentMediaID = currentMediaID
    }
}

public enum VideoQueueEvent: Equatable, Sendable {
    case snapshotChanged(VideoQueueSnapshot)
    case advanced(VideoQueueSnapshot)
    case exhausted
}

/// Advances a list of media through one `VideoPlayerControlling` instance.
///
/// Queue advancement loads each item's resolved URL directly on the controller.
/// It deliberately does not call `VideoPlaybackIntegrationCoordinator.load(media:)`,
/// so per-item media-session configuration and stored-position restore do not run.
/// Hosts that want resume-from-position or session reconfiguration per queue item
/// should observe `events` and route `.advanced` through their integration
/// coordinator instead of relying on the automatic load.
@MainActor
public final class VideoPlaybackQueueController {
    public let events: AsyncStream<VideoQueueEvent>

    private let controller: any VideoPlayerControlling
    private let continuation: AsyncStream<VideoQueueEvent>.Continuation
    private var items: [any VideoPlayableMedia]
    private var currentIndex: Int?
    private var observationTask: Task<Void, Never>?

    public init(controller: any VideoPlayerControlling, items: [any VideoPlayableMedia] = []) {
        self.controller = controller
        self.items = items

        var continuation: AsyncStream<VideoQueueEvent>.Continuation!
        self.events = AsyncStream { continuation = $0 }
        self.continuation = continuation
    }

    deinit {
        observationTask?.cancel()
        continuation.finish()
    }

    public var snapshot: VideoQueueSnapshot {
        VideoQueueSnapshot(
            currentIndex: currentIndex,
            count: items.count,
            currentMediaID: currentIndex.flatMap { items[safe: $0]?.videoMediaID }
        )
    }

    public func replaceQueue(with items: [any VideoPlayableMedia], startIndex: Int = 0) async throws {
        self.items = items
        guard items.indices.contains(startIndex) else {
            currentIndex = nil
            continuation.yield(.snapshotChanged(snapshot))
            return
        }

        currentIndex = startIndex
        continuation.yield(.snapshotChanged(snapshot))
        try await loadCurrentItem()
    }

    public func startObservingCompletion() {
        guard observationTask == nil else { return }
        let events = controller.events
        observationTask = Task { [weak self] in
            for await event in events {
                if Task.isCancelled { return }
                if event == .didPlayToEnd {
                    guard let self else { return }
                    _ = try? await self.advanceToNext()
                }
            }
        }
    }

    public func stopObservingCompletion() {
        observationTask?.cancel()
        observationTask = nil
    }

    @discardableResult
    public func advanceToNext() async throws -> Bool {
        guard let currentIndex else { return false }
        let nextIndex = currentIndex + 1
        guard items.indices.contains(nextIndex) else {
            continuation.yield(.exhausted)
            return false
        }

        self.currentIndex = nextIndex
        try await loadCurrentItem()
        continuation.yield(.advanced(snapshot))
        return true
    }

    @discardableResult
    public func moveToPrevious() async throws -> Bool {
        guard let currentIndex else { return false }
        let previousIndex = currentIndex - 1
        guard items.indices.contains(previousIndex) else { return false }

        self.currentIndex = previousIndex
        try await loadCurrentItem()
        continuation.yield(.advanced(snapshot))
        return true
    }

    private func loadCurrentItem() async throws {
        guard let currentIndex, let item = items[safe: currentIndex] else { return }
        try await controller.load(resolvedURL: item.resolvedPlaybackURL)
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
