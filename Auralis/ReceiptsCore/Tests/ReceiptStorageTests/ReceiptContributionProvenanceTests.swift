import AuralisFoundation
import Foundation
import ReceiptsCore
@testable import ReceiptStorage
import RuntimeCore
import SwiftData
import Testing

/// Phase 1 contribution provenance: the canonical principal, the affected-resource and
/// produced-result references, and the semantic parent receipt IDs.
///
/// Three properties have to hold together, and each is easy to get right while breaking another:
/// the new columns are **bound into the hash** (so they cannot be rewritten), receipts written
/// before they existed **still verify unchanged** (so adding them did not invalidate history), and the
/// parent contract is **enforced before the write** (because a receipt is immutable once signed).
@MainActor
struct ReceiptContributionProvenanceTests {
    private static let accountA = "0x1111111111111111111111111111111111111111"
    private static let accountB = "0x2222222222222222222222222222222222222222"

    // MARK: - Round trip

    @Test("contribution provenance round-trips through append and verifies")
    func provenanceRoundTripsAndVerifies() async throws {
        let context = try makeContext()
        let store = try makeStore(context: context)

        let parent = try await store.append(draft(kind: "parent"))
        let child = try await store.append(
            draft(
                kind: "child",
                principal: PrincipalID(rawValue: "did:example:alice"),
                affectedResource: ReceiptResourceReference(type: "nft", identifier: "eip155:1/erc721:0xabc/7"),
                producedResult: ReceiptResultReference(type: "artifact", identifier: "report-1"),
                parentReceiptIDs: [parent.id]
            )
        )

        #expect(child.principal?.rawValue == "did:example:alice")
        #expect(child.affectedResource?.type == "nft")
        #expect(child.affectedResource?.identifier == "eip155:1/erc721:0xabc/7")
        #expect(child.producedResult?.type == "artifact")
        #expect(child.producedResult?.identifier == "report-1")
        #expect(child.parentReceiptIDs == [parent.id])

        let result = try await store.verifyIntegrity()
        #expect(result.status == .verified, "\(result.failureReason ?? "-")")
    }

    /// Every receipt written today declares the version that binds these columns. Without this, a
    /// regression that left `current` at the old value would keep every test above green while
    /// quietly writing rows whose provenance claims to predate the question.
    @Test("a new receipt declares the provenance-binding envelope version")
    func newReceiptsDeclareTheProvenanceEnvelopeVersion() async throws {
        let context = try makeContext()
        let store = try makeStore(context: context)
        _ = try await store.append(draft(kind: "row"))

        let row = try #require(try context.fetch(FetchDescriptor<StoredReceipt>()).first)
        #expect(row.integrityEnvelopeVersion == ReceiptIntegrityEnvelopeVersion.bindsContributionProvenance)
        #expect(ReceiptIntegrityEnvelopeVersion.current == ReceiptIntegrityEnvelopeVersion.bindsContributionProvenance)
    }

    /// A receipt that states no provenance must read as *not stated* rather than as anything else,
    /// and must still verify — this is the overwhelmingly common receipt.
    @Test("a receipt with no stated provenance reads as absent and verifies")
    func absentProvenanceReadsAsAbsent() async throws {
        let context = try makeContext()
        let store = try makeStore(context: context)

        let record = try await store.append(draft(kind: "plain"))
        let row = try #require(try context.fetch(FetchDescriptor<StoredReceipt>()).first)

        #expect(record.principal == nil)
        #expect(record.affectedResource == nil)
        #expect(record.producedResult == nil)
        #expect(record.parentReceiptIDs == nil, "an empty parent list must normalize to nil, not []")
        #expect(row.principalIDRawValue == nil)
        #expect(row.parentReceiptIDsRawValue == nil)
        #expect(try await store.verifyIntegrity().status == .verified)
    }

    // MARK: - Tamper evidence, column by column

