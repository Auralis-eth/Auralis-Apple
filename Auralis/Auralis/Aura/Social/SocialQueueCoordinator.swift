import Foundation
import SocialCore

/// Keeps a session-linked AuraPlay playlist in sync with the session's accepted collaborative queue.
///
/// On each signal (e.g. after the inbound pump appends a relay message, or a local queue mutation is
/// enqueued) it reconciles the linked playlist to the current projected `queueItems`. Reconciliation is
/// idempotent, so a missed or duplicated signal is harmless — the playlist always converges to the
/// projection. The live playlist writes are device/QA-verified via ``AuraPlayPlaylistQueueTarget``.
actor SocialQueueCoordinator {
    private let eventLogStore: SocialEventLogStore
    private let sessionID: UUID
    private let target: any SocialQueuePlaylistTarget
    private let applier: SocialQueueApplier
    private var task: Task<Void, Never>?

    init(
        eventLogStore: SocialEventLogStore,
        sessionID: UUID,
        playlistTarget: any SocialQueuePlaylistTarget,
        applier: SocialQueueApplier = SocialQueueApplier()
    ) {
        self.eventLogStore = eventLogStore
        self.sessionID = sessionID
        self.target = playlistTarget
        self.applier = applier
    }

    /// Reconciles the linked playlist to the session's currently-projected accepted queue.
    func reconcile() async throws {
        try await applier.applyProjectedQueue(from: eventLogStore, sessionID: sessionID, to: target)
    }

    /// Reconciles once now, then again on every element of `signals`, until ``stop()`` or the stream
    /// finishes. Per-reconcile errors are swallowed so one transient playlist-write failure doesn't tear
    /// down the coordinator; the next signal retries from the authoritative projection.
    func start(on signals: AsyncStream<Void>) {
        guard task == nil else { return }
        task = Task { [weak self] in
            try? await self?.reconcile()
            for await _ in signals {
                if Task.isCancelled { break }
                try? await self?.reconcile()
            }
        }
    }

    func stop() {
        task?.cancel()
        task = nil
    }
}
