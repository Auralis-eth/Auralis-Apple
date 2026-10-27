import CryptoKit
import Foundation
@testable import AuralisReceipts
import AuralisRuntime
import SwiftData
import Testing

/// The two things column-by-column tests cannot do: notice a *new* column, and notice that the byte
/// format shifted under everyone.
///
/// Both gaps are the reason the original defects existed. `id` and five authority columns sat outside
/// the hash because nothing enumerated the columns and asked; and the format's central claim — that a
/// third party can verify a receipt sequence without trusting Auralis — had no conformance target, so
/// "canonical" was only as pinned as whoever last read `ReceiptCanonicalJSON`.
@MainActor
struct ReceiptEnvelopeSpecificationTests {
    // MARK: - Every persisted column is accounted for

    /// Bound into the hashed envelope, so editing any of them changes `chainHash`.
    private static let envelopeBoundColumns: Set<String> = [
        "id",
        "integrityEnvelopeVersion",
        "sequenceID",
        "accountSequenceID",
        "createdAt",
        "actorRawValue",
        "actorKindRawValue",
        "actorIdentifier",
        "actorDisplayName",
        "actorInferenceLocalityRawValue",
        "actorInferenceProvider",
        "actorInferenceModelClass",
        "authoritySourceRawValue",
        "authorityLeaseID",
        "authorityCapabilityRawValue",
        "authorityScopeRawValue",
        "authorityReason",
        "authorityExpiresAt",
        "modeRawValue",
        "trigger",
        "scope",
        "summary",
        "provenance",
        "isSuccess",
        "correlationID",
        "accountAddress",
        "chainRawValue",
        "payloadHash",
        "signerPublicKey",
        "previousReceiptHash",
        // Phase 1 contribution provenance. Bound from
        // `ReceiptIntegrityEnvelopeVersion.bindsContributionProvenance`, and hashed whenever present
        // at any declared version — see that symbol for why they are deliberately not gated on the
        // version column the way `id` is.
        "principalIDRawValue",
        "affectedResourceType",
        "affectedResourceIdentifier",
        "producedResultType",
        "producedResultIdentifier",
        "parentReceiptIDsRawValue"
    ]

    /// Not in the envelope, and each with a stated reason it does not need to be. Adding an entry
    /// here is a deliberate act; the reason has to hold.
    private static let independentlyCheckedColumns: [String: String] = [
        // A pure function of `accountAddress`, which *is* hashed, and re-derived and compared on
        // every verification pass (`performVerifyIntegrity`). Editing it is editing a cache.
        "accountKey": "re-derived from the hashed accountAddress and compared",
        // The hash itself. Recomputed from the row's own columns and compared.
        "chainHash": "recomputed and compared — it is the hash",
        // Verified as a P-256 signature over `chainHash`, whose envelope commits to the signer key,
        // so neither the signature nor the key can be substituted independently.
        "signature": "P-256 verified over the chain hash",
        // Covered by `payloadHash`, which is in the envelope: the blob is decoded, re-hashed, and
        // compared. Also why a corrupt blob is a verdict rather than a thrown error.
        "detailsData": "decoded and re-hashed against the envelope-bound payloadHash"
    ]

    /// Fails when a column is added to ``StoredReceipt`` without a decision about the hash.
    ///
    /// This is the test that would have caught the original defects. Column-by-column assertions all
    /// pass while a *new* unhashed column sits next to them, which is exactly how `id` and five
    /// authority columns were missed — so this enumerates the model instead of trusting a list
    /// somebody remembered to extend.
    @Test("every persisted column is either envelope-bound or explicitly exempted")
    func everyPersistedColumnIsAccountedFor() throws {
        let row = try makeRow()
        // SwiftData's `@Model` macro adds the stored properties under a leading underscore, plus two
        // members of its own that are not persisted state.
        let persisted = Set(
            Mirror(reflecting: row).children
                .compactMap(\.label)
                .filter { !$0.hasPrefix("_$") }
                .map { String($0.dropFirst()) }
        )

        let accountedFor = Self.envelopeBoundColumns.union(Self.independentlyCheckedColumns.keys)

        let unaccounted = persisted.subtracting(accountedFor)
        #expect(
            unaccounted.isEmpty,
            """
            New persisted column(s) on StoredReceipt with no integrity decision: \
            \(unaccounted.sorted().joined(separator: ", ")).
            Either bind it into ReceiptIntegrityEnvelope and add it to envelopeBoundColumns, or add it \
            to independentlyCheckedColumns with the reason it does not need to be hashed. A column no \
            check reads is a column an attacker can rewrite while the ledger reports .verified.
            """
        )

