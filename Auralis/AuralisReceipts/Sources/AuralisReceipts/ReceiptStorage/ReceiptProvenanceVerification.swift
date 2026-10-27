import Foundation
import AuralisRuntime

/// The signing rules, and the standalone verifier that applies them to an exported archive.
///
/// Split out of `SwiftDataReceiptStore.swift` because none of it touches SwiftData: this is the half
/// of the package a third party runs against an archive with no database and no Keychain, and it is
/// the half most worth reading on its own.

/// How a row's signing columns classify — as *one* function, so the local store and the bundled
/// export verifier cannot disagree about it.
///
/// They did disagree, and the divergence landed at the one boundary that matters. The store treated
/// the columns as the legitimate unsigned prefix when they were `nil` **or empty**; the verifier
/// tested only for `nil`, and `Data(base64Encoded: "")` returns non-`nil` empty `Data`, so an
/// empty-string signature sailed past its guard into `verifyStatic`, where building a P-256 key from
/// no bytes throws and the row came back invalid. An honest row therefore verified locally as
/// `.unattested`, passed the `isValid` gate, was written into the archive — and the verifier shipped
/// alongside that archive called it `.tampered`.
///
/// The converse diverged too: a signature that is present but not valid base64 was `.invalid` in the
/// store and was swallowed into the verifier's "predates receipt signing" branch.
enum ReceiptSigningMetadata: Equatable {
    /// No signature was ever written. Legitimate only as a prefix from before provenance signing
    /// existed; after a signed row on the same account it means a signature was removed.
    case unsigned
    /// Columns are present but unusable — not base64. A row cannot be both absent and malformed, so
    /// this is always one that was written signed and then damaged.
    case malformed
    /// Exactly one of the two columns is present. Always tampering — see ``classify``.
    case halfSigned
    case signed(signature: Data, publicKey: Data)

    /// - Important: The two columns must be **both present or both absent**. Treating the pair as
    ///   `.unsigned` whenever *either* was missing was the single widest hole in this package, because
    ///   of an asymmetry that is easy to miss: `signerPublicKey` is inside the hashed envelope and
    ///   `signature` cannot be — it is the signature *over* that hash. So deleting only `signature`
    ///   left every chain hash verifying while turning a fully attested row into what looks exactly
    ///   like an honest pre-signing row.
    ///
    ///   Measured, with SwiftData write access alone and no Keychain and no signing key: clearing
    ///   `signature` on all three rows of a `.verified` ledger produced `.unattested` reading
    ///   *"predates receipt signing"*, still exportable — a signed history silently demoted to an
    ///   unattestable one. Worse, it emptied `currentIdentitySeen`, which is the
    ///   `thisDeviceWroteSomeRow` input to
    ///   ``ReceiptPersistenceStore/unrecomputableRowVerdict(_:floor:thisDeviceWroteSomeRow:)`` — so the
    ///   attacker could then raise `integrityEnvelopeVersion` on a row and rewrite its `summary` and
    ///   `isSuccess` in place, and the forged text travelled into the manifest-signed archive. That
    ///   defeated the envelope-version floor *while the floor was present and correct*, by
    ///   manufacturing the restore signature the floor's escape hatch trusts.
    ///
    ///   The pairing rule closes it at the root, and it is exact rather than heuristic: because the
    ///   envelope commits to `signerPublicKey`, a row naming a signer is a row that *was* signed, so a
    ///   missing signature beside a present key is proof of removal rather than an inference. Removing
    ///   both columns instead changes the envelope and fails the chain hash. There is therefore no
    ///   longer any way to de-attest a signed row with row-store writes, which is what makes
    ///   `currentIdentitySeen` sound enough for the floor's hatch to rely on.
    ///
    ///   An honest row cannot reach this state: ``ReceiptPersistenceStore/append(_:)`` resolves the key
    ///   and the signature before it writes anything and treats a signing failure as a write failure,
    ///   so it never commits one without the other.
    static func classify(signature: String?, signerPublicKey: String?) -> ReceiptSigningMetadata {
        let hasSignature = !(signature ?? "").isEmpty
        let hasPublicKey = !(signerPublicKey ?? "").isEmpty
        guard hasSignature || hasPublicKey else {
            return .unsigned
        }
        guard let signature, let signerPublicKey, hasSignature, hasPublicKey else {
            return .halfSigned
        }
        guard let signatureData = Data(base64Encoded: signature),
              let publicKeyData = Data(base64Encoded: signerPublicKey) else {
            return .malformed
        }
        return .signed(signature: signatureData, publicKey: publicKeyData)
    }
}

