import AuralisFoundation
import Foundation

public enum ReceiptPayloadFieldSensitivity: Equatable, Sendable {
    case `public`
    case redact
    case hash
    case truncate(maxLength: Int)
}

public enum ReceiptPayloadValueKind: Equatable, Sendable {
    case chain
    case url
    case walletAddress
    case timestamp
    case label
    case errorMessage
    case copiedText
    case freeformText
    case opaqueToken
    case unknownString
    case number
    case bool
    case object
    case array
    case null
}

public struct ReceiptPayloadField: Equatable, Sendable {
    public let key: String
    public let value: ReceiptJSONValue
    public let sensitivity: ReceiptPayloadFieldSensitivity
    public let valueKind: ReceiptPayloadValueKind
    /// What the *elements* of an array value are, when `value` is `.array`.
    ///
    /// Separate from ``valueKind`` because both facts are true at once: the field's value really is
    /// an array, and its elements really are (say) labels. Collapsing the two lost the second one —
    /// the sanitizer classifies each element against its parent field, so an element inherited
    /// `.array`, and `.array` is not a string kind. Every element of every `stringArray` therefore
    /// sanitized to `<redacted-unexpected-string>`: the media ids a music receipt claims to record,
    /// and the chains a context receipt claims to scope to, were both placeholders on disk.
    ///
    /// `nil` for non-array values, and for an array whose elements have no declared kind — the
    /// sanitizer falls back to ``valueKind`` there, which is the pre-existing behaviour.
    public let elementValueKind: ReceiptPayloadValueKind?

    public init(
        key: String,
        value: ReceiptJSONValue,
        sensitivity: ReceiptPayloadFieldSensitivity,
        valueKind: ReceiptPayloadValueKind,
        elementValueKind: ReceiptPayloadValueKind? = nil
    ) {
        self.key = key
        self.value = value
        self.sensitivity = sensitivity
        self.valueKind = valueKind
        self.elementValueKind = elementValueKind
    }
}

/// Unsanitized input used at orchestration boundaries before persistence.
public struct RawReceiptPayload: Equatable, Sendable {
    public let fields: [ReceiptPayloadField]

    public init(fields: [ReceiptPayloadField]) {
        self.fields = fields
    }
}

public protocol TypedReceiptPayload {
    var fields: [ReceiptPayloadField] { get }
}

public extension TypedReceiptPayload {
    var rawPayload: RawReceiptPayload {
        RawReceiptPayload(fields: fields)
    }
}

public extension ReceiptPayloadField {
    static func `public`(_ key: String, string value: String, kind: ReceiptPayloadValueKind) -> ReceiptPayloadField {
        ReceiptPayloadField(
            key: key,
            value: .string(value),
            sensitivity: .public,
            valueKind: kind
        )
    }

    static func redacted(_ key: String, string value: String, kind: ReceiptPayloadValueKind) -> ReceiptPayloadField {
        ReceiptPayloadField(
            key: key,
            value: .string(value),
            sensitivity: .redact,
            valueKind: kind
        )
    }

    static func hashed(_ key: String, string value: String, kind: ReceiptPayloadValueKind) -> ReceiptPayloadField {
        ReceiptPayloadField(
            key: key,
            value: .string(value),
            sensitivity: .hash,
            valueKind: kind
        )
    }

    static func truncated(
        _ key: String,
        string value: String,
        kind: ReceiptPayloadValueKind,
        maxLength: Int
    ) -> ReceiptPayloadField {
        ReceiptPayloadField(
            key: key,
            value: .string(value),
            sensitivity: .truncate(maxLength: maxLength),
            valueKind: kind
        )
    }

    static func number(_ key: String, _ value: Double) -> ReceiptPayloadField {
        ReceiptPayloadField(
            key: key,
            value: .number(value),
            sensitivity: .public,
            valueKind: .number
        )
    }

