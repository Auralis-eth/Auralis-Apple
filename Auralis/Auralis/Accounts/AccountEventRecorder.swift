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
    func record(_ event: AccountEvent)
}

@MainActor
struct NoOpAccountEventRecorder: AccountEventRecorder {
    func record(_ event: AccountEvent) { }
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

    func record(_ event: AccountEvent) {
        do {
            _ = try receiptStore.append(makeDraft(for: event))
        } catch {
            logger.error("Failed to append account receipt: \(error.localizedDescription, privacy: .public)")
        }
    }
}

@MainActor
enum AccountEventRecorders {
    static func live(modelContext: ModelContext) -> any AccountEventRecorder {
        ReceiptBackedAccountEventRecorder(
            receiptStore: SwiftDataReceiptStore(modelContext: modelContext)
        )
    }
}

private extension ReceiptBackedAccountEventRecorder {
    func makeDraft(for event: AccountEvent) -> ReceiptDraft {
        let (kind, summary, payloadValues): (String, String, [String: ReceiptJSONValue]) = switch event {
        case .added(let address):
            (
                "account.added",
                "Added watch-only account",
                ["address": .string(address)]
            )
        case .removed(let address):
            (
                "account.removed",
                "Removed watch-only account",
                ["address": .string(address)]
            )
        case .selected(let address):
            (
                "account.selected",
                "Selected active account",
                ["address": .string(address)]
            )
        case .preferredChainChanged(let address, let from, let to):
            (
                "account.chain.preferred.changed",
                "Updated preferred chain scope",
                [
                    "address": .string(address),
                    "from_chain": .string(from.rawValue),
                    "to_chain": .string(to.rawValue)
                ]
            )
        case .currentChainChanged(let address, let from, let to):
            (
                "account.chain.current.changed",
                "Updated active chain scope",
                [
                    "address": .string(address),
                    "from_chain": .string(from.rawValue),
                    "to_chain": .string(to.rawValue)
                ]
            )
        }

        let payload = payloadSanitizer.sanitize(
            RawReceiptPayload(values: payloadValues)
        )

        return ReceiptDraft(
            actor: .user,
            mode: .observe,
            trigger: kind,
            scope: kind.contains(".chain.") ? "accounts.chain_scope" : "accounts",
            summary: summary,
            provenance: "user_provided",
            isSuccess: true,
            details: payload
        )
    }
}
