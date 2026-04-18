import Foundation
import OSLog
import SwiftData
import SwiftUI

@MainActor
protocol NFTRefreshEventRecording {
    func recordRefreshStarted(
        accountAddress: String,
        chain: Chain,
        correlationID: String
    ) async

    func recordFetchSucceeded(
        accountAddress: String,
        chain: Chain,
        correlationID: String,
        itemCount: Int,
        totalCount: Int?
    ) async

    func recordFetchFailed(
        accountAddress: String,
        chain: Chain,
        correlationID: String,
        error: Error
    ) async

    func recordPersistenceCompleted(
        accountAddress: String,
        chain: Chain,
        correlationID: String,
        persistedCount: Int
    ) async

    func recordPersistenceFailed(
        accountAddress: String,
        chain: Chain,
        correlationID: String,
        error: Error
    ) async
}

struct NoOpNFTRefreshEventRecorder: NFTRefreshEventRecording {
    func recordRefreshStarted(
        accountAddress: String,
        chain: Chain,
        correlationID: String
    ) async { }

    func recordFetchSucceeded(
        accountAddress: String,
        chain: Chain,
        correlationID: String,
        itemCount: Int,
        totalCount: Int?
    ) async { }

    func recordFetchFailed(
        accountAddress: String,
        chain: Chain,
        correlationID: String,
        error: Error
    ) async { }

    func recordPersistenceCompleted(
        accountAddress: String,
        chain: Chain,
        correlationID: String,
        persistedCount: Int
    ) async { }

    func recordPersistenceFailed(
        accountAddress: String,
        chain: Chain,
        correlationID: String,
        error: Error
    ) async { }
}

@MainActor
final class ReceiptBackedNFTRefreshEventRecorder: NFTRefreshEventRecording {
    private let receiptStore: any ReceiptStore
    private let payloadSanitizer: any ReceiptPayloadSanitizing
    private let logger = Logger(subsystem: "Auralis", category: "NFTRefreshReceipts")

    init(
        receiptStore: any ReceiptStore,
        payloadSanitizer: any ReceiptPayloadSanitizing = DefaultReceiptPayloadSanitizer()
    ) {
        self.receiptStore = receiptStore
        self.payloadSanitizer = payloadSanitizer
    }

    func recordRefreshStarted(
        accountAddress: String,
        chain: Chain,
        correlationID: String
    ) async {
        append(
            kind: "nft.refresh.started",
            correlationID: correlationID,
            rawPayload: NFTRefreshStartedPayload(
                accountAddress: accountAddress,
                chain: chain
            ).rawPayload,
            summary: "Started NFT refresh",
            isSuccess: true
        )
    }

    func recordFetchSucceeded(
        accountAddress: String,
        chain: Chain,
        correlationID: String,
        itemCount: Int,
        totalCount: Int?
    ) async {
        append(
            kind: "nft.fetch.succeeded",
            correlationID: correlationID,
            rawPayload: NFTFetchSucceededPayload(
                accountAddress: accountAddress,
                chain: chain,
                itemCount: itemCount,
                totalCount: totalCount
            ).rawPayload,
            summary: "Fetched NFT page successfully",
            isSuccess: true
        )
    }

    func recordFetchFailed(
        accountAddress: String,
        chain: Chain,
        correlationID: String,
        error: Error
    ) async {
        append(
            kind: "nft.fetch.failed",
            correlationID: correlationID,
            rawPayload: NFTFetchFailedPayload(
                accountAddress: accountAddress,
                chain: chain,
                errorDescription: String(describing: error),
                providerFailure: NFTProviderFailure(error: error)
            ).rawPayload,
            summary: "NFT fetch failed",
            isSuccess: false
        )
    }

    func recordPersistenceCompleted(
        accountAddress: String,
        chain: Chain,
        correlationID: String,
        persistedCount: Int
    ) async {
        append(
            kind: "nft.persistence.completed",
            correlationID: correlationID,
            rawPayload: NFTPersistenceCompletedPayload(
                accountAddress: accountAddress,
                chain: chain,
                persistedCount: persistedCount
            ).rawPayload,
            summary: "Persisted refreshed NFTs",
            isSuccess: true
        )
    }