    static func bool(_ key: String, _ value: Bool) -> ReceiptPayloadField {
        ReceiptPayloadField(
            key: key,
            value: .bool(value),
            sensitivity: .public,
            valueKind: .bool
        )
    }

    /// An array of strings, where `kind` describes each *element*.
    ///
    /// `kind` used to be accepted and dropped on the floor, which made every element of every array
    /// receipt a `<redacted-unexpected-string>` placeholder. It is now carried on
    /// ``ReceiptPayloadField/elementValueKind``, which is what the sanitizer classifies elements by.
    static func stringArray(
        _ key: String,
        values: [String],
        kind: ReceiptPayloadValueKind,
        sensitivity: ReceiptPayloadFieldSensitivity = .public
    ) -> ReceiptPayloadField {
        ReceiptPayloadField(
            key: key,
            value: .array(values.map(ReceiptJSONValue.string)),
            sensitivity: sensitivity,
            valueKind: .array,
            elementValueKind: kind
        )
    }

    static func null(_ key: String) -> ReceiptPayloadField {
        ReceiptPayloadField(
            key: key,
            value: .null,
            sensitivity: .public,
            valueKind: .null
        )
    }
}

/// Phase 0 append requests are immutable facts. The store adds identifiers and ordering metadata.
public struct ReceiptDraft: Equatable, Sendable {
    public let createdAt: Date
    /// The coarse filter column, *derived* from ``actorDetail`` and not settable on its own.
    ///
    /// It used to be an independent defaulted parameter beside a required `actorDetail`, which made
    /// `ReceiptDraft(actorDetail: .human, …)` yield `actor == .system` alongside
    /// `actorDetail == .human`. That is not a display glitch: `actor` is persisted as the filterable
    /// column *and* committed to the integrity chain as `actorRawValue`, so once written the
    /// disagreement is unfalsifiable — the ledger attests to two different answers for who acted and
    /// neither can be shown to be the wrong one. Writers were also free to pass a third answer that
    /// matched neither. Deriving it makes the disagreement unrepresentable rather than merely
    /// discouraged, which is what `ReceiptEventLogger.append` and `StoredReceipt` were each
    /// hand-asserting at their own boundary.
    public let actor: ReceiptActor
    /// Structured actor attribution (P0.5-602). Required on the way in — a receipt that cannot say who
    /// acted has no place on a trust surface, and while this was optional the majority of receipts by
    /// volume persisted `nil`. Optional on ``ReceiptRecord`` on the way out only because the column
    /// itself is optional in storage.
    public let actorDetail: ReceiptActorDetail?
    /// The authority the action proceeded under (P0.5-601/602).
    ///
    /// Required on the way in, with no default, for the same reason as ``actorDetail``: while it was
    /// defaulted to `nil`, only 2 of 18 writers ever set it, so the "under what authority" leg was
    /// absent from the large majority of history. The type stays optional because `nil` is a real
    /// answer — the action never reached a point where authority was resolved — but the writer now
    /// has to say so deliberately. Standing-policy work should pass
    /// ``ReceiptAuthorityDetail/policyDefault(capability:reason:)`` rather than `nil`.
    public let authorityDetail: ReceiptAuthorityDetail?
    public let mode: ReceiptMode
    public let trigger: String
    public let scope: String
    public let summary: String
    public let provenance: String
    public let isSuccess: Bool
    /// The workflow run this receipt belongs to — the "through what workflow" leg of actor attribution
    /// (P0.5-601/602), and the key that files a receipt alongside the session and worklog entries for
    /// the same work.
    ///
    /// Required on the way in, with no default, for the same reason as ``authorityDetail``: while it
    /// defaulted to `nil`, writers that *had* a correlation id in hand still shipped receipts without
    /// one — the runtime pause receipt opened a session under `runtime.pause` and then filed its
    /// receipt under nothing, so `receipts(forCorrelationID:)` could never retrieve it. `nil` stays a
    /// real answer for genuinely un-correlated work (a one-shot search answer, a standing-policy
    /// denial), but the writer now has to say so deliberately.
    ///
    /// Stays optional on purpose. Substituting a fresh UUID for `nil` would make the receipt *assert*
    /// membership in a workflow run that no session, worklog, or caller holds — unretrievable by
    /// ``ReceiptStore/receipts(forCorrelationID:)`` and, because the value is folded into the chain
    /// hash, permanently unfalsifiable. An empty string normalizes to `nil` so that "" and `nil`
    /// cannot hash differently while meaning the same thing.
    public let correlationID: String?
    public let timelineAccountAddress: String?
    public let timelineChainRawValue: String?
    /// The canonical principal this contribution is attributed to (Phase 1), or `nil` when no stable
    /// principal identity is available.
    ///
    /// Optional, and must stay optional. ``actorDetail`` already answers *who acted* for the runtime,
    /// and it answers it for every receipt; this answers the narrower question of which principal the
    /// contribution belongs to in ownership terms, which is frequently unknown. Substituting a minted
    /// identifier for `nil` would make the receipt *assert* an attribution nobody holds — the same
    /// failure ``correlationID`` documents, and worse here, because a principal is the thing a future
    /// economic system would key on.
    ///
    /// Carries no authority. See `OWNERSHIP.md`, constraint 5.
    public let principal: PrincipalID?
    /// What this action affected, as a receipt-owned reference (Phase 1).
    ///
    /// Distinct from ``scope``, which is a coarse string category the console groups by, and from
    /// ``timelineAccountAddress``, which is the ledger's account *key*. This names a specific resource
    /// in a specific domain.
    public let affectedResource: ReceiptResourceReference?
    /// What this action produced (Phase 1) — a result or an artifact.
    public let producedResult: ReceiptResultReference?
    /// Receipts that semantically caused or enabled this action (Phase 1), in the order the writer
    /// stated them.
    ///
    /// **Never inferred.** See ``ReceiptContributionParents`` for why `previousReceiptHash`,
    /// timestamps, correlation IDs and sequence order are all unacceptable substitutes. Validated at
    /// append time rather than here, because two of the three rules — self-reference and existence —
    /// need facts a draft does not have: the receipt's own id and the ledger to look in.
    public let parentReceiptIDs: [UUID]
    public let details: ReceiptPayload

