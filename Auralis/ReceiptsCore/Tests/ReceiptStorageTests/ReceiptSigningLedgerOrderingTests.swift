import AuralisPrimaryModels
import CryptoKit
import Foundation
import ReceiptsCore
@testable import ReceiptStorage
import RuntimeCore
import SwiftData
import Testing

/// The **ledger-wide** half of the forward-only signing rule, and the injection hole its absence left.
///
/// `ReceiptSigningProgression` enforces "signing may only move forward" per *account*, which is all a
/// single row can support. That left an attacker holding write access to the row store **alone** — no
/// signing key, no Keychain — able to invent a brand-new `accountKey`, chain a fabricated receipt off
/// the genesis hash with correct unkeyed hashes and no signature, and have it read as the legitimate
/// pre-signing prefix: no signed predecessor on that account to regress from, and a missing anchor for
/// an account this device never wrote is only an unattested *reason*, never a verdict. The verdict was
/// `.unattested`, worded identically to an honestly upgraded install, and `isValid` accepts
/// `.unattested`, so the fabricated row travelled inside the signed archive too.
///
/// That is a larger claim than this package concedes. ``ReceiptIntegrityVerificationResult/isValid``
/// deliberately accepts an attacker who can write *both* stores and therefore rewrite history that is
/// already there; *injecting events that never happened* with store access only is a different thing.
///
/// What closes it is `sequenceID`: allocated globally and monotonically, and an append that cannot
/// sign does not write at all — so on an honest ledger every unsigned row precedes every signed one
/// ledger-wide, not merely per account. These tests pin both directions of that: the injection is
/// tampering, and the honest shapes that produce unsigned or other-identity rows are untouched.
@MainActor
struct ReceiptSigningLedgerOrderingTests {
    private static let accountA = "0x1111111111111111111111111111111111111111"
    private static let fabricatedAccount = "0x9999999999999999999999999999999999999999"

    // MARK: - The injection

    /// The confirmed hole, from the attacker's side: store writes only.
    @Test("a fabricated unsigned account injected above the signed rows is tampering")
    func injectedUnsignedAccountAboveSignedRowsIsTampering() async throws {
        let context = try makeContext()
        let headStore = InMemoryReceiptIntegrityHeadStore()
        let store = try makeStore(context: context, headStore: headStore)

        for index in 0..<3 {
            _ = try await store.append(draft(kind: "a-\(index)"))
        }
        #expect(try await store.verifyIntegrity().status == .verified)

        // Everything the attacker can do with SwiftData write access and nothing else: a new account,
        // a genesis link, both unkeyed hashes computed correctly, and no signature because they hold
        // no key. Sequence 4, because 1...3 are taken and the mark forbids reuse anyway.
        try insertFabricatedUnsignedRow(
            into: context,
            sequenceID: 4,
            summary: "FORGED: user approved unlimited spend"
        )

        let result = try await store.verifyIntegrity()
        #expect(result.status == .tampered, "\(result.failureReason ?? "-")")
        #expect(result.isValid == false)
        #expect(
            result.failureReason?.contains("carries no signing metadata but sits at ledger position 4") == true,
            "\(result.failureReason ?? "-")"
        )
        // Not reported as an honest upgrade, which is how it used to read.
        #expect(result.failureReason?.contains("predates receipt signing") == false)

