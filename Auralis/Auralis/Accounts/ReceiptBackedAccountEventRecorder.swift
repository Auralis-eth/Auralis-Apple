import AccountsCore
import AuralisPrimaryModels
import Foundation
import OSLog
import AuralisReceipts
import SwiftData

@MainActor
struct ReceiptBackedAccountEventRecorder: AccountEventRecorder {
    private let receiptStore: any ReceiptStore
    private let payloadSanitizer: any ReceiptPayloadSanitizing
    private let modeProvider: @MainActor () -> ReceiptMode
    private let logger = Logger(subsystem: "Auralis", category: "AccountReceipts")

    init(
        receiptStore: any ReceiptStore,
        payloadSanitizer: any ReceiptPayloadSanitizing = DefaultReceiptPayloadSanitizer(),
        // Persisted mode rather than a hardcoded `.observe`: `mode` is hashed into the receipt, so a
        // defaulted literal is ledger corruption, not a wrong label.
        modeProvider: @escaping @MainActor () -> ReceiptMode = { PersistedCryptoMode.currentReceiptMode }
    ) {
        self.receiptStore = receiptStore
        self.payloadSanitizer = payloadSanitizer
        self.modeProvider = modeProvider
    }

    func record(_ event: AccountEvent, correlationID: String?) async {
        do {
            _ = try await receiptStore.append(makeDraft(for: event, correlationID: correlationID))
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
        let (kind, summary, rawPayload, timelineAccountAddress, timelineChainRawValue): (String, String, RawReceiptPayload, String?, String?) = switch event {
        case .added(let address):
            (
                "account.added",
                "Added watch-only account",
                AccountAddressReceiptPayload(address: address).rawPayload,
                address,
                nil
            )
        case .removed(let address):
            (
                "account.removed",
                "Removed watch-only account",
                AccountAddressReceiptPayload(address: address).rawPayload,
                address,
                nil
            )
        case .selected(let address):
            (
                "account.selected",
                "Selected active account",
                AccountAddressReceiptPayload(address: address).rawPayload,
                address,
                nil
            )
        case .preferredChainChanged(let address, let from, let to):
            (
                "account.chain.preferred.changed",
                "Updated preferred chain scope",
                ChainChangeReceiptPayload(
                    address: address,
                    from: from,
                    to: to
                ).rawPayload,
                address,
                to.rawValue
            )
        case .currentChainChanged(let address, let from, let to):
            (
                "account.chain.current.changed",
                "Updated active chain scope",
                ChainChangeReceiptPayload(
                    address: address,
                    from: from,
                    to: to
                ).rawPayload,
                address,
                to.rawValue
            )
        }

        let payload = payloadSanitizer.sanitize(rawPayload)

        return ReceiptDraft(
            actorDetail: .human,
            authorityDetail: ReceiptAuthorityDetail(source: "humanApproval", reason: "The person explicitly changed account or chain state."),
            mode: modeProvider(),
            trigger: kind,
            scope: kind.contains(".chain.") ? "accounts.chain_scope" : "accounts",
            summary: summary,
            provenance: "user_provided",
            isSuccess: true,
            correlationID: correlationID,
            timelineAccountAddress: timelineAccountAddress,
            timelineChainRawValue: timelineChainRawValue,
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