    /// - Note: There is deliberately no `actor:` parameter — see ``actor``.
    public init(
        createdAt: Date = .now,
        actorDetail: ReceiptActorDetail,
        authorityDetail: ReceiptAuthorityDetail?,
        mode: ReceiptMode = .observe,
        trigger: String,
        scope: String,
        summary: String,
        provenance: String,
        isSuccess: Bool,
        correlationID: String?,
        timelineAccountAddress: String? = nil,
        timelineChainRawValue: String? = nil,
        principal: PrincipalID? = nil,
        affectedResource: ReceiptResourceReference? = nil,
        producedResult: ReceiptResultReference? = nil,
        parentReceiptIDs: [UUID] = [],
        details: ReceiptPayload
    ) {
        self.principal = principal
        self.affectedResource = affectedResource
        self.producedResult = producedResult
        self.parentReceiptIDs = parentReceiptIDs
        self.createdAt = createdAt
        self.actor = actorDetail.coarseActor
        self.actorDetail = actorDetail
        self.authorityDetail = authorityDetail
        self.mode = mode
        self.trigger = trigger
        self.scope = scope
        self.summary = summary
        self.provenance = provenance
        self.isSuccess = isSuccess
        self.correlationID = correlationID.flatMap { $0.isEmpty ? nil : $0 }
        self.timelineAccountAddress = timelineAccountAddress
        self.timelineChainRawValue = timelineChainRawValue
        self.details = details
    }

