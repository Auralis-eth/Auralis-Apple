import AuralisFoundation
import AuralisPrimaryModels
import CryptoKit
import Foundation

/// The definition of the receipt chain hash: which fields it covers, in what form, and how they are
/// reduced to bytes.
///
/// Lives here rather than in `ReceiptStorage` because that package imports SwiftData, and the format
/// it produces claims to be independently verifiable — "a third party can confirm the sequence
/// without trusting Auralis". While the field set and ordering that *define* every hash lived behind
/// a SwiftData dependency and a `private` envelope type, that claim could not be met by anyone
/// outside this app: `ReceiptCanonicalJSON` pinned the byte encoding but nothing published what was
/// being encoded. Only the one overload that reads a persisted SwiftData row stayed behind.
public enum ReceiptIntegrity {
    public static let genesisHash = "GENESIS"

    /// Completeness evidence that is visible **in the rows themselves**, with no durable state
    /// outside the row store — duplicate `sequenceID`s, and interior holes.
    ///
    /// This half affects the verdict, and can, because it needs nothing an attacker could
    /// independently delete or roll back: `sequenceID` is allocated globally and monotonically,
    /// `resetAll()` restarts at 1, so the surviving IDs disagreeing with their own maximum is
    /// self-evident from a single fetch. Shared with ``ReceiptProvenanceVerifier`` so an exported
    /// archive is held to the same standard as the live store.
    ///
    /// The *other* half — a deleted suffix, which the rows cannot show because the survivors are
    /// still a contiguous `1...k` — is
    /// ``completenessAdvisory(sequenceIDs:highWaterMark:completenessUnconfirmed:)``, and is
    /// deliberately advisory rather than verdict-affecting. See that function for why.
    ///
    /// **Reported as unattested, not tampered, deliberately.** A hole means rows are gone, but not
    /// *why*: builds before the sequence cache was removed could burn an ID on a failed signature,
    /// which leaves an identical hole in a ledger nobody touched. Calling that tampering would brand
    /// those installs permanently invalid and, because ``ReceiptPersistenceStore/exportAll()`` refuses
    /// on an invalid verdict, leave destroying the history as the only way to get it out — the failure
    /// this whole `Status` trichotomy exists to prevent. Unattested says the true thing: the rows that
    /// are here are intact, and this device cannot vouch that they are all of them.
    public static func sequenceGapReasons(sequenceIDs: [Int]) -> [String] {
        let distinct = Set(sequenceIDs)
        guard distinct.count == sequenceIDs.count else {
            return ["The receipt ledger contains duplicate sequence numbers."]
        }
        guard let highest = distinct.max() else { return [] }
        // Sequence IDs are allocated from 1. A non-positive one cannot have been issued by this
        // device, and the count comparison below silently misreads them — `[0, 1, 2]` would otherwise
        // report "missing -1 of 2". These arrive from `exportAll()` archives, so the input is
        // untrusted and has to be rejected rather than assumed away.
        guard let lowest = distinct.min(), lowest > 0 else {
            return ["The receipt ledger contains sequence numbers this device could not have issued."]
        }
        // Distinct positive integers whose maximum equals their count can only be exactly
        // `1...count`, so this single comparison covers every interior hole.
        guard highest != sequenceIDs.count else { return [] }
        return [
            "The receipt ledger is missing \(highest - sequenceIDs.count) of \(highest) receipts written on this device."
        ]
    }