/// The forward-only signing rule: **signing may only move forward on an account.** An unsigned row,
/// or one signed by an older identity, is legitimate *before* the first row signed by the identity
/// being compared against, and is a regression after it — and the only way to produce that regression
/// is to strip or swap a signature.
///
/// One evaluator, because the store and ``ReceiptProvenanceVerifier`` both apply this rule to the
/// same columns. Sharing ``ReceiptSigningMetadata`` removed the disagreement about *classification*
/// but left the rule itself, its ordering, and most of its verdict strings written out twice in
/// near-identical form — the same drift risk one layer up, in the code whose two halves must agree or
/// an honest export gets called forged.
///
/// The "identity being compared against" is the only thing that differs between the two callers: this
/// device's current signing key in the store, the fingerprint-pinned manifest signer in the verifier.
/// That is a parameter, not a second implementation.
enum ReceiptSigningProgression: Equatable {
    /// No signature, and none was required yet: the legitimate pre-signing prefix.
    case unsignedPrefix
    /// Signed by the reference identity. The caller records that it has seen one for this account.
    case referenceIdentity
    /// Validly signed, but by some other identity — a restore or a key rotation. Unattestable rather
    /// than invalid. The caller supplies its own wording, because "not this device's current
    /// identity" and "not the pinned export identity" are different statements.
    case otherIdentity
    /// A rule violation, carrying the whole verdict string.
    case violation(String)

    /// - Parameters:
    ///   - chainHash: The row's own chain hash, which is what the signature covers. It commits to the
    ///     signer key, so a substituted key has already failed the chain-hash check by the time this
    ///     runs; verifying against the row's recorded key is therefore sound.
    ///   - referenceKey: The identity to compare against, or `nil` when the caller cannot produce one
    ///     — a locked Keychain. Every row then classifies as ``otherIdentity``, which is why a caller
    ///     in that state must say so separately rather than let the per-row reasons imply a rotation.
    ///   - hasSeenReferenceIdentity: Whether a reference-identity row has already been seen *on this
    ///     account*. The rule is per account, not per ledger.
    static func evaluate(
        receiptID: UUID,
        chainHash: String,
        signature: String?,
        signerPublicKey: String?,
        referenceKey: Data?,
        hasSeenReferenceIdentity: Bool
    ) -> ReceiptSigningProgression {
        switch ReceiptSigningMetadata.classify(signature: signature, signerPublicKey: signerPublicKey) {
        case .unsigned:
            guard !hasSeenReferenceIdentity else {
                return .violation(
                    "Receipt \(receiptID.uuidString) is missing signing metadata after a signed receipt."
                )
            }
            return .unsignedPrefix
        case .halfSigned:
            // Never a legitimate shape, at any position on any account, so it does not consult
            // `hasSeenReferenceIdentity` the way the unsigned case must. See
            // ``ReceiptSigningMetadata/classify(signature:signerPublicKey:)``.
            return .violation(
                "Receipt \(receiptID.uuidString) names a signing key but carries no signature, so its signature was removed."
            )
        case .malformed:
            return .violation("Receipt \(receiptID.uuidString) has invalid signing metadata.")
        case let .signed(signatureData, publicKeyData):
            guard SoftwareReceiptSigner.verifyStatic(
                chainHash,
                signature: ReceiptSignature(
                    signature: signatureData,
                    publicKeyRepresentation: publicKeyData
                )
            ) else {
                return .violation("Receipt \(receiptID.uuidString) has an invalid signature.")
            }
            if publicKeyData == referenceKey {
                return .referenceIdentity
            }
            guard !hasSeenReferenceIdentity else {
                return .violation(
                    "Receipt \(receiptID.uuidString) reverts to a previous signing identity."
                )
            }
            return .otherIdentity
        }
    }
}

