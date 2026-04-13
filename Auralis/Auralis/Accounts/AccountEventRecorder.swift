import Foundation
import OSLog
import SwiftData

enum AccountEvent: Equatable {
    case added(address: String)
    case removed(address: String)
    case selected(address: String)
    case preferredChainChanged(address: String, from: Chain, to: Chain)
    case currentChainChanged(address: String, from: Chain, to: Chain)
}

@MainActor
protocol AccountEventRecorder {
    func record(_ event: AccountEvent, correlationID: String?)
}

extension AccountEventRecorder {
    func record(_ event: AccountEvent) {
        record(event, correlationID: nil)
    }
}

@MainActor
struct NoOpAccountEventRecorder: AccountEventRecorder {
    func record(_ event: AccountEvent, correlationID: String?) { }
}

@MainActor
struct ReceiptBackedAccountEventRecorder: AccountEventRecorder {
    private let receiptStore: any ReceiptStore
    private let payloadSanitizer: any ReceiptPayloadSanitizing
    private let logger = Logger(subsystem: "Auralis", category: "AccountReceipts")

    init(
        receiptStore: any ReceiptStore,
        payloadSanitizer: any ReceiptPayloadSanitizing = DefaultReceiptPayloadSanitizer()
    ) {
        self.receiptStore = receiptStore
        self.payloadSanitizer = payloadSanitizer
    }

    func record(_ event: AccountEvent, correlationID: String?) {
        do {
            _ = try receiptStore.append(makeDraft(for: event, correlationID: correlationID))
        } catch {
            logger.error("Failed to append account receipt: \(error.localizedDescription, privacy: .public)")
        }
    }
}

@MainActor
enum AccountEventRecorders {
    static func live(modelContext: ModelContext) -> any AccountEventRecorder {
        ReceiptBackedAccountEventRecorder(
            receiptStore: ReceiptStores.live(modelContext: modelContext)
        )
    }
}

private extension ReceiptBackedAccountEventRecorder {
    func makeDraft(for event: AccountEvent, correlationID: String?) -> ReceiptDraft {
        let (kind, summary, rawPayload): (String, String, RawReceiptPayload) = switch event {
        case .added(let address):
            (
                "account.added",
                "Added watch-only account",
                AccountAddressReceiptPayload(address: address).rawPayload
            )
        case .removed(let address):
            (
                "account.removed",
                "Removed watch-only account",
                AccountAddressReceiptPayload(address: address).rawPayload
            )
        case .selected(let address):
            (
                "account.selected",
                "Selected active account",
                AccountAddressReceiptPayload(address: address).rawPayload
            )
        case .preferredChainChanged(let address, let from, let to):
            (
                "account.chain.preferred.changed",
                "Updated preferred chain scope",
                ChainChangeReceiptPayload(
                    address: address,
                    from: from,
                    to: to
                ).rawPayload
            )
        case .currentChainChanged(let address, let from, let to):
            (
                "account.chain.current.changed",
                "Updated active chain scope",
                ChainChangeReceiptPayload(
                    address: address,
                    from: from,
                    to: to
                ).rawPayload
            )
        }

        let payload = payloadSanitizer.sanitize(rawPayload)

        return ReceiptDraft(
            actor: .user,
            mode: .observe,
            trigger: kind,
            scope: kind.contains(".chain.") ? "accounts.chain_scope" : "accounts",
            summary: summary,
            provenance: "user_provided",
            isSuccess: true,
            correlationID: correlationID,
            details: payload
        )
    }
}

private struct AccountAddressReceiptPayload: TypedReceiptPayload {
    let address: String

    var fields: [ReceiptPayloadField] {
        [
            .hashed("address", string: address, kind: .walletAddress)
        ]
    }
}

private struct ChainChangeReceiptPayload: TypedReceiptPayload {
    let address: String
    let from: Chain
    let to: Chain

    var fields: [ReceiptPayloadField] {
        [
            .hashed("address", string: address, kind: .walletAddress),
            .public("from_chain", string: from.rawValue, kind: .chain),
            .public("to_chain", string: to.rawValue, kind: .chain)
        ]
    }
}
