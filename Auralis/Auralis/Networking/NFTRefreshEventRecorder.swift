import Foundation
import OSLog
import SwiftData
import SwiftUI

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
            rawPayload: RawReceiptPayload(values: basePayload(accountAddress: accountAddress, chain: chain))
        )
    }

    func recordFetchSucceeded(
        accountAddress: String,
        chain: Chain,
        correlationID: String,
        itemCount: Int,
        totalCount: Int?
    ) async {
        var payload = basePayload(accountAddress: accountAddress, chain: chain)
        payload["itemCount"] = .number(Double(itemCount))

        if let totalCount {
            payload["totalCount"] = .number(Double(totalCount))
        }

        append(
            kind: "nft.fetch.succeeded",
            correlationID: correlationID,
            rawPayload: RawReceiptPayload(values: payload)
        )
    }

    func recordFetchFailed(
        accountAddress: String,
        chain: Chain,
        correlationID: String,
        error: Error
    ) async {
        var payload = basePayload(accountAddress: accountAddress, chain: chain)
        payload["error"] = .string(String(describing: error))

        append(
            kind: "nft.fetch.failed",
            correlationID: correlationID,
            rawPayload: RawReceiptPayload(values: payload)
        )
    }

    func recordPersistenceCompleted(
        accountAddress: String,
        chain: Chain,
        correlationID: String,
        persistedCount: Int
    ) async {
        var payload = basePayload(accountAddress: accountAddress, chain: chain)
        payload["persistedCount"] = .number(Double(persistedCount))

        append(
            kind: "nft.persistence.completed",
            correlationID: correlationID,
            rawPayload: RawReceiptPayload(values: payload)
        )
    }

    func recordPersistenceFailed(
        accountAddress: String,
        chain: Chain,
        correlationID: String,
        error: Error
    ) async {
        var payload = basePayload(accountAddress: accountAddress, chain: chain)
        payload["error"] = .string(String(describing: error))

        append(
            kind: "nft.persistence.failed",
            correlationID: correlationID,
            rawPayload: RawReceiptPayload(values: payload)
        )
    }
}

@MainActor
enum NFTRefreshEventRecorders {
    static func live(modelContext: ModelContext) -> any NFTRefreshEventRecording {
        ReceiptBackedNFTRefreshEventRecorder(
            receiptStore: SwiftDataReceiptStore(modelContext: modelContext)
        )
    }
}

@MainActor
private extension ReceiptBackedNFTRefreshEventRecorder {
    func append(
        kind: String,
        correlationID: String,
        rawPayload: RawReceiptPayload
    ) {
        var values = rawPayload.values
        values["mode"] = .string(AppMode.observe.rawValue)
        let payload = payloadSanitizer.sanitize(RawReceiptPayload(values: values))

        do {
            _ = try receiptStore.append(
                ReceiptDraft(
                    category: "networking",
                    kind: kind,
                    correlationID: correlationID,
                    payload: payload
                )
            )
        } catch {
            logger.error("Failed to append NFT refresh receipt: \(error.localizedDescription, privacy: .public)")
        }
    }

    func basePayload(accountAddress: String, chain: Chain) -> [String: ReceiptJSONValue] {
        [
            "accountAddress": .string(accountAddress),
            "chain": .string(chain.rawValue)
        ]
    }
}