/// The **ledger-wide** half of the forward-only signing rule, accumulated across a whole pass.
///
/// ``ReceiptSigningProgression`` applies the rule per *account*, which is all one row can support —
/// and that is not the whole rule. The gap was reachable: an account this ledger has never carried a
/// signed row for has no signed predecessor to regress from, and a missing Keychain anchor for such an
/// account is only an unattested *reason*, never a verdict. So an attacker holding write access to the
/// row store **alone** — no signing key, no Keychain — could invent a fresh `accountKey`, chain a
/// fabricated receipt off the genesis hash with correct unkeyed hashes and no signature, and have it
/// classify as the legitimate pre-signing prefix: `.unattested`, worded identically to an honestly
/// upgraded install, and carried inside the signed export because ``isValid`` accepts `.unattested`.
///
/// That exceeds what this package concedes. `isValid` knowingly accepts an attacker who can write
/// *both* stores and therefore rewrite what is already there; injecting events that never happened,
/// with store access only, is a different and larger claim.
///
/// The closing argument is `sequenceID`. It is allocated globally and monotonically (see
/// `ReceiptPersistenceStore.nextSequenceIDAllocation(notBelow:)`), and
/// `ReceiptPersistenceStore.performAppend(_:)` treats a signing failure as a *write* failure — no row
/// has entered the ledger unsigned since signing existed. On an honest ledger, therefore, every
/// unsigned row precedes every signed one ledger-wide, not merely per account, and a row that is
/// unsigned but sits above a signed row cannot be part of the pre-signing prefix.
///
/// Drawn on the unsigned/signed boundary rather than on identity, which is what makes it safe against
/// the two events that legitimately produce unattestable rows: a device restore and a key rotation
/// both leave rows that are *validly signed* by some other identity, and those classify as
/// ``ReceiptSigningProgression/otherIdentity`` and count as signed here.
///
/// **This rule is necessary but not sufficient on its own, and that is worth stating plainly here
/// because an earlier version of this comment claimed otherwise.** It only fires on rows classified
/// *unsigned*, so it is blind to a fabricated row that carries a working signature — and a row can
/// carry one without the attacker holding any key, by replaying another row's `chainHash` and
/// `signature` together. That bypass was real and is closed by two other checks, which have to stay
/// in place for this one to mean anything: ``ReceiptChainHashUniqueness`` (a repeated chain hash is a
/// replay) and the envelope-version floor on
/// ``ReceiptIntegrityHeadStoring/loadHighestEnvelopeVersion()`` (a row cannot opt out of having its
/// hash recomputed).
///
/// The residual, stated rather than glossed: a fabricated unsigned row can still be placed *below*
/// every signed row, which needs a free low `sequenceID` and so needs a prior deletion to have freed
/// one. Barring that it collides with an issued ID or goes non-positive, and
/// ``ReceiptIntegrity/sequenceGapReasons(sequenceIDs:)`` reports both — as `.unattested`, not
/// `.verified`. Closing it completely needs an external witness this package does not keep.
struct ReceiptSigningLedgerOrdering {
    private var highestUnsigned: (receiptID: UUID, sequenceID: Int)?
    private var lowestSigned: (receiptID: UUID, sequenceID: Int)?

    mutating func recordUnsigned(receiptID: UUID, sequenceID: Int) {
        if let highestUnsigned, highestUnsigned.sequenceID >= sequenceID { return }
        highestUnsigned = (receiptID, sequenceID)
    }

    /// Any *validly signed* row, whichever identity signed it. See the note above on why rotation and
    /// restore belong on this side of the boundary.
    mutating func recordSigned(receiptID: UUID, sequenceID: Int) {
        if let lowestSigned, lowestSigned.sequenceID <= sequenceID { return }
        lowestSigned = (receiptID, sequenceID)
    }

    /// The verdict string for an unsigned row above a signed one, or `nil` when the ledger's unsigned
    /// rows really are a prefix.
    var violation: String? {
        guard let highestUnsigned,
              let lowestSigned,
              highestUnsigned.sequenceID > lowestSigned.sequenceID else {
            return nil
        }
        return "Receipt \(highestUnsigned.receiptID.uuidString) carries no signing metadata but sits at ledger position \(highestUnsigned.sequenceID), after receipt \(lowestSigned.receiptID.uuidString) was signed at position \(lowestSigned.sequenceID)."
    }
}

