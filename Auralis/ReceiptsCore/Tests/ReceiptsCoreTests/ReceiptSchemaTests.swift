import AuralisPrimaryModels
import Foundation
@testable import ReceiptsCore
import Testing

/// What remains of ``ReceiptSchema`` once the record-shape version is gone: the declared-field
/// contract. The version constants, the legacy-row fallback, and the `schemaVersion` column they
/// interpreted were removed because nothing has shipped — there is no older shape to read, so the
/// column could only ever hold one value while being persisted on every row and committed to the
/// integrity hash.
@Suite("Receipt schema")
struct ReceiptSchemaTests {
    @Test("declared field problems catch a payload key no one could read")
    func declaredFieldProblems() {
        #expect(ReceiptSchema.problems(inDeclared: [:]).isEmpty)
        #expect(ReceiptSchema.problems(inDeclared: ["address": "0xabc"]).isEmpty)
        #expect(ReceiptSchema.problems(inDeclared: ["": "orphaned"]).count == 1)
        #expect(ReceiptSchema.problems(inDeclared: ["  ": "orphaned"]).count == 1)
    }

    /// The export format is versioned independently and deliberately stays that way: it crosses a
    /// trust boundary to a verifier that may be running a different build, which is the case a
    /// recorded version actually earns its keep in.
    @Test("the export envelope keeps its own version")
    func exportEnvelopeRemainsVersioned() {
        #expect(ReceiptProvenanceExport.currentVersion > 0)
        #expect(ReceiptProvenanceExport.currentFormat.isEmpty == false)
    }

    /// A record round-trips without a version key. Asserted because ``ReceiptProvenanceExport``
    /// hashes the canonical encoding of its records — a stray key here changes `recordsHash` and
    /// breaks verification of every archive.
    @Test("a record encodes with no schema-version key")
    func recordEncodesWithoutASchemaVersionKey() throws {
        // Must be the canonical encoder, not a bare `JSONEncoder`: `ReceiptProvenanceExport` hashes
        // *this* encoding, so a bare encoder would let a date-strategy or key-order change alter
        // every archive's `recordsHash` while this test stayed green.
        let encoder = ReceiptCanonicalJSON.encoder()
        let record = ReceiptRecord(
            id: UUID(uuidString: "00000000-0000-0000-0000-0000000000AA")!,
            sequenceID: 1,
            createdAt: Date(timeIntervalSince1970: 1_000),
            actor: .system,
            actorDetail: nil,
            authorityDetail: nil,
            mode: .observe,
            trigger: "tool.executed",
            scope: "runtime",
            summary: "did a thing",
            provenance: "local",
            isSuccess: true,
            correlationID: "run-1",
            details: ReceiptPayload(values: [:])
        )

        let json = try #require(String(bytes: try encoder.encode(record), encoding: .utf8))
        #expect(!json.contains("schemaVersion"))

        // The nil-valued optional columns must be *omitted*, not encoded as null. Turning any of
        // these into a non-optional with a default would start emitting the key and silently change
        // the `recordsHash` of every archive already written, so a correctly-stored archive would
        // then verify as tampered.
        for omittedKey in ["actorDetail", "authorityDetail", "signature", "accountAddress", "integrityEnvelopeVersion"] {
            #expect(!json.contains(omittedKey), "\(omittedKey) must stay omitted when nil")
        }

        let decoded = try ReceiptCanonicalJSON.decoder().decode(
            ReceiptRecord.self,
            from: try encoder.encode(record)
        )
        #expect(decoded == record)
    }

    /// Sequence IDs are allocated from 1, but `sequenceIDs` reaches this function from an
    /// `exportAll()` archive, so the input is untrusted. `[0, 1, 2]` used to report "missing -1 of 2".
    @Test("a non-positive sequence number is rejected rather than reported as a negative shortfall")
    func nonPositiveSequenceNumbersAreRejected() {
        let reasons = ReceiptIntegrity.sequenceGapReasons(sequenceIDs: [0, 1, 2])
        #expect(reasons.count == 1)
        let reason = try? #require(reasons.first)
        #expect(reason?.contains("-") == false, "must not report a negative shortfall")
        #expect(reason?.contains("could not have issued") == true)

        #expect(ReceiptIntegrity.sequenceGapReasons(sequenceIDs: [-3, -2, -1]).count == 1)
        // An intact 1-based ledger still reports clean, and a real hole still reports a hole.
        #expect(ReceiptIntegrity.sequenceGapReasons(sequenceIDs: [1, 2, 3]).isEmpty)
        #expect(ReceiptIntegrity.sequenceGapReasons(sequenceIDs: [1, 2, 4]).count == 1)
    }
}

/// The high-water mark half of completeness. Advisory by design — see the doc comment on
/// ``ReceiptIntegrity/completenessAdvisory(sequenceIDs:highWaterMark:completenessUnconfirmed:)`` —
/// which is exactly why its *wording* needs pinning: it is the only thing a person is told about a
/// deleted suffix, and the two ways to get it wrong are accusing an untouched ledger and staying
/// silent about a truncated one.
@Suite("Receipt ledger completeness advisory")
struct ReceiptCompletenessAdvisoryTests {
    @Test("an intact ledger whose mark agrees with its rows says nothing")
    func intactLedgerIsSilent() {
        #expect(ReceiptIntegrity.completenessAdvisory(sequenceIDs: [1, 2, 3], highWaterMark: 3) == nil)
        // No mark is not evidence: a device restore and a pre-mark ledger both land here, and
        // downgrading them was the bug that made the mark a gate instead of a note.
        #expect(ReceiptIntegrity.completenessAdvisory(sequenceIDs: [1, 2, 3], highWaterMark: nil) == nil)
    }

