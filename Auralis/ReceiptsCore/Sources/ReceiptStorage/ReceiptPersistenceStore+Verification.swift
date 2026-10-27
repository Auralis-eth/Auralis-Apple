import CryptoKit
import Foundation
import ReceiptsCore
import RuntimeCore
import SwiftData
import AuralisFoundation

/// The verify-and-export half of ``ReceiptPersistenceStore``.
///
/// An extension in its own file rather than more of the actor's body. The two reasons are the same
/// reason: this is the read-modify-write surface over the anchors — `verifyIntegrity()`,
/// `exportAll()`, `restoreHeads(_:)` and the head selection they share — and it is the part of the
/// store worth reading as a unit, separately from the append path and the lock that serializes both.
/// Keeping it inline also pushed the actor's body past the length the linter allows.
///
/// Everything here is actor-isolated exactly as if it were inline; `performX()` halves still exist so
/// they can compose inside one ``withLedgerLock(_:_:)`` acquisition.
///
/// The cost of the split, stated because it is a real one: `withLedgerLock(_:_:)`, `signer`,
/// `integrityHeadStore` and `backfillAccountKeysIfNeeded()` had to widen from `private` to
/// `internal` to be reachable from here. They are module-internal, not public, and each carries a
/// note at its declaration saying this file is the only other legitimate caller —
/// `withLedgerLock(_:_:)` especially, since it is non-reentrant and a misplaced call hangs.
extension ReceiptPersistenceStore {
    /// Verification and the export it gates run in *one* lock acquisition, so the rows that were
    /// verified are the rows that get exported. Splitting them let a receipt appended in between
    /// travel in a signed archive having never been checked.
    public func exportAll() async throws -> Data {
        try await withLedgerLock(.exportAll) { [self] in
            try await performExportAll()
        }
    }

    private func performExportAll() async throws -> Data {
        let (integrity, ledgerHighWaterMark) = try await performVerifyIntegrity()
        // `isValid` excludes only a tampered ledger. An unattested one still exports: refusing it is
        // what left an upgraded install unable to export the history it had, forever, with deleting
        // that history as the only way out. The archive stays honest without a format change —
        // unsigned rows travel with `signature == nil`, and `ReceiptProvenanceVerifier` applies the
        // same prefix rule and returns `.unattested` for them.
        guard integrity.isValid else {
            throw ReceiptProvenanceExportError.integrityFailure(
                integrity.failureReason ?? "Receipt integrity verification failed."
            )
        }

        let descriptor = FetchDescriptor<StoredReceipt>(
            sortBy: [
                SortDescriptor(\StoredReceipt.createdAt),
                SortDescriptor(\StoredReceipt.sequenceID)
            ]
        )

        let storedReceipts = try modelContext.fetch(descriptor)
        // Strict decode, unlike every display path: an archive whose `payloadHash` columns describe
        // payloads it does not actually carry is worse than no archive.
        //
        // **This is where an unreadable payload stops the export, and it is deliberate.**
        // `performVerifyIntegrity()` reports a lost `.externalStorage` blob as *unattested* rather
        // than tampered — it is a non-adversarial event and branding the ledger altered is what made
        // it unrecoverable — so the verdict gate above admits such a ledger and this decode is the
        // check that refuses the archive. The refusal is the right answer here for the reason
        // ``StoredReceipt/asExportableReceiptRecord()`` gives: an exported record carrying an empty
        // payload alongside the real payload's hash would make every external verifier recompute a
        // mismatch and call the archive tampered. Refusing with a stated reason is strictly better
        // than shipping an archive that indicts itself.
        //
        // The distinction that matters: the ledger stays *readable* and the person is told the
        // specific receipt at fault, instead of the whole history reading `.tampered` with
        // `resetAll()` as the only exit.
        let records: [ReceiptRecord]
        do {
            records = try storedReceipts.map { try $0.asExportableReceiptRecord() }
        } catch {
            throw ReceiptProvenanceExportError.integrityFailure(
                "A receipt payload could not be read for export: \(error.localizedDescription)"
            )
        }
        // Wrapped for the reason the payload decode above is: a row can hold a column with no
        // canonical byte form — a non-finite `createdAt` is enough — and letting the raw
        // `EncodingError` out meant `exportAll()` failed with something no caller matching
        // `ReceiptProvenanceExportError` could see. `performVerifyIntegrity()` rejects such a row
        // before this point, so reaching this catch means the columns changed inside the lock.
        let recordsHash: String
        do {
            recordsHash = ReceiptIntegrity.sha256Hex(try ReceiptIntegrity.canonicalData(records))
        } catch {
            throw ReceiptProvenanceExportError.integrityFailure(
                "The receipt set could not be canonically encoded for export: \(error.localizedDescription)"
            )
        }
        // Taken from the head *rows* rather than recomputed. This used to call `latestHeads`, which
        // selects each account's tip row and then discards it via `mapValues(\.chainHash)`, and then
        // re-scan every receipt with a `filter`/`max` per account to recover the `accountSequenceID`
        // that tip row already carried — O(accounts × rows) to rebuild data thrown away one line up.
        let chainHeads = latestHeadRows(from: storedReceipts)
            .map { accountKey, headRow in
                ReceiptProvenanceChainHead(
                    accountKey: accountKey,
                    accountSequenceID: headRow.accountSequenceID,
                    chainHash: headRow.chainHash
                )
            }
            .sorted { $0.accountKey < $1.accountKey }
        let manifest = ReceiptProvenanceManifest(
            recordCount: records.count,
            recordsHash: recordsHash,
            chainHeads: chainHeads,
            // The value `performVerifyIntegrity()` actually read and reasoned about, inside this same
            // lock acquisition, rather than a second Keychain read that could disagree with it —
            // including after the stale-mark heal that runs in there. Publishing it is what lets a
            // third party apply the completeness test locally; without it, exporting first defeated
            // the check exactly as omitting `sequenceGapReasons` from the verifier once did.
            ledgerHighWaterMark: ledgerHighWaterMark,
            // Stated rather than left to be inferred from the absent mark, which would be
            // indistinguishable from an archive predating the field. `nil` on an empty archive: with
            // no rows and no mark there is nothing to be incomplete about that is not already
            // indistinguishable from a fresh install.
            //
            // **Deliberately a wider condition than the local advisory's, which is the one place the
            // two halves of this package are allowed to disagree.** `performVerifyIntegrity()`
            // additionally requires `!currentIdentitySeen.isEmpty` before raising its advisory, so a
            // *restored* ledger — rows present, no mark, nothing signed by this identity — is not
            // accused locally; that conjunct exists because a restore legitimately has no
            // `ThisDeviceOnly` state and telling the person their history looks truncated would be a
            // false accusation on the most ordinary of events.
            //
            // A third party reading the archive is not in that position. For them an omitted mark is
            // ambiguous between "this archive predates the field" and "the exporting device had no
            // mark", and disambiguating it is the entire reason this flag exists — suppressing it here
            // would restore the ambiguity the field was added to remove. So the archive says the true
            // thing without hedging, and the local surface declines to alarm. Pinned by
            // `restoredLedgerArchiveDeclaresCompletenessUnconfirmed`.
            ledgerCompletenessUnconfirmed: records.isEmpty || ledgerHighWaterMark != nil ? nil : true
        )
        let manifestHash: String
        do {
            manifestHash = ReceiptIntegrity.sha256Hex(try ReceiptIntegrity.canonicalData(manifest))
        } catch {
            throw ReceiptProvenanceExportError.integrityFailure(
                "The provenance manifest could not be canonically encoded: \(error.localizedDescription)"
            )
        }
        // Wrapped for the same reason the payload decode above is, and it was the last plain `try` on
        // this path. `performVerifyIntegrity()` goes out of its way to tolerate a signer that cannot
        // answer (`try?`) and a Keychain that cannot be read, precisely so an honest-but-unattestable
        // ledger stays exportable — and then this threw whatever the signer threw. A caller matching
        // `ReceiptProvenanceExportError`, the documented contract, saw nothing and the person got an
        // opaque `CryptoKitError` instead of a stated reason.
        let signedManifest: ReceiptSignature
        do {
            signedManifest = try await signer.sign(manifestHash)
        } catch {
            throw ReceiptProvenanceExportError.integrityFailure(
                "This device could not sign the provenance manifest: \(error.localizedDescription)"
            )
        }
        let trustAnchor = trustAnchor(publicKey: signedManifest.publicKeyRepresentation)
        let export = ReceiptProvenanceExport(
            records: records,
            manifest: manifest,
            manifestHash: manifestHash,
            manifestSignature: signedManifest.signature.base64EncodedString(),
            trustAnchor: trustAnchor
        )
        do {
            return try ReceiptIntegrity.canonicalData(export)
        } catch {
            throw ReceiptProvenanceExportError.integrityFailure(
                "The provenance archive could not be canonically encoded: \(error.localizedDescription)"
            )
        }
    }

