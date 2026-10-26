import AuralisFoundation
import Foundation

/// The contribution-provenance vocabulary a receipt uses to say *what it acted on*, *what it
/// produced*, and *what came before it* — Phase 1, item 5.
///
/// Everything here is receipt-owned and dependency-light on purpose. The authoritative identity of an
/// NFT, a playlist, an account or an artifact lives in the domain that owns it, and importing those
/// domains here would reverse the dependency direction ADR-008 fixes: `ReceiptsCore` sits at layer 2
/// alongside `ArtifactCore`, and a receipt has to be able to name a resource from *any* layer above
/// it. So a reference carries a stable type namespace plus an opaque identifier, and resolution — if
/// a surface ever needs it — is the reader's job, performed in a layer that can see both domains.
///
/// This is deliberately **not** one universal identifier replacing domain-owned identity. The type
/// namespace is what keeps `nft/42` and `playlist/42` apart, and the identifier stays whatever the
/// owning domain already uses rather than being re-minted into a receipt-global scheme that would then
/// have to be kept in sync forever.

/// The resource a receipt's action affected.
///
/// `type` names the domain that owns the identifier; `identifier` is opaque to this package. Both are
/// required and non-empty, because a reference missing either half identifies nothing while looking
/// like it identifies something — and on an audit record that is worse than an absent reference, which
/// is at least visibly absent.
public struct ReceiptResourceReference: Hashable, Codable, Sendable {
    /// A stable type or namespace owned by the domain the identifier comes from — `"nft"`,
    /// `"playlist"`, `"account"`, `"operator"`. Stability matters more than beauty: it is persisted,
    /// hashed, and exported, so renaming one after receipts exist changes nothing already written and
    /// leaves two spellings of the same concept in history.
    public let type: String
    /// The identifier as the owning domain spells it. Opaque here: nothing in this package parses it,
    /// and no reader may branch on its contents — the same rule ``PrincipalID`` carries, for the same
    /// reason.
    public let identifier: String

    public init?(type: String, identifier: String) {
        guard type.isEmpty == false, identifier.isEmpty == false else {
            return nil
        }
        self.type = type
        self.identifier = identifier
    }

    // MARK: - Codable

    private enum CodingKeys: String, CodingKey {
        case type
        case identifier
    }

    /// Hand-written so the non-empty bound holds on the decoding path too. A synthesized conformance
    /// writes the stored properties directly, which would have made the half-identifying reference this
    /// type refuses to construct freely decodable from an archive.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)
        let identifier = try container.decode(String.self, forKey: .identifier)
        guard let reference = ReceiptResourceReference(type: type, identifier: identifier) else {
            throw DecodingError.dataCorruptedError(
                forKey: .identifier,
                in: container,
                debugDescription: "An affected-resource reference needs a non-empty type and identifier."
            )
        }
        self = reference
    }
}

/// What a receipt's action produced — a result or an artifact.
///
/// Structurally identical to ``ReceiptResourceReference`` and deliberately a *separate type*. The two
/// appear adjacently on every receipt that carries either, they take the same arguments, and swapping
/// them silently rewrites what the audit record claims: "acted on X, produced Y" becomes "acted on Y,
/// produced X", with both halves well-formed and nothing to notice. Making the swap a compile error
/// costs a duplicated six-line struct.
public struct ReceiptResultReference: Hashable, Codable, Sendable {
    /// See ``ReceiptResourceReference/type``. For artifacts this is conventionally `"artifact"`, with
    /// the `ArtifactCore` identifier in ``identifier`` — named rather than imported, for the
    /// dependency reason at the top of this file.
    public let type: String
    /// See ``ReceiptResourceReference/identifier``.
    public let identifier: String

    public init?(type: String, identifier: String) {
        guard type.isEmpty == false, identifier.isEmpty == false else {
            return nil
        }
        self.type = type
        self.identifier = identifier
    }

    // MARK: - Codable

    private enum CodingKeys: String, CodingKey {
        case type
        case identifier
    }

    /// See ``ReceiptResourceReference/init(from:)``.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)
        let identifier = try container.decode(String.self, forKey: .identifier)
        guard let reference = ReceiptResultReference(type: type, identifier: identifier) else {
            throw DecodingError.dataCorruptedError(
                forKey: .identifier,
                in: container,
                debugDescription: "A produced-result reference needs a non-empty type and identifier."
            )
        }
        self = reference
    }
}