        // The other direction, so the lists cannot rot into describing columns that no longer exist.
        let stale = accountedFor.subtracting(persisted)
        #expect(stale.isEmpty, "these columns no longer exist: \(stale.sorted().joined(separator: ", "))")
    }

    /// The exemption list is only as good as its reasons, so the two that are mechanically checkable
    /// are checked here rather than taken on trust.
    @Test("the exempted columns really are checked by something")
    func exemptedColumnsAreActuallyChecked() async throws {
        let context = try ReceiptStorageTestModelContainers.context()
        let store = ReceiptPersistenceStore(
            modelContainer: context.container,
            integrityHeadStore: InMemoryReceiptIntegrityHeadStore(),
            signer: SoftwareReceiptSigner()
        )
        _ = try await store.append(
            ReceiptDraft(
                createdAt: Date(timeIntervalSince1970: 100),
                actorDetail: .system,
                authorityDetail: nil,
                trigger: "t",
                scope: "accounts",
                summary: "Fixture",
                provenance: "test",
                isSuccess: true,
                correlationID: nil,
                timelineAccountAddress: "0x1111111111111111111111111111111111111111",
                timelineChainRawValue: nil,
                details: ReceiptPayload(values: [:])
            )
        )

        // accountKey: re-derived and compared.
        let row = try #require(try context.fetch(FetchDescriptor<StoredReceipt>()).first)
        row.accountKey = "0x9999999999999999999999999999999999999999"
        try context.save()
        let editedKey = try await store.verifyIntegrity()
        #expect(editedKey.status == .tampered, "\(editedKey.failureReason ?? "-")")
        #expect(editedKey.failureReason?.contains("invalid account key") == true)
        row.accountKey = row.derivedAccountKey
        try context.save()
        #expect(try await store.verifyIntegrity().status == .verified)

        // detailsData: decoded and re-hashed against the envelope-bound payloadHash.
        row.replaceDetailsDataForTesting(Data(#"{"values":{"forged":{"string":"x"}}}"#.utf8))
        try context.save()
        let editedPayload = try await store.verifyIntegrity()
        #expect(editedPayload.status == .tampered, "\(editedPayload.failureReason ?? "-")")
        #expect(editedPayload.failureReason?.contains("invalid payload hash") == true)
    }

    // MARK: - The byte format, pinned

    /// Golden vectors for the chain hash, one per envelope version.
    ///
    /// The format's whole point is that "a third party can confirm the sequence without trusting
    /// Auralis", and nothing gave such a party a conformance target or protected against a Foundation
    /// change silently altering every hash in the ledger. If one of these values shifts, either the
    /// envelope changed — in which case ``ReceiptIntegrityEnvelopeVersion`` must be bumped and every
    /// existing row keeps verifying under its own version — or the encoder drifted, which is a format
    /// break.
    ///
    /// **The v1 vector is the no-rehash proof and must never change.** It is the value this test
    /// published before Phase 1 added the contribution-provenance columns, asserted here against an
    /// explicit `envelopeVersion: bindsReceiptID` rather than against `current`. Every receipt written
    /// before those columns existed declares v1 and carries none of them, so if this vector still
    /// holds, no row already on disk was rehashed by the addition — which is the compatibility
    /// requirement, stated as bytes instead of as prose.
    ///
    /// The v2 vector is the same receipt with the version bumped and still no provenance stated. It
    /// differs from v1 only because the version is itself inside the envelope, which is what stops a
    /// v2 row being downgraded to v1 to re-admit a weaker check.
    @Test(
        "the chain hash of a fixed receipt matches its published vector",
        arguments: [
            (ReceiptIntegrityEnvelopeVersion.bindsReceiptID, "167f5da98ecebe5069c2008655d26de5142b01274b4c686593250c5c05f0b752"),
            (ReceiptIntegrityEnvelopeVersion.bindsContributionProvenance, "b0921a90320979e0aa86dd74ecb807ee01233e6917beebf034e6212bb0d0cad9")
        ]
    )
    func chainHashGoldenVector(envelopeVersion: Int, expected: String) throws {
        #expect(try Self.goldenVectorHash(envelopeVersion: envelopeVersion, contributionColumns: .unattributed) == expected)
    }

    /// The same receipt with every contribution-provenance column populated, so the *content* of the
    /// new fields is pinned and not just their absence.
    ///
    /// Without this, the v2 vector above would be satisfied by an envelope that bumped the version and
    /// then dropped the provenance on the floor — which is exactly the defect the authority columns
    /// once had, and the reason this file enumerates columns rather than trusting a list.
    @Test("the chain hash binds the contribution-provenance columns")
    func chainHashBindsContributionProvenance() throws {
        let stated = try Self.goldenVectorHash(
            envelopeVersion: ReceiptIntegrityEnvelopeVersion.bindsContributionProvenance,
            contributionColumns: ReceiptContributionColumns(
                principalID: "did:example:principal",
                affectedResourceType: "nft",
                affectedResourceIdentifier: "eip155:1/erc721:0xabc/7",
                producedResultType: "artifact",
                producedResultIdentifier: "22222222-3333-4444-5555-666666666666",
                parentReceiptIDs: "33333333-4444-5555-6666-777777777777"
            )
        )

        #expect(stated == "4d03e3b037241df02d65bda5310ffbf5c1436e1fea8cff1f9cf6eaf138918ade")
    }

    /// Each of the six columns on its own, because a single combined vector cannot tell "all six are
    /// hashed" from "one of them is hashed and the other five are not".
    ///
    /// This is the per-column half of the same discipline
    /// ``everyPersistedColumnIsAccountedFor()`` applies structurally, and it is the test that would
    /// have caught the five authority columns sitting outside the envelope.
    @Test("each contribution-provenance column changes the chain hash on its own")
    func eachContributionColumnIsHashedIndependently() throws {
        let version = ReceiptIntegrityEnvelopeVersion.bindsContributionProvenance
        let baseline = try Self.goldenVectorHash(envelopeVersion: version, contributionColumns: .unattributed)
        let variants: [(String, ReceiptContributionColumns)] = [
            ("principalID", ReceiptContributionColumns(principalID: "p", affectedResourceType: nil, affectedResourceIdentifier: nil, producedResultType: nil, producedResultIdentifier: nil, parentReceiptIDs: nil)),
            ("affectedResourceType", ReceiptContributionColumns(principalID: nil, affectedResourceType: "t", affectedResourceIdentifier: nil, producedResultType: nil, producedResultIdentifier: nil, parentReceiptIDs: nil)),
            ("affectedResourceIdentifier", ReceiptContributionColumns(principalID: nil, affectedResourceType: nil, affectedResourceIdentifier: "i", producedResultType: nil, producedResultIdentifier: nil, parentReceiptIDs: nil)),
            ("producedResultType", ReceiptContributionColumns(principalID: nil, affectedResourceType: nil, affectedResourceIdentifier: nil, producedResultType: "t", producedResultIdentifier: nil, parentReceiptIDs: nil)),
            ("producedResultIdentifier", ReceiptContributionColumns(principalID: nil, affectedResourceType: nil, affectedResourceIdentifier: nil, producedResultType: nil, producedResultIdentifier: "i", parentReceiptIDs: nil)),
            ("parentReceiptIDs", ReceiptContributionColumns(principalID: nil, affectedResourceType: nil, affectedResourceIdentifier: nil, producedResultType: nil, producedResultIdentifier: nil, parentReceiptIDs: "33333333-4444-5555-6666-777777777777"))
        ]
        var hashes: Set<String> = [baseline]

        for (column, columns) in variants {
            let hash = try Self.goldenVectorHash(envelopeVersion: version, contributionColumns: columns)
            #expect(hash != baseline, "\(column) is unhashed")
            #expect(hashes.insert(hash).inserted, "\(column) collides with another column's hash")
        }
    }

    /// A half-written reference must not vanish from the envelope.
    ///
    /// This is the property ``ReceiptContributionColumns`` exists for. Hashing the composed
    /// `ReceiptResourceReference?` instead would reconstruct `nil` from a type with no identifier, so
    /// *both* columns would drop out and a fabricated type could be written into a row without
    /// changing its chain hash — the identical defect the authority columns had before they were
    /// passed as columns.
    @Test("a half-written reference is still hashed")
    func halfWrittenReferenceIsStillHashed() throws {
        let version = ReceiptIntegrityEnvelopeVersion.bindsContributionProvenance
        let absent = try Self.goldenVectorHash(envelopeVersion: version, contributionColumns: .unattributed)
        let typeOnly = try Self.goldenVectorHash(
            envelopeVersion: version,
            contributionColumns: ReceiptContributionColumns(
                principalID: nil,
                affectedResourceType: "nft",
                affectedResourceIdentifier: nil,
                producedResultType: nil,
                producedResultIdentifier: nil,
                parentReceiptIDs: nil
            )
        )

        #expect(typeOnly != absent)
    }

    /// An empty parent list and no parent list are the same claim, so they must hash the same.
    ///
    /// Pinned because the two spellings arrive from different places — a draft defaults to `[]`, a
    /// legacy row has `nil` — and letting them diverge would mean two receipts asserting "no stated
    /// cause" carried different chain hashes.
    @Test("an empty parent list hashes identically to no parent list")
    func emptyParentListHashesAsAbsent() throws {
        #expect(ReceiptContributionParents.canonicalRawValue([]) == nil)
        #expect(ReceiptContributionParents.canonicalRawValue(nil) == nil)
    }

    /// The one argument list every vector above shares, so a change to the fixture cannot silently
    /// apply to some of them and not others.
    private static func goldenVectorHash(
        envelopeVersion: Int,
        contributionColumns: ReceiptContributionColumns
    ) throws -> String {
        try ReceiptIntegrity.chainHash(
            receiptID: UUID(uuidString: "11111111-2222-3333-4444-555555555555")!,
            envelopeVersion: envelopeVersion,
            sequenceID: 1,
            accountSequenceID: 1,
            createdAt: Date(timeIntervalSince1970: 100),
            actorRawValue: "system",
            actorColumns: ReceiptActorColumns(.system),
            authorityColumns: ReceiptAuthorityColumns(nil),
            contributionColumns: contributionColumns,
            modeRawValue: "Observe",
            trigger: "token.transfer",
            scope: "accounts",
            summary: "Fixture",
            provenance: "test",
            isSuccess: true,
            correlationID: "flow-1",
            accountAddress: "0x1111111111111111111111111111111111111111",
            chainRawValue: "eth-mainnet",
            payloadHash: "abc123",
            signerPublicKey: "c2lnbmVy",
            previousReceiptHash: ReceiptIntegrity.genesisHash
        )
    }

    /// The canonical bytes themselves, so the two conventions a reimplementation is most likely to
    /// get wrong are written down as bytes rather than described in prose.
    ///
    /// Keys sort in codepoint order, and — the one worth stating — **an integral number emits without
    /// a fractional part**: `100`, not `100.0`. A reimplementation that formats doubles as
    /// `repr(100.0)` computes a different SHA-256 over identical data. That can only cause a false
    /// *mismatch*, never a false match, so it is an interop hazard rather than a security hole; but
    /// the format claims independent verifiability, so it has to be pinned somewhere.
    @Test("canonical JSON pins key order and integral number formatting")
    func canonicalJSONGoldenVector() throws {
        let payload = ReceiptPayload(values: ["n": .number(100), "s": .string("x"), "b": .bool(true)])
        let json = String(data: try ReceiptIntegrity.canonicalData(payload), encoding: .utf8)
        #expect(json == #"{"values":{"b":true,"n":100,"s":"x"}}"#)
        #expect(
            try ReceiptIntegrity.payloadHash(for: payload)
                == "4fb816a1673c8f00dcb94e0b48260104ea44d6b1f78b5ee924debc47bdde8dac"
        )
    }

    /// Codepoint order, not locale collation — a byte-sorting reimplementation has to agree.
    @Test("canonical key order is by codepoint, not locale collation")
    func canonicalKeyOrderIsByCodepoint() throws {
        let payload = ReceiptPayload(
            values: [
                "Apple": .number(2),
                "apple": .number(3),
                "zebra": .number(1),
                "éx": .number(4)
            ]
        )
        let json = String(data: try ReceiptIntegrity.canonicalData(payload), encoding: .utf8)
        #expect(json == #"{"values":{"Apple":2,"apple":3,"zebra":1,"éx":4}}"#)
    }

    /// The manifest's two optional completeness fields must be *omitted* when nil, not emitted as
    /// `null`.
    ///
    /// The whole reason they are optional is that an archive written before they existed has to keep
    /// its original bytes and therefore its original `manifestHash`. If Swift emitted
    /// `"ledgerHighWaterMark":null` instead of dropping the key, every such archive's manifest hash
    /// would change and its signature would stop verifying — a silent break of every previously
    /// exported ledger, discovered only by whoever tried to verify one.
    @Test("absent manifest completeness fields are omitted, not encoded as null")
    func absentManifestFieldsAreOmitted() throws {
        let legacyShaped = ReceiptProvenanceManifest(
            recordCount: 1,
            recordsHash: "rh",
            chainHeads: []
        )
        let json = String(data: try ReceiptIntegrity.canonicalData(legacyShaped), encoding: .utf8)
        #expect(json == #"{"chainHeads":[],"recordCount":1,"recordsHash":"rh"}"#)

        // And present when they carry a value, so the omission is not hiding a real one.
        let stated = ReceiptProvenanceManifest(
            recordCount: 1,
            recordsHash: "rh",
            chainHeads: [],
            ledgerHighWaterMark: 9,
            ledgerCompletenessUnconfirmed: true
        )
        let statedJSON = String(data: try ReceiptIntegrity.canonicalData(stated), encoding: .utf8)
        #expect(
            statedJSON == #"{"chainHeads":[],"ledgerCompletenessUnconfirmed":true,"ledgerHighWaterMark":9,"recordCount":1,"recordsHash":"rh"}"#
        )
    }

    /// The same omission rule for the record-level envelope version, for the same reason: an archive
    /// of pre-column rows has to keep the `recordsHash` it was signed with.
    @Test("an absent record envelope version is omitted from the exported record")
    func absentRecordEnvelopeVersionIsOmitted() throws {
        let legacyRecord = ReceiptRecord(
            id: UUID(uuidString: "11111111-2222-3333-4444-555555555555")!,
            sequenceID: 1,
            createdAt: Date(timeIntervalSince1970: 100),
            actor: .system,
            actorDetail: nil,
            authorityDetail: nil,
            mode: .observe,
            trigger: "t",
            scope: "accounts",
            summary: "Fixture",
            provenance: "test",
            isSuccess: true,
            correlationID: nil,
            details: ReceiptPayload(values: [:])
        )
        let json = String(data: try ReceiptIntegrity.canonicalData(legacyRecord), encoding: .utf8) ?? ""
        #expect(json.contains("integrityEnvelopeVersion") == false, "\(json)")
    }

    /// Dates are seconds since the Unix epoch, not Foundation's 2001 reference date. Pinned because
    /// getting it wrong shifts every `createdAt` by 31 years and the mismatch surfaces as a tampered
    /// verdict on an archive that was written correctly.
    @Test("canonical dates are seconds since the Unix epoch")
    func canonicalDatesUseTheUnixEpoch() throws {
        struct Wrapper: Encodable { let at: Date }
        let json = String(
            data: try ReceiptIntegrity.canonicalData(Wrapper(at: Date(timeIntervalSince1970: 100))),
            encoding: .utf8
        )
        #expect(json == #"{"at":100}"#)
    }

    // MARK: - Helpers

    private func makeRow() throws -> StoredReceipt {
        try StoredReceipt(
            sequenceID: 1,
            createdAt: Date(timeIntervalSince1970: 100),
            actor: .system,
            actorDetail: .system,
            authorityDetail: nil,
            mode: .observe,
            trigger: "t",
            scope: "accounts",
            summary: "Fixture",
            provenance: "test",
            isSuccess: true,
            correlationID: nil,
            accountSequenceID: 1,
            payloadHash: "ph",
            previousReceiptHash: ReceiptIntegrity.genesisHash,
            chainHash: "ch",
            details: ReceiptPayload(values: [:])
        )
    }
}
