import AuralisPrimaryModels
import ReceiptsCore

public extension ReceiptEventLogger {
    func recordMusicLibraryIndexStarted(
        accountAddress: String,
        chain: Chain,
        correlationID: String?
    ) async throws -> ReceiptRecord {
        try await append(
            trigger: "music.library_index.started",
            scope: "music.library",
            summary: "Started music library index rebuild",
            provenance: "local_cache",
            timelineAccountAddress: accountAddress,
            timelineChainRawValue: chain.rawValue,
            rawPayload: MusicLibraryIndexStartedReceiptPayload(
                accountAddress: accountAddress,
                chain: chain
            ).rawPayload,
            correlationID: correlationID,
            actor: .system,
            isSuccess: true
        )
    }

    func recordMusicLibraryIndexCompleted(
        accountAddress: String,
        chain: Chain,
        correlationID: String?,
        scannedCount: Int,
        writtenCount: Int,
        removedCount: Int
    ) async throws -> ReceiptRecord {
        try await append(
            trigger: "music.library_index.completed",
            scope: "music.library",
            summary: "Rebuilt music library index",
            provenance: "local_cache",
            timelineAccountAddress: accountAddress,
            timelineChainRawValue: chain.rawValue,
            rawPayload: MusicLibraryIndexCompletedReceiptPayload(
                accountAddress: accountAddress,
                chain: chain,
                scannedCount: scannedCount,
                writtenCount: writtenCount,
                removedCount: removedCount
            ).rawPayload,
            correlationID: correlationID,
            actor: .system,
            isSuccess: true
        )
    }

    func recordMusicLibraryIndexFailed(
        accountAddress: String,
        chain: Chain,
        correlationID: String?,
        error: Error
    ) async throws -> ReceiptRecord {
        try await append(
            trigger: "music.library_index.failed",
            scope: "music.library",
            summary: "Music library index rebuild failed",
            provenance: "local_cache",
            timelineAccountAddress: accountAddress,
            timelineChainRawValue: chain.rawValue,
            rawPayload: MusicLibraryIndexFailedReceiptPayload(
                accountAddress: accountAddress,
                chain: chain,
                errorCode: "musicLibraryIndexFailed"
            ).rawPayload,
            correlationID: correlationID,
            actor: .system,
            isSuccess: false
        )
    }
}

private struct MusicLibraryIndexStartedReceiptPayload: TypedReceiptPayload {
    let accountAddress: String
    let chain: Chain

    var fields: [ReceiptPayloadField] {
        [
            .hashed("accountAddress", string: accountAddress, kind: .walletAddress),
            .public("chain", string: chain.rawValue, kind: .chain)
        ]
    }
}

private struct MusicLibraryIndexCompletedReceiptPayload: TypedReceiptPayload {
    let accountAddress: String
    let chain: Chain
    let scannedCount: Int
    let writtenCount: Int
    let removedCount: Int

    var fields: [ReceiptPayloadField] {
        [
            .hashed("accountAddress", string: accountAddress, kind: .walletAddress),
            .public("chain", string: chain.rawValue, kind: .chain),
            .number("scannedCount", Double(scannedCount)),
            .number("writtenCount", Double(writtenCount)),
            .number("removedCount", Double(removedCount))
        ]
    }
}

private struct MusicLibraryIndexFailedReceiptPayload: TypedReceiptPayload {
    let accountAddress: String
    let chain: Chain
    let errorCode: String

    var fields: [ReceiptPayloadField] {
        [
            .hashed("accountAddress", string: accountAddress, kind: .walletAddress),
            .public("chain", string: chain.rawValue, kind: .chain),
            .public("errorCode", string: errorCode, kind: .label)
        ]
    }
}