/// Chain hashes must be unique across a ledger, because a **repeated** one is a replayed signature.
///
/// The chain hash is what a row's signature is taken over, so a row that carries another row's
/// `chainHash` also carries a signature that verifies against it. That was the second half of the
/// envelope-version bypass, and the more dangerous half: an attacker with SwiftData write access alone
/// could splice in a fabricated row on a fresh `accountKey` with a `chainHash`/`signature` pair copied
/// verbatim from a real row and the version column raised past `current`. Nothing recomputed the hash
/// (the version said it could not be), the replayed signature verified, so the row classified as
/// *validly signed* — which walked straight past ``ReceiptSigningLedgerOrdering``, since that rule
/// only fires on rows classified as unsigned. The fabricated account then entered
/// `currentIdentitySeen` with no anchor at `accountSequenceID == 1`, so the genesis heal **minted it a
/// Keychain anchor**, writing attacker state into the trusted store.
///
/// Uniqueness is the direct answer, and it costs nothing an honest ledger needs: the envelope binds
/// `sequenceID` in every version and `receiptID` from v1, so two honest rows cannot collide.
///
/// The one honest artefact that *can* collide is two byte-identical **legacy** rows, which a
/// pre-serialization build could produce by allocating one `sequenceID` twice under concurrent
/// appends. Such a ledger is already `.tampered` — the duplicate also breaks the account-sequence
/// chain — so this changes no verdict, and it is checked *before* that chain rather than after
/// precisely because nothing may trust a repeated hash. But it does mean the message has to state the
/// observation rather than the inference: replay is the overwhelmingly likely cause, not the only one.
///
/// Row-derived and so allowed to carry a verdict: it needs no durable state outside the rows, and
/// there is nothing here an attacker can roll back independently of the rows themselves.
struct ReceiptChainHashUniqueness {
    private var seen: Set<String> = []

    /// - Returns: `false` when `chainHash` has already been seen, which is a rule violation.
    mutating func record(_ chainHash: String) -> Bool {
        seen.insert(chainHash).inserted
    }

    static func violation(receiptID: UUID) -> String {
        "Receipt \(receiptID.uuidString) repeats another receipt's chain hash, so at most one of them can be the receipt it claims to be."
    }
}

/// Collapses per-row unattested notes into one reason, for both halves of the package.
///
/// A ledger upgraded from before signing produces one note per row, and a thousand-line string is not
/// a message anyone can act on. Shared for the same reason ``ReceiptSigningMetadata`` and
/// ``ReceiptSigningProgression`` are: the store and the export verifier report on the same rows, and
/// the two copies of this had already drifted to different wording.
enum ReceiptUnattestedSummary {
    static func summarize(_ reasons: [String]) -> String {
        guard let first = reasons.first else { return "" }
        guard reasons.count > 1 else { return first }
        return "\(first) (and \(reasons.count - 1) more unattested receipts.)"
    }
}

