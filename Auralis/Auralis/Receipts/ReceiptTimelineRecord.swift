import AuralisPrimaryModels
import Foundation
import ReceiptsCore
import ReceiptStorage
import AuralisRuntime

struct ReceiptTimelineRecord: Identifiable, Equatable, Sendable {
    let id: UUID
    let sequenceID: Int
    let createdAt: Date
    let actor: ReceiptActor
    /// Structured "who acted" (P0.5-602). `nil` for receipts written before the column existed.
    let actorDetail: ReceiptActorDetail?
    /// Structured "under what authority" (P0.5-602). `nil` for receipts written before the column.
    let authorityDetail: ReceiptAuthorityDetail?
    let mode: ReceiptMode
    let trigger: String
    let scope: String
    let summary: String
    let provenance: String
    let isSuccess: Bool
    let correlationID: String?
    let details: ReceiptPayload
    let accountAddress: String?
    let chainRawValue: String?
    let selectedChainRawValues: [String]

    init(
        id: UUID,
        sequenceID: Int,
        createdAt: Date,
        actor: ReceiptActor,
        actorDetail: ReceiptActorDetail? = nil,
        authorityDetail: ReceiptAuthorityDetail? = nil,
        mode: ReceiptMode,
        trigger: String,
        scope: String,
        summary: String,
        provenance: String,
        isSuccess: Bool,
        correlationID: String?,
        details: ReceiptPayload,
        accountAddress: String? = nil,
        chainRawValue: String? = nil,
        selectedChainRawValues: [String] = []
    ) {
        self.id = id
        self.sequenceID = sequenceID
        self.createdAt = createdAt
        self.actor = actor
        self.actorDetail = actorDetail
        self.authorityDetail = authorityDetail
        self.mode = mode
        self.trigger = trigger
        self.scope = scope
        self.summary = summary
        self.provenance = provenance
        self.isSuccess = isSuccess
        self.correlationID = correlationID
        self.details = details
        self.accountAddress = accountAddress
        self.chainRawValue = chainRawValue
        self.selectedChainRawValues = selectedChainRawValues
    }

    init(storedReceipt: StoredReceipt) {
        let payload = storedReceipt.decodedDetailsOrEmpty()

        self.id = storedReceipt.id
        self.sequenceID = storedReceipt.sequenceID
        self.createdAt = storedReceipt.createdAt
        self.actor = storedReceipt.actor
        self.actorDetail = storedReceipt.actorDetail
        self.authorityDetail = storedReceipt.authorityDetail
        self.mode = storedReceipt.mode
        self.trigger = storedReceipt.trigger
        self.scope = storedReceipt.scope
        self.summary = storedReceipt.summary
        self.provenance = storedReceipt.provenance
        self.isSuccess = storedReceipt.isSuccess
        self.correlationID = storedReceipt.correlationID
        self.details = payload
        self.accountAddress = storedReceipt.accountAddress ?? payload.timelineAccountAddress
        self.chainRawValue = storedReceipt.chainRawValue ?? payload.timelineChainRawValue
        self.selectedChainRawValues = payload.timelineSelectedChainRawValues
    }

    var statusTitle: String {
        isSuccess ? "Success" : "Failed"
    }

    /// Names *which* party acted, preferring the structured attribution (P0.5-602) over the coarse
    /// `user`/`system` column. Falls back to the coarse value for pre-column receipts, so history
    /// written before the migration still reads sensibly rather than showing nothing.
    var actorTitle: String {
        guard let actorDetail else { return actor.rawValue.capitalized }
        return ActorRef(receiptActorDetail: actorDetail).displayLabel
    }

    /// The "under what authority" leg for the detail surface: what permitted this action.
    /// `nil` when the receipt predates the column, so the row is omitted rather than showing "None".
    var authorityTitle: String? {
        guard let authorityDetail,
              let authority = AuthorityRef(receiptAuthorityDetail: authorityDetail) else { return nil }
        return authority.displaySummary
    }

    /// The operator-facing reason recorded on the grant, shown beneath ``authorityTitle``.
    var authorityReason: String? {
        guard let reason = authorityDetail?.reason, !reason.isEmpty else { return nil }
        return reason
    }

    var triggerTitle: String {
        let normalizedTrigger = trigger
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: ".", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !normalizedTrigger.isEmpty else {
            return "Unknown event"
        }

        let words = normalizedTrigger.split(separator: " ").map(String.init)
        return words.enumerated()
            .map { index, word in
                if word.localizedCaseInsensitiveCompare("ui") == .orderedSame {
                    return "UI"
                }

                return index == 0 ? word.capitalized : word.lowercased()
            }
            .joined(separator: " ")
    }

