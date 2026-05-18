import ReceiptsCore
import AuralisPrimaryModels
import Foundation
import OSLog

@MainActor
public protocol NFTRefreshEventRecording {
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

public struct NoOpNFTRefreshEventRecorder: NFTRefreshEventRecording {
    public init() { }

    public func recordRefreshStarted(
        accountAddress: String,
        chain: Chain,
        correlationID: String
    ) async { }

    public func recordFetchSucceeded(
        accountAddress: String,
        chain: Chain,
        correlationID: String,
        itemCount: Int,
        totalCount: Int?
    ) async { }

    public func recordFetchFailed(
        accountAddress: String,
        chain: Chain,
        correlationID: String,
        error: Error
    ) async { }

    public func recordPersistenceCompleted(
        accountAddress: String,
        chain: Chain,
        correlationID: String,
        persistedCount: Int
    ) async { }

    public func recordPersistenceFailed(
        accountAddress: String,
        chain: Chain,
        correlationID: String,
        error: Error
    ) async { }
}

@MainActor
public final class ReceiptBackedNFTRefreshEventRecorder: NFTRefreshEventRecording {
    private let receiptStore: any ReceiptStore
    private let payloadSanitizer: any ReceiptPayloadSanitizing
    private let logger = Logger(subsystem: "Auralis", category: "NFTRefreshReceipts")

    public init(
        receiptStore: any ReceiptStore,
        payloadSanitizer: any ReceiptPayloadSanitizing = DefaultReceiptPayloadSanitizer()
    ) {
        self.receiptStore = receiptStore
        self.payloadSanitizer = payloadSanitizer
    }

    public func recordRefreshStarted(
        accountAddress: String,
        chain: Chain,
        correlationID: String
    ) async {
        await append(
            kind: "nft.refresh.started",
            correlationID: correlationID,
            accountAddress: accountAddress,
            chain: chain,
            rawPayload: NFTRefreshStartedPayload(
                accountAddress: accountAddress,
                chain: chain
            ).rawPayload,
            summary: "Started NFT refresh",
            isSuccess: true
        )
    }

    public func recordFetchSucceeded(
        accountAddress: String,
        chain: Chain,
        correlationID: String,
        itemCount: Int,
        totalCount: Int?
    ) async {
        await append(
            kind: "nft.fetch.succeeded",
            correlationID: correlationID,
            accountAddress: accountAddress,
            chain: chain,
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

    public func recordFetchFailed(
        accountAddress: String,
        chain: Chain,
        correlationID: String,
        error: Error
    ) async {
        await append(
            kind: "nft.fetch.failed",
            correlationID: correlationID,
            accountAddress: accountAddress,
            chain: chain,
            rawPayload: NFTFetchFailedPayload(
                accountAddress: accountAddress,
                chain: chain,
                providerFailure: NFTProviderFailure(error: error)
            ).rawPayload,
            summary: "NFT fetch failed",
            isSuccess: false
        )
    }

    public func recordPersistenceCompleted(
        accountAddress: String,
        chain: Chain,
        correlationID: String,
        persistedCount: Int
    ) async {
        await append(
            kind: "nft.persistence.completed",
            correlationID: correlationID,
            accountAddress: accountAddress,
            chain: chain,
            rawPayload: NFTPersistenceCompletedPayload(
                accountAddress: accountAddress,
                chain: chain,
                persistedCount: persistedCount
            ).rawPayload,
            summary: "Persisted refreshed NFTs",
            isSuccess: true
        )
    }

    public func recordPersistenceFailed(
        accountAddress: String,
        chain: Chain,
        correlationID: String,
        error: Error
    ) async {
        await append(
            kind: "nft.persistence.failed",
            correlationID: correlationID,
            accountAddress: accountAddress,
            chain: chain,
            rawPayload: NFTPersistenceFailedPayload(
                accountAddress: accountAddress,
                chain: chain,
                errorCode: "persistenceFailed"
            ).rawPayload,
            summary: "Persisting refreshed NFTs failed",
            isSuccess: false
        )
    }
}


@MainActor
private extension ReceiptBackedNFTRefreshEventRecorder {
    func append(
        kind: String,
        correlationID: String,
        accountAddress: String,
        chain: Chain,
        rawPayload: RawReceiptPayload,
        summary: String,
        isSuccess: Bool
    ) async {
        let payload = payloadSanitizer.sanitize(rawPayload)

        do {
            _ = try await receiptStore.append(
                ReceiptDraft(
                    actor: .system,
                    mode: .observe,
                    trigger: kind,
                    scope: "networking",
                    summary: summary,
                    provenance: "on_chain",
                    isSuccess: isSuccess,
                    correlationID: correlationID,
                    timelineAccountAddress: accountAddress,
                    timelineChainRawValue: chain.rawValue,
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
    let providerFailure: NFTProviderFailure?

    var fields: [ReceiptPayloadField] {
        var fields: [ReceiptPayloadField] = [
            .hashed("accountAddress", string: accountAddress, kind: .walletAddress),
            .public("chain", string: chain.rawValue, kind: .chain),
            .public(
                "errorCode",
                string: (providerFailure?.publicErrorCode ?? .providerUnavailable).rawValue,
                kind: .label
            )
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
    let errorCode: String

    var fields: [ReceiptPayloadField] {
        [
            .hashed("accountAddress", string: accountAddress, kind: .walletAddress),
            .public("chain", string: chain.rawValue, kind: .chain),
            .public("errorCode", string: errorCode, kind: .label)
        ]
    }
}
