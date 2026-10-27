import Foundation
import ReceiptsCore
@testable import ReceiptStorage
import AuralisRuntime
import SwiftData
import Testing

/// What the hashed envelope actually covers, asserted column by column, plus the two ways a single
/// row could take the whole integrity check down with it.
///
/// The gap these close is narrow and was exploitable: a persisted column that no check reads is a
/// column an attacker may rewrite while the ledger vouches for itself. Two existed — the receipt's
/// own `id`, and five of the six authority columns on any row that had no recorded authority.
@MainActor
struct ReceiptEnvelopeCoverageTests {
    private static let accountA = "0x1111111111111111111111111111111111111111"

    // MARK: - The receipt id

    /// The id was the one persisted column neither hashed nor derivable from something hashed.
    ///
    /// Not academic: the id is a cross-store foreign key — `StoredArtifact.relatedReceiptIDs` and the
    /// trusted-UI registry's `reviewReceipt(receiptID)` both resolve through it — so repointing it
    /// changes which action an artifact's provenance link claims to be backed by, while the audit log
    /// reports `.verified`.
    @Test("rewriting a receipt id is tampering")
    func rewrittenReceiptIDIsTampering() async throws {
        let context = try makeContext()
        let store = try makeStore(context: context)

        _ = try await store.append(draft(kind: "approve"))
        let row = try #require(try context.fetch(FetchDescriptor<StoredReceipt>()).first)
        row.id = UUID()
        try context.save()

        let result = try await store.verifyIntegrity()
        #expect(result.status == .tampered, "\(result.failureReason ?? "-")")
        #expect(result.failureReason?.contains("invalid chain hash") == true)
    }

    /// Permuting ids among rows, which keeps `@Attribute(.unique)` satisfied and every id a real one —
    /// the version an attacker would actually use, and the one the original probe demonstrated
    /// reading as `.verified` with `isFullyAttested == true`.
    @Test("swapping two receipt ids is tampering")
    func swappedReceiptIDsAreTampering() async throws {
        let context = try makeContext()
        let store = try makeStore(context: context)

        let first = try await store.append(draft(kind: "approve-1-eth"))
        let second = try await store.append(draft(kind: "approve-1000-eth"))

        let rows = try context.fetch(
            FetchDescriptor<StoredReceipt>(sortBy: [SortDescriptor(\StoredReceipt.sequenceID)])
        )
        // Through a placeholder, because the unique constraint forbids the two colliding mid-swap.
        let placeholder = UUID()
        rows[0].id = placeholder
        try context.save()
        rows[1].id = first.id
        try context.save()
        rows[0].id = second.id
        try context.save()

        let result = try await store.verifyIntegrity()
        #expect(result.status == .tampered, "\(result.failureReason ?? "-")")
    }

    /// The same mutation at the archive boundary, since `.unattested` satisfies `isValid` and a
    /// locally-refused export is not the only way a record set reaches a third party.
    @Test("an exported record whose id was rewritten does not verify")
    func rewrittenExportedIDDoesNotVerify() async throws {
        let context = try makeContext()
        let store = try makeStore(context: context)
        _ = try await store.append(draft(kind: "approve"))

        let data = try await store.exportAll()
        let original = try ReceiptCanonicalJSON.decoder().decode(ReceiptProvenanceExport.self, from: data)

        // Rebuilt around one repointed id, with the manifest re-derived and re-signed so the record
        // set still matches its own hash — otherwise this would fire on the manifest instead.
        let repointed = replacingID(on: original.records[0], with: UUID())
        let (export, fingerprint) = try await rebuiltExport(records: [repointed], like: original)

        let result = try ReceiptProvenanceVerifier.verify(
            try ReceiptCanonicalJSON.encoder().encode(export),
            trustedSignerFingerprint: fingerprint
        )
        #expect(result.status == .tampered, "\(result.failureReason ?? "-")")
        #expect(result.failureReason?.contains("invalid exported integrity metadata") == true)
    }

    // MARK: - Authority columns on a row with no authority

    /// Five of the six authority columns were outside the hash whenever `authoritySourceRawValue` was
    /// `nil`, because the envelope took a `ReceiptAuthorityDetail?` and the row reconstructs one only
    /// when that column is present. `nil` authority is a documented, common answer — the draft type
    /// says so explicitly — so this was reachable on ordinary receipts.
    ///
    /// The existing authority tamper test only mutates columns on a row that *has* an authority,
    /// which is why this survived a suite that is otherwise deliberate about exactly this.
    @Test("each authority column is hashed on a row with no recorded authority")
    func authorityColumnsAreHashedWithoutASource() async throws {
        let context = try makeContext()
        let store = try makeStore(context: context)

        _ = try await store.append(draft(kind: "read-only"))
        let row = try #require(try context.fetch(FetchDescriptor<StoredReceipt>()).first)
        #expect(row.authoritySourceRawValue == nil, "the fixture must have no recorded authority")
        #expect(row.authorityDetail == nil)

        let baseline = try ReceiptIntegrity.chainHash(for: row)

        row.authorityLeaseID = "lease-forged"
        #expect(try ReceiptIntegrity.chainHash(for: row) != baseline, "authority lease id is unhashed")
        row.authorityLeaseID = nil

        row.authorityCapabilityRawValue = "wallet.spend"
        #expect(try ReceiptIntegrity.chainHash(for: row) != baseline, "authority capability is unhashed")
        row.authorityCapabilityRawValue = nil

        row.authorityScopeRawValue = "unlimited"
        #expect(try ReceiptIntegrity.chainHash(for: row) != baseline, "authority scope is unhashed")
        row.authorityScopeRawValue = nil

        row.authorityReason = "the user asked for this"
        #expect(try ReceiptIntegrity.chainHash(for: row) != baseline, "authority reason is unhashed")
        row.authorityReason = nil

        row.authorityExpiresAt = Date(timeIntervalSince1970: 9_000)
        #expect(try ReceiptIntegrity.chainHash(for: row) != baseline, "authority expiry is unhashed")
        row.authorityExpiresAt = nil

        #expect(try ReceiptIntegrity.chainHash(for: row) == baseline, "restoring the columns changed the hash")
    }