    /// What the ledger high-water mark *suggests* about receipts removed from the end of the ledger.
    ///
    /// **Best-effort detection, not a security control, and deliberately not part of any verdict.**
    /// The distinction is the point, so it is worth being exact about why.
    ///
    /// The mark is the only thing that can see a deleted *suffix*: every other check is per account —
    /// chain linkage, `accountSequenceID`, signatures, anchors — and ``sequenceGapReasons(sequenceIDs:)``
    /// measures against the highest *surviving* ID, so erasing whichever account was written last
    /// leaves the remainder a contiguous `1...k` with nothing to notice. A mark held outside the rows
    /// is the missing evidence.
    ///
    /// But it is evidence of a weak kind, and it cannot be strengthened into a control:
    ///
    /// - It is an unauthenticated Keychain item, so anyone who can write the Keychain can lower it to
    ///   agree with whatever rows they left behind.
    /// - Signing it would not help. The signing key lives in the same Keychain, and a Secure Enclave
    ///   key that cannot be *extracted* can still be *used* by anyone who can reach it.
    /// - Its absence is not evidence either: a device restore brings the rows back without any
    ///   `ThisDeviceOnly` item, and a ledger written before the mark existed never had one.
    /// - Detecting suffix truncation from purely local, mutable state is not achievable against an
    ///   attacker who can write that state. The sound constructions need an external witness — a
    ///   server, a notary, a published chain — which this package does not have.
    ///
    /// So it informs rather than gates: a person or a log gets told what the mark suggests, and
    /// `status`/`isFullyAttested` are decided without it. Letting it gate meant its *absence*
    /// downgraded honest restored and pre-mark ledgers, while its presence created a control whose
    /// guarantee evaporated against the very attacker it was drawn against. Anything that needs a real
    /// completeness guarantee has to come from
    /// ``ReceiptProvenanceVerifier/verify(_:trustedSignerFingerprint:)`` against an out-of-band pinned
    /// fingerprint, plus a witness this package does not yet keep.
    ///
    /// - Parameters:
    ///   - highWaterMark: The mark, or `nil` when absent or unreadable.
    ///   - completenessUnconfirmed: Set when the caller knows completeness cannot be confirmed at all
    ///     — an archive whose exporting device had no mark to publish.
    /// - Returns: A sentence for a person, or `nil` when the mark suggests nothing.
    public static func completenessAdvisory(
        sequenceIDs: [Int],
        highWaterMark: Int?,
        completenessUnconfirmed: Bool = false
    ) -> String? {
        if completenessUnconfirmed {
            return "This ledger carries no high-water mark, so it cannot be confirmed that no receipts were removed from the end of it."
        }
        guard let highWaterMark else { return nil }
        // Only ever the mark running *ahead* of the rows. A mark behind them is the append path's own
        // crash window, and saying anything about it would invent a gap in an untouched ledger.
        let distinct = Set(sequenceIDs)
        let survivingHighest = distinct.max() ?? 0
        guard highWaterMark > survivingHighest, highWaterMark > sequenceIDs.count else { return nil }
        return "The ledger high-water mark is \(highWaterMark) but only \(sequenceIDs.count) receipts are present, which suggests \(highWaterMark - sequenceIDs.count) were removed from the end of the ledger."
    }

    public static func accountKey(accountAddress: String?) -> String {
        guard let accountAddress, !accountAddress.isEmpty else {
            return "global"
        }
        return accountAddress.lowercased()
    }

    public static func payloadHash(for payload: ReceiptPayload) throws -> String {
        sha256Hex(try canonicalData(payload))
    }

