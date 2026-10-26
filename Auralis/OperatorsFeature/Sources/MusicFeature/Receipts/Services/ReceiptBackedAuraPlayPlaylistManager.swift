import Foundation

public actor ReceiptBackedAuraPlayPlaylistManager: AuraPlayPlaylistManaging {
    private let base: any AuraPlayPlaylistManaging
    private let receiptLogger: MusicReceiptEventLogger
    private let context: MusicReceiptContext

    public init(
        base: any AuraPlayPlaylistManaging,
        receiptLogger: MusicReceiptEventLogger,
        context: MusicReceiptContext
    ) {
        self.base = base
        self.receiptLogger = receiptLogger
        self.context = context
    }

    public func fetchPlaylistSnapshots() async throws -> [AuraPlayPlaylistSnapshot] {
        try await base.fetchPlaylistSnapshots()
    }

    public func fetchPlaylistSnapshot(id: String) async throws -> AuraPlayPlaylistSnapshot? {
        try await base.fetchPlaylistSnapshot(id: id)
    }

    public func createID(name: String, at date: Date) async throws -> String {
        let id = try await base.createID(name: name, at: date)
        try await recordCreation(id: id)
        return id
    }

    public func createSmartPlaylistID(
        name: String,
        mediaItemIDs: [String],
        smartQueryData: Data,
        at date: Date
    ) async throws -> String {
        let id = try await base.createSmartPlaylistID(
            name: name,
            mediaItemIDs: mediaItemIDs,
            smartQueryData: smartQueryData,
            at: date
        )
        try await recordCreation(id: id)
        return id
    }

    public func rename(id: String, name: String, at date: Date) async throws {
        let before = try await base.fetchPlaylistSnapshot(id: id)
        try await base.rename(id: id, name: name, at: date)
        try await recordModification(id: id, before: before, changedFields: ["name"])
    }

    public func delete(id: String) async throws {
        guard let before = try await base.fetchPlaylistSnapshot(id: id) else {
            try await base.delete(id: id)
            return
        }
        try await base.delete(id: id)
        _ = try await receiptLogger.recordPlaylistDeleted(
            playlistID: id,
            playlistTitle: before.name,
            affectedMediaIDs: before.itemIDs,
            beforeSummary: summary(before),
            context: context
        )
    }

    public func add(mediaItemID: String, toPlaylist playlistID: String, at date: Date) async throws {
        let before = try await base.fetchPlaylistSnapshot(id: playlistID)
        try await base.add(mediaItemID: mediaItemID, toPlaylist: playlistID, at: date)
        try await recordModification(id: playlistID, before: before, changedFields: ["items"])
    }

    public func remove(mediaItemID: String, fromPlaylist playlistID: String, at date: Date) async throws {
        let before = try await base.fetchPlaylistSnapshot(id: playlistID)
        try await base.remove(mediaItemID: mediaItemID, fromPlaylist: playlistID, at: date)
        try await recordModification(id: playlistID, before: before, changedFields: ["items"])
    }

    public func reorderItem(
        playlistID: String,
        fromPosition: Int,
        toPosition: Int,
        at date: Date
    ) async throws {
        let before = try await base.fetchPlaylistSnapshot(id: playlistID)
        try await base.reorderItem(
            playlistID: playlistID,
            fromPosition: fromPosition,
            toPosition: toPosition,
            at: date
        )
        try await recordModification(id: playlistID, before: before, changedFields: ["itemOrder"])
    }

    public func toggle(mediaItemID: String, playlistID: String, at date: Date) async throws {
        let before = try await base.fetchPlaylistSnapshot(id: playlistID)
        try await base.toggle(mediaItemID: mediaItemID, playlistID: playlistID, at: date)
        try await recordModification(id: playlistID, before: before, changedFields: ["items"])
    }

    public func createAndAddID(name: String, mediaItemID: String, at date: Date) async throws -> String {
        let id = try await base.createAndAddID(name: name, mediaItemID: mediaItemID, at: date)
        try await recordCreation(id: id)
        return id
    }

    private func recordCreation(id: String) async throws {
        let snapshot = try await requiredSnapshot(id: id)
        _ = try await receiptLogger.recordPlaylistCreated(
            playlistID: id,
            playlistTitle: snapshot.name,
            affectedMediaIDs: snapshot.itemIDs,
            itemCount: snapshot.itemCount,
            context: context
        )
    }

    private func recordModification(
        id: String,
        before: AuraPlayPlaylistSnapshot?,
        changedFields: [String]
    ) async throws {
        guard let before,
              let after = try await base.fetchPlaylistSnapshot(id: id),
              Self.isSubstantiveChange(from: before, to: after) else {
            return
        }
        _ = try await receiptLogger.recordPlaylistModified(
            playlistID: id,
            playlistTitle: after.name,
            affectedMediaIDs: Array(Set(before.itemIDs + after.itemIDs)).sorted(),
            beforeSummary: summary(before),
            afterSummary: summary(after),
            changedFields: changedFields,
            context: context
        )
    }

    private func requiredSnapshot(id: String) async throws -> AuraPlayPlaylistSnapshot {
        guard let snapshot = try await base.fetchPlaylistSnapshot(id: id) else {
            throw AuraPlayError.library("The playlist was saved but could not be read back.")
        }
        return snapshot
    }

    /// Whether anything a receipt reader would care about actually moved.
    ///
    /// Deliberately not `before != after`: `AuraPlayPlaylistSnapshot` carries `updatedAt`, and the
    /// live service stamps it on every accepted mutation — including ones that change nothing a
    /// reader can see, such as renaming a playlist to the name it already has or reordering an item
    /// onto its own position. Comparing whole snapshots would file a "modified" receipt for those.
    private static func isSubstantiveChange(
        from before: AuraPlayPlaylistSnapshot,
        to after: AuraPlayPlaylistSnapshot
    ) -> Bool {
        before.name != after.name
            || before.itemIDs != after.itemIDs
            || before.coverImageURLString != after.coverImageURLString
            || before.isSmart != after.isSmart
    }

    private func summary(_ snapshot: AuraPlayPlaylistSnapshot) -> MusicReceiptStateSummary {
        .playlist(
            playlistID: snapshot.id,
            playlistTitle: snapshot.name,
            itemCount: snapshot.itemCount
        )
    }
}
