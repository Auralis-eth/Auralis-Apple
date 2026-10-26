import AuralisFoundation
import Foundation
import OSLog
import ReceiptsCore
import SwiftData

private enum ReceiptStorageScopeNormalizer {
    static func normalizedAddress(_ rawValue: String) -> String? {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let body = trimmed.lowercased().hasPrefix("0x") ? String(trimmed.dropFirst(2)) : trimmed
        guard body.count == 40, body.allSatisfy({ $0.isASCII && $0.isHexDigit }) else {
            return nil
        }
        return "0x" + body.lowercased()
    }

    static func normalizedOpaqueChain(_ rawValue: String) -> String? {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

@Model
public final class StoredReceipt {
    #Index<StoredReceipt>(
        [\.correlationID],
        [\.sequenceID],
        [\.createdAt, \.sequenceID],
        [\.accountKey, \.accountSequenceID, \.sequenceID],
        [\.accountAddress, \.chainRawValue, \.createdAt, \.sequenceID]
    )

    private static let logger = Logger(subsystem: "Auralis", category: "StoredReceipt")

    @Attribute(.unique) public var id: UUID
    public var sequenceID: Int
    public var createdAt: Date
    public var actorRawValue: String
    // Structured actor attribution (P0.5-602). Optional because `nil` is a real answer, not to
    // accommodate older rows: nothing has shipped, so there are none.
    public var actorKindRawValue: String?
    public var actorIdentifier: String?
    public var actorDisplayName: String?
    public var actorInferenceLocalityRawValue: String?
    public var actorInferenceProvider: String?
    public var actorInferenceModelClass: String?
    // Authority attribution (P0.5-601/602): which grant permitted the action. `nil` means the action
    // never reached a point where authority was resolved.
    public var authoritySourceRawValue: String?
    public var authorityLeaseID: String?
    public var authorityCapabilityRawValue: String?
    public var authorityScopeRawValue: String?
    public var authorityReason: String?
    public var authorityExpiresAt: Date?
    public var modeRawValue: String
    public var trigger: String
    public var scope: String
    public var summary: String
    public var provenance: String
    public var isSuccess: Bool
    public var correlationID: String?
    public var accountAddress: String?
    /// The chain this row belongs to, persisted so the grouping used by `verifyIntegrity()` and the
    /// grouping used to pick an append's predecessor cannot disagree.
    ///
    /// They used to be derived from ``accountAddress`` on one side and predicated on it directly on
    /// the other, and the two are not the same function: the derivation folds `nil` and `""` into
    /// `"global"` and lowercases everything else, so a draft carrying the literal address `"global"`
    /// got its own append chain starting at `accountSequenceID == 1` while `verifyIntegrity()` merged
    /// it with the `nil` chain and reported `.tampered("invalid account sequence")` — permanently,
    /// with `resetAll()` as the only exit. One stored value, read by both.
    ///
    /// Defaulted to `""` so adding the column is a lightweight migration. Rows carrying that default
    /// are backfilled by ``ReceiptPersistenceStore`` before the first read or write that depends on
    /// it — see `backfillAccountKeysIfNeeded()`. A *read-time* fallback was tried first and was
    /// wrong: the fallback folds and lowercases, but a `#Predicate` cannot express either, so the
    /// append path had to match legacy rows by raw address equality and missed exactly the rows the
    /// fold exists for, reintroducing the forked chain described above.
    ///
    /// Not part of the hashed envelope, and it does not need to be: it is a pure function of
    /// ``accountAddress``, which *is* hashed, and ``ReceiptPersistenceStore/verifyIntegrity()``
    /// re-derives it from that column and rejects a row where the two disagree. Editing this column
    /// therefore has no more power than editing a cache.
    public var accountKey: String = ""
    public var chainRawValue: String?
    public var accountSequenceID: Int
    public var payloadHash: String
    public var previousReceiptHash: String
    public var chainHash: String
    public var signature: String?
    public var signerPublicKey: String?
    /// Which ``ReceiptIntegrityEnvelope`` shape ``chainHash`` was taken over — see
    /// ``ReceiptIntegrityEnvelopeVersion``.
    ///
    /// Defaulted to ``ReceiptIntegrityEnvelopeVersion/legacy`` so adding it is a lightweight
    /// migration and every row already on disk keeps verifying against the envelope it was actually
    /// hashed with. No backfill: the value is not derivable after the fact, and 0 is the correct
    /// answer for any row that predates the column.
    ///
    /// Editing this column is self-defeating rather than useful, because the version is inside the
    /// envelope from v1 on: changing it changes the hash the verifier recomputes.
    public var integrityEnvelopeVersion: Int = ReceiptIntegrityEnvelopeVersion.legacy
    // Phase 1 contribution provenance. All optional and defaulted to `nil`, so adding them is a
    // lightweight migration and every row already on disk reads back as *not stated* — which is the
    // honest answer for a row written before the question was asked. No backfill is possible or
    // wanted: none of these is derivable after the fact, and inventing one would make the ledger
    // assert an attribution nobody made.
    //
    // All six are inside the hashed envelope whenever present, at every declared envelope version —
    // see ``ReceiptIntegrityEnvelopeVersion/bindsContributionProvenance`` for why they are not gated
    // on the version column. Editing any of them changes the recomputed chain hash.
    /// The canonical principal the contribution is attributed to, as a raw string.
    ///
    /// Stored as the raw value rather than a `PrincipalID` because SwiftData persists primitives, and
    /// the hash commits to the string on disk for the reason ``actorRawValue`` does. Normalized so an
    /// empty column cannot exist: `PrincipalID` refuses an empty raw value, so a column holding `""`
    /// would read back as `nil` while hashing as `""` — two answers for one fact, which is the
    /// disagreement every derivation in this file exists to prevent.
    public var principalIDRawValue: String?
    /// The affected-resource reference, split into its two columns so each is hashed independently.
    /// See ``ReceiptContributionColumns`` for why the composed form must not be hashed.
    public var affectedResourceType: String?
    public var affectedResourceIdentifier: String?
    /// The produced-result reference, split for the reason the affected resource is.
    public var producedResultType: String?
    public var producedResultIdentifier: String?
    /// Semantic parent receipt IDs in the canonical joined form from
    /// ``ReceiptContributionParents/canonicalRawValue(_:)``.
    ///
    /// One string column rather than a SwiftData array: the envelope hashes a single canonical string,
    /// so storing the same string keeps the hashed value and the stored value the same object rather
    /// than two encodings that have to be kept in step. ``ReceiptPersistenceStore/verifyIntegrity()``
    /// additionally checks that the column *is* canonical for its own contents, so a non-canonical
    /// spelling of the same IDs cannot sit outside every check.
    public var parentReceiptIDsRawValue: String?
    @Attribute(.externalStorage) private var detailsData: Data

    public init(
        id: UUID = UUID(),
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
        correlationID: String? = nil,
        timelineAccountAddress: String? = nil,
        timelineChainRawValue: String? = nil,
        accountSequenceID: Int,
        payloadHash: String,
        previousReceiptHash: String,
        chainHash: String,
        signature: String? = nil,
        signerPublicKey: String? = nil,
        /// Defaulted to `current` rather than `legacy`: a new row is hashed with the current
        /// envelope, and a caller that forgot this parameter would otherwise mint a row claiming to
        /// predate the id binding — silently opting fresh history out of it.
        integrityEnvelopeVersion: Int = ReceiptIntegrityEnvelopeVersion.current,
        principal: PrincipalID? = nil,
        affectedResource: ReceiptResourceReference? = nil,
        producedResult: ReceiptResultReference? = nil,
        parentReceiptIDs: [UUID] = [],
        details: ReceiptPayload
    ) throws {
        self.integrityEnvelopeVersion = integrityEnvelopeVersion
        // Taken apart into columns here and reassembled by the accessors below, so the row and the
        // hashed envelope are built from one value rather than two that have to agree.
        self.principalIDRawValue = principal?.rawValue
        self.affectedResourceType = affectedResource?.type
        self.affectedResourceIdentifier = affectedResource?.identifier
        self.producedResultType = producedResult?.type
        self.producedResultIdentifier = producedResult?.identifier
        self.parentReceiptIDsRawValue = ReceiptContributionParents.canonicalRawValue(parentReceiptIDs)
        self.id = id
        self.sequenceID = sequenceID
        self.createdAt = createdAt
        // Derived from the structured detail when there is one, rather than trusting the coarse
        // parameter beside it (F-45). `ReceiptActorDetail.coarseActor` is a total function of `kind`
        // — `"human"` is a user, everything else is the system — and its own documentation says it
        // exists "so callers that only hold a `ReceiptActorDetail` cannot drift the two columns
        // apart by hardcoding one of them". Nothing enforced that here, so a row could persist *and
        // verify* with `actor = .system` while its detail said a person acted: a misleading answer on
        // the one column meant to say who did this. `ReceiptDraft.init` defaults `actor` to `.system`
        // while requiring `actorDetail`, so the mismatch needed no mistake beyond omitting an
        // argument.
        //
        // Structural rather than checked, which is why this derives instead of rejecting. The hash
        // input in ``SwiftDataReceiptStore/append(_:)`` derives the same way from the same draft, so
        // the hashed value and the stored column cannot disagree — the discipline that file already
        // applies to `id`, `accountAddress` and `integrityEnvelopeVersion`.
        self.actorRawValue = (actorDetail?.coarseActor ?? actor).rawValue
        self.actorKindRawValue = actorDetail?.kind
        self.actorIdentifier = actorDetail?.identifier
        self.actorDisplayName = actorDetail?.displayName
        self.actorInferenceLocalityRawValue = actorDetail?.inferenceLocality
        self.actorInferenceProvider = actorDetail?.inferenceProvider
        self.actorInferenceModelClass = actorDetail?.inferenceModelClass
        self.authoritySourceRawValue = authorityDetail?.source
        self.authorityLeaseID = authorityDetail?.leaseID
        self.authorityCapabilityRawValue = authorityDetail?.capability
        self.authorityScopeRawValue = authorityDetail?.scope
        self.authorityReason = authorityDetail?.reason
        self.authorityExpiresAt = authorityDetail?.expiresAt
        self.modeRawValue = mode.rawValue
        self.trigger = trigger
        self.scope = scope
        self.summary = summary
        self.provenance = provenance
        self.isSuccess = isSuccess
        self.correlationID = correlationID
        let resolvedAccountAddress = ReceiptAccountAddress.resolve(
            explicit: timelineAccountAddress,
            details: details
        )
        self.accountAddress = resolvedAccountAddress
        self.accountKey = ReceiptIntegrity.accountKey(accountAddress: resolvedAccountAddress)
        self.chainRawValue = ReceiptChainScope.resolve(
            explicit: timelineChainRawValue,
            details: details
        )
        self.accountSequenceID = accountSequenceID
        self.payloadHash = payloadHash
        self.previousReceiptHash = previousReceiptHash
        self.chainHash = chainHash
        self.signature = signature
        self.signerPublicKey = signerPublicKey
        self.detailsData = try Self.encodeDetails(details)
    }

    public var actor: ReceiptActor {
        get { ReceiptActor(rawValue: actorRawValue) ?? .system }
        set { actorRawValue = newValue.rawValue }
    }

    /// Reconstructs the structured attribution from its columns, or `nil` when the receipt predates the
    /// column (no `kind` was persisted).
    public var actorDetail: ReceiptActorDetail? {
        guard let actorKindRawValue else { return nil }
        return ReceiptActorDetail(
            kind: actorKindRawValue,
            identifier: actorIdentifier,
            displayName: actorDisplayName,
            inferenceLocality: actorInferenceLocalityRawValue,
            inferenceProvider: actorInferenceProvider,
            inferenceModelClass: actorInferenceModelClass
        )
    }

    /// Reconstructs the authority attribution from its columns, or `nil` when none was recorded.
    public var authorityDetail: ReceiptAuthorityDetail? {
        guard let authoritySourceRawValue else { return nil }
        return ReceiptAuthorityDetail(
            source: authoritySourceRawValue,
            leaseID: authorityLeaseID,
            capability: authorityCapabilityRawValue,
            scope: authorityScopeRawValue,
            reason: authorityReason,
            expiresAt: authorityExpiresAt
        )
    }

    /// The six actor columns as stored, for hashing.
    ///
    /// Not ``actorDetail``: that reconstructs a detail only when `actorKindRawValue` is present and
    /// returns `nil` otherwise, which put the other five columns outside the chain hash on any row
    /// without a kind. See the note on `ReceiptIntegrity.chainHash(…actorColumns:…)`.
    var actorColumns: ReceiptActorColumns {
        ReceiptActorColumns(
            kind: actorKindRawValue,
            identifier: actorIdentifier,
            displayName: actorDisplayName,
            inferenceLocality: actorInferenceLocalityRawValue,
            inferenceProvider: actorInferenceProvider,
            inferenceModelClass: actorInferenceModelClass
        )
    }

    /// The six authority columns as stored, for hashing. ``authorityColumns`` is to
    /// ``authorityDetail`` what ``actorColumns`` is to ``actorDetail``, and for the same reason.
    var authorityColumns: ReceiptAuthorityColumns {
        ReceiptAuthorityColumns(
            source: authoritySourceRawValue,
            leaseID: authorityLeaseID,
            capability: authorityCapabilityRawValue,
            scope: authorityScopeRawValue,
            reason: authorityReason,
            expiresAt: authorityExpiresAt
        )
    }

    /// The six contribution-provenance columns as stored, for hashing.
    ///
    /// `internal` rather than `public`, and taken from the columns rather than from the composed
    /// accessors below, for the reason ``actorColumns`` is: a composed reference reconstructs only
    /// when both of its halves are present, so hashing the composed form would leave a half-written
    /// pair outside the envelope entirely.
    var contributionColumns: ReceiptContributionColumns {
        ReceiptContributionColumns(
            principalID: principalIDRawValue,
            affectedResourceType: affectedResourceType,
            affectedResourceIdentifier: affectedResourceIdentifier,
            producedResultType: producedResultType,
            producedResultIdentifier: producedResultIdentifier,
            parentReceiptIDs: parentReceiptIDsRawValue
        )
    }

    /// The canonical principal, or `nil` when none was recorded or the column holds a value
    /// `PrincipalID` refuses.
    ///
    /// The refusal case is only reachable by writing the column directly — the append path takes a
    /// `PrincipalID`, so it cannot produce one — and it reads back as absent rather than throwing
    /// because a display surface must not fail on a damaged row. It does not escape notice: the
    /// *column* is hashed, so an edited one fails the chain hash regardless of what this returns.
    public var principal: PrincipalID? {
        principalIDRawValue.flatMap(PrincipalID.init(rawValue:))
    }

    /// The affected resource, or `nil` when none was recorded.
    ///
    /// Returns `nil` for a half-written pair as well, which is why the *columns* and not this are
    /// hashed — see ``contributionColumns``.
    public var affectedResource: ReceiptResourceReference? {
        guard let affectedResourceType, let affectedResourceIdentifier else { return nil }
        return ReceiptResourceReference(type: affectedResourceType, identifier: affectedResourceIdentifier)
    }

    /// The produced result, or `nil` when none was recorded. See ``affectedResource``.
    public var producedResult: ReceiptResultReference? {
        guard let producedResultType, let producedResultIdentifier else { return nil }
        return ReceiptResultReference(type: producedResultType, identifier: producedResultIdentifier)
    }

    /// The semantic parent receipt IDs, or `nil` when the stored column will not parse.
    ///
    /// Three-valued on purpose: `[]` means *no stated cause*, and `nil` means *this column has been
    /// edited into something no writer could have produced*. Collapsing the second into the first
    /// would let an unparseable value read as an innocent empty list, which is how a column ends up
    /// outside every check.
    public var parentReceiptIDs: [UUID]? {
        ReceiptContributionParents.parse(parentReceiptIDsRawValue)
    }

    /// Falls back to ``ReceiptMode/operate``, not `.observe`.
    ///
    /// The fallback only fires on a raw value this build has no case for, which in practice means an
    /// older build reading a store a newer one wrote. `.observe` was the wrong guess in the only
    /// direction that matters: it is the least alarming mode, so an Operate-class action — a signed
    /// transaction, a spend approval — would render on the audit surface as passive observation. An
    /// unknown mode is now reported as the most consequential one, which over-states rather than
    /// under-states and is the safe direction for every reader (a surface that warns on `.operate`
    /// warns; a surface that relaxes on `.observe` does not relax).
    ///
    /// The hash is unaffected either way: the envelope commits to ``modeRawValue``, precisely so a
    /// mode this build cannot name is not mistaken for a corrupted row.
    public var mode: ReceiptMode {
        get { ReceiptMode(rawValue: modeRawValue) ?? .operate }
        set { modeRawValue = newValue.rawValue }
    }

    /// The key this row's ``accountKey`` column should hold, derived from the column the chain hash
    /// commits to. Used to backfill pre-column rows and, afterwards, to assert the two still agree.
    var derivedAccountKey: String {
        ReceiptIntegrity.accountKey(accountAddress: accountAddress)
    }

    public func decodedDetails() throws -> ReceiptPayload {
        try Self.decodeDetails(from: detailsData)
    }

    /// The payload key a substituted payload carries, so "this receipt's details could not be read"
    /// is visible on the surface showing it rather than only in the log.
    ///
    /// Reading `detailsData` can fail with no adversary involved — it is
    /// `@Attribute(.externalStorage)`, so the blob can be pruned or lost — and substituting a plain
    /// empty payload made that indistinguishable from a receipt that genuinely recorded nothing. On
    /// an audit surface those are different claims, and the weaker one was being made silently.
    public static let unavailablePayloadKey = "auralisPayloadUnavailable"

    public func decodedDetailsOrEmpty() -> ReceiptPayload {
        do {
            return try decodedDetails()
        } catch {
            Self.logger.error(
                "Falling back to empty receipt payload for receipt id=\(self.id.uuidString, privacy: .public): \(error.localizedDescription, privacy: .public)"
            )
            return ReceiptPayload(values: [Self.unavailablePayloadKey: .bool(true)])
        }
    }

    /// The read model for this stored row, attribution columns included.
    ///
    /// Public so the storage layer's own contract is assertable: a row that predates the actor
    /// columns has to read back as *unattributed with an unchanged chain hash*, and that is only
    /// observable by converting a `StoredReceipt` directly — a draft can no longer produce that
    /// shape now that `actorDetail` is required (P0.5-602).
    public func asReceiptRecord() -> ReceiptRecord {
        makeReceiptRecord(details: decodedDetailsOrEmpty())
    }

    /// ``asReceiptRecord()`` without the empty-payload substitution.
    ///
    /// The substitution is right for display — one lost `.externalStorage` blob should not blank the
    /// whole console — but wrong for an export that is about to be hashed and signed: the record would
    /// travel with an empty payload while carrying the `payloadHash` of the real one, so every
    /// external verifier would recompute a mismatch and call the export tampered. Failing the export
    /// instead keeps the archive's promise that its hashes describe its contents.
    func asExportableReceiptRecord() throws -> ReceiptRecord {
        makeReceiptRecord(details: try decodedDetails())
    }

    private func makeReceiptRecord(details: ReceiptPayload) -> ReceiptRecord {
        ReceiptRecord(
            id: id,
            sequenceID: sequenceID,
            createdAt: createdAt,
            actor: actor,
            actorDetail: actorDetail,
            authorityDetail: authorityDetail,
            mode: mode,
            trigger: trigger,
            scope: scope,
            summary: summary,
            provenance: provenance,
            isSuccess: isSuccess,
            correlationID: correlationID,
            accountAddress: accountAddress,
            chainRawValue: chainRawValue,
            accountSequenceID: accountSequenceID,
            payloadHash: payloadHash,
            previousReceiptHash: previousReceiptHash,
            chainHash: chainHash,
            signature: signature,
            signerPublicKey: signerPublicKey,
            // Exported so an independent verifier rebuilds the envelope this row was hashed with.
            // `legacy` travels as `nil` so an archive of pre-column rows keeps its original bytes.
            //
            // `<=`, not `==`. The hashed envelope omits both `receiptID` and the version itself for
            // any value at or below `legacy`, so a row carrying a *negative* version hashes exactly
            // like a legacy row and verifies on both sides — but mapped with `==` it travelled into
            // the archive verbatim, advertising a version that does not exist and never will. No
            // forgery power either way, since the two halves agree; this just stops the archive
            // asserting something untrue about how it was built.
            integrityEnvelopeVersion: integrityEnvelopeVersion <= ReceiptIntegrityEnvelopeVersion.legacy
                ? nil
                : integrityEnvelopeVersion,
            // The stored strings, carried only when the typed case above is a degraded stand-in for
            // them — i.e. only when this build has no case for what the row holds. The chain hash
            // commits to these strings, so without them the archive described one value and was
            // hashed over another, and the verifier called an honest ledger tampered. See
            // ``ReceiptRecord/actorRawValue``.
            //
            // Compared against the round trip rather than against a list of known cases, so this
            // cannot drift as cases are added.
            actorRawValue: actor.rawValue == actorRawValue ? nil : actorRawValue,
            modeRawValue: mode.rawValue == modeRawValue ? nil : modeRawValue,
            // Phase 1 contribution provenance, carried in composed form because that is what a reader
            // of the archive wants and because an independent verifier rebuilds the hashed columns
            // from it through `ReceiptContributionColumns(principal:affectedResource:…)` — lossless
            // for every row an honest append can write.
            //
            // A *damaged* row loses information here, and that is the correct outcome rather than a
            // gap: a half-written reference or an unparseable parent column composes to `nil`, the
            // verifier recomputes a hash over absent columns, and the mismatch against the stored
            // `chainHash` — which committed to the damaged columns — reports the row as tampered.
            // Such a row also never reaches an archive, because `exportAll()` is gated on the local
            // verdict that already rejected it.
            principal: principal,
            affectedResource: affectedResource,
            producedResult: producedResult,
            parentReceiptIDs: parentReceiptIDs,
            details: details
        )
    }

    /// Corrupts the payload blob, so the "this row's details will not decode" path is reachable from
    /// a test. `detailsData` is `private` and `@Attribute(.externalStorage)`, and that condition
    /// arises in the field without an adversary — an external blob lost or pruned — so it needs
    /// coverage. Nothing in the package calls this.
    ///
    /// `#if DEBUG` so the one function in this file that exists to damage a tamper-evident row cannot
    /// reach a release binary. Tests build debug, so `@testable import` still sees it.
    #if DEBUG
    func replaceDetailsDataForTesting(_ data: Data) {
        detailsData = data
    }
    #endif

    /// `private`, not `public`. Both were public API with no reader outside this type — and a public
    /// encoder for the blob a `payloadHash` commits to is an invitation to write one without updating
    /// the other.
    private static func encodeDetails(_ details: ReceiptPayload) throws -> Data {
        try JSONEncoder().encode(details)
    }

    private static func decodeDetails(from data: Data) throws -> ReceiptPayload {
        try JSONDecoder().decode(ReceiptPayload.self, from: data)
    }
}

/// The one resolution of *which account* a receipt belongs to.
///
/// Both the integrity chain hash and the stored row read it from here, and that is the whole point.
/// They used to resolve it separately: `ReceiptPersistenceStore.append` hashed the draft's explicit
/// value trimmed and lowercased, while `StoredReceipt.init` stored that value **raw** and fell back
/// to the payload when it was absent. Either divergence — a checksummed (mixed-case) address, or a
/// draft with no explicit address whose payload carried one — hashed one string and verified another.
/// `verifyIntegrity()` then declared the whole ledger invalid and `exportAll()` refused to run, for
/// the life of the installation, on receipts that were written correctly. One function, one answer.
enum ReceiptAccountAddress {
    static func resolve(explicit: String?, details: ReceiptPayload) -> String? {
        if let trimmed = explicit?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty {
            // Normalized *if it is an address*, lowercased otherwise (F-107).
            //
            // `AuralisEthereumAddress` is not used as a validator here — it would also *reject*
            // anything that is not 40 hex digits, and this is the receipt ledger's account *key*, not
            // an address parser: turning an unrecognized value into `nil` would silently move that
            // receipt onto the "global" chain. So a failed parse falls through to the raw lowercased
            // key, exactly as before.
            //
            // What the parse fixes is the one shape the two writers disagreed about. The payload
            // branch below has always gone through `AuralisEthereumAddress.normalized` (see
            // `ReceiptPayload.timelineAccountAddress`), which always emits `"0x" + 40hex`; this branch
            // lowercased only. A caller passing a valid but **unprefixed** address therefore stored
            // `"abc…"` while `ReceiptTimelineRecord.accountKey` — and so every SwiftData fetch
            // predicate built from it — searched for `"0xabc…"`, excluding the row from its own
            // account's timeline permanently, since a post-fetch filter can only narrow and never
            // recover a row the predicate dropped. The two branches of one function now answer the
            // same question the same way.
            //
            // **Hash-neutral for everything any writer produces today.** For an already-prefixed
            // valid address the two expressions are byte-identical — `AuralisEthereumAddress` trims,
            // lowercases, and re-emits `"0x" + 40hex` — and for a non-address key the parse fails and
            // the old expression is used unchanged. The *only* input whose stored bytes change is the
            // bare-40-hex form, which no production writer emits (the assertion below has sat over
            // this call since Round 18 and ReceiptStorage stayed green), and whose previous value was
            // an orphaned row. So nothing already on disk is re-interpreted and nothing currently
            // writable re-hashes.
            //
            // The assertion stays. It is now a *detector for a call site that needs fixing* rather
            // than the only thing standing between that call site and a lost receipt: normalization
            // handles it correctly in release, and in debug the first violation still says loudly
            // which writer supplied the wrong shape.
            assertAddressLikeValuesArePrefixed(trimmed)
            return normalizedAccountKey(trimmed)
        }
        assertAddressLikeValuesArePrefixed(details.timelineAccountAddress)
        return details.timelineAccountAddress
    }

