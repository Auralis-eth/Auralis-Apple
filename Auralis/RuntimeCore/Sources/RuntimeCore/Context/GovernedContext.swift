import CryptoKit
import Foundation

/// The immutable result of successful context-contract validation.
///
/// Operators receive this value instead of an untraceable dictionary. They can consume the approved
/// projection while retaining the contract, provenance, freshness, and evidence needed for audit.
public struct GovernedContext: Equatable, Sendable {
    public let bundle: ContextBundle
    public let contractIdentifier: String
    public let contractSchemaVersion: Int
    public let validatedAt: Date
    public let evidenceDigest: String

    /// Only ``ContextGovernanceBoundary`` may mint this proof of authorization.
    ///
    /// Keeping construction inside `RuntimeCore` makes the type a real capability: downstream
    /// packages can consume a governed context, but cannot manufacture or decode one around the
    /// validation boundary.
    init(
        bundle: ContextBundle,
        contract: ContextBundleContract,
        validatedAt: Date
    ) {
        self.bundle = bundle
        contractIdentifier = contract.identifier
        contractSchemaVersion = contract.schemaVersion
        self.validatedAt = validatedAt
        let evidence = "\(contract.evidenceDigest())|\(bundle.evidenceDigest())|\(validatedAt.timeIntervalSince1970)"
        evidenceDigest = SHA256.hash(data: Data(evidence.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
    }

    /// Reads one approved field without discarding its provenance, freshness, or data classification.
    public func field(_ key: String) -> ContextField? { bundle.field(key) }

    /// A value-free summary safe for worklogs and receipts.
    public var auditSummary: String {
        let fields = bundle.fields.map(\.key).sorted().joined(separator: ",")
        let sources = Set(bundle.fields.compactMap(\.source).map(\.rawValue)).sorted().joined(separator: ",")
        return "contract=\(contractIdentifier)@\(contractSchemaVersion); fields=[\(fields)]; sources=[\(sources)]; digest=\(evidenceDigest)"
    }
}