    /// The actor columns had the identical shape, gated on `actorKindRawValue`. Unreachable through
    /// the append path today because the draft requires a detail, but the gate was the same one and
    /// a legacy row has no kind.
    @Test("each actor column is hashed on a row with no recorded kind")
    func actorColumnsAreHashedWithoutAKind() async throws {
        let context = try makeContext()
        let store = try makeStore(context: context)

        _ = try await store.append(draft(kind: "read-only"))
        let row = try #require(try context.fetch(FetchDescriptor<StoredReceipt>()).first)
        // The legacy shape: a row written before the structured actor column existed.
        row.actorKindRawValue = nil
        row.actorIdentifier = nil
        row.actorDisplayName = nil
        row.actorInferenceLocalityRawValue = nil
        row.actorInferenceProvider = nil
        row.actorInferenceModelClass = nil
        #expect(row.actorDetail == nil)

        let baseline = try ReceiptIntegrity.chainHash(for: row)

        row.actorIdentifier = "operator-forged"
        #expect(try ReceiptIntegrity.chainHash(for: row) != baseline, "actor identifier is unhashed")
        row.actorIdentifier = nil

        row.actorDisplayName = "Someone Else"
        #expect(try ReceiptIntegrity.chainHash(for: row) != baseline, "actor display name is unhashed")
        row.actorDisplayName = nil

        row.actorInferenceLocalityRawValue = "local"
        #expect(try ReceiptIntegrity.chainHash(for: row) != baseline, "inference locality is unhashed")
        row.actorInferenceLocalityRawValue = nil

        row.actorInferenceProvider = "nobody"
        #expect(try ReceiptIntegrity.chainHash(for: row) != baseline, "inference provider is unhashed")
        row.actorInferenceProvider = nil

        row.actorInferenceModelClass = "frontier"
        #expect(try ReceiptIntegrity.chainHash(for: row) != baseline, "inference model class is unhashed")
        row.actorInferenceModelClass = nil

        #expect(try ReceiptIntegrity.chainHash(for: row) == baseline)
    }

    /// The fix must not have rehashed anything: a row with no authority and no actor detail has to
    /// hash exactly as it did when the envelope took the optional structs, or every receipt already
    /// on disk reads as tampered.
    @Test("all-nil attribution columns hash identically to an absent detail")
    func allNilColumnsMatchAnAbsentDetail() throws {
        let columnsForm = try ReceiptIntegrity.chainHash(
            receiptID: Self.fixedID,
            envelopeVersion: ReceiptIntegrityEnvelopeVersion.legacy,
            sequenceID: 1,
            accountSequenceID: 1,
            createdAt: Date(timeIntervalSince1970: 100),
            actorRawValue: "system",
            actorColumns: ReceiptActorColumns(
                kind: nil,
                identifier: nil,
                displayName: nil,
                inferenceLocality: nil,
                inferenceProvider: nil,
                inferenceModelClass: nil
            ),
            authorityColumns: ReceiptAuthorityColumns(
                source: nil,
                leaseID: nil,
                capability: nil,
                scope: nil,
                reason: nil,
                expiresAt: nil
            ),
            contributionColumns: .unattributed,
            modeRawValue: "Observe",
            trigger: "t",
            scope: "s",
            summary: "sum",
            provenance: "test",
            isSuccess: true,
            correlationID: nil,
            accountAddress: nil,
            chainRawValue: nil,
            payloadHash: "ph",
            signerPublicKey: nil,
            previousReceiptHash: ReceiptIntegrity.genesisHash
        )
        let detailForm = try ReceiptIntegrity.chainHash(
            receiptID: Self.fixedID,
            envelopeVersion: ReceiptIntegrityEnvelopeVersion.legacy,
            sequenceID: 1,
            accountSequenceID: 1,
            createdAt: Date(timeIntervalSince1970: 100),
            actorRawValue: "system",
            actorColumns: ReceiptActorColumns(nil),
            authorityColumns: ReceiptAuthorityColumns(nil),
            contributionColumns: .unattributed,
            modeRawValue: "Observe",
            trigger: "t",
            scope: "s",
            summary: "sum",
            provenance: "test",
            isSuccess: true,
            correlationID: nil,
            accountAddress: nil,
            chainRawValue: nil,
            payloadHash: "ph",
            signerPublicKey: nil,
            previousReceiptHash: ReceiptIntegrity.genesisHash
        )
        #expect(columnsForm == detailForm)
    }

    // MARK: - One row must not take down the check