    public init(
        createdAt: Date = .now,
        category: String,
        kind: String,
        correlationID: String?,
        payload: ReceiptPayload,
        actorDetail: ReceiptActorDetail,
        authorityDetail: ReceiptAuthorityDetail?,
        mode: ReceiptMode = .observe,
        summary: String? = nil,
        provenance: String = "local",
        isSuccess: Bool = true,
        timelineAccountAddress: String? = nil,
        timelineChainRawValue: String? = nil,
        principal: PrincipalID? = nil,
        affectedResource: ReceiptResourceReference? = nil,
        producedResult: ReceiptResultReference? = nil,
        parentReceiptIDs: [UUID] = []
    ) {
        self.init(
            createdAt: createdAt,
            actorDetail: actorDetail,
            authorityDetail: authorityDetail,
            mode: mode,
            trigger: kind,
            scope: category,
            summary: summary ?? kind,
            provenance: provenance,
            isSuccess: isSuccess,
            correlationID: correlationID,
            timelineAccountAddress: timelineAccountAddress,
            timelineChainRawValue: timelineChainRawValue,
            principal: principal,
            affectedResource: affectedResource,
            producedResult: producedResult,
            parentReceiptIDs: parentReceiptIDs,
            details: payload
        )
    }

    /// This draft's contribution provenance as the columns the integrity envelope hashes.
    ///
    /// Exists so the append path cannot derive them differently from the way the stored row does —
    /// the same discipline `accountAddress` and `chainRawValue` are held to by
    /// ``ReceiptAccountAddress`` and ``ReceiptChainScope``, and for the same reason: a writer that
    /// hashes one value and stores another produces a row `verifyIntegrity()` reports as tampered,
    /// permanently, on a receipt that was written correctly.
    public var contributionColumns: ReceiptContributionColumns {
        ReceiptContributionColumns(
            principal: principal,
            affectedResource: affectedResource,
            producedResult: producedResult,
            parentReceiptIDs: parentReceiptIDs
        )
    }
}

