import Foundation

struct ReceiptTimelineRecord: Identifiable, Equatable, Sendable {
    let id: UUID
    let sequenceID: Int
    let createdAt: Date
    let actor: ReceiptActor
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
        let payload = (try? storedReceipt.decodedPayload()) ?? ReceiptPayload(values: [:])

        self.id = storedReceipt.id
        self.sequenceID = storedReceipt.sequenceID
        self.createdAt = storedReceipt.createdAt
        self.actor = storedReceipt.actor
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

    var actorTitle: String {
        actor.rawValue.capitalized
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

    func matches(_ scope: ReceiptTimelineScope) -> Bool {
        let normalizedScopeAddress = scope.accountAddress.extractedEthereumAddress?.lowercased()

        if let accountAddress {
            guard accountAddress == normalizedScopeAddress else {
                return false
            }
        }

        if let chainRawValue {
            guard chainRawValue == scope.chain.rawValue else {
                return false
            }
        }

        if !selectedChainRawValues.isEmpty {
            guard selectedChainRawValues.contains(scope.chain.rawValue) else {
                return false
            }
        }

        return true
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
