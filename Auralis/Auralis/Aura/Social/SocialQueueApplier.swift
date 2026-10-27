import Foundation
import AuralisOperators

/// A single playlist as a reorderable list of media items — the seam the queue applier writes through.
/// Abstracted so the applier is unit-testable with an in-memory fake, while the live adapter maps onto
/// the AuraPlay playlist service.
protocol SocialQueuePlaylistTarget: Sendable {
    func currentMediaItemIDs() async throws -> [String]
    func add(mediaItemID: String) async throws
    func remove(mediaItemID: String) async throws
    func move(fromPosition: Int, toPosition: Int) async throws
}

/// Maps an accepted collaborative queue (from the social projection) onto a live AuraPlay playlist.
///
/// Reconciles the target to the queue's ordered, de-duplicated media items: removes tracks no longer
/// queued, adds new ones, then reorders to match. Reconciliation (rather than replaying each mutation)
/// is idempotent, so it can run after every accepted mutation or a recovery snapshot without ever
/// duplicating or dropping a track.
struct SocialQueueApplier {
    /// Reconciles `target` to the ordered media items of `queueItems`.
    func apply(queueItems: [SocialQueueItem], to target: any SocialQueuePlaylistTarget) async throws {
        let desired = orderedUnique(queueItems.map(\.mediaItemID))
        let desiredSet = Set(desired)

        let existing = try await target.currentMediaItemIDs()

        // The target's own list is reconciled by *occurrence count*, not just by membership. The linked
        // session playlist is an ordinary AuraPlay playlist the user can also edit by hand, so it can
        // hold the same media id twice. When only `queueItems` was de-duplicated, a duplicated desired
        // row survived the removal filter and `current.count` stayed above `desired.count` — and the
        // reorder loop is bounded by `desired.indices`, so nothing could ever delete the extra. The
        // playlist diverged from the projection permanently, which the "always converges" contract
        // above forbids.
        //
        // One `remove` call per *excess* occurrence, because the live adapter deletes a single row:
        // `AuraPlayPlaylistService.remove` resolves `items.first(where:)` and deletes that one item. So
        // an id present twice and wanted once needs exactly one call, and an id present twice and no
        // longer wanted needs two.
        var occurrences: [String: Int] = [:]
        for mediaItemID in existing { occurrences[mediaItemID, default: 0] += 1 }

        var removedAny = false
        for (mediaItemID, count) in occurrences {
            let keep = desiredSet.contains(mediaItemID) ? 1 : 0
            guard count > keep else { continue }
            for _ in 0..<(count - keep) {
                try await target.remove(mediaItemID: mediaItemID)
                removedAny = true
            }
        }

        // Re-read rather than predicting locally which row survived. Each `remove` drops the *first*
        // match, so for a duplicated id the surviving copy is the last one — modelling that here means
        // encoding the adapter's deletion semantics in the applier, which is exactly the assumption
        // that was previously wrong. One extra snapshot read makes the reconcile self-correcting.
        var current = removedAny ? try await target.currentMediaItemIDs() : existing

        let currentSet = Set(current)
        for mediaItemID in desired where !currentSet.contains(mediaItemID) {
            try await target.add(mediaItemID: mediaItemID)
            current.append(mediaItemID)
        }

        // Reorder in place until playlist order matches desired (remove-then-insert semantics).
        for targetIndex in desired.indices {
            guard targetIndex < current.count, current[targetIndex] != desired[targetIndex] else { continue }
            guard let fromIndex = current.firstIndex(of: desired[targetIndex]) else { continue }
            try await target.move(fromPosition: fromIndex, toPosition: targetIndex)
            let moved = current.remove(at: fromIndex)
            current.insert(moved, at: targetIndex)
        }
    }

    /// Bridges the social event log to a playlist: reduces the session's accepted queue events into the
    /// projected `queueItems` and reconciles `target` to them.
    func applyProjectedQueue(
        from eventLogStore: SocialEventLogStore,
        sessionID: UUID,
        to target: any SocialQueuePlaylistTarget
    ) async throws {
        let projection = await eventLogStore.projection(sessionID: sessionID)
        try await apply(queueItems: projection.queueItems, to: target)
    }

    private func orderedUnique(_ ids: [String]) -> [String] {
        var seen = Set<String>()
        return ids.filter { seen.insert($0).inserted }
    }
}

/// Live ``SocialQueuePlaylistTarget`` over the AuraPlay playlist service for one playlist. Reads the
/// current order from a playlist snapshot; writes via the service's add/remove/reorder. Thin glue —
/// its runtime behavior against SwiftData is device/QA-verified.
struct AuraPlayPlaylistQueueTarget: SocialQueuePlaylistTarget {
    private let playlistManager: any AuraPlayPlaylistManaging
    private let playlistID: String

    init(playlistManager: any AuraPlayPlaylistManaging, playlistID: String) {
        self.playlistManager = playlistManager
        self.playlistID = playlistID
    }

    func currentMediaItemIDs() async throws -> [String] {
        try await playlistManager.fetchPlaylistSnapshot(id: playlistID)?.itemIDs ?? []
    }

    func add(mediaItemID: String) async throws {
        try await playlistManager.add(mediaItemID: mediaItemID, toPlaylist: playlistID, at: .now)
    }

    func remove(mediaItemID: String) async throws {
        try await playlistManager.remove(mediaItemID: mediaItemID, fromPlaylist: playlistID, at: .now)
    }

    func move(fromPosition: Int, toPosition: Int) async throws {
        try await playlistManager.reorderItem(
            playlistID: playlistID,
            fromPosition: fromPosition,
            toPosition: toPosition,
            at: .now
        )
    }
}