    var accountTitle: String? {
        guard let accountAddress, !accountAddress.isEmpty else {
            return nil
        }

        return accountAddress.displayAddress
    }

    var chainTitle: String? {
        guard let chainRawValue,
              let chain = Chain(rawValue: chainRawValue) else {
            return nil
        }

        return chain.routingDisplayName
    }

    var searchIndex: String {
        [
            summary,
            trigger,
            scope,
            provenance,
            correlationID ?? "",
            flattenedDetails(details.values)
        ]
        .joined(separator: " ")
        .lowercased()
    }

    /// Whether this receipt belongs to the scope's **account**.
    ///
    /// Separated from the chain filter because the two are different kinds of rule. This one is a
    /// visibility boundary — another account's receipt must never be shown — so it applies everywhere,
    /// including on a directly-addressed detail route. The chain filter is a list presentation choice
    /// and must not be.
    func matchesAccountScope(_ scope: ReceiptTimelineScope) -> Bool {
        guard let scopeKey = Self.accountKey(scope.accountAddress) else { return true }
        guard let recordKey = Self.accountKey(accountAddress) else { return true }
        return recordKey == scopeKey
    }

    /// Whether this receipt passes the scope's **chain** filter.
    ///
    /// Only meaningful for the timeline list. Applying it to a receipt the user navigated or deep-linked
    /// directly to rendered "Receipt Unavailable — could not be found in local storage" for a row that
    /// exists and is readable, which is both a dead end and a false statement of cause.
    func matchesChainFilter(_ scope: ReceiptTimelineScope) -> Bool {
        if let chainRawValue, chainRawValue != scope.chain.rawValue {
            return false
        }

        if !selectedChainRawValues.isEmpty, !selectedChainRawValues.contains(scope.chain.rawValue) {
            return false
        }

        return true
    }

    func matches(_ scope: ReceiptTimelineScope) -> Bool {
        matchesAccountScope(scope) && matchesChainFilter(scope)
    }

    /// The comparable form of a receipt-ledger account key, applied to **both** sides of the scope
    /// comparison.
    ///
    /// It has to mirror `ReceiptStorage.ReceiptAccountAddress.resolve`, which is what actually wrote
    /// the stored key: canonical `0x…` when the value parses as an address, and a plain lowercased
    /// string when it does not — because that function deliberately accepts keys that are not
    /// addresses rather than dropping those receipts onto the global timeline.
    ///
    /// Previously only the *scope* side was normalized, and through `AuralisEthereumAddress`, which
    /// **adds** the `0x` prefix. The stored side was only `.lowercased()`. So a writer that passed an
    /// unprefixed address — the `timelineAccountAddress` parameter is a bare `String?` with no
    /// normalization contract, and the call sites are split between normalizing and not — produced a
    /// key that could never equal the scope's, and that receipt was filtered out of its own account's
    /// timeline forever. A ledger that quietly reads short is the failure mode receipts exist to
    /// prevent.
    /// Internal, not private, because the SwiftData **fetch predicates** must use it too.
    ///
    /// Normalizing only here left the fix half-applied: a fetch narrowed by a differently-normalized
    /// account key excludes the row before `matches(_:)` ever sees it, and a post-fetch filter can only
    /// narrow further — it can never recover a row the predicate dropped. Every comparison against
    /// `StoredReceipt.accountAddress`, in-memory or in a predicate, goes through this one function.
    static func accountKey(_ value: String?) -> String? {
        if let normalized = AuralisEthereumAddress.normalized(value) { return normalized }
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty else { return nil }
        return trimmed.lowercased()
    }

    private func flattenedDetails(_ object: [String: ReceiptJSONValue]) -> String {
        object
            .sorted(by: { $0.key < $1.key })
            .map { key, value in
                "\(key) \(flattenedValue(value))"
            }
            .joined(separator: " ")
    }

    private func flattenedValue(_ value: ReceiptJSONValue) -> String {
        switch value {
        case .string(let string):
            return string
        case .number(let number):
            return number.formatted()
        case .bool(let bool):
            return bool ? "true" : "false"
        case .null:
            return "null"
        case .object(let object):
            return flattenedDetails(object)
        case .array(let values):
            return values.map(flattenedValue).joined(separator: " ")
        }
    }
}