        // And the consequence that made it worth a verdict rather than a note: the fabricated row can
        // no longer reach a signed archive. `exportAll()` is gated on `isValid`, which `.unattested`
        // satisfied.
        await #expect(throws: ReceiptProvenanceExportError.self) {
            _ = try await store.exportAll()
        }
    }

    /// The same rule in the export verifier, which is the half a third party runs.
    ///
    /// Held to the same standard as the live store on purpose, and not because a lone store-writing
    /// attacker can reach it — `exportAll()` now refuses, so they cannot. It is here because the two
    /// halves of this package have already drifted on exactly this rule once (see
    /// ``ReceiptSigningMetadata``), and a divergence surfaces at the worst place available: an honest
    /// archive called forged, or a forged one accepted by whichever half a reader happens to run.
    @Test("the export verifier applies the same ledger-wide rule to an archive")
    func exportVerifierRejectsAnUnsignedRecordAboveASignedOne() async throws {
        let context = try makeContext()
        let signer = SoftwareReceiptSigner()
        let store = try makeStore(
            context: context,
            headStore: InMemoryReceiptIntegrityHeadStore(),
            signer: signer
        )
        let anchor = try await store.provenanceTrustAnchor()

        _ = try await store.append(draft(kind: "a-0"))
        let honest = try ReceiptCanonicalJSON.decoder().decode(
            ReceiptProvenanceExport.self,
            from: try await store.exportAll()
        )
        #expect(
            try ReceiptProvenanceVerifier.verify(
                try canonicalData(honest),
                trustedSignerFingerprint: anchor.fingerprint
            ).status == .verified
        )

        // The archive an exporter would have written had the store check not caught the injection:
        // everything self-consistent and the manifest correctly signed, with one unsigned fabricated
        // record sitting above the signed one.
        let fabricated = fabricatedRecord(sequenceID: 2)
        let archive = try await signedArchive(
            records: honest.records + [fabricated],
            signedBy: signer,
            trustAnchor: anchor
        )

        let result = try ReceiptProvenanceVerifier.verify(
            archive,
            trustedSignerFingerprint: anchor.fingerprint
        )
        #expect(result.status == .tampered, "\(result.failureReason ?? "-")")
        #expect(
            result.failureReason?.contains("carries no signing metadata") == true,
            "\(result.failureReason ?? "-")"
        )
    }

    /// The archive twin of the store's replay check, which had no coverage at all until this existed.
    ///
    /// Proven missing rather than assumed: with this test absent, deleting the verifier's uniqueness
    /// guard entirely left the whole suite green — while the sibling ordering rule *did* have a
    /// verifier-side test. That asymmetry is exactly how the two halves of this package drifted on the
    /// signing rule once before, and the file's own header records that the divergence surfaced as an
    /// honest archive being called forged.
    @Test("the export verifier rejects a record that repeats another record's chain hash")
    func exportVerifierRejectsARepeatedChainHash() async throws {
        let context = try makeContext()
        let signer = SoftwareReceiptSigner()
        let store = try makeStore(
            context: context,
            headStore: InMemoryReceiptIntegrityHeadStore(),
            signer: signer
        )
        let anchor = try await store.provenanceTrustAnchor()

        _ = try await store.append(draft(kind: "a-0"))
        let honest = try ReceiptCanonicalJSON.decoder().decode(
            ReceiptProvenanceExport.self,
            from: try await store.exportAll()
        )
        let donor = try #require(honest.records.first)

        // A fabricated record on a fresh account carrying the donor's chain hash *and* the signature
        // that covers it — the replay, which needs no key — and a version column raised so no
        // verifier recomputes the hash and notices.
        let details = ReceiptPayload(values: [:])
        let replayed = ReceiptRecord(
            id: UUID(),
            sequenceID: 2,
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
            accountAddress: Self.fabricatedAccount,
            chainRawValue: nil,
            accountSequenceID: 1,
            payloadHash: try ReceiptIntegrity.payloadHash(for: details),
            previousReceiptHash: ReceiptIntegrity.genesisHash,
            chainHash: donor.chainHash,
            signature: donor.signature,
            signerPublicKey: donor.signerPublicKey,
            integrityEnvelopeVersion: ReceiptIntegrityEnvelopeVersion.current + 1,
            details: details
        )
        let archive = try await signedArchive(
            records: honest.records + [replayed],
            signedBy: signer,
            trustAnchor: anchor
        )

        let result = try ReceiptProvenanceVerifier.verify(
            archive,
            trustedSignerFingerprint: anchor.fingerprint
        )
        #expect(result.status == .tampered, "\(result.failureReason ?? "-")")
        #expect(
            result.failureReason?.contains("repeats another receipt's chain hash") == true,
            "\(result.failureReason ?? "-")"
        )
    }

    // MARK: - The honest shapes the rule must not touch

    /// The upgrade case, which is the whole reason the unsigned prefix is tolerated at all.
    ///
    /// The rule is drawn ledger-wide, so this is the shape most at risk from it: if it were drawn even
    /// slightly wrong — on identity rather than on the unsigned/signed boundary, or with a
    /// non-strict comparison — an install that predates signing would read `.tampered`, and because
    /// `exportAll()` refuses on `.tampered` the only recovery on offer would be destroying the
    /// history.
    @Test("an unsigned prefix below the signed rows stays unattested")
    func unsignedPrefixBelowSignedRowsStaysUnattested() async throws {
        let context = try makeContext()
        let headStore = InMemoryReceiptIntegrityHeadStore()
        let store = try makeStore(context: context, headStore: headStore)

        // Rows 1 and 2 become the pre-signing prefix, and the signed row is appended *after* they are
        // stripped so the store links and signs it over their real hashes. Stripping a row changes its
        // chain hash, so re-linking a later signed row onto it by hand would invalidate that row's own
        // signature — a broken fixture that the signature check catches before this rule is reached.
        for index in 0..<2 {
            _ = try await store.append(draft(kind: "legacy-\(index)"))
        }
        let legacy = try context.fetch(
            FetchDescriptor<StoredReceipt>(sortBy: [SortDescriptor(\StoredReceipt.sequenceID)])
        )
        #expect(legacy.count == 2)
        for row in legacy {
            row.signature = nil
            row.signerPublicKey = nil
        }
        try relinkChain(legacy, in: context)
        _ = try await store.append(draft(kind: "signed"))

        let result = try await store.verifyIntegrity()
        #expect(result.status == .unattested, "\(result.failureReason ?? "-")")
        #expect(result.isValid, "an upgraded ledger must not read as tampered with")
        #expect(result.failureReason?.contains("predates receipt signing") == true)
        // Still exportable, which is the property the whole trichotomy exists to preserve.
        #expect(try await store.exportAll().isEmpty == false)
    }

    /// A key rotation, which is why the boundary is unsigned/signed rather than
    /// signed-by-the-current-identity.
    ///
    /// `DeviceReceiptSigner.secureEnclaveSigner()` rotates when it writes off an unrestorable Enclave
    /// blob, and the rows it signed before then remain — *validly signed*, by a key this device no
    /// longer holds. Those sit above rows the current identity never signed and below rows it did, in
    /// any order. Had the rule counted "not signed by the reference identity" as unsigned, an ordinary
    /// rotation would have read as tampering.
    @Test("rows signed by a previous identity are not treated as unsigned")
    func rotatedIdentityRowsAreNotTreatedAsUnsigned() async throws {
        let context = try makeContext()
        let headStore = InMemoryReceiptIntegrityHeadStore()
        let signer = RotatingSigner()
        let store = try makeStore(context: context, headStore: headStore, signer: signer)

        // One genuinely unsigned row at the bottom (the upgrade prefix), then the old identity, then
        // the rotated one — every boundary this rule looks at, in one ledger.
        _ = try await store.append(draft(kind: "legacy"))
        let legacy = try #require(
            try context.fetch(
                FetchDescriptor<StoredReceipt>(sortBy: [SortDescriptor(\StoredReceipt.sequenceID)])
            ).first
        )
        legacy.signature = nil
        legacy.signerPublicKey = nil
        legacy.chainHash = try ReceiptIntegrity.chainHash(for: legacy)
        try context.save()

        _ = try await store.append(draft(kind: "old-identity"))
        await signer.rotate()
        _ = try await store.append(draft(kind: "new-identity"))

        let result = try await store.verifyIntegrity()
        #expect(result.status == .unattested, "\(result.failureReason ?? "-")")
        #expect(result.isValid, "a rotated signing identity is not tampering")
        #expect(try await store.exportAll().isEmpty == false)
    }

    /// The comparison is strict, so a row *level with* the lowest signed row does not trip it — and
    /// that is the boundary where the rule hands off rather than a gap in it.
    ///
    /// Duplicates are reported by ``ReceiptIntegrity/sequenceGapReasons(sequenceIDs:)`` as
    /// `.unattested`, deliberately: a pre-serialization build could allocate one sequence ID twice
    /// under concurrent appends, so a ledger nobody touched can carry a duplicate, and promoting that
    /// to `.tampered` would make those installs unexportable. This test pins where the residual noted
    /// on ``ReceiptSigningLedgerOrdering`` actually lands: the attacker's best remaining placement
    /// still costs them a duplicate-sequence reason and an anchorless account, not silence.
    @Test("an unsigned row level with the lowest signed row is unattested, not tampering")
    func unsignedRowLevelWithTheLowestSignedRowIsUnattested() async throws {
        let context = try makeContext()
        let store = try makeStore(context: context, headStore: InMemoryReceiptIntegrityHeadStore())

        _ = try await store.append(draft(kind: "a-0"))
        _ = try await store.append(draft(kind: "a-1"))

        // Sequence 1 twice: level with the *lowest* signed row, which is the only placement the strict
        // comparison lets through. Anywhere above it — including sequence 2 — is tampering.
        try insertFabricatedUnsignedRow(into: context, sequenceID: 1, summary: "Level")

        let result = try await store.verifyIntegrity()
        #expect(result.status == .unattested, "\(result.failureReason ?? "-")")
        #expect(
            result.failureReason?.contains("duplicate sequence numbers") == true,
            "\(result.failureReason ?? "-")"
        )
    }

    /// The residual, pinned as a test because it is a load-bearing *claim* rather than an oversight.
    ///
    /// ``ReceiptSigningLedgerOrdering`` documents that a fabricated unsigned row can still be placed
    /// *below* every signed row, and that placing it there costs the attacker a row-derived reason
    /// instead of silence. That claim had no coverage: only the duplicate-sequence placement was
    /// tested, not the non-positive one. A claim about what an attacker can still do is worth pinning
    /// in both directions — it must stay reachable (so the documentation is honest) and it must stay
    /// *reported* (so it never quietly becomes `.verified`).
    @Test("a fabricated row below every signed row is reported, not silently verified")
    func injectedRowBelowEverySignedRowIsReported() async throws {
        let context = try makeContext()
        let headStore = InMemoryReceiptIntegrityHeadStore()
        let store = try makeStore(context: context, headStore: headStore)

        for index in 0..<2 {
            _ = try await store.append(draft(kind: "a-\(index)"))
        }
        #expect(try await store.verifyIntegrity().status == .verified)

        // Below the lowest signed row, which on a ledger with no freed IDs means non-positive.
        try insertFabricatedUnsignedRow(into: context, sequenceID: 0, summary: "FORGED")

        let result = try await store.verifyIntegrity()
        // Not `.verified`, which is the part that matters.
        #expect(result.status == .unattested, "\(result.failureReason ?? "-")")
        #expect(
            result.failureReason?.contains("could not have issued") == true,
            "\(result.failureReason ?? "-")"
        )
        // And the residual is stated honestly: `.unattested` satisfies `isValid`, so this ledger does
        // still export. Closing that needs an external witness the package does not keep — if this
        // assertion ever flips, the documented threat model on `ReceiptSigningLedgerOrdering` and
        // `ReceiptIntegrityVerificationResult.isValid` needs updating with it.
        #expect(result.isValid)
    }

    // MARK: - Helpers

    private func makeContext() throws -> ModelContext {
        try ReceiptStorageTestModelContainers.context()
    }

    private func makeStore(
        context: ModelContext,
        headStore: any ReceiptIntegrityHeadStoring,
        signer: any ReceiptSigning = SoftwareReceiptSigner()
    ) throws -> ReceiptPersistenceStore {
        ReceiptPersistenceStore(
            modelContainer: context.container,
            integrityHeadStore: headStore,
            signer: signer
        )
    }

    private func draft(kind: String, account: String? = nil) -> ReceiptDraft {
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
            timelineAccountAddress: account ?? Self.accountA,
            timelineChainRawValue: nil,
            details: ReceiptPayload(values: [:])
        )
    }

    /// A row built with exactly the capability the threat model grants the attacker: SwiftData writes,
    /// no signing key, no Keychain. Both unkeyed hashes are therefore correct — that is the point.
    private func insertFabricatedUnsignedRow(
        into context: ModelContext,
        sequenceID: Int,
        summary: String
    ) throws {
        let details = ReceiptPayload(values: [:])
        let row = try StoredReceipt(
            sequenceID: sequenceID,
            createdAt: Date(timeIntervalSince1970: 100),
            actor: .system,
            actorDetail: .system,
            authorityDetail: nil,
            mode: .observe,
            trigger: "injected",
            scope: "accounts",
            summary: summary,
            provenance: "attacker",
            isSuccess: true,
            correlationID: nil,
            timelineAccountAddress: Self.fabricatedAccount,
            timelineChainRawValue: nil,
            accountSequenceID: 1,
            payloadHash: try ReceiptIntegrity.payloadHash(for: details),
            previousReceiptHash: ReceiptIntegrity.genesisHash,
            // Placeholder: the real value needs the row itself, and every other column is already set.
            chainHash: "",
            details: details
        )
        row.chainHash = try ReceiptIntegrity.chainHash(for: row)
        context.insert(row)
        try context.save()
    }

    /// The record form of the same fabricated row, for the archive half.
    private func fabricatedRecord(sequenceID: Int) -> ReceiptRecord {
        let details = ReceiptPayload(values: [:])
        let payloadHash = (try? ReceiptIntegrity.payloadHash(for: details)) ?? ""
        let id = UUID()
        let chainHash = (
            try? ReceiptIntegrity.chainHash(
                receiptID: id,
                sequenceID: sequenceID,
                accountSequenceID: 1,
                createdAt: Date(timeIntervalSince1970: 100),
                actorRawValue: ReceiptActor.system.rawValue,
                actorColumns: ReceiptActorColumns(ReceiptActorDetail.system),
                authorityColumns: ReceiptAuthorityColumns(nil),
                contributionColumns: .unattributed,
                modeRawValue: ReceiptMode.observe.rawValue,
                trigger: "injected",
                scope: "accounts",
                summary: "FORGED",
                provenance: "attacker",
                isSuccess: true,
                correlationID: nil,
                accountAddress: Self.fabricatedAccount,
                chainRawValue: nil,
                payloadHash: payloadHash,
                signerPublicKey: nil,
                previousReceiptHash: ReceiptIntegrity.genesisHash
            )
        ) ?? ""
        return ReceiptRecord(
            id: id,
            sequenceID: sequenceID,
            createdAt: Date(timeIntervalSince1970: 100),
            actor: .system,
            actorDetail: .system,
            authorityDetail: nil,
            mode: .observe,
            trigger: "injected",
            scope: "accounts",
            summary: "FORGED",
            provenance: "attacker",
            isSuccess: true,
            correlationID: nil,
            accountAddress: Self.fabricatedAccount,
            chainRawValue: nil,
            accountSequenceID: 1,
            payloadHash: payloadHash,
            previousReceiptHash: ReceiptIntegrity.genesisHash,
            chainHash: chainHash,
            signature: nil,
            signerPublicKey: nil,
            integrityEnvelopeVersion: ReceiptIntegrityEnvelopeVersion.current,
            details: details
        )
    }

    /// Re-links a mutated run of rows so the chain stays consistent, which is what makes the fixture a
    /// migration artefact rather than a broken chain the earlier checks would catch first.
    private func relinkChain(_ rows: [StoredReceipt], in context: ModelContext) throws {
        var previousHash = ReceiptIntegrity.genesisHash
        for row in rows {
            row.previousReceiptHash = previousHash
            row.chainHash = try ReceiptIntegrity.chainHash(for: row)
            previousHash = row.chainHash
        }
        try context.save()
    }

    private func signedArchive(
        records: [ReceiptRecord],
        signedBy signer: SoftwareReceiptSigner,
        trustAnchor: ReceiptProvenanceTrustAnchor
    ) async throws -> Data {
        let heads = Dictionary(
            grouping: records,
            by: { ReceiptIntegrity.accountKey(accountAddress: $0.accountAddress) }
        ).compactMap { accountKey, grouped -> ReceiptProvenanceChainHead? in
            guard let head = grouped.max(by: { $0.accountSequenceID < $1.accountSequenceID }) else {
                return nil
            }
            return ReceiptProvenanceChainHead(
                accountKey: accountKey,
                accountSequenceID: head.accountSequenceID,
                chainHash: head.chainHash
            )
        }.sorted { $0.accountKey < $1.accountKey }

        let manifest = ReceiptProvenanceManifest(
            recordCount: records.count,
            recordsHash: ReceiptIntegrity.sha256Hex(try canonicalData(records)),
            chainHeads: heads
        )
        let manifestHash = ReceiptIntegrity.sha256Hex(try canonicalData(manifest))
        let manifestSignature = try await signer.sign(manifestHash)
        return try canonicalData(
            ReceiptProvenanceExport(
                records: records,
                manifest: manifest,
                manifestHash: manifestHash,
                manifestSignature: manifestSignature.signature.base64EncodedString(),
                trustAnchor: trustAnchor
            )
        )
    }

    private func canonicalData<Value: Encodable>(_ value: Value) throws -> Data {
        try ReceiptIntegrity.canonicalData(value)
    }
}
