import ArtifactCore
import Foundation
import ReceiptsCore
import AuralisRuntime

// The record-shape deterministic checks (P0.5-802).
//
// These live in `RuntimeKit` rather than beside the other standard checks in `AuralisRuntime` because
// `ArtifactCore` already depends on `AuralisRuntime` — authoring them there would close a dependency
// cycle. `RuntimeKit` sits above both `ArtifactCore` and `ReceiptsCore`, so it is the lowest point in
// the graph that can see the schemas it validates. Their *identifiers* stay in `AuralisRuntime` as
// ``RecordSchemaCheckID``, so tools further down the graph can still name them.

public extension RecordSchemaKey {
    /// The record-shape versions this build writes, in the form the host stamps onto a proposal.
    ///
    /// Artifacts only. Receipts carry no version — see ``ReceiptSchema`` — so there is nothing for
    /// the host to stamp on their behalf.
    static var currentDeclaration: [String: String] {
        [
            artifactVersion: String(ArtifactSchema.currentVersion)
        ]
    }
}

/// Refuses a run whose declared receipt fields would produce a record no one can interpret.
///
/// Field contract only; there is no version to validate. ``ReceiptSchema`` records no version
/// because nothing has shipped, so a proposal cannot name a receipt shape this build has no reader
/// for — there is exactly one shape. What a caller *does* contribute is the parameter set rendered
/// into the record's readable plan, and a blank key there produces a row no one can interpret, which
/// is the kind of unreadable governance record an append-only ledger must not accept.
///
/// The check keeps its identity (``RecordSchemaCheckID/receiptSchema``) because every operator tool
/// requires it, and because the version branch belongs here if receipts are ever versioned again.
public struct ReceiptSchemaCheck: DeterministicCheck {
    public let id = RecordSchemaCheckID.receiptSchema

    public init() { }

    public func evaluate(_ proposal: ActionProposal) async -> DeterministicCheckResult {
        let fieldProblems = ReceiptSchema.problems(inDeclared: proposal.parameters)
        guard fieldProblems.isEmpty else {
            return .init(checkID: id, passed: false, detail: fieldProblems.joined(separator: "; "))
        }
        return .init(checkID: id, passed: true)
    }
}

/// Refuses a run that would write an artifact under a shape this build cannot interpret, or whose
/// declared artifact fields violate ``ArtifactSchema``.
///
/// Same drift argument as ``ReceiptSchemaCheck``, plus a field contract: an artifact is a durable
/// work product, so an operator declaring an unknown `artifactType` or an unbounded body should be
/// refused before it runs rather than persisted and rejected at the storage layer.
public struct ArtifactSchemaCheck: DeterministicCheck {
    public let id = RecordSchemaCheckID.artifactSchema

    public init() { }

    public func evaluate(_ proposal: ActionProposal) async -> DeterministicCheckResult {
        // Field problems are checked even with no declared version: the values are present either
        // way, and an unknown `artifactType` is wrong regardless of which schema it claims.
        let fieldProblems = ArtifactSchema.problems(inDeclared: proposal.parameters)
        guard fieldProblems.isEmpty else {
            return .init(checkID: id, passed: false, detail: fieldProblems.joined(separator: "; "))
        }
        guard let declared = proposal.parameters[RecordSchemaKey.artifactVersion] else {
            return .init(checkID: id, passed: true, detail: "no declared artifact schema version")
        }
        guard let version = Int(declared.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            return .init(checkID: id, passed: false, detail: "unparseable artifact schema version")
        }
        guard ArtifactSchema.supports(version) else {
            let supported = ArtifactSchema.supportedVersions.sorted().map(String.init).joined(separator: ", ")
            return .init(
                checkID: id,
                passed: false,
                detail: "artifact schema version \(version) is not one this build reads (supports: \(supported))"
            )
        }
        return .init(checkID: id, passed: true)
    }
}

public extension DeterministicCheckRegistry {
    /// Registers the record-shape checks. Called from ``RuntimeHost/bootstrap()`` alongside the
    /// standard and policy check sets.
    /// - Returns: The IDs that collided with an already-registered check of a different type.
    @discardableResult
    func registerSchemaChecks() async -> [String] {
        let checks: [any DeterministicCheck] = [
            ReceiptSchemaCheck(),
            ArtifactSchemaCheck()
        ]
        return checks.compactMap { check in
            guard case let .conflict(id) = register(check) else { return nil }
            return id
        }
    }
}