    /// Each new column rewritten on its own, because one combined mutation cannot distinguish "all
    /// six are hashed" from "one is hashed and the rest are free".
    @Test(
        "rewriting any contribution-provenance column is tampering",
        arguments: [
            "principalIDRawValue",
            "affectedResourceType",
            "affectedResourceIdentifier",
            "producedResultType",
            "producedResultIdentifier",
            "parentReceiptIDsRawValue"
        ]
    )
    func rewritingAProvenanceColumnIsTampering(column: String) async throws {
        let context = try makeContext()
        let store = try makeStore(context: context)

        let parent = try await store.append(draft(kind: "parent"))
        _ = try await store.append(
            draft(
                kind: "child",
                principal: PrincipalID(rawValue: "did:example:alice"),
                affectedResource: ReceiptResourceReference(type: "nft", identifier: "7"),
                producedResult: ReceiptResultReference(type: "artifact", identifier: "report-1"),
                parentReceiptIDs: [parent.id]
            )
        )
        #expect(try await store.verifyIntegrity().status == .verified, "the fixture must start clean")

        let rows = try context.fetch(
            FetchDescriptor<StoredReceipt>(sortBy: [SortDescriptor(\StoredReceipt.sequenceID)])
        )
        let row = try #require(rows.last)
        switch column {
        case "principalIDRawValue": row.principalIDRawValue = "did:example:mallory"
        case "affectedResourceType": row.affectedResourceType = "playlist"
        case "affectedResourceIdentifier": row.affectedResourceIdentifier = "8"
        case "producedResultType": row.producedResultType = "receipt"
        case "producedResultIdentifier": row.producedResultIdentifier = "report-2"
        // A *different but well-formed* parent list, so the canonical-form guard does not fire first
        // and this measures the hash rather than the shape check.
        case "parentReceiptIDsRawValue": row.parentReceiptIDsRawValue = UUID().uuidString
        default: Issue.record("unhandled column \(column)")
        }
        try context.save()

        let result = try await store.verifyIntegrity()
        #expect(result.status == .tampered, "\(column): \(result.failureReason ?? "-")")
        #expect(result.failureReason?.contains("invalid chain hash") == true, "\(column)")
    }

    /// Adding provenance to a row that stated none is the mutation the version gate would have
    /// allowed if the columns were bound only from v2 onward. They are bound unconditionally, so this
    /// is caught regardless of what the version column says.
    @Test("writing provenance onto a receipt that stated none is tampering")
    func addingProvenanceToABareReceiptIsTampering() async throws {
        let context = try makeContext()
        let store = try makeStore(context: context)
        _ = try await store.append(draft(kind: "plain"))

        let row = try #require(try context.fetch(FetchDescriptor<StoredReceipt>()).first)
        row.affectedResourceType = "nft"
        row.affectedResourceIdentifier = "7"
        try context.save()

        let result = try await store.verifyIntegrity()
        #expect(result.status == .tampered, "\(result.failureReason ?? "-")")
    }

    /// The half-written pair: a type with no identifier reconstructs as *no reference at all*, so if
    /// the composed form were hashed this column would sit outside every check. It is the columns
    /// that are hashed, so it does not.
    @Test("a half-written resource reference is still caught")
    func halfWrittenResourceReferenceIsCaught() async throws {
        let context = try makeContext()
        let store = try makeStore(context: context)
        _ = try await store.append(draft(kind: "plain"))

        let row = try #require(try context.fetch(FetchDescriptor<StoredReceipt>()).first)
        row.affectedResourceType = "nft"
        try context.save()

        #expect(row.affectedResource == nil, "a type with no identifier must not compose a reference")
        let result = try await store.verifyIntegrity()
        #expect(result.status == .tampered, "\(result.failureReason ?? "-")")
    }

    // MARK: - The parent contract