/// The semantic-causality rules for ``ReceiptDraft/parentReceiptIDs``, and the one canonical byte form
/// the integrity envelope commits to.
///
/// **A parent means the earlier receipt semantically caused or enabled this action.** That is a claim a
/// writer makes deliberately, and it is the reason causality is *not* inferred from anything already on
/// a receipt. Timestamps, correlation IDs, artifact links, sequence order and `previousReceiptHash`
/// all correlate with causality without establishing it — `previousReceiptHash` especially, since it
/// is an integrity-chain link between whichever two receipts happened to be adjacent on an account and
/// has no semantic content whatsoever. Deriving causality from it would mean the ledger asserts a
/// causal story it was never told, and asserts it unfalsifiably, because the value is hashed.
///
/// Typed relationship kinds (`caused`, `enabled`, `derivedFrom`) and cross-ledger parent references are
/// deferred. Zero or more parent IDs in a stated order is the smallest thing that is useful and does
/// not commit to a taxonomy before there is evidence about which distinctions matter.
public enum ReceiptContributionParents {
    /// The separator in the canonical form. A UUID string contains no commas, so the encoding is
    /// unambiguous and ``parse(_:)`` is its exact inverse.
    private static let separator = ","

    /// The single string the integrity envelope hashes, or `nil` for no parents.
    ///
    /// Empty and `nil` must map to the same bytes, because they are the same claim — "this action had
    /// no stated cause" — and letting them hash differently would mean two receipts asserting the same
    /// thing carried different chain hashes. This is the same normalization
    /// ``ReceiptDraft/correlationID`` applies to `""`, for the same reason.
    ///
    /// `UUID.uuidString` is uppercase, so the canonical form is uppercase. Order is preserved rather
    /// than sorted: the order is part of what the writer stated.
    public static func canonicalRawValue(_ parentReceiptIDs: [UUID]?) -> String? {
        guard let parentReceiptIDs, parentReceiptIDs.isEmpty == false else {
            return nil
        }
        return parentReceiptIDs.map(\.uuidString).joined(separator: separator)
    }

    /// The inverse of ``canonicalRawValue(_:)``.
    ///
    /// - Returns: The parsed IDs, `[]` for `nil`, or `nil` when the stored column does not parse —
    ///   which an honestly written row cannot produce, since every writer goes through
    ///   ``canonicalRawValue(_:)``. A caller that gets `nil` is looking at an edited column and must
    ///   report it rather than silently treating it as "no parents": dropping an unparseable value
    ///   would put the column outside the reach of every check, which is exactly the hole the
    ///   envelope-coverage test exists to catch.
    public static func parse(_ rawValue: String?) -> [UUID]? {
        guard let rawValue else { return [] }
        guard rawValue.isEmpty == false else { return nil }
        var parsed: [UUID] = []
        for component in rawValue.components(separatedBy: separator) {
            guard let id = UUID(uuidString: component) else { return nil }
            parsed.append(id)
        }
        return parsed
    }

    /// Whether a stored column is exactly what ``canonicalRawValue(_:)`` would have written for its own
    /// parsed contents.
    ///
    /// Needed because the hash commits to the *parsed list* by way of the canonical form, while the
    /// row stores a string. Those agree for every honest row and can be made to disagree by editing
    /// the column into a non-canonical spelling of the same IDs — lowercased, reordered whitespace, a
    /// trailing separator. Such an edit changes nothing a reader sees and would otherwise sit outside
    /// every check, so the storage layer compares the column against its own canonical form the same
    /// way it compares `accountKey` against `derivedAccountKey`.
    public static func isCanonical(_ rawValue: String?) -> Bool {
        guard let parsed = parse(rawValue) else { return false }
        return canonicalRawValue(parsed) == rawValue
    }

    /// Human-readable violations of the parent contract, or an empty array when the list is valid.
    ///
    /// Advisory in the same way ``ReceiptSchema/problems(inDeclared:)`` is: it states the rule so that
    /// any store can apply it. ``ReceiptPersistenceStore`` enforces it, plus the existence requirement
    /// this function cannot check — it has no ledger to look in.
    ///
    /// - Parameter receiptID: The id of the receipt being written, when it is known. Self-reference is
    ///   checked against it. The append path mints the id before hashing, so it is known there; a
    ///   caller validating a draft has no id yet and passes `nil`.
    public static func problems(_ parentReceiptIDs: [UUID]?, receiptID: UUID? = nil) -> [String] {
        guard let parentReceiptIDs, parentReceiptIDs.isEmpty == false else { return [] }
        var problems: [String] = []
        var seen = Set<UUID>()
        for parent in parentReceiptIDs where seen.insert(parent).inserted == false {
            problems.append("Parent receipt \(parent.uuidString) is listed more than once.")
        }
        if let receiptID, parentReceiptIDs.contains(receiptID) {
            problems.append("Receipt \(receiptID.uuidString) lists itself as its own parent.")
        }
        return problems
    }
}