    /// A mark *behind* the rows is the append path's own crash window — the row committed and the
    /// Keychain write did not. Saying anything here invents a gap in a ledger nobody touched.
    @Test("a mark trailing the rows is not reported as a deletion")
    func trailingMarkIsNotADeletion() {
        #expect(ReceiptIntegrity.completenessAdvisory(sequenceIDs: [1, 2, 3], highWaterMark: 2) == nil)
    }

    @Test("a mark ahead of the rows reports the suffix shortfall")
    func markAheadReportsShortfall() throws {
        let advisory = try #require(
            ReceiptIntegrity.completenessAdvisory(sequenceIDs: [1, 2, 3], highWaterMark: 5)
        )
        #expect(advisory.contains("suggests 2 were removed from the end"))
        // "high-water" is hyphenated, so check the shortfall itself rather than the whole sentence.
        #expect(!advisory.contains("suggests -"), "a shortfall must never be reported as a negative count")

        // The whole ledger erased, with the mark the only surviving evidence.
        let emptied = try #require(ReceiptIntegrity.completenessAdvisory(sequenceIDs: [], highWaterMark: 4))
        #expect(emptied.contains("suggests 4 were removed from the end"))
    }

    /// `completenessUnconfirmed` is the exporting device saying "I had rows and no mark". It has to
    /// win over whatever mark the reader happens to hold, or an archive's own disclaimer is lost.
    @Test("an unconfirmed ledger says so regardless of any mark supplied")
    func unconfirmedWins() throws {
        for mark in [nil, 1, 99] as [Int?] {
            let advisory = try #require(
                ReceiptIntegrity.completenessAdvisory(
                    sequenceIDs: [1, 2, 3],
                    highWaterMark: mark,
                    completenessUnconfirmed: true
                )
            )
            #expect(advisory.contains("carries no high-water mark"))
        }
    }
}

/// The chain-hash field set, from the package that now owns the specification.
@Suite("Receipt chain hash coverage")
struct ReceiptChainHashCoverageTests {
    private func hash(
        signerPublicKey: String?,
        createdAt: Date = Date(timeIntervalSince1970: 100),
        authorityExpiresAt: Date? = nil
    ) throws -> String {
        try ReceiptIntegrity.chainHash(
            receiptID: UUID(uuidString: "11111111-2222-3333-4444-555555555555")!,
            sequenceID: 1,
            accountSequenceID: 1,
            createdAt: createdAt,
            actorRawValue: "system",
            actorColumns: ReceiptActorColumns(nil),
            authorityColumns: ReceiptAuthorityColumns(
                source: nil,
                leaseID: nil,
                capability: nil,
                scope: nil,
                reason: nil,
                expiresAt: authorityExpiresAt
            ),
            contributionColumns: .unattributed,
            modeRawValue: "Observe",
            trigger: "token.transfer",
            scope: "accounts",
            summary: "Fixture",
            provenance: "test",
            isSuccess: true,
            correlationID: nil,
            accountAddress: nil,
            chainRawValue: nil,
            payloadHash: "abc123",
            signerPublicKey: signerPublicKey,
            previousReceiptHash: ReceiptIntegrity.genesisHash
        )
    }

    /// The asymmetry the whole signing scheme rests on: `signerPublicKey` is *inside* the hash, and
    /// `signature` cannot be because it is computed over that hash. Committing the key is what makes
    /// a signer substitution change the chain hash instead of producing a self-consistent forged row.
    /// `signature` is not even a parameter here, which is the structural half of the guarantee.
    @Test("the signing identity is committed to the chain hash")
    func signerPublicKeyIsHashed() throws {
        let signed = try hash(signerPublicKey: "c2lnbmVy")
        let substituted = try hash(signerPublicKey: "YXR0YWNrZXI=")
        let unsigned = try hash(signerPublicKey: nil)

        #expect(signed != substituted, "swapping the signer must break the chain hash")
        #expect(signed != unsigned)
        // Omitted-when-nil, so rows written before signing existed keep their original hash.
        #expect(try hash(signerPublicKey: nil) == unsigned)
        #expect(try hash(signerPublicKey: "c2lnbmVy") == signed, "hashing must be deterministic")
    }

    /// A single column holding `.infinity` must produce a *named* error, not an `EncodingError` from
    /// inside `JSONEncoder`. The thrown-error path propagated out of `verifyIntegrity()` and
    /// `exportAll()`, so one written column meant no verdict at all and an export that could only be
    /// recovered by destroying the history.
    @Test("a non-finite date column is a named error, not a raw encoding failure")
    func nonFiniteDatesAreNamedErrors() {
        #expect(throws: ReceiptIntegrityEncodingError.nonFiniteDate(field: "createdAt")) {
            _ = try hash(signerPublicKey: nil, createdAt: Date(timeIntervalSince1970: .infinity))
        }
        #expect(throws: ReceiptIntegrityEncodingError.nonFiniteDate(field: "authorityExpiresAt")) {
            _ = try hash(
                signerPublicKey: nil,
                authorityExpiresAt: Date(timeIntervalSince1970: .nan)
            )
        }
    }
}