    /// This device's signer fingerprint, for pinning through a channel separate from the export.
    ///
    /// Reads the public key directly. It used to sign a fixed string and then use only the public key
    /// the signature carried back, discarding the signature itself — so the operation cost a P-256
    /// signature and proved nothing to anybody, while the local variable was named `identityProof`
    /// and claimed otherwise. A fingerprint is only trustworthy because of the channel it arrives
    /// over; a self-signed proof bundled with it adds nothing.
    public func provenanceTrustAnchor() async throws -> ReceiptProvenanceTrustAnchor {
        trustAnchor(publicKey: try await signer.publicKeyRepresentation())
    }

    private func trustAnchor(publicKey: Data) -> ReceiptProvenanceTrustAnchor {
        ReceiptProvenanceTrustAnchor(
            algorithm: "P-256/SHA-256",
            publicKey: publicKey.base64EncodedString(),
            fingerprint: ReceiptIntegrity.sha256Hex(publicKey)
        )
    }

    /// Queued with the ledger mutations because it *is* one: it overwrites the durable half of the
    /// chain invariant, and an append committing between a caller deciding on a head and this writing
    /// it rewinds the anchor behind the rows.
    ///
    /// **`internal`, and it should stay that way until a real restore feature needs it.** It writes
    /// caller-supplied anchors without checking that any of them corresponds to a persisted row, so it
    /// is a one-line defeat of the only truncation the package catches *without* Keychain access: a
    /// deleted suffix currently lands on `.invalid("Receipt chain head mismatch …")` because the
    /// anchor runs ahead of the surviving tip, and pointing the anchor at that tip turns the verdict
    /// back to `.verified`. Exported as `public` it was an unvalidated anchor overwrite on the public
    /// surface of a tamper-evidence store — out of step with a package that deliberately made
    /// ``ReceiptPersistenceStore/signer`` a required parameter and `encodeDetails` private for the
    /// same class of reason. Today the only callers are this file's anchor heal (via
    /// ``performRestoreHeads(_:)``, which skips the lock) and three tests.
    ///
    /// Whoever does wire a restore feature to this should validate first: require each supplied hash
    /// to match a head row already on disk.
    func restoreHeads(_ heads: [String: String]) async throws {
        try await withLedgerLock(.restoreHeads) { [self] in
            try await performRestoreHeads(heads)
        }
    }

    private func performRestoreHeads(_ heads: [String: String]) async throws {
        var failures: [String] = []
        for (accountKey, chainHash) in heads {
            do {
                try await integrityHeadStore.saveHead(chainHash, for: accountKey)
            } catch {
                failures.append("\(accountKey): \(error.localizedDescription)")
            }
        }
        if !failures.isEmpty {
            throw ReceiptHeadRestorationError(failures: failures.sorted())
        }
    }

    /// Tells the external witness where the ledger has got to.
    ///
    /// **Best-effort by design, and that is the same decision the high-water mark write already
    /// makes.** By the time this runs the receipt and its anchor are committed, so throwing would
    /// report a write failure for a receipt that exists and invite a retry that appends it twice. A
    /// failed publish leaves the witness one checkpoint behind, which the comparison tolerates — it
    /// only ever fires on a *backwards* move — and which verification reports as an advisory.
    ///
    /// ## The exposure window, and the Phase 1 decision about it
    ///
    /// **Publishing is asynchronous with the append, deliberately, and the residual is accepted for
    /// Phase 1.** The known limitation: receipts written *since the last successful publish* are
    /// outside anything the witness can vouch for, so an attacker who removes only those is not
    /// caught. Publishing on every append keeps that window one receipt wide when the network is
    /// healthy, and arbitrarily wide when it is not.
    ///
    /// The alternative — awaiting a CloudKit round trip before the append returns — was considered and
    /// rejected: it puts the network in the critical path of every receipt, so an offline device could
    /// not record its own audit trail. That trades a narrow, detectable-in-aggregate gap for an
    /// outright loss of history, which is the wrong direction for this package.
    ///
    /// Two follow-ups are recorded rather than built, neither a blocker:
    ///
    /// 1. **Shrink the window without blocking the append.** A durable "publish pending" queue with
    ///    aggressive retry, surfaced through the integrity status, so an unpublished tail is visible
    ///    instead of merely unwitnessed. Note the queue itself must live somewhere the attacker cannot
    ///    rewrite, or it becomes another self-authorising local signal — the mistake this package made
    ///    four separate times.
    /// 2. **A witness outside the person's Apple account**, when protection against the account owner
    ///    is actually required: a transparency log, an L2 commitment, or another independently
    ///    controlled party. See ``CloudKitReceiptLedgerWitness`` for exactly what the current witness
    ///    does and does not defend against.
    ///
    /// Takes the state to publish as a parameter rather than re-reading it, so what reaches the
    /// witness is exactly what the caller verified or wrote — never a second, possibly racing, read.
    func publishWitnessCheckpoint(
        highestVerifiedSequenceID: Int,
        chainHeads: [ReceiptProvenanceChainHead],
        recordCount: Int
    ) async {
        do {
            try await witness.publish(
                ReceiptLedgerCheckpoint(
                    ledgerHighWaterMark: highestVerifiedSequenceID,
                    chainHeads: chainHeads,
                    recordCount: recordCount,
                    publishedAt: Date()
                )
            )
        } catch ReceiptLedgerWitnessError.notConfigured {
            // Not worth a log line on every append: no witness is wired up, which verification
            // already reports once, as an advisory, where a person will see it.
        } catch {
            Self.logger.error(
                "Receipt ledger checkpoint could not be published to the external witness at sequence \(highestVerifiedSequenceID, privacy: .public): \(error.localizedDescription, privacy: .public)"
            )
        }
    }