/// Receipt records are immutable historical facts. Append-only means stores may create and list them, export them, or reset the full collection.
public struct ReceiptRecord: Identifiable, Codable, Equatable, Sendable {
    public let id: UUID
    public let sequenceID: Int
    public let createdAt: Date
    public let actor: ReceiptActor
    /// Structured actor attribution (P0.5-602); `nil` for legacy receipts written before the column.
    public let actorDetail: ReceiptActorDetail?
    /// The authority the action proceeded under (P0.5-601/602); `nil` when none was resolved or for
    /// legacy receipts written before the column.
    public let authorityDetail: ReceiptAuthorityDetail?
    public let mode: ReceiptMode
    public let trigger: String
    public let scope: String
    public let summary: String
    public let provenance: String
    public let isSuccess: Bool
    public let correlationID: String?
    /// Normalized account scope used by the integrity chain. Exported so an independent verifier
    /// can reproduce the exact chain hash without inferring identity from presentation payloads.
    public let accountAddress: String?
    /// Chain scope used by the integrity chain, when the receipt is chain-specific.
    public let chainRawValue: String?
    public let accountSequenceID: Int
    public let payloadHash: String
    public let previousReceiptHash: String
    public let chainHash: String
    /// Base64 DER P-256 signature over `chainHash` (SEC-101). Optional for back-compat.
    public let signature: String?
    /// Base64 raw P-256 public key that verifies `signature`.
    public let signerPublicKey: String?
    /// Which ``ReceiptIntegrityEnvelope`` shape this record's `chainHash` was taken over, so an
    /// independent verifier rebuilds the same envelope. `nil` means
    /// ``ReceiptIntegrityEnvelopeVersion/legacy``, which keeps archives written before this field
    /// decodable and their `recordsHash` unchanged.
    public let integrityEnvelopeVersion: Int?
    /// The `actor`/`mode` strings **as stored**, carried only when this build cannot name them.
    ///
    /// The chain hash commits to the raw strings rather than to the typed cases, precisely so a row
    /// written by a newer build is not mistaken for a corrupted one (see
    /// ``ReceiptIntegrity/chainHash(receiptID:envelopeVersion:sequenceID:accountSequenceID:createdAt:actorRawValue:actorColumns:authorityColumns:contributionColumns:modeRawValue:trigger:scope:summary:provenance:isSuccess:correlationID:accountAddress:chainRawValue:payloadHash:signerPublicKey:previousReceiptHash:)``).
    /// `ReceiptRecord` had no way to carry those strings, so the export wrote the *degraded* typed
    /// value — `ReceiptMode(rawValue:) ?? .operate` — while copying the `chainHash` column verbatim,
    /// and the bundled verifier then recomputed from the degraded value and reported an honest
    /// archive of a downgraded ledger as `.tampered`. The local store was fixed for this in Round 10;
    /// the archive boundary was not, which is where the guarantee actually has to hold.
    ///
    /// **Present only when the stored string does not round-trip through the typed case**, which is
    /// the same discipline ``integrityEnvelopeVersion`` uses and it matters for the same reason: for
    /// every value this build *can* name the raw string is identical to `mode.rawValue`, so omitting
    /// it leaves the overwhelmingly common archive byte-identical and its `recordsHash` unchanged. A
    /// verifier reads `modeRawValue ?? mode.rawValue`, which is exact in both cases.
    public let actorRawValue: String?
    /// See ``actorRawValue``.
    public let modeRawValue: String?
    /// The canonical principal this contribution is attributed to (Phase 1); `nil` when none was
    /// recorded or for receipts written before the column. See ``ReceiptDraft/principal``.
    public let principal: PrincipalID?
    /// What the action affected (Phase 1); `nil` when none was recorded or for legacy receipts.
    public let affectedResource: ReceiptResourceReference?
    /// What the action produced (Phase 1); `nil` when none was recorded or for legacy receipts.
    public let producedResult: ReceiptResultReference?
    /// Receipts that semantically caused or enabled this action (Phase 1).
    ///
    /// **Optional rather than a defaulted `[UUID]`, and the distinction is about bytes, not taste.**
    /// `ReceiptRecord` is `Codable` and *is* the export format, and a non-optional array would be
    /// emitted on every record — `"parentReceiptIDs":[]` — which changes the canonical bytes of every
    /// receipt ever exported and therefore the `recordsHash` of every archive already signed. The
    /// optional is omitted when `nil`, so an archive of receipts with no stated parents stays
    /// byte-identical to one written before this field existed.
    ///
    /// `nil` and `[]` mean the same thing — no stated cause — and
    /// ``ReceiptContributionParents/canonicalRawValue(_:)`` maps them to the same hashed bytes, so the
    /// two cannot produce different chain hashes while making the same claim. The initializer
    /// normalizes `[]` to `nil` so this package never *writes* the redundant spelling; a decoder that
    /// reads one from a third-party archive preserves it, since re-encoding it unchanged is what keeps
    /// that archive's own `recordsHash` reproducible.
    public let parentReceiptIDs: [UUID]?
    public let details: ReceiptPayload

    /// This record's contribution provenance as the columns the integrity envelope hashes, so an
    /// independent verifier rebuilds the envelope the exporting store committed to.
    public var contributionColumns: ReceiptContributionColumns {
        ReceiptContributionColumns(
            principal: principal,
            affectedResource: affectedResource,
            producedResult: producedResult,
            parentReceiptIDs: parentReceiptIDs
        )
    }