    public static func chainHash(
        receiptID: UUID,
        envelopeVersion: Int = ReceiptIntegrityEnvelopeVersion.current,
        sequenceID: Int,
        accountSequenceID: Int,
        createdAt: Date,
        // Raw strings, not `ReceiptActor`/`ReceiptMode`. `StoredReceipt` degrades an unrecognized
        // raw value to `.system`/`.observe` on read, so hashing the *typed* value re-hashed the
        // degraded stand-in rather than what the row actually stores: a receipt written by a newer
        // build carrying a mode this build has no case for verified as "invalid chain hash", i.e.
        // reported as tampering when the only problem was a downgrade. Hashing the stored string
        // commits to the bytes on disk and keeps the verdict honest.
        actorRawValue: String,
        // Columns, not the `ReceiptActorDetail?`/`ReceiptAuthorityDetail?` these used to take.
        //
        // Those structs make `kind` and `source` non-optional, so a row reconstructs its detail only
        // when that one column is present and returns `nil` otherwise — which meant a row with no
        // recorded authority omitted *all six* authority fields from the envelope, leaving
        // `authorityLeaseID`, `authorityCapabilityRawValue`, `authorityScopeRawValue`,
        // `authorityReason` and `authorityExpiresAt` outside the hash entirely. Fabricated values
        // could be written into them without changing the chain hash, forging the "under what
        // authority did this happen" leg of the audit record on any row that legitimately had none.
        // `actorKindRawValue` gated the six actor columns the same way.
        //
        // Passing the columns keeps every one of them hashed independently. This changes no honest
        // row's hash: a writer sets all six from one detail, so `source == nil` implies the other
        // five are `nil` too, and all-nil still encodes as all-omitted.
        actorColumns: ReceiptActorColumns,
        authorityColumns: ReceiptAuthorityColumns,
        // Columns, not the composed `PrincipalID?`/`ReceiptResourceReference?`/`ReceiptResultReference?`,
        // for the reason spelled out on ``ReceiptContributionColumns``: a composed reference
        // reconstructs as `nil` unless *both* of its halves are present, which would drop both columns
        // out of the envelope on a row carrying only one and let a fabricated type be written without
        // changing the chain hash. Deliberately without a default — the two production call sites
        // state it at both ends, the same discipline `envelopeVersion` is held to below.
        contributionColumns: ReceiptContributionColumns,
        modeRawValue: String,
        trigger: String,
        scope: String,
        summary: String,
        provenance: String,
        isSuccess: Bool,
        correlationID: String?,
        accountAddress: String?,
        chainRawValue: String?,
        payloadHash: String,
        // Committing the signing identity is what separates a legitimate key rotation from a signer
        // substitution. The signature alone cannot: it is computed *over* this hash, so an attacker
        // who re-signs a row with their own key produces a self-consistent row, and the only defence
        // left was pinning every row to the single current key — which is precisely what made
        // restoring to a new device invalidate the whole ledger. With the key inside the envelope, a
        // swap changes the chain hash, cascades into every later `previousReceiptHash`, and breaks
        // the Keychain-anchored head, while an old key that was always this row's key still verifies.
        signerPublicKey: String?,
        previousReceiptHash: String
    ) throws -> String {
        // Before the encode, so a column that cannot be canonically represented is a *named* error
        // rather than whatever `JSONEncoder` raises from four frames down.
        //
        // `createdAt` and `authorityExpiresAt` reach the envelope as `TimeInterval`, and the canonical
        // encoder rejects non-finite doubles — correctly, since there is no canonical JSON spelling of
        // infinity. But the resulting `EncodingError` propagated straight out of `verifyIntegrity()`
        // and `exportAll()`, so a single row holding `Date(timeIntervalSince1970: .infinity)` produced
        // *no verdict at all* and an export that failed with a raw `EncodingError` instead of
        // `ReceiptProvenanceExportError.integrityFailure`. That is a permanent denial of the audit
        // trail — recoverable only by `resetAll()`, i.e. by destroying the history — reached by
        // writing one column, and it is the same failure mode the unreadable-payload path was already
        // careful to turn into a verdict.
        try requireFiniteInterval(createdAt.timeIntervalSince1970, field: "createdAt")
        if let expiresAt = authorityColumns.expiresAt {
            try requireFiniteInterval(expiresAt.timeIntervalSince1970, field: "authorityExpiresAt")
        }
        let envelope = ReceiptIntegrityEnvelope(
            // Omitted for ``ReceiptIntegrityEnvelopeVersion/legacy`` rows and present from v1 on, so
            // binding the id costs no rehash of anything already written. See
            // ``ReceiptIntegrityEnvelopeVersion`` for why the version is inside the envelope too.
            receiptID: envelopeVersion >= ReceiptIntegrityEnvelopeVersion.bindsReceiptID
                ? receiptID.uuidString
                : nil,
            envelopeVersion: envelopeVersion > ReceiptIntegrityEnvelopeVersion.legacy
                ? envelopeVersion
                : nil,
            sequenceID: sequenceID,
            accountSequenceID: accountSequenceID,
            createdAt: createdAt.timeIntervalSince1970,
            actor: actorRawValue,
            // Optional structured-actor fields are omitted from the encoded envelope when nil, so
            // legacy receipts (no structured detail) hash identically to before this column existed.
            actorKind: actorColumns.kind,
            actorIdentifier: actorColumns.identifier,
            actorDisplayName: actorColumns.displayName,
            actorInferenceLocality: actorColumns.inferenceLocality,
            actorInferenceProvider: actorColumns.inferenceProvider,
            actorInferenceModelClass: actorColumns.inferenceModelClass,
            // Authority fields follow the same omitted-when-nil rule, so receipts without a recorded
            // authority keep hashing exactly as they did before the column existed.
            authoritySource: authorityColumns.source,
            authorityLeaseID: authorityColumns.leaseID,
            authorityCapability: authorityColumns.capability,
            authorityScope: authorityColumns.scope,
            authorityReason: authorityColumns.reason,
            authorityExpiresAt: authorityColumns.expiresAt?.timeIntervalSince1970,
            mode: modeRawValue,
            trigger: trigger,
            scope: scope,
            summary: summary,
            provenance: provenance,
            isSuccess: isSuccess,
            correlationID: correlationID,
            accountAddress: accountAddress,
            chainRawValue: chainRawValue,
            payloadHash: payloadHash,
            // Omitted-when-nil, like the attribution fields above, so receipts written before
            // signing existed keep hashing exactly as they did.
            signerPublicKey: signerPublicKey,
            previousReceiptHash: previousReceiptHash,
            // Phase 1 contribution provenance, following the same omitted-when-nil rule, which is
            // what makes this a no-rehash addition for every receipt written before these columns
            // existed — all six are `nil` on such a row and all-nil still encodes as all-omitted.
            principalID: contributionColumns.principalID,
            affectedResourceType: contributionColumns.affectedResourceType,
            affectedResourceIdentifier: contributionColumns.affectedResourceIdentifier,
            producedResultType: contributionColumns.producedResultType,
            producedResultIdentifier: contributionColumns.producedResultIdentifier,
            parentReceiptIDs: contributionColumns.parentReceiptIDs
        )
        return sha256Hex(try canonicalData(envelope))
    }