    func recordPersistenceFailed(
        accountAddress: String,
        chain: Chain,
        correlationID: String,
        error: Error
    ) async {
        append(
            kind: "nft.persistence.failed",
            correlationID: correlationID,
            rawPayload: NFTPersistenceFailedPayload(
                accountAddress: accountAddress,
                chain: chain,
                errorDescription: String(describing: error)
            ).rawPayload,
            summary: "Persisting refreshed NFTs failed",
            isSuccess: false
        )
    }
}

@MainActor
enum NFTRefreshEventRecorders {
    static func live(modelContext: ModelContext) -> any NFTRefreshEventRecording {
        ReceiptBackedNFTRefreshEventRecorder(
            receiptStore: ReceiptStores.live(modelContext: modelContext)
        )
    }
}

@MainActor
private extension ReceiptBackedNFTRefreshEventRecorder {
    func append(
        kind: String,
        correlationID: String,
        rawPayload: RawReceiptPayload,
        summary: String,
        isSuccess: Bool
    ) {
        let payload = payloadSanitizer.sanitize(rawPayload)

        do {
            _ = try receiptStore.append(
                ReceiptDraft(
                    actor: .system,
                    mode: .observe,
                    trigger: kind,
                    scope: "networking",
                    summary: summary,
                    provenance: "on_chain",
                    isSuccess: isSuccess,
                    correlationID: correlationID,
                    details: payload
                )
            )
        } catch {
            logger.error("Failed to append NFT refresh receipt: \(error.localizedDescription, privacy: .public)")
        }
    }
}

private struct NFTRefreshStartedPayload: TypedReceiptPayload {
    let accountAddress: String
    let chain: Chain

    var fields: [ReceiptPayloadField] {
        [
            .hashed("accountAddress", string: accountAddress, kind: .walletAddress),
            .public("chain", string: chain.rawValue, kind: .chain)
        ]
    }
}

private struct NFTFetchSucceededPayload: TypedReceiptPayload {
    let accountAddress: String
    let chain: Chain
    let itemCount: Int
    let totalCount: Int?

    var fields: [ReceiptPayloadField] {
        var fields: [ReceiptPayloadField] = [
            .hashed("accountAddress", string: accountAddress, kind: .walletAddress),
            .public("chain", string: chain.rawValue, kind: .chain),
            .number("itemCount", Double(itemCount))
        ]

        if let totalCount {
            fields.append(.number("totalCount", Double(totalCount)))
        }

        return fields
    }
}

private struct NFTFetchFailedPayload: TypedReceiptPayload {
    let accountAddress: String
    let chain: Chain
    let errorDescription: String
    let providerFailure: NFTProviderFailure?

    var fields: [ReceiptPayloadField] {
        var fields: [ReceiptPayloadField] = [
            .hashed("accountAddress", string: accountAddress, kind: .walletAddress),
            .public("chain", string: chain.rawValue, kind: .chain),
            .redacted("error", string: errorDescription, kind: .errorMessage)
        ]

        if let providerFailure {
            fields.append(.public("errorKind", string: providerFailure.kind.rawValue, kind: .label))
            fields.append(.bool("isRetryable", providerFailure.isRetryable))
        }

        return fields
    }
}

private struct NFTPersistenceCompletedPayload: TypedReceiptPayload {
    let accountAddress: String
    let chain: Chain
    let persistedCount: Int

    var fields: [ReceiptPayloadField] {
        [
            .hashed("accountAddress", string: accountAddress, kind: .walletAddress),
            .public("chain", string: chain.rawValue, kind: .chain),
            .number("persistedCount", Double(persistedCount))
        ]
    }
}

private struct NFTPersistenceFailedPayload: TypedReceiptPayload {
    let accountAddress: String
    let chain: Chain
    let errorDescription: String

    var fields: [ReceiptPayloadField] {
        [
            .hashed("accountAddress", string: accountAddress, kind: .walletAddress),
            .public("chain", string: chain.rawValue, kind: .chain),
            .redacted("error", string: errorDescription, kind: .errorMessage)
        ]
    }
}