    public init(
        id: UUID,
        sequenceID: Int,
        createdAt: Date,
        actor: ReceiptActor,
        actorDetail: ReceiptActorDetail?,
        authorityDetail: ReceiptAuthorityDetail?,
        mode: ReceiptMode,
        trigger: String,
        scope: String,
        summary: String,
        provenance: String,
        isSuccess: Bool,
        correlationID: String?,
        accountAddress: String? = nil,
        chainRawValue: String? = nil,
        accountSequenceID: Int = 1,
        payloadHash: String = "",
        previousReceiptHash: String = "",
        chainHash: String = "",
        signature: String? = nil,
        signerPublicKey: String? = nil,
        integrityEnvelopeVersion: Int? = nil,
        actorRawValue: String? = nil,
        modeRawValue: String? = nil,
        principal: PrincipalID? = nil,
        affectedResource: ReceiptResourceReference? = nil,
        producedResult: ReceiptResultReference? = nil,
        parentReceiptIDs: [UUID]? = nil,
        details: ReceiptPayload
    ) {
        self.integrityEnvelopeVersion = integrityEnvelopeVersion
        self.actorRawValue = actorRawValue
        self.modeRawValue = modeRawValue
        self.principal = principal
        self.affectedResource = affectedResource
        self.producedResult = producedResult
        // Normalized so this package never writes `[]` where `nil` means the same thing — see
        // ``parentReceiptIDs``.
        self.parentReceiptIDs = (parentReceiptIDs?.isEmpty == true) ? nil : parentReceiptIDs
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
        self.accountAddress = accountAddress
        self.chainRawValue = chainRawValue
        self.accountSequenceID = accountSequenceID
        self.payloadHash = payloadHash
        self.previousReceiptHash = previousReceiptHash
        self.chainHash = chainHash
        self.signature = signature
        self.signerPublicKey = signerPublicKey
        self.details = details
    }
}

/// The canonical JSON form of the receipt provenance format — the one both the hashes and the wire
/// bytes are defined in terms of.
///
/// It exists because "canonical" was previously only half-specified. The storage layer sorted keys
/// but left dates at `JSONEncoder`'s default, so `createdAt` went out as seconds since the *2001*
/// reference date: a Foundation implementation detail rather than a documented format, which made the
/// manifest hashes reproducible only by this same Swift runtime. That is at odds with the point of
/// the format, which is that a third party can confirm a receipt sequence without trusting Auralis.
///
/// Every producer and consumer of these bytes must go through here. A plain `JSONDecoder` reads a
/// pinned `createdAt` 31 years off and then recomputes a mismatched `recordsHash`, which the verifier
/// reports as a tampered export on an archive that was written correctly.
public enum ReceiptCanonicalJSON {
    public static func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .secondsSince1970
        return encoder
    }

    public static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        return decoder
    }
}

/// The independently verifiable receipt-export format. The manifest authenticates the complete
/// record set and protected chain heads; callers establish external provenance by pinning and
/// supplying ``trustAnchor/fingerprint`` to the storage verifier.
public struct ReceiptProvenanceExport: Codable, Equatable, Sendable {
    public static let currentFormat = "com.auralis.receipts.provenance"
    public static let currentVersion = 1

    public let format: String
    public let version: Int
    public let records: [ReceiptRecord]
    public let manifest: ReceiptProvenanceManifest
    public let manifestHash: String
    public let manifestSignature: String
    public let trustAnchor: ReceiptProvenanceTrustAnchor

    public init(
        format: String = Self.currentFormat,
        version: Int = Self.currentVersion,
        records: [ReceiptRecord],
        manifest: ReceiptProvenanceManifest,
        manifestHash: String,
        manifestSignature: String,
        trustAnchor: ReceiptProvenanceTrustAnchor
    ) {
        self.format = format
        self.version = version
        self.records = records
        self.manifest = manifest
        self.manifestHash = manifestHash
        self.manifestSignature = manifestSignature
        self.trustAnchor = trustAnchor
    }
}