    private static func requireFiniteInterval(_ interval: TimeInterval, field: String) throws {
        guard interval.isFinite else {
            throw ReceiptIntegrityEncodingError.nonFiniteDate(field: field)
        }
    }

    /// The byte form every hash in this file is taken over. Defined by ``ReceiptCanonicalJSON`` rather
    /// than here, because the export's consumers — the console, an external verifier — have to be able
    /// to reproduce it without depending on this package.
    public static func canonicalData<Value: Encodable>(_ value: Value) throws -> Data {
        try ReceiptCanonicalJSON.encoder().encode(value)
    }

    public static func sha256Hex(_ data: Data) -> String {
        SHA256.hash(data: data)
            .map { String(format: "%02x", $0) }
            .joined()
    }
}

/// A receipt column that has no canonical byte form, reported as itself so the integrity check can
/// return a *verdict* about the row instead of unwinding with a `JSONEncoder` internal error.
public enum ReceiptIntegrityEncodingError: Error, Equatable, Sendable {
    /// A date column holds a non-finite instant — `.infinity` or `.nan` — which canonical JSON cannot
    /// represent. Only reachable by writing the column directly; the append path cannot produce it.
    case nonFiniteDate(field: String)
}

/// Which shape of ``ReceiptIntegrityEnvelope`` a row's stored `chainHash` was taken over.
///
/// Exists so the envelope can gain fields without invalidating rows already on disk. Adding a field
/// unconditionally would change every existing hash, so `verifyIntegrity()` would recompute a
/// mismatch for the whole ledger and report `.tampered` — permanently, with `resetAll()` as the only
/// exit, which is precisely the outcome this package's `Status` trichotomy exists to prevent. The
/// version travels in a defaulted column, so old rows keep hashing the old way and new rows get the
/// stronger envelope.
///
/// **The version is itself inside the envelope** (omitted at ``legacy``, so v0 bytes are unchanged).
/// Without that, downgrading a v1 row's version column to 0 would make the verifier rebuild the
/// weaker envelope and re-admit exactly the forgery the new field closes. With it, the downgrade
/// changes the recomputed hash and the row reads as tampered. An attacker also cannot mint fresh v0
/// rows, because every row still has to carry a valid signature over its chain hash.
public enum ReceiptIntegrityEnvelopeVersion {
    /// Rows written before the envelope bound the receipt id. Their ids are unverifiable; the set is
    /// closed and shrinks to nothing as history is appended.
    public static let legacy = 0
    /// First version to bind ``ReceiptRecord/id``.
    public static let bindsReceiptID = 1
    /// First version to bind the Phase 1 contribution-provenance columns — the canonical principal,
    /// the affected-resource and produced-result references, and the semantic parent receipt IDs.
    ///
    /// **Rows already on disk are not rehashed, and nothing here could have rehashed them.** The six
    /// columns are optional and omitted-when-nil, so a v0 or v1 row — which cannot carry any of them,
    /// because the columns postdate it — encodes exactly the bytes it always did. What the bump buys is
    /// the *statement*: a row declaring v2 asserts that its provenance fields were inside the hash when
    /// it was written, which is what lets a verifier tell "this receipt says no resource was affected"
    /// apart from "this receipt predates the question".
    ///
    /// Note what is deliberately **not** done here: the provenance fields are hashed regardless of the
    /// declared version rather than gated behind `>= bindsContributionProvenance` the way `receiptID`
    /// is gated behind ``bindsReceiptID``. The gate exists for `receiptID` because that field is
    /// non-optional and would otherwise change v0 bytes. Gating these as well would be strictly worse:
    /// it would put the columns outside the hash on any row whose version column says v1, so an
    /// attacker could write provenance onto an old row, or downgrade a v2 row's version and then
    /// rewrite its provenance, with the chain hash still verifying. Hashing them unconditionally means
    /// either edit changes the recomputed hash and the row reads as tampered.
    public static let bindsContributionProvenance = 2
    /// What the append path writes today.
    public static let current = bindsContributionProvenance
}

