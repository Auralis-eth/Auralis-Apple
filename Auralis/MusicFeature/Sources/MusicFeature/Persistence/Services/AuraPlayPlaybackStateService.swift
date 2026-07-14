import Foundation
import SwiftData

@ModelActor
public actor AuraPlayPlaybackPositionStateService {
    public func writePosition(
        mediaID: String,
        positionMilliseconds: Int,
        durationMilliseconds: Int?,
        at date: Date = .now
    ) throws {
        let row = try fetchState(mediaID: mediaID) ?? {
            let newRow = AuraPlayPlaybackPositionState(
                mediaID: mediaID,
                positionMilliseconds: 0,
                durationMilliseconds: nil,
                lastPlayedAt: date,
                updatedAt: date
            )
            modelContext.insert(newRow)
            return newRow
        }()

        row.positionMilliseconds = max(0, positionMilliseconds)
        row.durationMilliseconds = durationMilliseconds.map { max(0, $0) }
        row.lastPlayedAt = date
        row.completedAt = nil
        row.updatedAt = date
        try modelContext.save()
    }

    public func markCompleted(mediaID: String, at date: Date = .now) throws {
        let row = try fetchState(mediaID: mediaID) ?? {
            let newRow = AuraPlayPlaybackPositionState(
                mediaID: mediaID,
                positionMilliseconds: 0,
                durationMilliseconds: nil,
                lastPlayedAt: date,
                completedAt: date,
                updatedAt: date
            )
            modelContext.insert(newRow)
            return newRow
        }()

        row.positionMilliseconds = 0
        row.lastPlayedAt = date
        row.completedAt = date
        row.updatedAt = date
        try modelContext.save()
    }

    public func storedPosition(for mediaID: String) throws -> AuraPlayPlaybackPositionStateSnapshot? {
        try fetchState(mediaID: mediaID).map(Self.snapshot(from:))
    }

    public func mostRecentPlaybackState() throws -> AuraPlayPlaybackPositionStateSnapshot? {
        var descriptor = FetchDescriptor<AuraPlayPlaybackPositionState>(
            sortBy: [SortDescriptor(\.lastPlayedAt, order: .reverse)]
        )
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first.map(Self.snapshot(from:))
    }

    private func fetchState(mediaID: String) throws -> AuraPlayPlaybackPositionState? {
        var descriptor = FetchDescriptor<AuraPlayPlaybackPositionState>(
            predicate: #Predicate<AuraPlayPlaybackPositionState> { state in
                state.mediaID == mediaID
            }
        )
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first
    }

    private static func snapshot(from state: AuraPlayPlaybackPositionState) -> AuraPlayPlaybackPositionStateSnapshot {
        AuraPlayPlaybackPositionStateSnapshot(
            mediaID: state.mediaID,
            positionMilliseconds: state.positionMilliseconds,
            durationMilliseconds: state.durationMilliseconds,
            lastPlayedAt: state.lastPlayedAt,
            completedAt: state.completedAt
        )
    }
}