    /// Whether rows declaring an envelope this build cannot reproduce are a downgrade or a forgery.
    ///
    /// **This is the one decision in the pass where "cannot verify" had to be told apart from "did not
    /// verify" using something other than the row**, because the input that disables the
    /// recomputation — `integrityEnvelopeVersion` — is itself a column an attacker with SwiftData
    /// write access can set. Left unbounded it was a complete bypass of the chain hash: measured, on a
    /// three-receipt ledger with store writes alone, raising that column let a receipt's `summary`,
    /// `mode` and `isSuccess` be rewritten in place and carried into the manifest-signed archive at
    /// `.unattested`, which ``ReceiptIntegrityVerificationResult/isValid`` accepts.
    ///
    /// Two things can vouch for such a row, and it needs *either*:
    ///
    /// - **The durable floor.** A build that writes envelope version N records N on every append, in
    ///   the same `ThisDeviceOnly` Keychain as the mark, so a row at or below the recorded floor was
    ///   written by a real build on this device. A row-store attacker cannot raise it.
    /// - **A total absence of local evidence** — *no floor recorded at all*, and nothing in the ledger
    ///   signed by this device's current identity. That is the restore signature: a transfer brings
    ///   the SwiftData store back without the `ThisDeviceOnly` signing key *or* the floor, so a store
    ///   written by a newer build on another device legitimately arrives above anything this device
    ///   recorded.
    ///
    /// The second clause is what makes the first safe to require, and it took three passes to get its
    /// shape right. Gating on the floor alone left it absent — and therefore permissive — on the most
    /// ordinary state there is: every install upgrading to the first build that records a floor has
    /// rows and no floor until its next append. Eagerly minting a floor instead would brand a genuine
    /// restore-from-a-newer-build `.tampered`, and minting `max(current, highest row version)` would
    /// let an attacker who moves first make their own forged version durably legitimate.
    ///
    /// **Both halves of the second clause are load-bearing, and requiring the floor to be absent is
    /// the half that is easy to get wrong.** Keying the hatch on `thisDeviceWroteSomeRow` alone was
    /// circular in the same way the version column itself is: an attacker with row-store writes can
    /// *manufacture* an unattestable ledger by clearing the signing columns on every row, and the
    /// version bump they already needed is what hides the resulting chain-hash mismatch. Measured with
    /// store writes alone, against a ledger whose floor was present and correct at 1: clearing both
    /// signing columns and raising every row to version 2 produced `.unattested` and carried a
    /// rewritten `summary` into the manifest-signed archive. Demanding `floor == nil` breaks the
    /// circle, because the floor is the one input here that no row asserts — an attacker cannot delete
    /// it without Keychain access, which is the attacker
    /// ``ReceiptIntegrityVerificationResult/isValid`` concedes by design.
    ///
    /// The companion half of the same repair is the pairing rule in
    /// ``ReceiptSigningMetadata/classify(signature:signerPublicKey:)``, which stops a signature being
    /// removed on its own. The two are independent and both are needed: one closes de-attestation, the
    /// other stops a manufactured de-attestation from licensing anything.
    ///
    /// The residual, stated rather than glossed: a restore-from-a-newer-build onto a device that
    /// *does* have a floor reads `.tampered` by this rule. Such a ledger is already `.tampered` before
    /// reaching here — the receiving device's own anchors name accounts the incoming store does not
    /// have, or name a different tip for one it does — so this adds no new false positive, but it is
    /// resting on that and would need revisiting if the anchor checks ever softened.
    ///
    /// - Returns: The verdict string, or `nil` when every such row is vouched for.
    private static func unrecomputableRowVerdict(
        _ rows: [(receiptID: UUID, envelopeVersion: Int)],
        floor: Int?,
        thisDeviceWroteSomeRow: Bool
    ) -> String? {
        guard !rows.isEmpty else { return nil }
        // The restore case: no durable evidence of any kind. `floor == nil` is checked as well as
        // attestability precisely because the rows can fake the latter and cannot fake the former.
        if floor == nil, !thisDeviceWroteSomeRow { return nil }
        guard let offender = rows.first(where: { $0.envelopeVersion > (floor ?? ReceiptIntegrityEnvelopeVersion.current) }) else {
            return nil
        }
        let vouched = floor ?? ReceiptIntegrityEnvelopeVersion.current
        return "Receipt \(offender.receiptID.uuidString) declares integrity envelope version \(offender.envelopeVersion), but no build on this device has written past version \(vouched)."
    }

    /// Each account's tip row — the row itself, so a caller that needs both its hash and its
    /// sequence does not have to rediscover the second by rescanning the ledger.
    ///
    /// The single definition of "tip", used by both ``performVerifyIntegrity()`` and
    /// ``performExportAll()``. Independent of the caller's fetch order on purpose: it takes the max
    /// by `(accountSequenceID, sequenceID)` rather than the last row it is handed, and the two call
    /// sites do sort differently.
    private func latestHeadRows(from receipts: [StoredReceipt]) -> [String: StoredReceipt] {
        var latestByAccount: [String: StoredReceipt] = [:]
        for receipt in receipts where receipt.hasCompleteIntegrityMetadata {
            let accountKey = receipt.accountKey
            if receipt.isNewerIntegrityHead(than: latestByAccount[accountKey]) {
                latestByAccount[accountKey] = receipt
            }
        }
        return latestByAccount
    }

    public func verifyIntegrity() async throws -> ReceiptIntegrityVerificationResult {
        try await withLedgerLock(.verifyIntegrity) { [self] in
            try await performVerifyIntegrity().result
        }
    }

