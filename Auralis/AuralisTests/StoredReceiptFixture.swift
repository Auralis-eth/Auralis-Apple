import AuralisCrypto
import AuralisTestSupport
import Foundation
import AuralisReceipts

/// App-integration fixture for tests that exercise persisted receipt cleanup and presentation.
///
/// This deliberately lives in `AuralisTests`: `StoredReceipt` is a AuralisReceipts adapter model,
/// so exposing its builder from dependency-clean `AuralisTestSupport` created a reverse dependency
/// from generic test utilities to receipt persistence.
struct StoredReceiptFixture: @unchecked Sendable {
    static var successful: StoredReceiptFixture { StoredReceiptFixture() }

    var id: UUID
    var sequenceID: Int
    var createdAt: Date
    var actor: ReceiptActor
    var mode: ReceiptMode
    var trigger: String
    var scope: String
    var summary: String
    var provenance: String
    var isSuccess: Bool
    var correlationID: String?
    var accountAddress: String?
    var chainRawValue: String?
    var accountSequenceID: Int
    var payloadHash: String
    var previousReceiptHash: String
    var chainHash: String
    var details: ReceiptPayload

    init(
        id: UUID = UUID(),
        sequenceID: Int = 1,
        createdAt: Date = Fixture.referenceDate,
        actor: ReceiptActor = .system,
        mode: ReceiptMode = .observe,
        trigger: String = "fixture.trigger",
        scope: String = "fixture.scope",
        summary: String = "fixture.summary",
        provenance: String = "tests",
        isSuccess: Bool = true,
        correlationID: String? = nil,
        accountAddress: String? = Fixture.Accounts.primary,
        chainRawValue: String? = Chain.ethMainnet.rawValue,
        accountSequenceID: Int = 1,
        payloadHash: String = "fixture-payload-hash",
        previousReceiptHash: String = "fixture-previous-hash",
        chainHash: String = "fixture-chain-hash",
        details: ReceiptPayload = ReceiptPayload(values: [:])
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
        self.accountAddress = accountAddress
        self.chainRawValue = chainRawValue
        self.accountSequenceID = accountSequenceID
        self.payloadHash = payloadHash
        self.previousReceiptHash = previousReceiptHash
        self.chainHash = chainHash
        self.details = details
    }

    func with(_ transform: (inout StoredReceiptFixture) -> Void) -> StoredReceiptFixture {
        var copy = self
        transform(&copy)
        return copy
    }

    func build() throws -> StoredReceipt {
        try StoredReceipt(
            id: id,
            sequenceID: sequenceID,
            createdAt: createdAt,
            actor: actor,
            mode: mode,
            trigger: trigger,
            scope: scope,
            summary: summary,
            provenance: provenance,
            isSuccess: isSuccess,
            correlationID: correlationID,
            timelineAccountAddress: accountAddress,
            timelineChainRawValue: chainRawValue,
            accountSequenceID: accountSequenceID,
            payloadHash: payloadHash,
            previousReceiptHash: previousReceiptHash,
            chainHash: chainHash,
            details: details
        )
    }
}
