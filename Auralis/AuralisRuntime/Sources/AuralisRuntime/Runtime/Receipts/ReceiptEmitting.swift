import Foundation

/// The terminal disposition of a governed tool call, for receipt emission.
public enum GovernedOutcomeKind: String, CaseIterable, Equatable, Sendable {
    case executed
    case blocked
    case failed
    case needsRevision
    case needsApproval
}

/// Canonical receipt-taxonomy strings for governed runtime receipts. Single source of truth shared by
/// the emitter (the app's `ReceiptStoreSink`) and every reader (e.g. Mission Control's policy summary),
/// so the stored `category`/`kind` strings can never silently drift out of sync — a renamed outcome
/// becomes a compile error at the readers rather than a count that quietly reads zero.
public enum GovernedReceiptTaxonomy {
    /// Receipt category (stored as `scope`) for every governed runtime receipt.
    public static let category = "runtime"

    /// Receipt kind (stored as `trigger`) for a governed tool call with the given outcome.
    public static func toolKind(_ outcome: GovernedOutcomeKind) -> String {
        "tool.\(outcome.rawValue)"
    }

    /// Resolves the outcome kind from a stored receipt kind, or `nil` if it isn't a governed tool receipt.
    public static func outcome(fromToolKind kind: String) -> GovernedOutcomeKind? {
        GovernedOutcomeKind.allCases.first { toolKind($0) == kind }
    }
}

/// A durable, human-summarizable fact about one governed tool call, handed to a ``ReceiptEmitting``
/// sink at the end of the pipeline. Kept free of any storage type so `AuralisRuntime` stays a leaf; the
/// app layer's adapter translates this into a `ReceiptDraft` and appends it to the real store.
public struct GovernedReceipt: Equatable, Sendable {
    public let proposal: ActionProposal
    public let toolID: String
    public let outcome: GovernedOutcomeKind
    public let artifactID: UUID?
    public let reason: String?
    public let outputFields: [String: String]
    /// The authority the run proceeded under (P0.5-601/602). Present for outcomes that actually got
    /// permission to act; `nil` for runs refused or sent back before any authority was resolved, where
    /// recording one would be a lie.
    public let authority: AuthorityRef?

    public init(
        proposal: ActionProposal,
        toolID: String,
        outcome: GovernedOutcomeKind,
        artifactID: UUID? = nil,
        reason: String? = nil,
        outputFields: [String: String] = [:],
        authority: AuthorityRef? = nil
    ) {
        self.proposal = proposal
        self.toolID = toolID
        self.outcome = outcome
        self.artifactID = artifactID
        self.reason = reason
        self.outputFields = outputFields
        self.authority = authority
    }
}

/// Sink for governed receipts. The AfterToolCall phase of the pipeline emits one of these per run.
public protocol ReceiptEmitting: Sendable {
    func emit(_ receipt: GovernedReceipt) async throws
}

/// In-memory receipt sink for tests and previews.
public actor InMemoryReceiptEmitter: ReceiptEmitting {
    private var receipts: [GovernedReceipt] = []

    public init() { }

    public func emit(_ receipt: GovernedReceipt) {
        receipts.append(receipt)
    }

    public func allReceipts() -> [GovernedReceipt] {
        receipts
    }
}