/// The six structured-actor columns, carried as columns so each is hashed on its own.
///
/// See the note on ``ReceiptIntegrity/chainHash(receiptID:envelopeVersion:sequenceID:accountSequenceID:createdAt:actorRawValue:actorColumns:authorityColumns:contributionColumns:modeRawValue:trigger:scope:summary:provenance:isSuccess:correlationID:accountAddress:chainRawValue:payloadHash:signerPublicKey:previousReceiptHash:)``
/// for why passing ``ReceiptActorDetail`` here was unsound.
public struct ReceiptActorColumns: Equatable, Sendable {
    public let kind: String?
    public let identifier: String?
    public let displayName: String?
    public let inferenceLocality: String?
    public let inferenceProvider: String?
    public let inferenceModelClass: String?

    public init(
        kind: String?,
        identifier: String?,
        displayName: String?,
        inferenceLocality: String?,
        inferenceProvider: String?,
        inferenceModelClass: String?
    ) {
        self.kind = kind
        self.identifier = identifier
        self.displayName = displayName
        self.inferenceLocality = inferenceLocality
        self.inferenceProvider = inferenceProvider
        self.inferenceModelClass = inferenceModelClass
    }

    /// For callers that hold the read model rather than the raw columns — the export verifier, which
    /// only ever sees a ``ReceiptRecord``. Lossless in that direction: a detail that exists carries
    /// all six values, and a `nil` detail means all six columns were `nil`.
    public init(_ detail: ReceiptActorDetail?) {
        self.init(
            kind: detail?.kind,
            identifier: detail?.identifier,
            displayName: detail?.displayName,
            inferenceLocality: detail?.inferenceLocality,
            inferenceProvider: detail?.inferenceProvider,
            inferenceModelClass: detail?.inferenceModelClass
        )
    }
}