    @Test("an append naming a parent that is not in the ledger is refused")
    func unknownParentIsRefused() async throws {
        let context = try makeContext()
        let store = try makeStore(context: context)
        let stranger = UUID()

        await #expect(throws: ReceiptParentContractError.unknownParent(stranger)) {
            _ = try await store.append(draft(kind: "child", parentReceiptIDs: [stranger]))
        }
        // Refused means nothing was written, including no burned sequence number.
        #expect(try context.fetchCount(FetchDescriptor<StoredReceipt>()) == 0)
    }

    @Test("an append naming the same parent twice is refused")
    func duplicateParentIsRefused() async throws {
        let context = try makeContext()
        let store = try makeStore(context: context)
        let parent = try await store.append(draft(kind: "parent"))

        await #expect(throws: ReceiptParentContractError.self) {
            _ = try await store.append(draft(kind: "child", parentReceiptIDs: [parent.id, parent.id]))
        }
        #expect(try context.fetchCount(FetchDescriptor<StoredReceipt>()) == 1)
    }

    /// Several parents, in a stated order that must survive the round trip. Order is part of the
    /// claim, so it is neither sorted nor deduplicated into a set.
    @Test("multiple parents preserve their stated order")
    func multipleParentsPreserveOrder() async throws {
        let context = try makeContext()
        let store = try makeStore(context: context)

        let first = try await store.append(draft(kind: "p1"))
        let second = try await store.append(draft(kind: "p2"))
        let third = try await store.append(draft(kind: "p3"))
        let child = try await store.append(
            draft(kind: "child", parentReceiptIDs: [third.id, first.id, second.id])
        )

        #expect(child.parentReceiptIDs == [third.id, first.id, second.id])
        #expect(try await store.verifyIntegrity().status == .verified)
    }

    /// A parent column edited into a non-canonical spelling of the same IDs changes nothing a reader
    /// sees, which is exactly why it has to be checked: otherwise it is the one part of the
    /// provenance that nothing verifies.
    @Test(
        "a non-canonical parent column is tampering",
        arguments: ["lowercased", "trailingSeparator", "unparseable", "emptyString"]
    )
    func nonCanonicalParentColumnIsTampering(shape: String) async throws {
        let context = try makeContext()
        let store = try makeStore(context: context)
        let parent = try await store.append(draft(kind: "parent"))
        _ = try await store.append(draft(kind: "child", parentReceiptIDs: [parent.id]))

        let rows = try context.fetch(
            FetchDescriptor<StoredReceipt>(sortBy: [SortDescriptor(\StoredReceipt.sequenceID)])
        )
        let row = try #require(rows.last)
        switch shape {
        case "lowercased": row.parentReceiptIDsRawValue = parent.id.uuidString.lowercased()
        case "trailingSeparator": row.parentReceiptIDsRawValue = "\(parent.id.uuidString),"
        case "unparseable": row.parentReceiptIDsRawValue = "not-a-uuid"
        case "emptyString": row.parentReceiptIDsRawValue = ""
        default: Issue.record("unhandled shape \(shape)")
        }
        try context.save()

        let result = try await store.verifyIntegrity()
        #expect(result.status == .tampered, "\(shape): \(result.failureReason ?? "-")")
        #expect(result.failureReason?.contains("non-canonical parent receipt list") == true, "\(shape)")
    }

    /// Duplicates and self-reference written straight into the column, past the append guard. Both
    /// are refused at write time, so a row carrying either has had the column rewritten — and the
    /// chain hash is re-derived here so the *shape* rule is what fires rather than the hash.
    @Test("a parent list that repeats itself is tampering even when the hash agrees")
    func duplicateParentColumnIsTampering() async throws {
        let context = try makeContext()
        let headStore = InMemoryReceiptIntegrityHeadStore()
        let signer = SoftwareReceiptSigner()
        let store = try makeStore(context: context, headStore: headStore, signer: signer)
        let parent = try await store.append(draft(kind: "parent"))
        _ = try await store.append(draft(kind: "child", parentReceiptIDs: [parent.id]))

        let rows = try context.fetch(
            FetchDescriptor<StoredReceipt>(sortBy: [SortDescriptor(\StoredReceipt.sequenceID)])
        )
        let row = try #require(rows.last)
        row.parentReceiptIDsRawValue = ReceiptContributionParents.canonicalRawValue([parent.id, parent.id])
        row.chainHash = try ReceiptIntegrity.chainHash(for: row)
        row.signature = try await signer.sign(row.chainHash).signature.base64EncodedString()
        try context.save()
        await headStore.saveHead(row.chainHash, for: row.accountKey)

        let result = try await store.verifyIntegrity()
        #expect(result.status == .tampered, "\(result.failureReason ?? "-")")
        #expect(result.failureReason?.contains("invalid parent receipt list") == true)
    }

    @Test("a receipt that is its own parent is tampering even when the hash agrees")
    func selfReferencingParentColumnIsTampering() async throws {
        let context = try makeContext()
        let headStore = InMemoryReceiptIntegrityHeadStore()
        let signer = SoftwareReceiptSigner()
        let store = try makeStore(context: context, headStore: headStore, signer: signer)
        _ = try await store.append(draft(kind: "only"))

        let row = try #require(try context.fetch(FetchDescriptor<StoredReceipt>()).first)
        row.parentReceiptIDsRawValue = ReceiptContributionParents.canonicalRawValue([row.id])
        row.chainHash = try ReceiptIntegrity.chainHash(for: row)
        row.signature = try await signer.sign(row.chainHash).signature.base64EncodedString()
        try context.save()
        await headStore.saveHead(row.chainHash, for: row.accountKey)

        let result = try await store.verifyIntegrity()
        #expect(result.status == .tampered, "\(result.failureReason ?? "-")")
        #expect(result.failureReason?.contains("lists itself as its own parent") == true)
    }

    /// A parent that has stopped existing is **unattested, not tampered**, and that asymmetry is the
    /// whole point of the three-state verdict. The child row is intact; what is missing is a receipt,
    /// and the rows cannot say why it is missing. Calling it tampering would cost the person their
    /// export over an ordinary deletion.
    ///
    /// The fixture puts the parent on its **own account** and removes its anchor along with its row,
    /// and both details are load-bearing. Deleting a row from the middle of an account's chain breaks
    /// `accountSequenceID` and `previousReceiptHash`, and leaving the anchor behind trips "protected
    /// heads without persisted receipts" — either way the ledger is genuinely inconsistent and
    /// reports `.tampered` for reasons that have nothing to do with parents. Whole-account deletion
    /// with its anchor is the one shape that leaves every surviving row internally consistent, which
    /// is exactly the scenario this package documents as the hard case for completeness.
    ///
    /// The assertion on the summary is indirect for a reason worth stating. `ReceiptUnattestedSummary`
    /// keeps only the first reason plus a count, and the ledger-wide sequence-gap statement is
    /// deliberately inserted ahead of per-row notes, so the dangling-parent note cannot be the
    /// headline here. In this fixture exactly two reasons are possible — the gap and the dangling
    /// parent — because every surviving row is signed by the current identity and its anchor matches.
    /// So "and 1 more" is proof that the second reason fired.
    @Test("a parent deleted after the fact is unattested, not tampering")
    func deletedParentIsUnattestedNotTampering() async throws {
        let context = try makeContext()
        let headStore = InMemoryReceiptIntegrityHeadStore()
        let store = try makeStore(context: context, headStore: headStore)

        let parent = try await store.append(draft(kind: "parent", accountAddress: Self.accountA))
        _ = try await store.append(
            draft(kind: "child", accountAddress: Self.accountB, parentReceiptIDs: [parent.id])
        )
        #expect(try await store.verifyIntegrity().status == .verified, "the fixture must start clean")

        let parentID = parent.id
        let rows = try context.fetch(
            FetchDescriptor<StoredReceipt>(predicate: #Predicate<StoredReceipt> { $0.id == parentID })
        )
        for row in rows { context.delete(row) }
        try context.save()
        await headStore.clearHead(for: Self.accountA.lowercased())

        let result = try await store.verifyIntegrity()
        #expect(result.status == .unattested, "\(result.failureReason ?? "-")")
        #expect(result.isValid, "an intact row naming a vanished parent must stay exportable")
        #expect(
            result.failureReason?.contains("and 1 more") == true,
            "the dangling-parent note must be among the reasons: \(result.failureReason ?? "-")"
        )
    }

    // MARK: - Backward compatibility

    /// A receipt written before these columns existed has to verify **unchanged**.
    ///
    /// Simulated the way an upgraded install actually looks: a row declaring the pre-provenance
    /// envelope version with every new column absent, re-hashed and re-signed at that version so it
    /// is exactly what the old build would have written. If the addition had rehashed anything, this
    /// reads `.tampered` — which is the outcome the whole versioning mechanism exists to prevent.
    @Test("a receipt written at the previous envelope version still verifies")
    func previousEnvelopeVersionStillVerifies() async throws {
        let context = try makeContext()
        let headStore = InMemoryReceiptIntegrityHeadStore()
        let signer = SoftwareReceiptSigner()
        let store = try makeStore(context: context, headStore: headStore, signer: signer)
        _ = try await store.append(draft(kind: "written-before-phase-1"))

        let row = try #require(try context.fetch(FetchDescriptor<StoredReceipt>()).first)
        row.integrityEnvelopeVersion = ReceiptIntegrityEnvelopeVersion.bindsReceiptID
        row.chainHash = try ReceiptIntegrity.chainHash(for: row)
        row.signature = try await signer.sign(row.chainHash).signature.base64EncodedString()
        try context.save()
        await headStore.saveHead(row.chainHash, for: row.accountKey)

        let result = try await store.verifyIntegrity()
        #expect(result.status == .verified, "\(result.failureReason ?? "-")")
        #expect(row.asReceiptRecord().principal == nil)
        #expect(row.asReceiptRecord().affectedResource == nil)
        #expect(row.asReceiptRecord().parentReceiptIDs == nil)
    }

    /// A ledger that mixes pre- and post-Phase-1 receipts, which is what an upgraded install is for
    /// as long as its history survives. Both rows verify under the envelope each was written with.
    @Test("a ledger mixing both envelope versions verifies")
    func mixedEnvelopeVersionLedgerVerifies() async throws {
        let context = try makeContext()
        let headStore = InMemoryReceiptIntegrityHeadStore()
        let signer = SoftwareReceiptSigner()
        let store = try makeStore(context: context, headStore: headStore, signer: signer)

        _ = try await store.append(draft(kind: "old"))
        let old = try #require(try context.fetch(FetchDescriptor<StoredReceipt>()).first)
        old.integrityEnvelopeVersion = ReceiptIntegrityEnvelopeVersion.bindsReceiptID
        old.chainHash = try ReceiptIntegrity.chainHash(for: old)
        old.signature = try await signer.sign(old.chainHash).signature.base64EncodedString()
        try context.save()
        await headStore.saveHead(old.chainHash, for: old.accountKey)

        _ = try await store.append(
            draft(
                kind: "new",
                affectedResource: ReceiptResourceReference(type: "nft", identifier: "7")
            )
        )

        let rows = try context.fetch(
            FetchDescriptor<StoredReceipt>(sortBy: [SortDescriptor(\StoredReceipt.sequenceID)])
        )
        #expect(rows.map(\.integrityEnvelopeVersion) == [
            ReceiptIntegrityEnvelopeVersion.bindsReceiptID,
            ReceiptIntegrityEnvelopeVersion.bindsContributionProvenance
        ])
        let result = try await store.verifyIntegrity()
        #expect(result.status == .verified, "\(result.failureReason ?? "-")")
    }

    /// An exported record with no stated provenance must carry **none of the new keys**.
    ///
    /// This is the archive-compatibility requirement expressed as bytes. The keys are inside
    /// `recordsHash`, which is inside the signed `manifestHash`, so emitting `"parentReceiptIDs":[]`
    /// or `"principal":null` on every record would change the hash of every archive ever exported and
    /// break its signature — discovered only by whoever next tried to verify one.
    @Test("an exported record with no provenance omits the new keys entirely")
    func exportedRecordOmitsAbsentProvenance() async throws {
        let context = try makeContext()
        let store = try makeStore(context: context)
        _ = try await store.append(draft(kind: "plain"))

        let data = try await store.exportAll()
        let json = try #require(String(data: data, encoding: .utf8))

        for key in ["principal", "affectedResource", "producedResult", "parentReceiptIDs"] {
            #expect(json.contains("\"\(key)\"") == false, "\(key) must be omitted, not encoded as null")
        }
    }

    // MARK: - The archive boundary

    @Test("an archive carrying contribution provenance verifies")
    func archiveWithProvenanceVerifies() async throws {
        let context = try makeContext()
        let store = try makeStore(context: context)
        let parent = try await store.append(draft(kind: "parent"))
        _ = try await store.append(
            draft(
                kind: "child",
                principal: PrincipalID(rawValue: "did:example:alice"),
                affectedResource: ReceiptResourceReference(type: "nft", identifier: "7"),
                producedResult: ReceiptResultReference(type: "artifact", identifier: "report-1"),
                parentReceiptIDs: [parent.id]
            )
        )

        let data = try await store.exportAll()
        let fingerprint = try await store.provenanceTrustAnchor().fingerprint
        let result = try ReceiptProvenanceVerifier.verify(data, trustedSignerFingerprint: fingerprint)

        #expect(result.status == .verified, "\(result.failureReason ?? "-")")

        let archive = try ReceiptCanonicalJSON.decoder().decode(ReceiptProvenanceExport.self, from: data)
        let child = try #require(archive.records.first { $0.trigger == "child" })
        #expect(child.principal?.rawValue == "did:example:alice")
        #expect(child.affectedResource?.identifier == "7")
        #expect(child.producedResult?.type == "artifact")
        #expect(child.parentReceiptIDs == [parent.id])
    }

    /// The same mutation at the boundary that matters most, since an archive reaches a third party
    /// who has no access to the originating store.
    @Test("an exported record whose affected resource was rewritten does not verify")
    func rewrittenExportedResourceDoesNotVerify() async throws {
        let context = try makeContext()
        let store = try makeStore(context: context)
        _ = try await store.append(
            draft(
                kind: "child",
                affectedResource: ReceiptResourceReference(type: "nft", identifier: "7")
            )
        )

        let data = try await store.exportAll()
        let original = try ReceiptCanonicalJSON.decoder().decode(ReceiptProvenanceExport.self, from: data)
        let rewritten = replacingProvenance(
            on: original.records[0],
            affectedResource: ReceiptResourceReference(type: "nft", identifier: "8")
        )
        let (export, fingerprint) = try await rebuiltExport(records: [rewritten], like: original)

        let result = try ReceiptProvenanceVerifier.verify(
            try ReceiptCanonicalJSON.encoder().encode(export),
            trustedSignerFingerprint: fingerprint
        )
        #expect(result.status == .tampered, "\(result.failureReason ?? "-")")
        #expect(result.failureReason?.contains("invalid exported integrity metadata") == true)
    }

    /// Self-reference is the rule that only bites on an archive: the store mints a fresh `UUID` per
    /// append, so it cannot write one, while a hand-built file can claim anything.
    @Test("an exported record that is its own parent does not verify")
    func selfParentingExportedRecordDoesNotVerify() async throws {
        let context = try makeContext()
        let store = try makeStore(context: context)
        _ = try await store.append(draft(kind: "only"))

        let data = try await store.exportAll()
        let original = try ReceiptCanonicalJSON.decoder().decode(ReceiptProvenanceExport.self, from: data)
        let selfParenting = replacingProvenance(
            on: original.records[0],
            parentReceiptIDs: [original.records[0].id]
        )
        let (export, fingerprint) = try await rebuiltExport(records: [selfParenting], like: original)

        let result = try ReceiptProvenanceVerifier.verify(
            try ReceiptCanonicalJSON.encoder().encode(export),
            trustedSignerFingerprint: fingerprint
        )
        #expect(result.status == .tampered, "\(result.failureReason ?? "-")")
        #expect(result.failureReason?.contains("lists itself as its own parent") == true)
    }

    /// A parent the archive does not contain is unattested rather than forged: a partial export of a
    /// longer ledger is a legitimate thing to hold.
    ///
    /// Produced by *removing* the parent record rather than by fabricating a parent id, and that is
    /// the only way to produce it. The parent list is inside the chain hash, so inventing one makes
    /// the record fail its own recomputation and the verdict becomes `.tampered` before the existence
    /// question is ever reached — which is correct, and which means the dangling branch is reachable
    /// only from a genuinely incomplete archive.
    ///
    /// The parent is on its own account so that dropping it leaves the surviving record linking from
    /// genesis exactly as it did; and the summary assertion is indirect for the reason given on
    /// ``deletedParentIsUnattestedNotTampering()``.
    @Test("an exported record naming a parent the archive lacks is unattested")
    func danglingExportedParentIsUnattested() async throws {
        let context = try makeContext()
        let store = try makeStore(context: context)
        let parent = try await store.append(draft(kind: "parent", accountAddress: Self.accountA))
        _ = try await store.append(
            draft(kind: "child", accountAddress: Self.accountB, parentReceiptIDs: [parent.id])
        )

        let data = try await store.exportAll()
        let original = try ReceiptCanonicalJSON.decoder().decode(ReceiptProvenanceExport.self, from: data)
        let child = try #require(original.records.first { $0.trigger == "child" })
        let childHead = try #require(
            original.manifest.chainHeads.first { $0.accountKey == Self.accountB.lowercased() }
        )
        let (export, fingerprint) = try await rebuiltExport(
            records: [child],
            like: original,
            chainHeads: [childHead]
        )

        let result = try ReceiptProvenanceVerifier.verify(
            try ReceiptCanonicalJSON.encoder().encode(export),
            trustedSignerFingerprint: fingerprint
        )
        #expect(result.status == .unattested, "\(result.failureReason ?? "-")")
        #expect(result.isValid, "an incomplete archive of intact receipts must still read")
        // Three reasons are possible in this fixture and all three fire: the ledger-wide sequence
        // gap left by the removed record, the dangling parent, and "not signed by the pinned export
        // identity" — `rebuiltExport` re-signs the manifest with a fresh key, so the record's own
        // signer is not the pinned one. The count is what proves the middle one ran, since the gap
        // statement is deliberately placed ahead of per-row notes and the summary keeps only the
        // first.
        #expect(
            result.failureReason?.contains("and 2 more") == true,
            "the dangling-parent note must be among the reasons: \(result.failureReason ?? "-")"
        )
    }

    // MARK: - The economic boundary

    /// Contribution provenance records what happened. It must never acquire a field that says what
    /// anyone is owed for it — see `OWNERSHIP.md` and `FOUNDERS_COVENANT.md`.
    ///
    /// Checked as a structural scan rather than trusted to review, because the failure is additive:
    /// nobody is going to write `tokensEarned` today, and the risk is a later feature growing one on
    /// the type that already carries "who contributed what" and nobody connecting it to the boundary
    /// this project drew.
    @Test("receipt contracts carry no economic or ownership-share semantics")
    func receiptContractsCarryNoEconomicSemantics() throws {
        let prohibited = [
            "tokensEarned",
            "equityPercentage",
            "ownershipPercentage",
            "financialReward",
            "governanceWeight",
            "vestingSchedule",
            "compensation"
        ]
        let sources = [
            "ReceiptsCore/Sources/ReceiptsCore/Models/ReceiptContracts.swift",
            "ReceiptsCore/Sources/ReceiptsCore/Models/ReceiptContributionProvenance.swift",
            "ReceiptsCore/Sources/ReceiptsCore/Models/ReceiptIntegrity.swift",
            "ReceiptsCore/Sources/ReceiptStorage/StoredReceipt.swift"
        ]
        var offenders: [String] = []

        for relativePath in sources {
            let url = try projectRootURL().appending(path: relativePath)
            let source = try String(contentsOf: url, encoding: .utf8)
            for token in prohibited where source.contains(token) {
                offenders.append("\(relativePath): \(token)")
            }
        }

        #expect(
            offenders.isEmpty,
            "Contribution provenance must not imply ownership, compensation, or governance power: \(offenders.sorted())"
        )
    }

    // MARK: - Helpers

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

    private func draft(
        kind: String,
        accountAddress: String = ReceiptContributionProvenanceTests.accountA,
        principal: PrincipalID? = nil,
        affectedResource: ReceiptResourceReference? = nil,
        producedResult: ReceiptResultReference? = nil,
        parentReceiptIDs: [UUID] = []
    ) -> ReceiptDraft {
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
            principal: principal,
            affectedResource: affectedResource,
            producedResult: producedResult,
            parentReceiptIDs: parentReceiptIDs,
            details: ReceiptPayload(values: [:])
        )
    }

    /// One record with its provenance replaced and everything else — `chainHash` included — copied
    /// verbatim, which is what makes the recomputation the thing under test.
    private func replacingProvenance(
        on record: ReceiptRecord,
        principal: PrincipalID? = nil,
        affectedResource: ReceiptResourceReference? = nil,
        producedResult: ReceiptResultReference? = nil,
        parentReceiptIDs: [UUID]? = nil
    ) -> ReceiptRecord {
        ReceiptRecord(
            id: record.id,
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
            actorRawValue: record.actorRawValue,
            modeRawValue: record.modeRawValue,
            principal: principal ?? record.principal,
            affectedResource: affectedResource ?? record.affectedResource,
            producedResult: producedResult ?? record.producedResult,
            parentReceiptIDs: parentReceiptIDs ?? record.parentReceiptIDs,
            details: record.details
        )
    }

    /// Re-signs a hand-built record set with a fresh identity whose fingerprint the caller pins, so
    /// the manifest and trust-anchor checks all pass and the per-record check is the only thing left
    /// that can fail.
    private func rebuiltExport(
        records: [ReceiptRecord],
        like original: ReceiptProvenanceExport,
        chainHeads: [ReceiptProvenanceChainHead]? = nil
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
            chainHeads: chainHeads ?? original.manifest.chainHeads,
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

    private func projectRootURL(filePath: String = #filePath) throws -> URL {
        var candidate = URL(fileURLWithPath: filePath).deletingLastPathComponent()
        while candidate.path != "/" {
            if FileManager.default.fileExists(atPath: candidate.appending(path: "Auralis.xcodeproj").path()) {
                return candidate
            }
            candidate.deleteLastPathComponent()
        }
        Issue.record("Unable to locate project root from \(filePath)")
        throw CocoaError(.fileNoSuchFile)
    }
}