    /// - Returns: The verdict, and the ledger high-water mark this pass read — so
    ///   ``performExportAll()`` publishes the value that was actually reasoned about here instead of
    ///   taking its own second Keychain read.
    private func performVerifyIntegrity() async throws -> (
        result: ReceiptIntegrityVerificationResult,
        ledgerHighWaterMark: Int?
    ) {
        // Before the fetch below sorts on `accountKey` and the loop checks it against its derivation.
        // Without this a pre-column row would sort under `""` and then fail that check as an edited
        // key — a migration artefact reported as tampering.
        try backfillAccountKeysIfNeeded()

        let receipts = try modelContext.fetch(
            FetchDescriptor<StoredReceipt>(
                sortBy: [
                    // Sorted by the grouping key, and *not* also by `accountAddress`. Two spellings
                    // that fold onto one key must stay interleaved in sequence order: sorting on the
                    // raw column split them into blocks, so the second block restarted at
                    // `accountSequenceID == 1` and the whole ledger verified as an invalid account
                    // sequence. The key is the only account column this loop is entitled to order by.
                    SortDescriptor(\StoredReceipt.accountKey),
                    SortDescriptor(\StoredReceipt.accountSequenceID),
                    SortDescriptor(\StoredReceipt.sequenceID)
                ]
            )
        )

        // Read up front so every exit below can report it, and tolerated for the same reason the
        // identity read beneath it is: the mark lives in the same `ThisDeviceOnly` Keychain, so a
        // locked device cannot produce it, and that makes completeness *unconfirmed* rather than the
        // ledger invalid. The two outcomes are kept apart — an unreadable mark says why, an absent one
        // says there is none — because on a device that demonstrably wrote this chain those are
        // different claims, and the second one is the one that matters.
        //
        // A `var` because the heal at the end of this function may raise it, and the value handed
        // back — the one `performExportAll()` publishes in the signed manifest — should be the mark
        // this ledger actually carries when the pass finishes, not the one it started with.
        var ledgerHighWaterMark: Int?
        let highWaterMarkReadFailure: String?
        do {
            ledgerHighWaterMark = try await integrityHeadStore.loadLedgerHighWaterMark()
            highWaterMarkReadFailure = nil
        } catch {
            ledgerHighWaterMark = nil
            highWaterMarkReadFailure = error.localizedDescription
        }

        // The durable floor that bounds the "this build cannot recompute that envelope" concession
        // below. Read here, beside the mark, because it comes from the same `ThisDeviceOnly` Keychain
        // and a locked device cannot produce either.
        //
        // `try?`, so an unreadable floor falls back to `nil` — the permissive case. That is the same
        // trade the mark makes and it is deliberate: a device that cannot read its own Keychain must
        // not report its history as forged. The cost is that a locked Keychain reopens the version
        // concession, which is acceptable because reaching *that* state on purpose already means
        // writing or deleting Keychain items, which is the attacker
        // ``ReceiptIntegrityVerificationResult/isValid`` concedes by design.
        let highestRecordedEnvelopeVersion = try? await integrityHeadStore.loadHighestEnvelopeVersion()

        var previousByAccount: [String: StoredReceipt] = [:]
        // `try?`, not `try`: on a locked Keychain or a restored device this device simply has no
        // identity to compare against, which makes the ledger unattestable, not invalid. Throwing
        // here would propagate out of `exportAll()` as an outright failure.
        let currentSignerPublicKey = receipts.isEmpty ? nil : try? await signer.publicKeyRepresentation()
        // Whether this device can say *anything* about who signed these rows. When it cannot, every
        // identity-dependent check below has to be read as "unknown", not as "no".
        //
        // Carries no `receipts.isEmpty` disjunct of its own. Its readers supply that where they need
        // it: the loop over `persistedHeads` does not, because that collection is derived from
        // `receipts` and so is empty whenever `receipts` is, while the headline note after the loop
        // spells out `!receipts.isEmpty` because it runs unconditionally.
        let hasSignerIdentity = currentSignerPublicKey != nil
        // Accounts for which a row signed by the *current* identity has already been seen. Signing
        // may only move forward: an unsigned or previously-keyed row appearing after one is a
        // regression, and the only way to produce it is to strip or swap a signature.
        var currentIdentitySeen: Set<String> = []
        var unattestedReasons: [String] = []
        // The ledger-wide half of that same rule, which no single row can support. See
        // ``ReceiptSigningLedgerOrdering`` — the per-account rule alone let a whole account fabricated
        // after signing began pass as a pre-signing prefix.
        var signingOrdering = ReceiptSigningLedgerOrdering()
        // Every chain hash seen so far, because a *repeated* one is a replayed signature. See
        // ``ReceiptChainHashUniqueness``.
        var chainHashUniqueness = ReceiptChainHashUniqueness()
        // Rows declaring an envelope this build cannot reproduce, judged after the loop because the
        // decision needs `currentIdentitySeen` in its final state.
        var unrecomputableRows: [(receiptID: UUID, envelopeVersion: Int)] = []
        // The top of the ledger *as this build was able to verify it* — the max `sequenceID` over rows
        // whose chain hash was recomputed and matched. The mark heal writes durable trusted state from
        // this, so it must not include a row whose columns nothing checked.
        var highestVerifiedSequenceID: Int?
        // The `(account, sequence) -> chainHash` lookup the external witness comparison needs, built in
        // this one sweep rather than by re-fetching. Populated for every row that clears the
        // structural checks, including rows whose envelope this build cannot recompute: the witness
        // statement is about `chainHash` values, so comparing a stored hash against a witnessed one is
        // meaningful — and is in fact the only thing that can *confirm* a conceded row is genuine.
        var chainHashesByAccountSequence: [ReceiptWitnessRowKey: String] = [:]
        var tipSequenceByAccount: [String: Int] = [:]
        // Every receipt id in this ledger, so the loop can tell a *dangling* semantic parent from a
        // present one. Built from the same fetch rather than by a per-parent query: the loop already
        // holds every row, and a second fetch inside it would be O(rows × parents) against the store
        // for data already in hand.
        let presentReceiptIDs = Set(receipts.map(\.id))

        // Every exit from here on carries the mark, so `performExportAll()` publishes the same value
        // this pass judged the ledger against.
        func verdict(_ result: ReceiptIntegrityVerificationResult) -> (
            result: ReceiptIntegrityVerificationResult,
            ledgerHighWaterMark: Int?
        ) {
            (result, ledgerHighWaterMark)
        }

        for receipt in receipts {
            guard receipt.hasCompleteIntegrityMetadata else {
                return verdict(.invalid("Receipt \(receipt.id.uuidString) is missing integrity metadata."))
            }

            // The stored column is what every grouping and every Keychain anchor key uses, and it is
            // the one grouping input not inside the hashed envelope — so it is checked against the
            // column that is. `accountKey` is a pure function of `accountAddress`, which the chain
            // hash commits to, so a row where they disagree has had the column edited: that gives it
            // no power to forge anything, but it can move a row onto another account's chain, and
            // silently accepting it would make the grouping the one part of the row nobody verifies.
            let accountKey = receipt.accountKey
            guard accountKey == receipt.derivedAccountKey else {
                return verdict(.invalid("Receipt \(receipt.id.uuidString) has an invalid account key."))
            }

            // The parent column is checked against its own canonical form for the same reason
            // `accountKey` is checked against its derivation: the envelope commits to the *string*,
            // while the claim the string makes is a list, and the two can be made to disagree.
            //
            // A non-canonical spelling of the same IDs — lowercased, reordered separators, a trailing
            // comma — changes nothing a reader sees, so without this it would be the one part of the
            // provenance nobody verifies. An unparseable column is caught by the same guard, since
            // `isCanonical` is false for anything `parse` rejects.
            //
            // `.tampered`, not unattested: no writer can produce either shape. `canonicalRawValue` is
            // the only thing that ever writes this column, and it emits uppercase UUIDs joined by
            // commas or nothing at all.
            guard ReceiptContributionParents.isCanonical(receipt.parentReceiptIDsRawValue) else {
                return verdict(
                    .invalid("Receipt \(receipt.id.uuidString) has a non-canonical parent receipt list.")
                )
            }
            // The two row-local halves of the parent contract. Duplicates and self-reference are both
            // refused at append time, so a row carrying either has had the column rewritten.
            let declaredParents = receipt.parentReceiptIDs ?? []
            let parentProblems = ReceiptContributionParents.problems(
                declaredParents,
                receiptID: receipt.id
            )
            guard parentProblems.isEmpty else {
                return verdict(
                    .invalid(
                        "Receipt \(receipt.id.uuidString) has an invalid parent receipt list: \(parentProblems.joined(separator: " "))"
                    )
                )
            }
            // The third half — existence — is **unattested rather than tampered**, and that asymmetry
            // is deliberate.
            //
            // Append refuses a parent that is not already in the ledger, so every row was written with
            // its parents present. A parent can stop being present afterwards without anybody altering
            // this row, though: the same ordinary events that leave a sequence hole do it, and
            // `resetAll()` on a store some other process exported from does it too. Branding the ledger
            // altered for a row that is itself intact is the mistake
            // ``ReceiptIntegrity/sequenceGapReasons(sequenceIDs:)`` is careful not to make, and it
            // would cost the person their export.
            for missingParent in declaredParents where presentReceiptIDs.contains(missingParent) == false {
                unattestedReasons.append(
                    "Receipt \(receipt.id.uuidString) names parent receipt \(missingParent.uuidString), which is no longer in this ledger."
                )
            }

            // Before anything trusts this row's `chainHash`, including the signature check.
            guard chainHashUniqueness.record(receipt.chainHash) else {
                return verdict(.invalid(ReceiptChainHashUniqueness.violation(receiptID: receipt.id)))
            }
            let previousReceipt = previousByAccount[accountKey]
            // Overflow-reporting rather than `+ 1`. Today the fetch sorts `accountSequenceID`
            // ascending, so a row at `Int.max` is reached last and its successor never exists — which
            // is why this cannot trap *at present*, and is far too subtle a thing to leave a verdict
            // resting on. An overflow means the predecessor's column is out of range, which is the
            // same invalid sequence this guard already reports.
            let (expectedAccountSequenceID, expectedOverflowed) =
                (previousReceipt?.accountSequenceID ?? 0).addingReportingOverflow(1)
            guard !expectedOverflowed, receipt.accountSequenceID == expectedAccountSequenceID else {
                return verdict(.invalid("Receipt \(receipt.id.uuidString) has an invalid account sequence."))
            }

            let expectedPreviousHash = previousReceipt?.chainHash ?? ReceiptIntegrity.genesisHash
            guard receipt.previousReceiptHash == expectedPreviousHash else {
                return verdict(.invalid("Receipt \(receipt.id.uuidString) has an invalid previous hash."))
            }

            // A payload that will not decode is a *verdict*, and an **unattested** one.
            //
            // `detailsData` is `@Attribute(.externalStorage)`, so the blob can be pruned or lost with
            // no adversary involved — storage pressure and a partially-restored container both do it.
            // That is the same "rows are gone, but not *why*" shape that
            // ``ReceiptIntegrity/sequenceGapReasons(sequenceIDs:)`` already refuses to call tampering,
            // for the reason written there.
            //
            // Two earlier spellings were both wrong, in opposite directions. Letting `DecodingError`
            // escape meant `exportAll()` threw a raw decoding error instead of
            // `ReceiptProvenanceExportError.integrityFailure`, so a caller matching the documented
            // type saw nothing. Replacing it with `.invalid` fixed the error type and kept the real
            // damage: `.invalid` *is* `.tampered`, so one lost blob branded the whole ledger altered,
            // `isValid` refused the export permanently, and `resetAll()` — destroying the history —
            // was the only exit. That is F-39 and F-40's failure mode reached by an ordinary event,
            // and the display path had already settled the question the other way: see
            // ``StoredReceipt/unavailablePayloadKey``, which exists so a lost blob reads as
            // "unavailable" rather than "recorded nothing".
            //
            // So: skip only the payload-hash comparison, the one check that needs the decoded bytes,
            // and let every other check run on this row. The chain hash commits to the `payloadHash`
            // *column* rather than to the payload (see ``SwiftDataReceiptStore/chainHash(for:)``), so
            // linkage, the signature, the sequence and the anchors are all still fully verified here.
            // A payload that decodes but does *not* match its column is a different claim and stays
            // `.tampered` below: that is substitution, not loss.
            let decodedDetails: ReceiptPayload?
            do {
                decodedDetails = try receipt.decodedDetails()
            } catch {
                decodedDetails = nil
                unattestedReasons.append(
                    "Receipt \(receipt.id.uuidString) has an unreadable payload, so its contents cannot be confirmed against the recorded payload hash."
                )
            }

            // Both hashes are computed inside a `do`, and that is the same argument as the decode
            // above rather than defensive noise. A column can be *unencodable* as well as
            // unreadable: `createdAt` and `authorityExpiresAt` reach the canonical encoder as
            // doubles, which rejects non-finite values, so writing
            // `Date(timeIntervalSince1970: .infinity)` into one row made these plain `try`s throw
            // straight out of the integrity check — no verdict at all, and an `exportAll()` that
            // failed with a raw `EncodingError` instead of `ReceiptProvenanceExportError`. One
            // column was therefore a permanent denial of the whole audit trail, escapable only by
            // `resetAll()`. A row whose columns have no canonical form is exactly what tampering
            // looks like, so it gets a verdict like every other damaged row.
            let expectedPayloadHash: String?
            let expectedChainHash: String?
            do {
                // `nil` only when the blob above would not decode. A payload that is present is
                // always hashed, so this cannot silently skip the comparison on a readable row.
                expectedPayloadHash = try decodedDetails.map(ReceiptIntegrity.payloadHash(for:))
                // Derived from the row's own stored columns — including the raw mode/actor strings, so
                // a value this build has no case for is not mistaken for a corrupted hash.
                //
                // `nil` when the row declares an envelope this build has never heard of: a newer
                // build's envelope covers fields that do not exist here, so recomputing it would
                // produce a mismatch and report a *downgrade* as an altered ledger — the same
                // mistake hashing the typed `mode` once made, one level up. See the unattested note
                // below for why this is not a bypass.
                expectedChainHash = try ReceiptIntegrity.chainHash(forVerifiable: receipt)
            } catch {
                return verdict(
                    .invalid(
                        "Receipt \(receipt.id.uuidString) has integrity columns that cannot be canonically encoded: \(error.localizedDescription)"
                    )
                )
            }
            // Skipped rather than defaulted when the payload could not be read. The unattested reason
            // recorded above is what says this leg went unchecked; letting the `guard` run against a
            // stand-in hash would either fail an honest row or count an unchecked one as a pass.
            if let expectedPayloadHash {
                guard receipt.payloadHash == expectedPayloadHash else {
                    return verdict(.invalid("Receipt \(receipt.id.uuidString) has an invalid payload hash."))
                }
            }
            if let expectedChainHash {
                guard receipt.chainHash == expectedChainHash else {
                    return verdict(.invalid("Receipt \(receipt.id.uuidString) has an invalid chain hash."))
                }
                // Recorded only here, past the hash match, so the mark heal below can never advance
                // the durable mark off a `sequenceID` that nothing verified.
                highestVerifiedSequenceID = max(highestVerifiedSequenceID ?? receipt.sequenceID, receipt.sequenceID)
            } else {
                // A row this build cannot recompute. Whether that is a downgrade or a forgery cannot
                // be decided from the row — the version column is what disabled the recomputation, so
                // letting it also license the concession was circular — and it cannot be decided here
                // at all, because it depends on `currentIdentitySeen`, which is still being built.
                // Collected now, judged after the loop by ``unrecomputableRowVerdict(_:floor:)``.
                unrecomputableRows.append(
                    (receiptID: receipt.id, envelopeVersion: receipt.integrityEnvelopeVersion)
                )
                unattestedReasons.append(
                    "Receipt \(receipt.id.uuidString) was written with integrity envelope version \(receipt.integrityEnvelopeVersion), which this build cannot recompute."
                )
            }

            // Through ``ReceiptSigningProgression``, which is the same evaluator
            // ``ReceiptProvenanceVerifier`` applies to an archive — including the signature check
            // against the row's own recorded key, which is sound because that key is inside the chain
            // hash verified just above and so cannot have been substituted without failing it.
            //
            // The reference identity is this device's current signing key. When it is `nil` the
            // device cannot read its own identity, and every row comes back `.otherIdentity`; the
            // note appended below would then be a lie, which is why `hasSignerIdentity` gets its own
            // headline reason after the loop rather than being left to per-row wording.
            switch ReceiptSigningProgression.evaluate(
                receiptID: receipt.id,
                chainHash: receipt.chainHash,
                signature: receipt.signature,
                signerPublicKey: receipt.signerPublicKey,
                referenceKey: currentSignerPublicKey,
                hasSeenReferenceIdentity: currentIdentitySeen.contains(accountKey)
            ) {
            case .unsignedPrefix:
                signingOrdering.recordUnsigned(receiptID: receipt.id, sequenceID: receipt.sequenceID)
                unattestedReasons.append("Receipt \(receipt.id.uuidString) predates receipt signing.")
            case .referenceIdentity:
                signingOrdering.recordSigned(receiptID: receipt.id, sequenceID: receipt.sequenceID)
                currentIdentitySeen.insert(accountKey)
            case .otherIdentity:
                signingOrdering.recordSigned(receiptID: receipt.id, sequenceID: receipt.sequenceID)
                unattestedReasons.append(
                    "Receipt \(receipt.id.uuidString) was signed by a previous device identity."
                )
            case let .violation(reason):
                return verdict(.invalid(reason))
            }

            // Recorded after every structural check on this row has passed, so the witness comparison
            // never reasons about a row the pass has already rejected.
            chainHashesByAccountSequence[
                ReceiptWitnessRowKey(accountKey: accountKey, accountSequenceID: receipt.accountSequenceID)
            ] = receipt.chainHash
            tipSequenceByAccount[accountKey] = max(
                tipSequenceByAccount[accountKey] ?? receipt.accountSequenceID,
                receipt.accountSequenceID
            )

            previousByAccount[accountKey] = receipt
        }

        // The per-account rule above completed by the ledger-wide one. Checked here rather than inside
        // the loop because it is a statement about the whole ledger: `sequenceID` is allocated
        // globally and monotonically and an append that cannot sign does not write, so an unsigned row
        // above a signed one has no honest explanation. ``ReceiptSigningLedgerOrdering`` carries the
        // argument and the residual.
        if let orderingViolation = signingOrdering.violation {
            return verdict(.invalid(orderingViolation))
        }

        // **The external witness**, and the only check in this pass whose evidence the local attacker
        // could not have written. See ``ReceiptLedgerWitnessing`` for why nothing above it could
        // deliver these properties, and ``ReceiptWitnessComparison`` for the rules.
        //
        // Placed after the local rules so a ledger that is locally broken is reported as locally
        // broken — those messages name a receipt and a reason a person can act on, whereas "the
        // witness disagrees" is the right thing to say only once the rows are internally consistent.
        //
        // Three outcomes, and keeping them apart is the point:
        // - the witness answers and **contradicts** the ledger → `.tampered`, full stop. This is the
        //   one place suffix truncation and whole-account deletion become verdicts rather than
        //   suggestions.
        // - the witness answers and agrees, or has no record yet → nothing to say.
        // - the witness **cannot be reached** → an advisory, never a verdict. A first run, an offline
        //   device, a signed-out iCloud account and a service outage all land here and none of them is
        //   evidence about the receipts.
        var witnessAdvisory: String?
        do {
            if let witnessed = try await witness.latestCheckpoint() {
                let localLedger = ReceiptWitnessComparison.LocalLedger(
                    highestVerifiedSequenceID: highestVerifiedSequenceID ?? 0,
                    chainHashesByAccountSequence: chainHashesByAccountSequence,
                    tipSequenceByAccount: tipSequenceByAccount
                )
                if let contradiction = ReceiptWitnessComparison.contradiction(
                    local: localLedger,
                    witnessed: witnessed
                ) {
                    return verdict(.invalid(contradiction))
                }
            } else if !receipts.isEmpty {
                // The witness exists and has never been told about this ledger. Worth saying on a
                // ledger that has rows — it means the publish path has never once succeeded — and
                // worth *not* saying on an empty one, where there is nothing to witness.
                witnessAdvisory = ReceiptWitnessComparison.unwitnessedAdvisory(
                    reason: "it has never been recorded with the witness"
                )
            }
        } catch ReceiptLedgerWitnessError.notConfigured {
            // Logged, never surfaced — the same line the package already draws for a high-water mark
            // this device cannot read. "No witness is configured" is a fact about the *build*, identical
            // for every ledger in it, so putting it in this person's trust advisory tells them nothing
            // actionable about their own receipts while crowding out the mark's specific observation.
            // A witness that exists and cannot be reached is a different claim and does get surfaced.
            Self.logger.debug("No external receipt-ledger witness is configured; skipping the witness check.")
        } catch {
            witnessAdvisory = ReceiptWitnessComparison.unwitnessedAdvisory(
                reason: error.localizedDescription
            )
        }

        // Now that `currentIdentitySeen` is final, the rows this build could not recompute can be
        // judged. See ``unrecomputableRowVerdict(_:floor:thisDeviceWroteSomeRow:)``.
        if let unrecomputableViolation = Self.unrecomputableRowVerdict(
            unrecomputableRows,
            floor: highestRecordedEnvelopeVersion,
            thisDeviceWroteSomeRow: !currentIdentitySeen.isEmpty
        ) {
            return verdict(.invalid(unrecomputableViolation))
        }

        // Said once, up front, when the device cannot read its own signing identity.
        //
        // Without this the per-row notes above claim every row "was signed by a previous device
        // identity" — because `publicKeyData == nil` is never true, so the comparison always falls
        // to `.otherIdentity`. The truth is that this device cannot say who signed them, which is a
        // different statement and the one a person needs; `hasSignerIdentity` was computed for
        // exactly this distinction and was only ever consulted in the missing-anchor branch.
        if !receipts.isEmpty, !hasSignerIdentity {
            unattestedReasons.insert(
                "This device cannot produce its signing identity, so it cannot say which receipts it wrote.",
                at: 0
            )
        }

        let sequenceIDs = receipts.map(\.sequenceID)
        // The row-derived half only: duplicates and interior holes, both visible in a single fetch
        // with no durable state outside the row store. That is why this half is allowed to move the
        // verdict — there is nothing here an attacker could delete or roll back independently of the
        // rows themselves.
        //
        // Inserted at the front, not appended. These are statements about the *ledger* — receipts are
        // missing, or a sequence number was issued twice — while everything already in the list is a
        // per-row note. ``ReceiptUnattestedSummary`` keeps only the first reason and a count, so
        // appending buried the strongest evidence available behind an upgraded install's hundreds of
        // "predates receipt signing" lines, where nobody would ever read it.
        unattestedReasons.insert(
            contentsOf: ReceiptIntegrity.sequenceGapReasons(sequenceIDs: sequenceIDs),
            at: 0
        )

        // The mark-derived half is computed here and then kept **out** of `unattestedReasons`.
        //
        // It is the only thing that can see a deleted suffix, and it is also the weakest evidence in
        // this file: an unauthenticated Keychain item that anyone able to write the Keychain can lower
        // to agree with the rows they left, and whose *absence* says nothing either (a restored device
        // has no `ThisDeviceOnly` state at all). Gating on it was wrong in both directions — its
        // absence downgraded honest restored and pre-mark ledgers, and its presence advertised a
        // guarantee that dissolved against the attacker it was drawn against.
        //
        // So it is reported as an advisory a person or a log can act on, and the verdict is decided
        // without it. `ReceiptIntegrity.completenessAdvisory(…)` carries the full argument; the
        // consequence to be clear-eyed about is that a *sequential* whole-account deletion now reads
        // `.verified` with this note attached, rather than `.unattested`.
        let markAdvisory = ReceiptIntegrity.completenessAdvisory(
            sequenceIDs: sequenceIDs,
            highWaterMark: ledgerHighWaterMark,
            // Only where this device demonstrably wrote part of the chain. `currentIdentitySeen` is
            // the same test the missing-anchor branch below uses: a restored store legitimately has
            // neither anchors nor a mark, and an empty ledger says nothing either way.
            completenessUnconfirmed: !receipts.isEmpty
                && !currentIdentitySeen.isEmpty
                && ledgerHighWaterMark == nil
        )
        // The mark's observation and the witness's, folded into the one advisory field every exit
        // already carries. Merged here — before any of the three attachment sites — so adding the
        // witness could not reintroduce the bug where one early exit silently dropped the note.
        //
        // Both halves are advisory for the same reason and neither can become a verdict: the mark is
        // an unauthenticated local item, and an *unreachable* witness is a statement about the network
        // rather than the receipts. A witness that answers and disagrees never reaches here — it
        // returned `.tampered` above.
        let completenessAdvisory = [markAdvisory, witnessAdvisory]
            .compactMap { $0 }
            .joined(separator: " ")
            .nilWhenEmpty
        if let highWaterMarkReadFailure {
            // Logged rather than surfaced: it is a diagnostic about this device, not a statement
            // about the ledger, and the advisory above already says completeness is unconfirmed.
            Self.logger.error(
                "Receipt ledger high-water mark could not be read: \(highWaterMarkReadFailure, privacy: .public)"
            )
        }

        // Through ``latestHeadRows(from:)`` — the same selection ``performExportAll()`` publishes as
        // its chain heads — rather than reusing the loop's `previousByAccount`.
        //
        // The two agreed, but only by coincidence: this loop takes the last row of a key-ordered
        // fetch while that one takes the max by `(accountSequenceID, sequenceID)` behind a
        // `hasCompleteIntegrityMetadata` filter, and they line up only because the loop has already
        // rejected every incomplete row. A divergence would have surfaced at the worst place
        // available — `ReceiptProvenanceVerifier` reporting "the exported chain heads do not match
        // the receipt sequences" on an archive that was written correctly. One function, one answer.
        let persistedHeadRows = latestHeadRows(from: receipts)
        let persistedHeads = persistedHeadRows.mapValues(\.chainHash)
        let protectedHeads: [String: String]
        do {
            protectedHeads = try await integrityHeadStore.loadAllHeads()
        } catch {
            // Tolerated for exactly the reason the identity read above is, and it has to be: both hit
            // the same Keychain. Reading the anchors with a plain `try` meant the locked-device case
            // that the `try?` exists for threw *here* instead and unwound the whole call —
            // `exportAll()` failed with a raw `ReceiptIntegrityHeadStoreError` rather than
            // `ReceiptProvenanceExportError.integrityFailure`, so a caller matching the documented
            // type saw nothing and the person got an opaque failure. It also made the graceful
            // `.unattested` path below unreachable whenever the cause was a locked Keychain rather
            // than a test double.
            //
            // Unattested, not tampered: every row above has already passed its chain, payload, and
            // signature checks. What is missing is this device's ability to read its own anchors,
            // which says nothing about whether the rows were altered.
            //
            // Listed first so it is the headline rather than a hidden entry in the "and N more" tail.
            //
            // Carries the advisory like the two settled exits below do. Omitting it here was worse
            // than an inconsistency: the condition most likely to produce an unreadable anchor is a
            // locked `ThisDeviceOnly` Keychain, which takes the mark read down with it — so the one
            // exit that dropped the note was the one reached precisely when the note ("this ledger
            // carries no high-water mark") is true and most worth saying.
            return verdict(
                .unattested(
                    ReceiptUnattestedSummary.summarize(
                        ["This device cannot read its integrity anchors: \(error.localizedDescription)"]
                            + unattestedReasons
                    )
                )
                .withCompletenessAdvisory(completenessAdvisory)
            )
        }
        let persistedHeadKeys = Set(persistedHeads.keys)
        let protectedHeadKeys = Set(protectedHeads.keys)
        let protectedOnlyKeys = protectedHeadKeys.subtracting(persistedHeadKeys)
        guard protectedOnlyKeys.isEmpty else {
            return verdict(.invalid("Receipt integrity has protected heads without persisted receipts."))
        }

        // Anchor checking is per account, not all-or-nothing. A restored install brings the SwiftData
        // store back without the `ThisDeviceOnly` Keychain anchors, and the moment it writes one new
        // receipt it has an anchor for *that* account and none for the rest — so a global "are any
        // anchors missing" test would brand the whole restored ledger tampered on the first write.
        //
        // The distinction is whether this device wrote the chain. `currentIdentitySeen` implies it
        // did, and the forward-only rule above means the account's head row is current-identity
        // signed, so a missing anchor there is a real inconsistency. An account this device never
        // wrote is simply not attestable from here.
        var anchorsToHeal: [String: String] = [:]
        for (accountKey, chainHash) in persistedHeads {
            if let protectedHead = protectedHeads[accountKey] {
                if protectedHead == chainHash {
                    continue
                }
                // The append path saves the row and *then* writes the anchor, so a crash between
                // those two steps leaves the anchor exactly one row behind — and demanding strict
                // equality called that tampering. It is not: the tip row has already passed the
                // chain, payload, and signature checks above, and the branch below additionally
                // requires it to be signed by *this device's current identity*, which nobody but this
                // device can produce. Anyone who could forge that signature already holds the signing
                // key and does not need this window.
                //
                // Deliberately only one row behind, and only that. Accepting any ancestor would let
                // an attacker append an unbounded run of forged rows past a stale anchor.
                let tipRow = persistedHeadRows[accountKey]
                let isOneRowBehind = tipRow?.previousReceiptHash == protectedHead
                let isKnownCrashWindow = isOneRowBehind && currentIdentitySeen.contains(accountKey)
                guard isKnownCrashWindow else {
                    // One row behind but *not* current-identity signed. The rows have passed every
                    // structural check and the anchor still names the tip's own parent; what is
                    // missing is this device's ability to confirm it wrote them, which is the
                    // definition of unattested rather than tampered.
                    //
                    // This deliberately does not also require `!hasSignerIdentity`. That conjunct
                    // rested on "`currentIdentitySeen` is empty only when the signer could not
                    // produce a key at all — a locked Keychain, most likely", and that premise is
                    // false: the set is also empty when the signer works fine but no row was signed
                    // by *that* key, which is precisely what this package's own key rotation
                    // produces (``DeviceReceiptSigner.secureEnclaveSigner()``). A device that
                    // crashed in the append window and then rotated its identity — the anchors live
                    // under a different Keychain service and survive untouched — read as
                    // `.tampered`, durably, for any account that never receives another receipt.
                    // That is the exact outcome the healing below exists to prevent, reached from
                    // the other direction.
                    //
                    // The cost, stated rather than glossed: this accepts an attacker who appends
                    // exactly one forged row onto a chain with no current-identity rows. That buys
                    // them nothing new — anyone who can write both the store and the Keychain can
                    // already rewrite the whole ledger and land on `.unattested`, which
                    // ``isValid`` accepts by design (see ``ReceiptIntegrityVerificationResult``).
                    // More than one row behind is still tampering, which is what bounds the window.
                    guard isOneRowBehind else {
                        return verdict(.invalid("Receipt chain head mismatch for \(accountKey)."))
                    }
                    unattestedReasons.append(
                        "A trusted integrity anchor for \(accountKey) is one receipt behind, and this device cannot confirm it wrote the newer receipt."
                    )
                    continue
                }
                anchorsToHeal[accountKey] = chainHash
            } else if currentIdentitySeen.contains(accountKey) {
                // No anchor at all for a chain this device wrote. That is a real inconsistency for
                // every account except one: the account whose *first* receipt is still its only one.
                //
                // `performAppend` saves the row and then writes the anchor, so a crash in that window
                // leaves no anchor whatsoever when the row being written is the account's genesis —
                // there was no earlier append to leave one behind. The one-row-behind branch above
                // handles the same crash at `accountSequenceID >= 2` and heals it; landing here
                // instead meant the *first* receipt on a new wallet was the one case where an
                // interrupted append produced `.tampered`, for the whole ledger (the verdict is not
                // per account) and permanently, unless that account happened to receive another
                // receipt. `ReceiptPersistenceConsistencyError.appendCompensationFailed` reaches the
                // identical state without any crash at all.
                //
                // Bounded to `accountSequenceID == 1` for the reason the other window is bounded to
                // one row: at sequence 2 or beyond, the previous append would have written an anchor,
                // so its absence has no innocent explanation. And an absent anchor — as opposed to a
                // stale one — already requires Keychain delete access, which per
                // ``ReceiptIntegrityVerificationResult/isValid`` is enough to rewrite the entire
                // ledger into `.unattested` anyway. Healing here concedes nothing that is not
                // already conceded.
                guard persistedHeadRows[accountKey]?.accountSequenceID == 1 else {
                    return verdict(
                        .invalid("Receipt integrity has persisted receipts without protected heads.")
                    )
                }
                anchorsToHeal[accountKey] = chainHash
            } else if !hasSignerIdentity {
                unattestedReasons.append(
                    "No local integrity anchor exists for \(accountKey), and this device cannot produce its signing identity to say whether it wrote the chain."
                )
            } else {
                unattestedReasons.append("No local integrity anchor exists for \(accountKey).")
            }
        }

        // Advanced here rather than left for the next append. The next append to *this* account would
        // fix it, but an account that never receives another receipt — a wallet the person stopped
        // using — would read as tampered permanently, which is the case that mattered.
        //
        // A failure to heal is not a verdict: the rows are intact and the anchor still names a real
        // ancestor, so the ledger is exactly as trustworthy as it was a line ago. Reported as
        // unattested so the state is visible rather than silently carried.
        if !anchorsToHeal.isEmpty {
            do {
                // The unlocked half: this already runs inside the ledger lock, and
                // `restoreHeads(_:)` would acquire it again and wait on itself forever.
                try await performRestoreHeads(anchorsToHeal)
            } catch {
                unattestedReasons.append(
                    "A trusted integrity anchor is one receipt behind and could not be advanced: \(error.localizedDescription)"
                )
            }
        }

        // A mark *behind* the rows is the append path's own crash window — it commits the row and its
        // anchor before raising the mark — so it is advanced here for the reason the anchors are:
        // otherwise a ledger that stops receiving receipts carries the discrepancy forever.
        //
        // **`if let mark`, not `mark ?? 0`, and that distinction is the whole correctness of this
        // block.** Treating an absent mark as zero made this fire on the absent case too, writing a
        // mark derived from the rows now on disk — which is precisely what the note above says must
        // never happen. It laundered the deletion: a truncated ledger reported `.unattested` once,
        // this heal minted a mark agreeing with the survivors, and every later pass read `.verified`
        // with `isFullyAttested == true`. Worse, `performExportAll()` publishes the value this
        // function returns, so the manufactured mark reached the signed archive on the *first* pass —
        // a third party was told a ledger missing half its history was complete.
        //
        // An absent mark converges the honest way instead: the next real append raises it from the
        // sequence it actually allocated. Until then completeness is reported as unconfirmed, above.
        //
        // Only ever upward. Lowering the mark would destroy the only evidence a deletion cannot
        // reach, so this heal is structurally incapable of it and `saveLedgerHighWaterMark(_:)`
        // refuses a lower value too. A mark *ahead* of the rows is never healed at all, because that
        // is the deletion this whole mechanism exists to report.
        // **Only over rows whose chain hash this build actually recomputed and matched**, which is
        // `highestVerifiedSequenceID` rather than `sequenceIDs.max()`.
        //
        // This is a durable, monotonic, irreversible write into the trusted store, derived from a
        // column — and for an unrecomputable row that column is not covered by anything. With
        // `sequenceIDs.max()` an attacker holding row-store writes alone could set one conceded row's
        // `sequenceID` to an arbitrary number and have this heal *write it to the Keychain*. Measured
        // in the restore-concession state (no floor, nothing attestable): `sequenceID = 500_000`
        // raised the mark to 500000, permanently, and every later pass then reported "the receipt
        // ledger is missing 499998 of 500000 receipts written on this device". `saveLedgerHighWaterMark`
        // refuses to lower it, so there is no way back except `resetAll()` — destroying the history.
        // Not a forgery, but a durable false accusation against an honest ledger with deletion as the
        // only recovery, which is the exact outcome the `Status` trichotomy exists to prevent.
        //
        // Restricting it to verified rows costs nothing legitimate: the window this heal exists for is
        // an append that committed its row and anchor but not its mark, and such a row is by
        // construction recomputable and signed.
        if let mark = ledgerHighWaterMark, let highestOnDisk = highestVerifiedSequenceID, highestOnDisk > mark {
            do {
                try await integrityHeadStore.saveLedgerHighWaterMark(highestOnDisk)
                ledgerHighWaterMark = highestOnDisk
            } catch {
                // Not a verdict, exactly like a failed anchor heal: the rows are intact and the mark
                // still names a real earlier state of this ledger.
                Self.logger.error(
                    "Receipt ledger high-water mark could not be advanced to \(highestOnDisk, privacy: .public) during verification: \(error.localizedDescription, privacy: .public)"
                )
            }
        }

        // The advisory is attached only here, after the verdict is settled, so it cannot influence it.
        guard unattestedReasons.isEmpty else {
            return verdict(
                .unattested(ReceiptUnattestedSummary.summarize(unattestedReasons))
                    .withCompletenessAdvisory(completenessAdvisory)
            )
        }
        return verdict(ReceiptIntegrityVerificationResult.valid.withCompletenessAdvisory(completenessAdvisory))
    }
}