    /// A column with no canonical byte form was a permanent denial of the audit trail.
    ///
    /// `createdAt` reaches the envelope as a `TimeInterval` and canonical JSON has no spelling for
    /// infinity, so the encoder threw — straight out of `verifyIntegrity()`, which returned no
    /// verdict at all, and out of `exportAll()` as a raw `EncodingError` rather than the
    /// `ReceiptProvenanceExportError` its contract promises. Recovery required `resetAll()`, i.e.
    /// destroying the history, which is the outcome the `Status` trichotomy exists to prevent.
    @Test("a non-finite createdAt is a verdict, not a thrown encoding error")
    func nonFiniteCreatedAtIsAVerdict() async throws {
        let context = try makeContext()
        let store = try makeStore(context: context)

        _ = try await store.append(draft(kind: "row"))
        let row = try #require(try context.fetch(FetchDescriptor<StoredReceipt>()).first)
        row.createdAt = Date(timeIntervalSince1970: .infinity)
        try context.save()

        let result = try await store.verifyIntegrity()
        #expect(result.status == .tampered, "\(result.failureReason ?? "-")")
        #expect(result.failureReason?.contains("cannot be canonically encoded") == true)

        // And the export fails as an export error, which is the type its callers match on.
        await #expect(throws: ReceiptProvenanceExportError.self) {
            _ = try await store.exportAll()
        }
    }

    /// The authority expiry is the other date in the envelope, and it reaches the encoder by a
    /// different path — through the authority columns rather than as a direct parameter. Set on a row
    /// with no authority source, so it also pins that the expiry is guarded even where the pre-fix
    /// envelope would have elided the column entirely.
    ///
    /// `.infinity` rather than `.nan`: NaN does not survive the SQLite round trip (it reads back as
    /// NULL), so a NaN fixture would silently exercise nothing.
    @Test("a non-finite authority expiry is a verdict, not a thrown encoding error")
    func nonFiniteAuthorityExpiryIsAVerdict() async throws {
        let context = try makeContext()
        let store = try makeStore(context: context)

        _ = try await store.append(draft(kind: "row"))
        let row = try #require(try context.fetch(FetchDescriptor<StoredReceipt>()).first)
        row.authorityExpiresAt = Date(timeIntervalSince1970: .infinity)
        try context.save()

        let result = try await store.verifyIntegrity()
        #expect(result.status == .tampered, "\(result.failureReason ?? "-")")
        #expect(result.failureReason?.contains("cannot be canonically encoded") == true)
    }

    @Test("the non-finite guard names the field it rejected")
    func nonFiniteGuardNamesTheField() {
        #expect(throws: ReceiptIntegrityEncodingError.nonFiniteDate(field: "createdAt")) {
            try ReceiptIntegrity.chainHash(
                receiptID: Self.fixedID,
                sequenceID: 1,
                accountSequenceID: 1,
                createdAt: Date(timeIntervalSince1970: .infinity),
                actorRawValue: "system",
                actorColumns: ReceiptActorColumns(nil),
                authorityColumns: ReceiptAuthorityColumns(nil),
                contributionColumns: .unattributed,
                modeRawValue: "Observe",
                trigger: "t",
                scope: "s",
                summary: "sum",
                provenance: "test",
                isSuccess: true,
                correlationID: nil,
                accountAddress: nil,
                chainRawValue: nil,
                payloadHash: "ph",
                signerPublicKey: nil,
                previousReceiptHash: ReceiptIntegrity.genesisHash
            )
        }
    }

    // MARK: - Envelope versioning

    /// A row written by *this* build declares the current version, and that version is inside the
    /// hash — so downgrading the column to re-admit the weaker envelope is self-defeating.
    @Test("downgrading the envelope version column is tampering")
    func envelopeVersionDowngradeIsTampering() async throws {
        let context = try makeContext()
        let store = try makeStore(context: context)

        _ = try await store.append(draft(kind: "row"))
        let row = try #require(try context.fetch(FetchDescriptor<StoredReceipt>()).first)
        #expect(row.integrityEnvelopeVersion == ReceiptIntegrityEnvelopeVersion.current)

        row.integrityEnvelopeVersion = ReceiptIntegrityEnvelopeVersion.legacy
        try context.save()

        let result = try await store.verifyIntegrity()
        #expect(result.status == .tampered, "\(result.failureReason ?? "-")")
        #expect(result.failureReason?.contains("invalid chain hash") == true)
    }

    /// The downgrade case — an older build reading rows a newer one wrote. It cannot reproduce an
    /// envelope it does not implement, and calling that tampering would tell a person their history
    /// was altered because they rolled a build back. Unattested says the true thing.
    ///
    /// **Conditional on the durable envelope-version floor, which is the whole reason this concession
    /// is safe.** The row here is indistinguishable, by inspection of the rows alone, from one an
    /// attacker fabricated: raising the version column is what disables the chain-hash recomputation,
    /// so the column cannot also be the thing that licenses disabling it. What separates the two is
    /// that a real newer build recorded having written that envelope, in the same `ThisDeviceOnly`
    /// Keychain as the mark. This test therefore records the floor first, exactly as the newer build's
    /// append path would have. See ``futureEnvelopeVersionAboveTheRecordedFloorIsTampering`` for the
    /// same row without it.
    @Test("a row from a newer envelope version is unattested, not tampered")
    func futureEnvelopeVersionIsUnattested() async throws {
        let context = try makeContext()
        let headStore = InMemoryReceiptIntegrityHeadStore()
        let signer = SoftwareReceiptSigner()
        let store = try makeStore(context: context, headStore: headStore, signer: signer)

        _ = try await store.append(draft(kind: "from-the-future"))
        let row = try #require(try context.fetch(FetchDescriptor<StoredReceipt>()).first)

        // What a newer build leaves behind: a version this one has no envelope for, and a chain hash
        // and signature this one cannot recompute but which are internally consistent.
        row.integrityEnvelopeVersion = ReceiptIntegrityEnvelopeVersion.current + 1
        row.chainHash = "a-hash-only-a-newer-build-could-derive"
        row.signature = try await signer.sign(row.chainHash).signature.base64EncodedString()
        try context.save()
        await headStore.saveHead(row.chainHash, for: row.accountKey)
        // The floor that build would have raised on the very append that wrote the row.
        await headStore.saveHighestEnvelopeVersion(ReceiptIntegrityEnvelopeVersion.current + 1)

        let result = try await store.verifyIntegrity()
        #expect(result.status == .unattested, "\(result.failureReason ?? "-")")
        #expect(result.isValid, "a downgraded install must still be able to export its history")
        #expect(
            result.failureReason?.contains("this build cannot recompute") == true,
            "\(result.failureReason ?? "-")"
        )
        // The property the concession exists for, asserted rather than assumed.
        #expect(try await store.exportAll().isEmpty == false)
    }

    /// The same row with no floor vouching for it: the bypass, now closed.
    ///
    /// The version column is part of the row, so letting it decide whether the row's `chainHash` gets
    /// recomputed was circular — and it was a *complete* bypass of the chain hash, reachable with
    /// SwiftData write access alone. Measured before the fix, on a three-receipt ledger: raising this
    /// column let a receipt's `summary`, `mode` and `isSuccess` be rewritten in place and carried into
    /// the manifest-signed archive at `.unattested`, which `isValid` accepts.
    @Test("a row claiming an envelope version no build here ever wrote is tampering")
    func futureEnvelopeVersionAboveTheRecordedFloorIsTampering() async throws {
        let context = try makeContext()
        let headStore = InMemoryReceiptIntegrityHeadStore()
        let store = try makeStore(context: context, headStore: headStore)

        for index in 0..<3 {
            _ = try await store.append(draft(kind: "row-\(index)"))
        }
        #expect(try await store.verifyIntegrity().status == .verified)
        // The append path recorded what it actually wrote, and nothing above it.
        #expect(await headStore.loadHighestEnvelopeVersion() == ReceiptIntegrityEnvelopeVersion.current)

        // Store writes only: rewrite the content and raise the version so nothing recomputes the hash.
        let rows = try context.fetch(
            FetchDescriptor<StoredReceipt>(sortBy: [SortDescriptor(\StoredReceipt.sequenceID)])
        )
        let victim = rows[1]
        victim.summary = "FORGED: user approved unlimited spend"
        victim.isSuccess = false
        victim.integrityEnvelopeVersion = ReceiptIntegrityEnvelopeVersion.current + 1
        try context.save()

        let result = try await store.verifyIntegrity()
        #expect(result.status == .tampered, "\(result.failureReason ?? "-")")
        #expect(
            result.failureReason?.contains("no build on this device has written past version") == true,
            "\(result.failureReason ?? "-")"
        )
        // The consequence that made it critical: the rewritten receipt can no longer reach a signed
        // archive, because `exportAll()` is gated on `isValid` and `.unattested` satisfied it.
        await #expect(throws: ReceiptProvenanceExportError.self) {
            _ = try await store.exportAll()
        }
    }

    /// The state every install is in the moment it upgrades to the build that records the floor: rows
    /// present, no floor yet, next append not taken.
    ///
    /// Gating the concession on the floor *alone* left it wide open here, and this is the most
    /// ordinary state there is rather than an exotic one — so the bypass was reachable on essentially
    /// every install, reported with the same wording an honest downgrade produces. What closes it is
    /// that an upgraded install is not a restored one: its rows are still signed by this device's
    /// current identity, because the signing key survives an app upgrade while a floor that was never
    /// written does not exist to be found.
    @Test("a raised envelope version is tampering on an upgraded ledger that has no floor yet")
    func raisedEnvelopeVersionWithNoFloorOnAnAttestedLedgerIsTampering() async throws {
        let context = try makeContext()
        let headStore = InMemoryReceiptIntegrityHeadStore()
        let signer = SoftwareReceiptSigner()
        let store = try makeStore(context: context, headStore: headStore, signer: signer)

        for index in 0..<3 {
            _ = try await store.append(draft(kind: "row-\(index)"))
        }

        // Exactly the pre-floor build's durable state: rows, anchors and a mark, but no floor — which
        // is what an install carries until its first append on the new build.
        let withoutFloor = InMemoryReceiptIntegrityHeadStore()
        for row in try context.fetch(FetchDescriptor<StoredReceipt>()) {
            await withoutFloor.saveHead(row.chainHash, for: row.accountKey)
        }
        await withoutFloor.saveLedgerHighWaterMark(3)
        #expect(await withoutFloor.loadHighestEnvelopeVersion() == nil)
        // The same signer, so this device can still attest the rows — the upgrade case, not a restore.
        let upgraded = try makeStore(context: context, headStore: withoutFloor, signer: signer)
        #expect(try await upgraded.verifyIntegrity().status == .verified)

        let rows = try context.fetch(
            FetchDescriptor<StoredReceipt>(sortBy: [SortDescriptor(\StoredReceipt.sequenceID)])
        )
        let victim = rows[1]
        victim.summary = "FORGED: user approved unlimited spend"
        victim.isSuccess = false
        victim.integrityEnvelopeVersion = ReceiptIntegrityEnvelopeVersion.current + 1
        try context.save()

        let result = try await upgraded.verifyIntegrity()
        #expect(result.status == .tampered, "\(result.failureReason ?? "-")")
        #expect(
            result.failureReason?.contains("no build on this device has written past version") == true,
            "\(result.failureReason ?? "-")"
        )
        await #expect(throws: ReceiptProvenanceExportError.self) {
            _ = try await upgraded.exportAll()
        }
    }

    /// The other side of that gate, and the reason it is drawn on attestability rather than on the
    /// floor alone: a store restored from a device running a *newer* build legitimately arrives with
    /// rows above anything this device ever recorded, and with no floor either.
    ///
    /// What separates it from the upgraded install above is that nothing here is signed by this
    /// device's current identity — the signing key is `ThisDeviceOnly` and does not survive the
    /// transfer. An attacker cannot manufacture that state: emptying it means removing every
    /// current-identity signature, which the forward-only rule reports, or deleting the signing key,
    /// which is Keychain access.
    @Test("a newer envelope version on a ledger this device cannot attest is unattested, not tampered")
    func newerEnvelopeVersionOnARestoredLedgerIsUnattested() async throws {
        let context = try makeContext()
        let headStore = InMemoryReceiptIntegrityHeadStore()
        let writingSigner = SoftwareReceiptSigner()
        let writingStore = try makeStore(context: context, headStore: headStore, signer: writingSigner)

        _ = try await writingStore.append(draft(kind: "from-the-future"))
        let row = try #require(try context.fetch(FetchDescriptor<StoredReceipt>()).first)
        row.integrityEnvelopeVersion = ReceiptIntegrityEnvelopeVersion.current + 1
        row.chainHash = "a-hash-only-a-newer-build-could-derive"
        row.signature = try await writingSigner.sign(row.chainHash).signature.base64EncodedString()
        try context.save()

        // The restore: the rows arrive, the `ThisDeviceOnly` signing key and floor do not. The anchor
        // travels with the row here only so the pass reaches the version decision rather than
        // stopping at an orphaned head.
        let restoredHeadStore = InMemoryReceiptIntegrityHeadStore()
        await restoredHeadStore.saveHead(row.chainHash, for: row.accountKey)
        #expect(await restoredHeadStore.loadHighestEnvelopeVersion() == nil)
        let restored = try makeStore(
            context: context,
            headStore: restoredHeadStore,
            signer: SoftwareReceiptSigner()
        )

        let result = try await restored.verifyIntegrity()
        #expect(result.status == .unattested, "\(result.failureReason ?? "-")")
        #expect(result.isValid, "a restore from a newer build must still be able to export")
        #expect(try await restored.exportAll().isEmpty == false)
    }

    /// A reset must not leave the concession unbounded.
    ///
    /// `clearAllHeads()` takes the floor with it, and an absent floor is the *permissive* state — so
    /// between the reset and the next append a planted row had nothing bounding what version it could
    /// claim. `performResetAll()` re-records the current version straight after clearing, which costs
    /// nothing derived from the deleted history because the value is a constant of the build.
    @Test("a reset leaves the envelope-version floor recorded, not absent")
    func resetLeavesTheEnvelopeVersionFloorRecorded() async throws {
        let context = try makeContext()
        let headStore = InMemoryReceiptIntegrityHeadStore()
        let store = try makeStore(context: context, headStore: headStore)

        _ = try await store.append(draft(kind: "row"))
        try await store.resetAll()

        #expect(await headStore.loadAllHeads().isEmpty)
        // The mark *is* cleared, because an honest reset restarts sequence allocation at 1 and a
        // surviving mark would read as a ledger that lost everything.
        #expect(await headStore.loadLedgerHighWaterMark() == nil)
        // The floor is not, because absent means "concede anything".
        #expect(
            await headStore.loadHighestEnvelopeVersion() == ReceiptIntegrityEnvelopeVersion.current,
            "a reset left the envelope-version concession unbounded"
        )
    }

    /// De-attestation by deleting signatures, which is the attack that made every other rule here
    /// conditional on something an attacker controls.
    ///
    /// `signerPublicKey` is inside the hashed envelope; `signature` cannot be, since it signs that
    /// hash. So clearing only the signature leaves every chain hash verifying, and before the pairing
    /// rule it turned a `.verified` ledger into `.unattested` reading *"predates receipt signing"* —
    /// a signed history silently demoted to an unattestable one, still exportable, with store writes
    /// alone.
    @Test("clearing signatures while leaving the signer key is tampering, not a pre-signing ledger")
    func clearingSignaturesWhileKeepingTheSignerKeyIsTampering() async throws {
        let context = try makeContext()
        let store = try makeStore(context: context, headStore: InMemoryReceiptIntegrityHeadStore())

        for index in 0..<3 {
            _ = try await store.append(draft(kind: "row-\(index)"))
        }
        #expect(try await store.verifyIntegrity().status == .verified)

        // Note what is *not* done here: the chain hash is left alone, because it does not cover
        // `signature`. That is the whole point — nothing else in the pass notices.
        for row in try context.fetch(FetchDescriptor<StoredReceipt>()) {
            row.signature = nil
        }
        try context.save()

        let result = try await store.verifyIntegrity()
        #expect(result.status == .tampered, "\(result.failureReason ?? "-")")
        #expect(
            result.failureReason?.contains("names a signing key but carries no signature") == true,
            "\(result.failureReason ?? "-")"
        )
        #expect(result.failureReason?.contains("predates receipt signing") == false)
        await #expect(throws: ReceiptProvenanceExportError.self) {
            _ = try await store.exportAll()
        }
    }

    /// The follow-up door: clear *both* signing columns — which does break the chain hash — and hide
    /// that with the same raised version column that the resulting unattestable ledger then licenses.
    ///
    /// Fully circular, and it defeated the envelope-version floor **while the floor was present and
    /// correct**, by manufacturing the restore signature the floor's escape hatch trusted. Measured
    /// before the fix: `.unattested`, with a rewritten `summary` carried into the manifest-signed
    /// archive. The hatch now also requires the floor to be *absent*, which is the one input here that
    /// no row asserts.
    @Test("clearing both signing columns behind a raised version is tampering when a floor exists")
    func clearingBothSigningColumnsBehindARaisedVersionIsTampering() async throws {
        let context = try makeContext()
        let headStore = InMemoryReceiptIntegrityHeadStore()
        let store = try makeStore(context: context, headStore: headStore)

        for index in 0..<3 {
            _ = try await store.append(draft(kind: "row-\(index)"))
        }
        // The floor is present and correct, which is what makes this case pointed.
        #expect(await headStore.loadHighestEnvelopeVersion() == ReceiptIntegrityEnvelopeVersion.current)

        let rows = try context.fetch(
            FetchDescriptor<StoredReceipt>(sortBy: [SortDescriptor(\StoredReceipt.sequenceID)])
        )
        for row in rows {
            row.signature = nil
            row.signerPublicKey = nil
            row.integrityEnvelopeVersion = ReceiptIntegrityEnvelopeVersion.current + 1
        }
        rows[1].summary = "FORGED: user approved unlimited spend"
        rows[1].isSuccess = false
        try context.save()

        let result = try await store.verifyIntegrity()
        #expect(result.status == .tampered, "\(result.failureReason ?? "-")")
        #expect(
            result.failureReason?.contains("no build on this device has written past version") == true,
            "\(result.failureReason ?? "-")"
        )
        await #expect(throws: ReceiptProvenanceExportError.self) {
            _ = try await store.exportAll()
        }
    }

    /// A restored store has no floor at all, so the concession is permissive again — and that is the
    /// state the second defence covers.
    ///
    /// A fabricated row can carry a working signature without the attacker holding any key, by
    /// replaying another row's `chainHash` and `signature` *together*. With the recomputation disabled
    /// by the version column and no floor to object, the replayed signature verified and the row
    /// classified as validly *signed* — so ``ReceiptSigningLedgerOrdering``, which only fires on rows
    /// classified unsigned, never saw it. The fabricated account then reached the genesis anchor heal
    /// and was **minted a Keychain anchor**. ``ReceiptChainHashUniqueness`` is what closes this, and
    /// this is the case that proves it is not redundant with the floor.
    @Test("a replayed chain hash is tampering even when no floor bounds the envelope version")
    func replayedChainHashIsTamperingWithNoFloor() async throws {
        let context = try makeContext()
        let store = try makeStore(context: context, headStore: InMemoryReceiptIntegrityHeadStore())

        for index in 0..<3 {
            _ = try await store.append(draft(kind: "row-\(index)"))
        }

        // A restored store: the rows and anchors came back, the `ThisDeviceOnly` mark and floor did not.
        let anchorsOnly = InMemoryReceiptIntegrityHeadStore()
        for row in try context.fetch(FetchDescriptor<StoredReceipt>()) {
            await anchorsOnly.saveHead(row.chainHash, for: row.accountKey)
        }
        #expect(await anchorsOnly.loadHighestEnvelopeVersion() == nil)
        let restored = try makeStore(context: context, headStore: anchorsOnly)

        let donor = try #require(
            try context.fetch(
                FetchDescriptor<StoredReceipt>(sortBy: [SortDescriptor(\StoredReceipt.sequenceID)])
            ).first
        )
        let details = ReceiptPayload(values: [:])
        let forged = try StoredReceipt(
            sequenceID: 4,
            createdAt: Date(timeIntervalSince1970: 100),
            actor: .system,
            actorDetail: .system,
            authorityDetail: nil,
            mode: .observe,
            trigger: "injected",
            scope: "accounts",
            summary: "FORGED: injected receipt",
            provenance: "attacker",
            isSuccess: true,
            correlationID: nil,
            timelineAccountAddress: "0x9999999999999999999999999999999999999999",
            timelineChainRawValue: nil,
            accountSequenceID: 1,
            payloadHash: try ReceiptIntegrity.payloadHash(for: details),
            previousReceiptHash: ReceiptIntegrity.genesisHash,
            // The replay: another row's hash and the signature that covers it, together.
            chainHash: donor.chainHash,
            signature: donor.signature,
            signerPublicKey: donor.signerPublicKey,
            integrityEnvelopeVersion: ReceiptIntegrityEnvelopeVersion.current + 1,
            details: details
        )
        context.insert(forged)
        try context.save()

        let result = try await restored.verifyIntegrity()
        #expect(result.status == .tampered, "\(result.failureReason ?? "-")")
        #expect(
            result.failureReason?.contains("repeats another receipt's chain hash") == true,
            "\(result.failureReason ?? "-")"
        )
        // And no anchor was minted for the fabricated account, which the genesis heal used to do.
        #expect(await anchorsOnly.loadHead(for: "0x9999999999999999999999999999999999999999") == nil)
    }

    // MARK: - The coarse actor column cannot contradict the structured detail

    /// F-45. `ReceiptDraft.init` defaults `actor` to `.system` while *requiring* `actorDetail`, so a
    /// writer that recorded a human and omitted one argument persisted a row claiming the system
    /// acted — and it verified, because both the hash and the column read the same wrong value.
    ///
    /// The fix derives the column from `actorDetail.coarseActor` at both ends instead of checking
    /// them, so the drift is not representable rather than merely detected.
    @Test("a human detail beside a defaulted system actor persists as a user receipt")
    func coarseActorIsDerivedFromTheStructuredDetail() async throws {
        let context = try makeContext()
        let headStore = InMemoryReceiptIntegrityHeadStore()
        let store = try makeStore(context: context, headStore: headStore)

        // The mismatch, written the way a real caller reaches it: a human detail and no `actor:`.
        _ = try await store.append(
            ReceiptDraft(
                createdAt: Date(timeIntervalSince1970: 100),
                actorDetail: .human,
                authorityDetail: nil,
                trigger: "approve",
                scope: "accounts",
                summary: "Fixture",
                provenance: "test",
                isSuccess: true,
                correlationID: nil,
                timelineAccountAddress: Self.accountA,
                timelineChainRawValue: nil,
                details: ReceiptPayload(values: [:])
            )
        )

        let row = try #require(try context.fetch(FetchDescriptor<StoredReceipt>()).first)
        #expect(row.actor == .user, "the column must follow the detail, not the defaulted parameter")
        #expect(row.actorKindRawValue == "human")

        // And the row is still internally consistent: the hash input was derived the same way, so
        // deriving the column did not desynchronize it from what was signed.
        #expect(try await store.verifyIntegrity().status == .verified)
        #expect(row.chainHash == (try ReceiptIntegrity.chainHash(for: row)))
    }

    // MARK: - Raw mode and actor strings

    /// F-42's residual, which Round 10 opened and left uncovered.
    ///
    /// The envelope commits to `modeRawValue`/`actorRawValue` rather than to the typed
    /// `mode`/`actor`, and this is the case that distinction exists for. `StoredReceipt.mode`
    /// degrades an unrecognized raw value to `.operate` and `actor` to `.system` on read, so hashing
    /// the *typed* value re-hashed the degraded stand-in instead of what the row actually stores: a
    /// receipt written by a newer build, carrying a mode this build has no case for, recomputed a
    /// different chain hash and was reported as tampering. A downgrade presented as an altered
    /// ledger — the same class of false accusation as F-39, F-40 and F-44.
    @Test("a mode and actor this build cannot name still re-hash and verify")
    func unrecognizedModeAndActorRawValuesStillVerify() async throws {
        let context = try makeContext()
        let headStore = InMemoryReceiptIntegrityHeadStore()
        let signer = SoftwareReceiptSigner()
        let store = try makeStore(context: context, headStore: headStore, signer: signer)

        _ = try await store.append(draft(kind: "from-a-newer-build"))
        let row = try #require(try context.fetch(FetchDescriptor<StoredReceipt>()).first)

        // Values a newer build knows and this one does not. The envelope *version* is deliberately
        // untouched: this is the current envelope shape carrying unfamiliar values, so it has to
        // verify outright rather than land on the downgrade concession that
        // ``futureEnvelopeVersionIsUnattested`` covers.
        row.modeRawValue = "quorum"
        row.actorRawValue = "delegatedAgent"
        row.chainHash = try ReceiptIntegrity.chainHash(for: row)
        row.signature = try await signer.sign(row.chainHash).signature.base64EncodedString()
        try context.save()
        await headStore.saveHead(row.chainHash, for: row.accountKey)

        let result = try await store.verifyIntegrity()
        #expect(result.status == .verified, "\(result.failureReason ?? "-")")

        // The degradation still happens on read. The point is that it does not reach the hash.
        #expect(row.mode == .operate)
        #expect(row.actor == .system)
        #expect(row.modeRawValue == "quorum", "reading `mode` must not normalize the stored column")

        // The assertion that makes this test mean something. `chainHash(for:)` is the same function
        // the verifier uses, so a regression to hashing the typed values would recompute whatever
        // this test stored and still report `.verified` — the verdict above is tautological on its
        // own. These two independent hashes pin the inputs instead, built with an explicit argument
        // list in the golden-vector style of `ReceiptEnvelopeSpecificationTests`.
        func hash(actorRawValue: String, modeRawValue: String) throws -> String {
            try ReceiptIntegrity.chainHash(
                receiptID: row.id,
                envelopeVersion: row.integrityEnvelopeVersion,
                sequenceID: row.sequenceID,
                accountSequenceID: row.accountSequenceID,
                createdAt: row.createdAt,
                actorRawValue: actorRawValue,
                actorColumns: row.actorColumns,
                authorityColumns: row.authorityColumns,
                contributionColumns: row.contributionColumns,
                modeRawValue: modeRawValue,
                trigger: row.trigger,
                scope: row.scope,
                summary: row.summary,
                provenance: row.provenance,
                isSuccess: row.isSuccess,
                correlationID: row.correlationID,
                accountAddress: row.accountAddress,
                chainRawValue: row.chainRawValue,
                payloadHash: row.payloadHash,
                signerPublicKey: row.signerPublicKey,
                previousReceiptHash: row.previousReceiptHash
            )
        }
        #expect(row.chainHash == (try hash(actorRawValue: "delegatedAgent", modeRawValue: "quorum")))
        #expect(
            row.chainHash != (try hash(
                actorRawValue: ReceiptActor.system.rawValue,
                modeRawValue: ReceiptMode.operate.rawValue
            )),
            "the stored hash must commit to the raw strings, not to the degraded typed values"
        )
    }

    /// The same row at the **archive** boundary, which is where F-42's fix stops holding.
    ///
    /// `ReceiptRecord` carries `mode`/`actor` as typed enums and no raw strings, so
    /// `asExportableReceiptRecord()` writes the *degraded* value into the archive while copying the
    /// `chainHash` column — computed over the raw string — verbatim. The bundled verifier then
    /// recomputes from `record.mode.rawValue` and gets a different hash.
    @Test("an exported row whose mode this build cannot name still verifies from its archive")
    func unrecognizedModeSurvivesTheExportBoundary() async throws {
        let context = try makeContext()
        let headStore = InMemoryReceiptIntegrityHeadStore()
        let signer = SoftwareReceiptSigner()
        let store = try makeStore(context: context, headStore: headStore, signer: signer)

        _ = try await store.append(draft(kind: "from-a-newer-build"))
        let row = try #require(try context.fetch(FetchDescriptor<StoredReceipt>()).first)
        // Both legs, because the two columns are degraded by separate getters (`?? .operate` and
        // `?? .system`) and a fix applied to one would leave the other reporting tampering.
        row.modeRawValue = "quorum"
        row.actorRawValue = "delegatedAgent"
        row.chainHash = try ReceiptIntegrity.chainHash(for: row)
        row.signature = try await signer.sign(row.chainHash).signature.base64EncodedString()
        try context.save()
        await headStore.saveHead(row.chainHash, for: row.accountKey)

        // The local store is happy — that is what F-42's fix bought.
        #expect(try await store.verifyIntegrity().status == .verified)

        let data = try await store.exportAll()
        let fingerprint = try await store.provenanceTrustAnchor().fingerprint
        let verified = try ReceiptProvenanceVerifier.verify(data, trustedSignerFingerprint: fingerprint)

        // An honest archive of an honest ledger must not read as altered. The acceptable answers are
        // `.verified` or `.unattested`; `.tampered` is the false accusation.
        #expect(verified.status != .tampered, "\(verified.failureReason ?? "-")")

        // The archive carries the stored strings rather than the degraded stand-ins, which is the
        // mechanism the assertion above depends on.
        let archive = try ReceiptCanonicalJSON.decoder().decode(ReceiptProvenanceExport.self, from: data)
        #expect(archive.records[0].modeRawValue == "quorum")
        #expect(archive.records[0].actorRawValue == "delegatedAgent")
    }

    /// The other half of that field's contract, and the reason it can be added without a format
    /// version bump: a row whose values this build *can* name must leave both fields absent, so an
    /// ordinary archive's bytes — and therefore its `recordsHash` — are unchanged.
    @Test("an ordinary row exports with no raw mode or actor override")
    func recognizedModeAndActorAreOmittedFromTheArchive() async throws {
        let context = try makeContext()
        let store = try makeStore(context: context)
        _ = try await store.append(draft(kind: "ordinary"))

        let data = try await store.exportAll()
        let archive = try ReceiptCanonicalJSON.decoder().decode(ReceiptProvenanceExport.self, from: data)
        #expect(archive.records[0].modeRawValue == nil)
        #expect(archive.records[0].actorRawValue == nil)

        // And the encoded bytes really do omit the keys, rather than carrying them as JSON `null` —
        // which would change `recordsHash` for every archive despite the values being absent.
        let json = try #require(String(data: data, encoding: .utf8))
        #expect(json.contains("modeRawValue") == false)
        #expect(json.contains("actorRawValue") == false)
    }

    // MARK: - Unreadable payloads stay visible

    /// The empty-payload substitution is right for display — one lost external blob should not blank
    /// the console — but a plain empty payload made "could not be read" indistinguishable from "this
    /// receipt recorded nothing", which on an audit surface is a weaker claim made silently.
    @Test("an unreadable payload reads back marked, not merely empty")
    func unreadablePayloadIsMarked() async throws {
        let context = try makeContext()
        let store = try makeStore(context: context)

        _ = try await store.append(draft(kind: "row"))
        let row = try #require(try context.fetch(FetchDescriptor<StoredReceipt>()).first)
        row.replaceDetailsDataForTesting(Data("not json".utf8))
        try context.save()

        let record = row.asReceiptRecord()
        #expect(record.details.values[StoredReceipt.unavailablePayloadKey] == .bool(true))
        #expect(record.details.values.isEmpty == false)
    }

    // MARK: - Backfill

    /// `didBackfillAccountKeys` latches per store instance, and `resetAll()` deletes every row
    /// underneath it. Nothing covered the two together, so a latch that outlived the rows it was
    /// about could have gone unnoticed.
    @Test("the accountKey backfill latch survives a reset without forking the chain")
    func backfillLatchSurvivesReset() async throws {
        let context = try makeContext()
        let store = try makeStore(context: context)

        _ = try await store.append(draft(kind: "before", accountAddress: Self.accountA))
        try await store.resetAll()

        // A pre-column row inserted *after* the latch was set, which is the case a stale latch would
        // skip: its `accountKey` stays `""`, so the predecessor lookup would miss it and the next
        // append would fork a second chain off the genesis hash.
        _ = try await store.append(draft(kind: "after-1", accountAddress: Self.accountA))
        _ = try await store.append(draft(kind: "after-2", accountAddress: Self.accountA))

        let rows = try context.fetch(
            FetchDescriptor<StoredReceipt>(sortBy: [SortDescriptor(\StoredReceipt.sequenceID)])
        )
        #expect(rows.map(\.accountSequenceID) == [1, 2])
        #expect(rows.allSatisfy { $0.accountKey == Self.accountA.lowercased() })

        let result = try await store.verifyIntegrity()
        #expect(result.status == .verified, "\(result.failureReason ?? "-")")
    }

    // MARK: - Helpers

    private static let fixedID = UUID(uuidString: "11111111-2222-3333-4444-555555555555")!

    private func makeContext() throws -> ModelContext {
        try ReceiptStorageTestModelContainers.context()
    }

    private func makeStore(
        context: ModelContext,
        headStore: any ReceiptIntegrityHeadStoring = InMemoryReceiptIntegrityHeadStore(),
        signer: any ReceiptSigning = SoftwareReceiptSigner()
    ) throws -> ReceiptPersistenceStore {
        ReceiptPersistenceStore(
            modelContainer: context.container,
            integrityHeadStore: headStore,
            signer: signer
        )
    }

    private func replacingID(on record: ReceiptRecord, with id: UUID) -> ReceiptRecord {
        ReceiptRecord(
            id: id,
            sequenceID: record.sequenceID,
            createdAt: record.createdAt,
            actor: record.actor,
            actorDetail: record.actorDetail,
            authorityDetail: record.authorityDetail,
            mode: record.mode,
            trigger: record.trigger,
            scope: record.scope,
            summary: record.summary,
            provenance: record.provenance,
            isSuccess: record.isSuccess,
            correlationID: record.correlationID,
            accountAddress: record.accountAddress,
            chainRawValue: record.chainRawValue,
            accountSequenceID: record.accountSequenceID,
            payloadHash: record.payloadHash,
            previousReceiptHash: record.previousReceiptHash,
            chainHash: record.chainHash,
            signature: record.signature,
            signerPublicKey: record.signerPublicKey,
            integrityEnvelopeVersion: record.integrityEnvelopeVersion,
            details: record.details
        )
    }

    /// Re-signs a hand-built record set with a fresh identity whose fingerprint the caller pins, so
    /// the manifest and trust-anchor checks all pass and the per-record check is the only thing left
    /// that can fail. Without this the verdict would come from `recordsHash` and the test would pass
    /// for the wrong reason.
    private func rebuiltExport(
        records: [ReceiptRecord],
        like original: ReceiptProvenanceExport
    ) async throws -> (export: ReceiptProvenanceExport, fingerprint: String) {
        let signer = SoftwareReceiptSigner()
        let publicKey = try await signer.publicKeyRepresentation()
        let trustAnchor = ReceiptProvenanceTrustAnchor(
            algorithm: "P-256/SHA-256",
            publicKey: publicKey.base64EncodedString(),
            fingerprint: ReceiptIntegrity.sha256Hex(publicKey)
        )
        let manifest = ReceiptProvenanceManifest(
            recordCount: records.count,
            recordsHash: ReceiptIntegrity.sha256Hex(try ReceiptIntegrity.canonicalData(records)),
            chainHeads: original.manifest.chainHeads,
            ledgerHighWaterMark: original.manifest.ledgerHighWaterMark
        )
        let manifestHash = ReceiptIntegrity.sha256Hex(try ReceiptIntegrity.canonicalData(manifest))
        let manifestSignature = try await signer.sign(manifestHash)
        return (
            ReceiptProvenanceExport(
                records: records,
                manifest: manifest,
                manifestHash: manifestHash,
                manifestSignature: manifestSignature.signature.base64EncodedString(),
                trustAnchor: trustAnchor
            ),
            trustAnchor.fingerprint
        )
    }

    private func draft(kind: String, accountAddress: String? = ReceiptEnvelopeCoverageTests.accountA) -> ReceiptDraft {
        ReceiptDraft(
            createdAt: Date(timeIntervalSince1970: 100),
            actorDetail: .system,
            authorityDetail: nil,
            trigger: kind,
            scope: "accounts",
            summary: "Fixture",
            provenance: "test",
            isSuccess: true,
            correlationID: nil,
            timelineAccountAddress: accountAddress,
            timelineChainRawValue: nil,
            details: ReceiptPayload(values: [:])
        )
    }
}
