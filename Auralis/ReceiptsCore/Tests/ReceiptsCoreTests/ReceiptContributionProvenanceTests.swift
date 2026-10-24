import AuralisFoundation
import AuralisPrimaryModels
import Foundation
import ReceiptsCore
import Testing

/// The receipt-owned contribution-provenance vocabulary, independent of storage.
///
/// These pin the two properties the storage layer builds on: a reference identifies something or
/// nothing with no half-states in between, and the parent list has exactly one byte form so the hash
/// and the column cannot make different claims about the same list.
@Suite("Receipt contribution provenance")
struct ReceiptContributionProvenanceTests {
    // MARK: - References

    @Test("a reference needs both halves", arguments: [("", "id"), ("type", ""), ("", "")])
    func referenceNeedsBothHalves(type: String, identifier: String) {
        #expect(ReceiptResourceReference(type: type, identifier: identifier) == nil)
        #expect(ReceiptResultReference(type: type, identifier: identifier) == nil)
    }

    @Test("a well-formed reference preserves both halves exactly")
    func referencePreservesBothHalves() throws {
        let resource = try #require(
            ReceiptResourceReference(type: "nft", identifier: "eip155:1/erc721:0xAbC/7")
        )

        #expect(resource.type == "nft")
        #expect(resource.identifier == "eip155:1/erc721:0xAbC/7", "the identifier is opaque; no normalization")
    }

    @Test("references round-trip through Codable")
    func referencesRoundTrip() throws {
        let resource = try #require(ReceiptResourceReference(type: "playlist", identifier: "42"))
        let result = try #require(ReceiptResultReference(type: "artifact", identifier: "42"))

        #expect(
            try JSONDecoder().decode(
                ReceiptResourceReference.self,
                from: try JSONEncoder().encode(resource)
            ) == resource
        )
        #expect(
            try JSONDecoder().decode(
                ReceiptResultReference.self,
                from: try JSONEncoder().encode(result)
            ) == result
        )
    }

    /// The bound has to hold on the decoding path, which is the one a synthesized conformance would
    /// have left open and the one that receives archives from elsewhere.
    @Test("a reference with an empty half fails to decode")
    func referenceWithEmptyHalfFailsToDecode() {
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(
                ReceiptResourceReference.self,
                from: Data(#"{"type":"nft","identifier":""}"#.utf8)
            )
        }
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(
                ReceiptResultReference.self,
                from: Data(#"{"type":"","identifier":"7"}"#.utf8)
            )
        }
    }

    // MARK: - Parent receipt IDs

    @Test("no parents and an empty parent list produce the same canonical form")
    func absentAndEmptyParentListsAgree() {
        #expect(ReceiptContributionParents.canonicalRawValue(nil) == nil)
        #expect(ReceiptContributionParents.canonicalRawValue([]) == nil)
    }

    @Test("the canonical form is uppercase, comma-joined, and order-preserving")
    func canonicalFormIsPinned() throws {
        let first = try #require(UUID(uuidString: "11111111-2222-3333-4444-555555555555"))
        let second = try #require(UUID(uuidString: "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee"))

        #expect(
            ReceiptContributionParents.canonicalRawValue([second, first])
                == "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE,11111111-2222-3333-4444-555555555555"
        )
    }

    @Test("parsing is the exact inverse of the canonical form")
    func parsingInvertsCanonicalForm() throws {
        let ids = [UUID(), UUID(), UUID()]
        let raw = ReceiptContributionParents.canonicalRawValue(ids)

        #expect(ReceiptContributionParents.parse(raw) == ids)
        #expect(ReceiptContributionParents.parse(nil) == [])
    }

    /// `nil` from `parse` means *the column is damaged*, which is a different claim from "no parents"
    /// and must stay distinguishable — collapsing the two is how a column slips outside every check.
    @Test(
        "an unparseable column is nil rather than empty",
        arguments: ["", "not-a-uuid", "11111111-2222-3333-4444-555555555555,", ",", "1,2"]
    )
    func unparseableColumnIsNil(rawValue: String) {
        #expect(ReceiptContributionParents.parse(rawValue) == nil)
        #expect(ReceiptContributionParents.isCanonical(rawValue) == false)
    }

    /// The fixture needs hex *letters* in it — a digits-only UUID is its own lowercase form, which
    /// would make this test pass without exercising anything.
    @Test("a lowercased spelling of the same ids is not canonical")
    func lowercasedSpellingIsNotCanonical() throws {
        let id = try #require(UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE"))
        let canonical = try #require(ReceiptContributionParents.canonicalRawValue([id]))

        #expect(ReceiptContributionParents.isCanonical(canonical))
        #expect(ReceiptContributionParents.isCanonical(canonical.lowercased()) == false)
        #expect(ReceiptContributionParents.isCanonical(nil), "no parents is a canonical state")
    }

    @Test("duplicates and self-reference are reported as problems")
    func problemsReportsDuplicatesAndSelfReference() throws {
        let receiptID = UUID()
        let parent = UUID()

        #expect(ReceiptContributionParents.problems([parent]).isEmpty)
        #expect(ReceiptContributionParents.problems(nil).isEmpty)
        #expect(ReceiptContributionParents.problems([]).isEmpty)
        #expect(ReceiptContributionParents.problems([parent, parent]).count == 1)
        #expect(
            ReceiptContributionParents.problems([receiptID], receiptID: receiptID)
                .contains { $0.contains("lists itself as its own parent") }
        )
        // Without the receipt id there is nothing to compare against, so self-reference is simply not
        // checkable — which is why the append path and the archive verifier differ on this.
        #expect(ReceiptContributionParents.problems([receiptID]).isEmpty)
    }

    // MARK: - Columns

    /// The composed-to-columns direction is lossless for anything a writer can produce, which is what
    /// lets the archive verifier rebuild the hashed envelope from a `ReceiptRecord`.
    @Test("composed provenance maps losslessly onto the hashed columns")
    func composedProvenanceMapsOntoColumns() throws {
        let parent = UUID()
        let columns = ReceiptContributionColumns(
            principal: PrincipalID(rawValue: "did:example:alice"),
            affectedResource: ReceiptResourceReference(type: "nft", identifier: "7"),
            producedResult: ReceiptResultReference(type: "artifact", identifier: "report-1"),
            parentReceiptIDs: [parent]
        )

        #expect(columns.principalID == "did:example:alice")
        #expect(columns.affectedResourceType == "nft")
        #expect(columns.affectedResourceIdentifier == "7")
        #expect(columns.producedResultType == "artifact")
        #expect(columns.producedResultIdentifier == "report-1")
        #expect(columns.parentReceiptIDs == parent.uuidString)
    }

    @Test("stating nothing produces the unattributed columns")
    func statingNothingIsUnattributed() {
        let columns = ReceiptContributionColumns(
            principal: nil,
            affectedResource: nil,
            producedResult: nil,
            parentReceiptIDs: nil
        )

        #expect(columns == ReceiptContributionColumns.unattributed)
    }

    // MARK: - Draft and record wiring

    /// A draft's columns have to be the same values the row stores, because the append path hashes
    /// the first and persists the second. A divergence is a row that verifies as tampered forever.
    @Test("a draft's contribution columns reflect its stated provenance")
    func draftColumnsReflectStatedProvenance() throws {
        let parent = UUID()
        let draft = ReceiptDraft(
            actorDetail: .system,
            authorityDetail: nil,
            trigger: "t",
            scope: "s",
            summary: "sum",
            provenance: "test",
            isSuccess: true,
            correlationID: nil,
            principal: PrincipalID(rawValue: "did:example:alice"),
            affectedResource: ReceiptResourceReference(type: "nft", identifier: "7"),
            producedResult: ReceiptResultReference(type: "artifact", identifier: "report-1"),
            parentReceiptIDs: [parent],
            details: ReceiptPayload(values: [:])
        )

        #expect(draft.contributionColumns.principalID == "did:example:alice")
        #expect(draft.contributionColumns.parentReceiptIDs == parent.uuidString)
    }

    @Test("a draft that states no provenance produces unattributed columns")
    func bareDraftIsUnattributed() {
        let draft = ReceiptDraft(
            actorDetail: .system,
            authorityDetail: nil,
            trigger: "t",
            scope: "s",
            summary: "sum",
            provenance: "test",
            isSuccess: true,
            correlationID: nil,
            details: ReceiptPayload(values: [:])
        )

        #expect(draft.contributionColumns == ReceiptContributionColumns.unattributed)
        #expect(draft.parentReceiptIDs.isEmpty)
    }

    /// `[]` normalizes to `nil` on the record so this package never writes the redundant spelling
    /// into an archive — the two mean the same thing and only one of them costs bytes.
    @Test("an empty parent list normalizes to nil on a record")
    func emptyParentListNormalizesOnRecord() {
        let record = ReceiptRecord(
            id: UUID(),
            sequenceID: 1,
            createdAt: Date(timeIntervalSince1970: 100),
            actor: .system,
            actorDetail: .system,
            authorityDetail: nil,
            mode: .observe,
            trigger: "t",
            scope: "s",
            summary: "sum",
            provenance: "test",
            isSuccess: true,
            correlationID: nil,
            parentReceiptIDs: [],
            details: ReceiptPayload(values: [:])
        )

        #expect(record.parentReceiptIDs == nil)
        #expect(record.contributionColumns == ReceiptContributionColumns.unattributed)
    }

    /// The archive-compatibility requirement as bytes: a record stating no provenance must not emit
    /// any of the new keys, or the `recordsHash` of every archive already signed would change.
    @Test("a record with no provenance omits every new key")
    func recordWithNoProvenanceOmitsNewKeys() throws {
        let record = ReceiptRecord(
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
        let json = String(data: try ReceiptIntegrity.canonicalData(record), encoding: .utf8) ?? ""

        for key in ["principal", "affectedResource", "producedResult", "parentReceiptIDs"] {
            #expect(json.contains("\"\(key)\"") == false, "\(key) must be omitted: \(json)")
        }
    }

    /// And present when stated, so the omission above is not hiding a real value.
    @Test("a record with stated provenance encodes it")
    func recordWithStatedProvenanceEncodesIt() throws {
        let parent = try #require(UUID(uuidString: "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee"))
        let record = ReceiptRecord(
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
            principal: PrincipalID(rawValue: "did:example:alice"),
            affectedResource: ReceiptResourceReference(type: "nft", identifier: "7"),
            producedResult: ReceiptResultReference(type: "artifact", identifier: "report-1"),
            parentReceiptIDs: [parent],
            details: ReceiptPayload(values: [:])
        )
        let data = try ReceiptIntegrity.canonicalData(record)
        let decoded = try ReceiptCanonicalJSON.decoder().decode(ReceiptRecord.self, from: data)

        #expect(decoded == record)
        #expect(decoded.principal?.rawValue == "did:example:alice")
        #expect(decoded.parentReceiptIDs == [parent])
    }

    // MARK: - The economic boundary

    /// Contribution provenance says what happened, never what anyone is owed for it.
    @Test(
        "the provenance vocabulary carries no economic or ownership-share semantics",
        arguments: [
            "tokensEarned",
            "equityPercentage",
            "ownershipPercentage",
            "financialReward",
            "governanceWeight"
        ]
    )
    func provenanceCarriesNoEconomicSemantics(prohibited: String) throws {
        let columns = ReceiptContributionColumns.unattributed
        let members = Set(Mirror(reflecting: columns).children.compactMap(\.label))

        #expect(members.contains(prohibited) == false)
        #expect(
            members == [
                "principalID",
                "affectedResourceType",
                "affectedResourceIdentifier",
                "producedResultType",
                "producedResultIdentifier",
                "parentReceiptIDs"
            ]
        )
    }
}