/// The six authority columns, carried as columns for the reason ``ReceiptActorColumns`` is.
public struct ReceiptAuthorityColumns: Equatable, Sendable {
    public let source: String?
    public let leaseID: String?
    public let capability: String?
    public let scope: String?
    public let reason: String?
    public let expiresAt: Date?

    public init(
        source: String?,
        leaseID: String?,
        capability: String?,
        scope: String?,
        reason: String?,
        expiresAt: Date?
    ) {
        self.source = source
        self.leaseID = leaseID
        self.capability = capability
        self.scope = scope
        self.reason = reason
        self.expiresAt = expiresAt
    }

    public init(_ detail: ReceiptAuthorityDetail?) {
        self.init(
            source: detail?.source,
            leaseID: detail?.leaseID,
            capability: detail?.capability,
            scope: detail?.scope,
            reason: detail?.reason,
            expiresAt: detail?.expiresAt
        )
    }
}

/// The exact field set the chain hash covers, in the exact form it covers them.
///
/// Public because it *is* the specification: `ReceiptCanonicalJSON` says how these become bytes
/// (JSON, keys sorted, dates as seconds since the Unix epoch) and the property names below say what
/// is encoded. Optional fields are omitted when `nil`, which is what lets columns be added without
/// rehashing every receipt that predates them.
public struct ReceiptIntegrityEnvelope: Encodable {
    /// The receipt's own identifier, from ``ReceiptIntegrityEnvelopeVersion/bindsReceiptID`` on.
    ///
    /// It was the one persisted column neither hashed nor derivable from something hashed, so ids
    /// could be rewritten or permuted across rows while the ledger still verified as `.verified`.
    /// That is not an academic gap: the id is a cross-store foreign key — `StoredArtifact`
    /// keeps `relatedReceiptIDs` and the trusted-UI registry resolves `reviewReceipt(receiptID)` —
    /// so which receipt an artifact's provenance link resolves to could be repointed at a different
    /// action while the audit log vouched for itself.
    public let receiptID: String?
    /// See ``ReceiptIntegrityEnvelopeVersion``. Omitted at `legacy` so v0 bytes are untouched.
    public let envelopeVersion: Int?
    public let sequenceID: Int
    public let accountSequenceID: Int
    public let createdAt: TimeInterval
    public let actor: String
    public let actorKind: String?
    public let actorIdentifier: String?
    public let actorDisplayName: String?
    public let actorInferenceLocality: String?
    public let actorInferenceProvider: String?
    public let actorInferenceModelClass: String?
    public let authoritySource: String?
    public let authorityLeaseID: String?
    public let authorityCapability: String?
    public let authorityScope: String?
    public let authorityReason: String?
    public let authorityExpiresAt: TimeInterval?
    public let mode: String
    public let trigger: String
    public let scope: String
    public let summary: String
    public let provenance: String
    public let isSuccess: Bool
    public let correlationID: String?
    public let accountAddress: String?
    public let chainRawValue: String?
    public let payloadHash: String
    public let signerPublicKey: String?
    public let previousReceiptHash: String
    /// The Phase 1 contribution-provenance columns, from
    /// ``ReceiptIntegrityEnvelopeVersion/bindsContributionProvenance`` on — but hashed whenever
    /// present, at any declared version. See that symbol for why they are not gated on it.
    ///
    /// Omitted when `nil`, like every other optional here, which is what makes adding them a
    /// no-rehash change for receipts written before they existed.
    public let principalID: String?
    public let affectedResourceType: String?
    public let affectedResourceIdentifier: String?
    public let producedResultType: String?
    public let producedResultIdentifier: String?
    /// The canonical joined form from ``ReceiptContributionParents/canonicalRawValue(_:)``, so `nil`
    /// and an empty parent list cannot hash differently while making the same claim.
    public let parentReceiptIDs: String?
}
