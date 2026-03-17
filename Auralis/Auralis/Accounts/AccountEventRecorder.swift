import Foundation
import OSLog
import SwiftData

enum AccountEvent: Equatable {
    case added(address: String)
    case removed(address: String)
    case selected(address: String)
}

protocol AccountEventRecorder {
    func record(_ event: AccountEvent)
}

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
            try receiptStore.append(makeDraft(for: event))
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
        let (kind, address) = switch event {
        case .added(let address):
            ("account.added", address)
        case .removed(let address):
            ("account.removed", address)
        case .selected(let address):
            ("account.selected", address)
        }

        let payload = payloadSanitizer.sanitize(
            RawReceiptPayload(values: [
                "address": .string(address)
            ])
        )

        return ReceiptDraft(
            category: "accounts",
            kind: kind,
            payload: payload
        )
    }
}