/// Verifies an exported receipt ledger without access to the originating database or Keychain.
/// The expected fingerprint must be obtained through a separately trusted channel; accepting the
/// fingerprint embedded in the export would only prove internal consistency, not provenance.
public enum ReceiptProvenanceVerifier {
    public static func verify(
        _ data: Data,
        trustedSignerFingerprint: String
    ) throws -> ReceiptIntegrityVerificationResult {
        // The canonical decoder, not a default one. `canonicalData` pins dates to seconds since the
        // Unix epoch; a default decoder reads them as seconds since the 2001 reference date, which
        // shifts every `createdAt` by 31 years and then fails `recordsHash` — reported as a tampered
        // export on an archive that was written correctly one function call earlier.
        let export = try ReceiptCanonicalJSON.decoder().decode(ReceiptProvenanceExport.self, from: data)
        guard export.format == ReceiptProvenanceExport.currentFormat,
              export.version == ReceiptProvenanceExport.currentVersion,
              export.trustAnchor.algorithm == "P-256/SHA-256" else {
            throw ReceiptProvenanceExportError.unsupportedFormat
        }

        guard let publicKey = Data(base64Encoded: export.trustAnchor.publicKey),
              ReceiptIntegrity.sha256Hex(publicKey) == export.trustAnchor.fingerprint.lowercased(),
              export.trustAnchor.fingerprint.caseInsensitiveCompare(trustedSignerFingerprint) == .orderedSame else {
            return .invalid("The export signer does not match the trusted fingerprint.")
        }

        // Both wrapped, like the per-record hash further down, and for the same reason: the canonical
        // encoder rejects a non-finite `Date`, so a crafted archive could throw a raw `EncodingError`
        // out of a function documented to return a verdict. These two run *before* the per-record
        // guard, so leaving them as plain `try`s would have meant hitting that throw first and
        // defeating the guard that exists for it. A decoded archive with no canonical byte form is
        // exactly what a forged archive looks like, so it gets a verdict.
        let expectedRecordsHash: String
        let expectedManifestHash: String
        do {
            expectedRecordsHash = ReceiptIntegrity.sha256Hex(
                try ReceiptIntegrity.canonicalData(export.records)
            )
            expectedManifestHash = ReceiptIntegrity.sha256Hex(
                try ReceiptIntegrity.canonicalData(export.manifest)
            )
        } catch {
            return .invalid(
                "The exported receipt set cannot be canonically encoded: \(error.localizedDescription)"
            )
        }
        guard export.manifest.recordCount == export.records.count,
              export.manifest.recordsHash == expectedRecordsHash else {
            return .invalid("The exported receipt set does not match its manifest.")
        }

        guard export.manifestHash == expectedManifestHash,
              let manifestSignature = Data(base64Encoded: export.manifestSignature),
              SoftwareReceiptSigner.verifyStatic(
                  expectedManifestHash,
                  signature: ReceiptSignature(
                      signature: manifestSignature,
                      publicKeyRepresentation: publicKey
                  )
              ) else {
            return .invalid("The provenance manifest signature is invalid.")
        }

        var previousByAccount: [String: ReceiptRecord] = [:]
        var anchorIdentitySeen: Set<String> = []
        var unattestedReasons: [String] = []
        // The ledger-wide half of the forward-only rule, which the per-row evaluator cannot see. See
        // ``ReceiptSigningLedgerOrdering``.
        var signingOrdering = ReceiptSigningLedgerOrdering()
        // Applied here as well as in the store, because an archive is exactly where a replayed
        // signature would be most useful to an attacker and the hardest to notice. See
        // ``ReceiptChainHashUniqueness``.
        var chainHashUniqueness = ReceiptChainHashUniqueness()
        let orderedRecords = export.records.sorted {
            let lhsKey = ReceiptIntegrity.accountKey(accountAddress: $0.accountAddress)
            let rhsKey = ReceiptIntegrity.accountKey(accountAddress: $1.accountAddress)
            if lhsKey != rhsKey { return lhsKey < rhsKey }
            if $0.accountSequenceID != $1.accountSequenceID {
                return $0.accountSequenceID < $1.accountSequenceID
            }
            return $0.sequenceID < $1.sequenceID
        }

        // Every receipt id the archive carries, so a semantic parent can be told from a dangling one.
        let exportedReceiptIDs = Set(export.records.map(\.id))

        for record in orderedRecords {
            let accountKey = ReceiptIntegrity.accountKey(accountAddress: record.accountAddress)
            // Before anything trusts this record's `chainHash`, including the signature check.
            guard chainHashUniqueness.record(record.chainHash) else {
                return .invalid(ReceiptChainHashUniqueness.violation(receiptID: record.id))
            }

            // The Phase 1 parent contract, applied to the archive. This is where the self-reference
            // rule actually bites: the store mints a fresh `UUID` per append, so it cannot write one,
            // while a hand-built archive can say anything. A record that is its own cause, or that
            // names one cause twice, is a forged claim about causality rather than a damaged row, so
            // it gets a verdict rather than a note.
            let declaredParents = record.parentReceiptIDs ?? []
            let parentProblems = ReceiptContributionParents.problems(
                declaredParents,
                receiptID: record.id
            )
            guard parentProblems.isEmpty else {
                return .invalid(
                    "Receipt \(record.id.uuidString) has an invalid exported parent receipt list: \(parentProblems.joined(separator: " "))"
                )
            }
            // Dangling parents are unattested here for the reason they are unattested in the store: an
            // archive can legitimately be a partial export of a ledger whose earlier receipts are gone,
            // and `.unattested` still exports and still reads.
            for missingParent in declaredParents where exportedReceiptIDs.contains(missingParent) == false {
                unattestedReasons.append(
                    "Receipt \(record.id.uuidString) names parent receipt \(missingParent.uuidString), which this archive does not contain."
                )
            }
            let previous = previousByAccount[accountKey]
            // Overflow-reporting rather than `+ 1`, and the argument is stronger here than in the
            // store: the records come from an **untrusted archive**, so `accountSequenceID` is
            // whatever the file says. The ascending sort above means a record at `Int.max` is reached
            // last and cannot currently be a predecessor — but a verifier a third party runs against a
            // hostile file must return a verdict under every input, never abort.
            let (expectedAccountSequenceID, expectedOverflowed) =
                (previous?.accountSequenceID ?? 0).addingReportingOverflow(1)
            guard !expectedOverflowed,
                  record.accountSequenceID == expectedAccountSequenceID,
                  record.previousReceiptHash == (previous?.chainHash ?? ReceiptIntegrity.genesisHash) else {
                return .invalid("Receipt \(record.id.uuidString) has an invalid exported sequence.")
            }

            // Wrapped, like the store's equivalent: a record can carry a non-finite `createdAt` and
            // the canonical encoder rejects it, so a plain `try` here let one crafted record in an
            // archive throw a raw `EncodingError` out of the verifier instead of returning the
            // `.tampered` verdict such a record deserves.
            // The version the record declares, so the envelope rebuilt here is the one the exporting
            // store hashed. `nil` means `legacy`, which is what archives written before the id
            // binding carry.
            let recordEnvelopeVersion = record.integrityEnvelopeVersion
                ?? ReceiptIntegrityEnvelopeVersion.legacy
            // A record from a newer build cannot be recomputed here, and calling that forgery would
            // mean a verifier shipped today declares tomorrow's honest archives tampered. Reported as
            // unattested below, matching the store's handling of the same row.
            let isRecomputable = recordEnvelopeVersion <= ReceiptIntegrityEnvelopeVersion.current

            let payloadHash: String
            let chainHash: String?
            do {
                payloadHash = try ReceiptIntegrity.payloadHash(for: record.details)
                chainHash = isRecomputable ? try ReceiptIntegrity.chainHash(
                    receiptID: record.id,
                    envelopeVersion: recordEnvelopeVersion,
                    sequenceID: record.sequenceID,
                    accountSequenceID: record.accountSequenceID,
                    createdAt: record.createdAt,
                    // The stored strings when the archive carries them, and the typed case's raw
                    // value otherwise. The envelope commits to the raw strings, and `record.actor`
                    // /`record.mode` are degraded stand-ins — `?? .system` / `?? .operate` — for any
                    // value the *exporting* build could not name. Recomputing from the stand-in is
                    // what made an honest archive of a downgraded ledger verify as `.tampered`.
                    //
                    // The fallback is exact rather than merely tolerant: a value that round-trips
                    // through its typed case has `rawValue == modeRawValue` by construction, which is
                    // the condition under which the exporter omits the field. See
                    // ``ReceiptRecord/actorRawValue``.
                    actorRawValue: record.actorRawValue ?? record.actor.rawValue,
                    actorColumns: ReceiptActorColumns(record.actorDetail),
                    authorityColumns: ReceiptAuthorityColumns(record.authorityDetail),
                    // Rebuilt from the record's composed provenance, which is lossless for every row
                    // an honest append can write — see ``StoredReceipt/asReceiptRecord()``. A record
                    // whose provenance was damaged in the exporting store recomputes over absent
                    // columns here and fails the chain-hash comparison below, which is the right
                    // verdict for it.
                    contributionColumns: record.contributionColumns,
                    modeRawValue: record.modeRawValue ?? record.mode.rawValue,
                    trigger: record.trigger,
                    scope: record.scope,
                    summary: record.summary,
                    provenance: record.provenance,
                    isSuccess: record.isSuccess,
                    correlationID: record.correlationID,
                    accountAddress: record.accountAddress,
                    chainRawValue: record.chainRawValue,
                    payloadHash: payloadHash,
                    signerPublicKey: record.signerPublicKey,
                    previousReceiptHash: record.previousReceiptHash
                ) : nil
            } catch {
                return .invalid(
                    "Receipt \(record.id.uuidString) has exported integrity metadata that cannot be canonically encoded: \(error.localizedDescription)"
                )
            }
            guard record.payloadHash == payloadHash else {
                return .invalid("Receipt \(record.id.uuidString) has invalid exported integrity metadata.")
            }
            if let chainHash {
                guard record.chainHash == chainHash else {
                    return .invalid("Receipt \(record.id.uuidString) has invalid exported integrity metadata.")
                }
            } else {
                unattestedReasons.append(
                    "Receipt \(record.id.uuidString) was exported with integrity envelope version \(recordEnvelopeVersion), which this verifier cannot recompute."
                )
            }

            // The store's rule, through the store's evaluator — so an archive of an upgraded ledger is
            // accepted as unattested rather than rejected as forged, and stays that way if the rule
            // changes. The reference identity here is the fingerprint-pinned manifest signer.
            switch ReceiptSigningProgression.evaluate(
                receiptID: record.id,
                chainHash: record.chainHash,
                signature: record.signature,
                signerPublicKey: record.signerPublicKey,
                referenceKey: publicKey,
                hasSeenReferenceIdentity: anchorIdentitySeen.contains(accountKey)
            ) {
            case .unsignedPrefix:
                signingOrdering.recordUnsigned(receiptID: record.id, sequenceID: record.sequenceID)
                unattestedReasons.append("Receipt \(record.id.uuidString) predates receipt signing.")
            case .referenceIdentity:
                signingOrdering.recordSigned(receiptID: record.id, sequenceID: record.sequenceID)
                anchorIdentitySeen.insert(accountKey)
            case .otherIdentity:
                signingOrdering.recordSigned(receiptID: record.id, sequenceID: record.sequenceID)
                unattestedReasons.append(
                    "Receipt \(record.id.uuidString) was not signed by the pinned export identity."
                )
            case let .violation(reason):
                return .invalid(reason)
            }
            previousByAccount[accountKey] = record
        }

        // The per-account rule completed by the ledger-wide one: unsigned rows must be a prefix of the
        // *whole* ledger, not merely of their own account. Without this, an account fabricated after
        // signing began had no signed predecessor to regress from and its rows read as the legitimate
        // pre-signing prefix.
        if let orderingViolation = signingOrdering.violation {
            return .invalid(orderingViolation)
        }

        // The same ledger-wide completeness reasoning the store applies locally, split the same way.
        // Everything above this point is per account, so excising one account's records entirely
        // leaves the survivors linking cleanly; omitting any completeness check here would defeat the
        // local one at the boundary that matters most, since `.unattested` satisfies `isValid` and so
        // an incomplete ledger exports happily.
        //
        // The row-derived half, exactly as the store applies it locally: duplicates and interior
        // holes, visible in the record set itself. Verdict-affecting, because it needs nothing
        // outside the records.
        // At the front for the reason the store puts it there: this is a statement about the archive
        // as a whole, and the summary keeps only the first reason, so appending it behind an upgraded
        // ledger's per-row notes made the strongest evidence in the pass unreadable.
        unattestedReasons.insert(
            contentsOf: ReceiptIntegrity.sequenceGapReasons(sequenceIDs: export.records.map(\.sequenceID)),
            at: 0
        )

        // The mark-derived half, advisory here for the same reason it is advisory in the store.
        //
        // It is published inside the signed manifest, so it cannot be stripped without breaking the
        // signature verified above — but a signature only proves the *exporting device* said it, and
        // that device's mark is an unauthenticated local item. A third party gets told what the mark
        // suggested and decides for themselves; the verdict is computed from the records.
        let completenessAdvisory = ReceiptIntegrity.completenessAdvisory(
            sequenceIDs: export.records.map(\.sequenceID),
            highWaterMark: export.manifest.ledgerHighWaterMark,
            completenessUnconfirmed: export.manifest.ledgerCompletenessUnconfirmed == true
        )

        let exportedHeads = previousByAccount.map { accountKey, record in
            ReceiptProvenanceChainHead(
                accountKey: accountKey,
                accountSequenceID: record.accountSequenceID,
                chainHash: record.chainHash
            )
        }.sorted { $0.accountKey < $1.accountKey }
        guard export.manifest.chainHeads == exportedHeads else {
            return .invalid("The exported chain heads do not match the receipt sequences.")
        }

        // Attached after the verdict is settled, so it cannot influence it.
        guard unattestedReasons.isEmpty else {
            return .unattested(ReceiptUnattestedSummary.summarize(unattestedReasons))
                .withCompletenessAdvisory(completenessAdvisory)
        }
        return ReceiptIntegrityVerificationResult.valid
            .withCompletenessAdvisory(completenessAdvisory)
    }
}