/// A receipt violated the Phase 1 parent-receipt contract, so it was refused rather than written.
///
/// Refused rather than normalized, unlike duplicate beneficiaries on an `OwnershipDescriptor`. The
/// difference is what the two statements mean: naming the same beneficiary twice states one fact twice,
/// while naming the same parent twice, or naming a parent that does not exist, states something that
/// is not true about causality — and a receipt is an append-only, hashed, immutable fact. There is no
/// repairing it afterwards, so the only place to refuse is before the write.
public enum ReceiptParentContractError: LocalizedError, Equatable, Sendable {
    /// The same parent appears more than once, or the receipt names itself.
    case invalidParents(reasons: [String])
    /// A parent names a receipt that is not in this store. Parents must refer to receipts that already
    /// exist in the same ledger at append time — a dangling parent is a causal claim about something
    /// the ledger cannot show ever happened.
    case unknownParent(UUID)

    public var errorDescription: String? {
        switch self {
        case let .invalidParents(reasons):
            return "This receipt's parent list is invalid: \(reasons.joined(separator: " "))"
        case let .unknownParent(parentReceiptID):
            return "Parent receipt \(parentReceiptID.uuidString) is not present in this receipt store, so it cannot be named as a cause."
        }
    }
}

/// The six contribution-provenance columns, carried as columns so each is hashed on its own.
///
/// Grouped for exactly the reason ``ReceiptActorColumns`` and ``ReceiptAuthorityColumns`` are, and
/// against exactly the same defect. Passing the composed ``ReceiptResourceReference?`` and
/// ``ReceiptResultReference?`` instead would gate each pair of columns on one of its halves being
/// present: a row carrying an `affectedResourceType` with no identifier reconstructs as `nil`, so
/// *both* columns would drop out of the envelope and a fabricated type could be written into a row
/// without changing its chain hash. Columns keep every one of them hashed independently, and that
/// changes no honest row's hash — a writer sets both halves from one reference, and all-absent still
/// encodes as all-omitted.
public struct ReceiptContributionColumns: Equatable, Sendable {
    public let principalID: String?
    public let affectedResourceType: String?
    public let affectedResourceIdentifier: String?
    public let producedResultType: String?
    public let producedResultIdentifier: String?
    /// The canonical form from ``ReceiptContributionParents/canonicalRawValue(_:)``, hashed as one
    /// string rather than as a JSON array so the envelope keeps the "optional fields are omitted when
    /// nil" shape that lets columns be added without rehashing history.
    public let parentReceiptIDs: String?

    /// No receipt provenance at all — what every row written before these columns existed carries, and
    /// the default for every writer that does not state any.
    public static let unattributed = ReceiptContributionColumns(
        principalID: nil,
        affectedResourceType: nil,
        affectedResourceIdentifier: nil,
        producedResultType: nil,
        producedResultIdentifier: nil,
        parentReceiptIDs: nil
    )

    public init(
        principalID: String?,
        affectedResourceType: String?,
        affectedResourceIdentifier: String?,
        producedResultType: String?,
        producedResultIdentifier: String?,
        parentReceiptIDs: String?
    ) {
        self.principalID = principalID
        self.affectedResourceType = affectedResourceType
        self.affectedResourceIdentifier = affectedResourceIdentifier
        self.producedResultType = producedResultType
        self.producedResultIdentifier = producedResultIdentifier
        self.parentReceiptIDs = parentReceiptIDs
    }

    /// For callers that hold the read model rather than the raw columns — the append path, which has a
    /// ``ReceiptDraft``, and the export verifier, which only ever sees a ``ReceiptRecord``.
    ///
    /// Lossless in that direction, which is the only direction it is used in: a reference that exists
    /// carries both of its values, and an absent one means both columns were absent. The *other*
    /// direction is lossy by design — see the type's note on why a half-present pair must not
    /// reconstruct as absent.
    public init(
        principal: PrincipalID?,
        affectedResource: ReceiptResourceReference?,
        producedResult: ReceiptResultReference?,
        parentReceiptIDs: [UUID]?
    ) {
        self.init(
            principalID: principal?.rawValue,
            affectedResourceType: affectedResource?.type,
            affectedResourceIdentifier: affectedResource?.identifier,
            producedResultType: producedResult?.type,
            producedResultIdentifier: producedResult?.identifier,
            parentReceiptIDs: ReceiptContributionParents.canonicalRawValue(parentReceiptIDs)
        )
    }
}