    /// The explicit branch's key derivation, split out as a pure function so it can be tested.
    ///
    /// Not merely tidiness: ``assertAddressLikeValuesArePrefixed`` traps in `DEBUG`, and tests build
    /// debug, so calling ``resolve(explicit:details:)`` with the one input this fix is *about* would
    /// hit the assertion instead of the behaviour. Without this seam the normalization would be a live
    /// code path with no test — the exact class of defect this audit has now found three times
    /// (F-92, F-99, F-108). The assertion stays on the real write path; the decision it guards is
    /// pinnable here.
    static func normalizedAccountKey(_ trimmed: String) -> String {
        ReceiptStorageScopeNormalizer.normalizedAddress(trimmed) ?? trimmed.lowercased()
    }

    /// Debug-only guard on the one input shape this function cannot normalize away (F-100).
    ///
    /// The stored value is deliberately *not* `0x`-prefixed by this function — see above, an
    /// unrecognized key has to survive as itself. But the readers go the other way:
    /// `ReceiptTimelineRecord.accountKey`, and therefore every SwiftData fetch predicate built from
    /// it, resolves a valid 40-hex address through `AuralisEthereumAddress.normalized`, which always
    /// emits `"0x" + 40hex`. So a receipt written with a **valid but unprefixed** address is stored as
    /// `"abc…"` while every predicate searches for `"0xabc…"`, and it is excluded from its own
    /// account's timeline permanently — a post-fetch filter can only narrow, never recover a row the
    /// predicate dropped.
    ///
    /// **No longer the mitigation — the detector (F-107).** `resolve` now normalizes an address-like
    /// explicit value through `AuralisEthereumAddress`, so the orphaned-row outcome is closed in
    /// release builds too, which is what this assertion could never do: it is `#if DEBUG` and compiles
    /// out of exactly the configuration users run. The earlier reasoning for leaving normalization out
    /// — that it would change what future receipts hash — turned out not to bite, because for an
    /// already-prefixed address `AuralisEthereumAddress.normalized` is byte-identical to the previous
    /// `trimmed.lowercased()`, so the only receipts whose bytes change are ones no writer emits.
    ///
    /// What it still buys, and why it is kept: normalization silently *accepts* a call site that is
    /// passing the wrong shape, and that call site is a bug worth seeing. In debug and under test the
    /// first violation still names the writer; in release the receipt now lands on the right account
    /// instead of vanishing from its own timeline.
    ///
    /// Scoped to *address-like* values only: a 40-character ASCII-hex string with no prefix. Anything
    /// else is a legitimate non-address account key (ENS-style), which `accountKey` lowercases on both
    /// sides, so those round-trip correctly and must not trip this.
    private static func assertAddressLikeValuesArePrefixed(_ value: String?) {
        #if DEBUG
        guard let value, value.count == 40 else { return }
        guard value.allSatisfy({ $0.isASCII && $0.isHexDigit }) else { return }
        assertionFailure(
            """
            Receipt account address "\(value)" is a valid address with no "0x" prefix. \
            It would be stored unprefixed and excluded from every receipt-timeline fetch predicate, \
            which normalize through AuralisEthereumAddress and always search for the 0x form. \
            Prefix it at the call site (see F-100 in docs/audits/ship-readiness/02-FINDINGS.md).
            """
        )
        #endif
    }
}

/// The one resolution of *which chain* a receipt belongs to, for exactly the reason
/// ``ReceiptAccountAddress`` exists.
///
/// The same divergence was still live here after the address was fixed: `ReceiptPersistenceStore`
/// hashed the draft's raw `timelineChainRawValue`, while `StoredReceipt.init` stored
/// `timelineChainRawValue ?? details.timelineChainRawValue`. A draft with no explicit chain whose
/// payload carried a recognized `chain`/`to_chain` string therefore hashed `nil` and stored
/// `"eth-mainnet"`, so `verifyIntegrity()` re-hashed the row and returned
/// `.tampered("invalid chain hash")` for it and every later row on that account — for the life of the
/// install. That every current caller happens to pass both values is not an invariant; this is.
enum ReceiptChainScope {
    static func resolve(explicit: String?, details: ReceiptPayload) -> String? {
        if let trimmed = explicit?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty {
            // Not put through `Chain(rawValue:)`: like the account key, an unrecognized value has to
            // survive as itself rather than become `nil` and silently move the row onto another chain.
            return trimmed
        }
        return details.timelineChainRawValue
    }
}

extension ReceiptPayload {
    var timelineAccountAddress: String? {
        value(forKeys: ["accountAddress", "address"])
            .flatMap(ReceiptStorageScopeNormalizer.normalizedAddress)
    }

    var timelineChainRawValue: String? {
        guard let rawValue = value(forKeys: ["chain", "to_chain"]) else {
            return nil
        }

        return ReceiptStorageScopeNormalizer.normalizedOpaqueChain(rawValue)
    }

    func value(forKeys keys: [String]) -> String? {
        for key in keys {
            if case .string(let value)? = values[key] {
                return value
            }
        }

        return nil
    }
}