public struct ReceiptProvenanceManifest: Codable, Equatable, Sendable {
    public let recordCount: Int
    public let recordsHash: String
    public let chainHeads: [ReceiptProvenanceChainHead]
    /// The highest `sequenceID` the exporting ledger was known to have reached, so a third party can
    /// form the same completeness *observation* the live store does — see
    /// ``ReceiptIntegrity/completenessAdvisory(sequenceIDs:highWaterMark:completenessUnconfirmed:)``.
    ///
    /// **Advisory, not a verdict input.** It is inside the manifest and therefore inside the signed
    /// `manifestHash`, so it cannot be stripped without breaking the signature — but a signature only
    /// proves the *exporting device* asserted it, and that device's mark was an unauthenticated local
    /// Keychain item. So a verifier surfaces it and decides for itself; it does not gate on it.
    ///
    /// `nil` when the exporting device had no mark to publish, which keeps archives written before
    /// this field both decodable and byte-identical.
    public let ledgerHighWaterMark: Int?
    /// `true` when the exporting device held records but could not establish a high-water mark, so
    /// nobody — here or downstream — can say whether anything was removed from the end of the ledger.
    ///
    /// Needed because an omitted ``ledgerHighWaterMark`` is ambiguous: it means both "this archive
    /// predates the field" and "this device had no mark". Without the distinction, a verifier could
    /// not tell the two apart and the exporting device's own observation never crossed the boundary.
    /// Advisory in the same way ``ledgerHighWaterMark`` is.
    public let ledgerCompletenessUnconfirmed: Bool?

    public init(
        recordCount: Int,
        recordsHash: String,
        chainHeads: [ReceiptProvenanceChainHead],
        ledgerHighWaterMark: Int? = nil,
        ledgerCompletenessUnconfirmed: Bool? = nil
    ) {
        self.recordCount = recordCount
        self.recordsHash = recordsHash
        self.chainHeads = chainHeads
        self.ledgerHighWaterMark = ledgerHighWaterMark
        self.ledgerCompletenessUnconfirmed = ledgerCompletenessUnconfirmed
    }
}

public struct ReceiptProvenanceChainHead: Codable, Equatable, Sendable {
    public let accountKey: String
    public let accountSequenceID: Int
    public let chainHash: String

    public init(accountKey: String, accountSequenceID: Int, chainHash: String) {
        self.accountKey = accountKey
        self.accountSequenceID = accountSequenceID
        self.chainHash = chainHash
    }
}

public struct ReceiptProvenanceTrustAnchor: Codable, Equatable, Sendable {
    public let algorithm: String
    public let publicKey: String
    public let fingerprint: String

    public init(algorithm: String, publicKey: String, fingerprint: String) {
        self.algorithm = algorithm
        self.publicKey = publicKey
        self.fingerprint = fingerprint
    }
}

public extension ReceiptDraft {
    var category: String { scope }
    var kind: String { trigger }
    var payload: ReceiptPayload { details }
}

public extension ReceiptRecord {
    var category: String { scope }
    var kind: String { trigger }
    var payload: ReceiptPayload { details }
}

/// Sanitization must happen before persistence so export can use persisted payloads directly.
public protocol ReceiptPayloadSanitizing: Sendable {
    func sanitize(_ payload: RawReceiptPayload) -> ReceiptPayload
}

/// What this device can say about the integrity of the whole receipt ledger.
///
/// A dependency-free mirror of `ReceiptStorage`'s `ReceiptIntegrityVerificationResult`, declared here
/// because `ReceiptStore` lives in this leaf package and cannot reference the storage layer. The three
/// states carry the distinction that storage type exists to protect, so read its documentation before
/// changing any of this: **"this device cannot vouch for these rows"** is not **"these rows have been
/// altered"**.
public struct ReceiptLedgerAttestation: Equatable, Sendable {
    public enum Status: String, Equatable, Sendable {
        /// Every row chain-consistent and signed by this device's current identity.
        case verified
        /// Structurally intact but not provable from here — an unsigned prefix from before signing
        /// existed, rows signed by a previous identity, or missing anchors after a device restore.
        /// An ordinary, expected state. Must never be presented as tampering.
        case unattested
        /// Genuinely inconsistent: a broken chain, a sequence gap, or a substituted signature.
        case tampered
    }

    public let status: Status
    /// Why the verdict is not ``Status/verified``, whatever its severity.
    public let failureReason: String?
    /// A *suggestion to investigate* about rows possibly removed from the end of the ledger.
    ///
    /// Advisory only, and deliberately independent of ``status`` — it comes from an unauthenticated
    /// Keychain mark whose absence is equally uninformative. Show it alongside the status; never gate
    /// trust on it, and never read its absence as confirmation that nothing was removed.
    public let completenessAdvisory: String?

    public init(status: Status, failureReason: String? = nil, completenessAdvisory: String? = nil) {
        self.status = status
        self.failureReason = failureReason
        self.completenessAdvisory = completenessAdvisory
    }

    /// `true` only when this device can cryptographically vouch for every row present — the property
    /// a trust surface should show. Not a claim that no rows were removed; see
    /// ``completenessAdvisory``.
    public var isFullyAttested: Bool { status == .verified }
}

/// Append-only Phase 0 receipt storage surface.
///
/// Contract rules:
/// - `append` is the only write path for individual receipts
/// - normal reads must stay bounded
/// - `exportAll` is the only bulk-read path
/// - `resetAll` is a separate destructive operation, not a convenience delete helper
/// - stores must not invent correlation IDs
public protocol ReceiptStore: Sendable {
    func append(_ receipt: ReceiptDraft) async throws -> ReceiptRecord
    func latest(limit: Int) async throws -> [ReceiptRecord]
    func receipts(
        forCorrelationID correlationID: String,
        limit: Int
    ) async throws -> [ReceiptRecord]
    /// The complete history, newest first, as an ordinary read.
    ///
    /// Distinct from ``exportAll()`` on purpose. `exportAll()` builds a signed, independently
    /// verifiable archive: it runs a full integrity verification (a payload decode, two canonical
    /// encodes, two SHA-256s and a P-256 signature check *per row*), signs a manifest, and refuses
    /// outright on a tampered ledger. That is correct for an export and wrong for a query — callers
    /// that only wanted the rows were paying for N signature verifications and a JSON round trip on
    /// every read, and inheriting an all-or-nothing integrity gate that made an unrelated storage
    /// problem look like "history unavailable".
    func allRecords() async throws -> [ReceiptRecord]
    /// This device's integrity verdict for the whole ledger, or `nil` when this store cannot produce
    /// one.
    ///
    /// Exists because ``allRecords()`` deliberately performs no verification. Listing receipts is a
    /// read and should not pay for N signature checks — but a surface that *shows a person their
    /// audit trail* still has to be able to say whether the rows are attestable, and before this
    /// there was no way to ask without going through `exportAll()`'s all-or-nothing gate. Pair the
    /// two: `allRecords()` for the rows, this for what may be claimed about them.
    ///
    /// `nil` means **"unknown"**, not "fine". Render it as "cannot vouch", the same as
    /// ``ReceiptLedgerAttestation/Status/unattested``.
    func ledgerAttestation() async throws -> ReceiptLedgerAttestation?
    func exportAll() async throws -> Data
    func resetAll() async throws
}

public extension ReceiptStore {
    /// Falls back to a large bounded read, so a conformer that has no cheaper bulk path — test
    /// doubles, in-memory stores — does not have to implement one.
    func allRecords() async throws -> [ReceiptRecord] {
        try await latest(limit: Int.max)
    }

    /// Defaults to "unknown" so test doubles and in-memory stores need not implement verification.
    /// Callers must treat `nil` as *unable to vouch*, never as a clean bill of health.
    func ledgerAttestation() async throws -> ReceiptLedgerAttestation? { nil }
}
