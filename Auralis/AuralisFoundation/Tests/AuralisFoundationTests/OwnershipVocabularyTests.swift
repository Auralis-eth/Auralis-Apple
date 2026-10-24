import AuralisFoundation
import Foundation
import Testing

/// The Phase 1 ownership vocabulary: a stable opaque principal label, and the five-role descriptor
/// that uses it.
///
/// What these tests are mostly guarding is the *absence* of behaviour. The type is only safe to spread
/// through a codebase because it refuses to interpret its own contents and grants no authority, and
/// both of those are properties that a well-meaning later change erodes silently.
struct PrincipalIDTests {
    /// Values whose contents must stay uninterpreted. Each is a shape some consumer could be tempted
    /// to parse — a wallet address, a DID, a CAIP-10 account, a URN, a bare UUID — and the point of
    /// the parameterization is that this type treats all of them identically.
    private static let opaqueValues = [
        "0xd8dA6BF26964aF9D7eEd9e03E53415D37aA96045",
        "did:key:z6MkhaXgBZDvotDkL5257faiztiGiC2QtKLGpbnnEGta2doK",
        "eip155:1:0xd8dA6BF26964aF9D7eEd9e03E53415D37aA96045",
        "urn:auralis:operator:on-chain-watch",
        "6FB455DA-2CC5-BEBB-009A-055C00000000",
        "auralis.inc",
        "  leading and trailing space  ",
        "人",
        "🪪"
    ]

    @Test("a non-empty raw value constructs")
    func nonEmptyValueConstructs() throws {
        let principal = try #require(PrincipalID(rawValue: "a"))

        #expect(principal.rawValue == "a")
    }

    @Test("an empty raw value is refused")
    func emptyValueIsRefused() {
        #expect(PrincipalID(rawValue: "") == nil)
    }

    /// The one input the type validates, checked on the path that matters most: decoding is where
    /// untrusted data arrives, and a synthesized `Codable` would have admitted it.
    @Test("an empty raw value is refused by the decoder too")
    func emptyValueIsRefusedWhenDecoded() {
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(PrincipalID.self, from: Data(#""""#.utf8))
        }
    }

    @Test("the raw value is preserved exactly", arguments: opaqueValues)
    func rawValueIsPreservedExactly(value: String) throws {
        let principal = try #require(PrincipalID(rawValue: value))

        #expect(principal.rawValue == value)
        #expect(principal.description == value)
    }

    /// No case folding, no trimming, no normalization — so spellings that an address parser or a DID
    /// resolver would call equivalent are distinct principals here.
    @Test("equality is over the complete raw value")
    func equalityIsOverTheCompleteRawValue() throws {
        let lowercased = try #require(PrincipalID(rawValue: "0xabc"))
        let uppercased = try #require(PrincipalID(rawValue: "0xABC"))
        let padded = try #require(PrincipalID(rawValue: " 0xabc"))
        let sameAsLowercased = try #require(PrincipalID(rawValue: "0xabc"))

        #expect(lowercased == sameAsLowercased)
        #expect(lowercased != uppercased)
        #expect(lowercased != padded)
    }

    @Test("equal principals hash equally and distinct ones are usable as keys")
    func hashingFollowsEquality() throws {
        let first = try #require(PrincipalID(rawValue: "principal-1"))
        let same = try #require(PrincipalID(rawValue: "principal-1"))
        let other = try #require(PrincipalID(rawValue: "principal-2"))

        #expect(first.hashValue == same.hashValue)
        #expect(Set([first, same, other]).count == 2)
    }

    @Test("a principal round-trips through Codable", arguments: opaqueValues)
    func codableRoundTrip(value: String) throws {
        let principal = try #require(PrincipalID(rawValue: value))
        let data = try JSONEncoder().encode(principal)
        let decoded = try JSONDecoder().decode(PrincipalID.self, from: data)

        #expect(decoded == principal)
        #expect(decoded.rawValue == value)
    }

    /// Encoded as a bare string rather than an object, so an identifier reads as the label it is in
    /// any archive that carries one.
    @Test("a principal encodes as a single string value")
    func encodesAsASingleStringValue() throws {
        let principal = try #require(PrincipalID(rawValue: "auralis.inc"))
        let json = String(data: try JSONEncoder().encode(principal), encoding: .utf8)

        #expect(json == #""auralis.inc""#)
    }
}

struct OwnershipDescriptorTests {
    private static func principal(_ value: String) throws -> PrincipalID {
        try #require(PrincipalID(rawValue: value))
    }

    /// The case the whole type exists for: five roles, five different principals, no invariant pulling
    /// any of them together.
    @Test("every role can name a different principal")
    func rolesAreIndependent() throws {
        let descriptor = OwnershipDescriptor(
            creator: try Self.principal("creator"),
            owner: try Self.principal("owner"),
            controller: try Self.principal("controller"),
            custodian: try Self.principal("custodian"),
            beneficiaries: [try Self.principal("beneficiary")]
        )

        #expect(descriptor.creator?.rawValue == "creator")
        #expect(descriptor.owner?.rawValue == "owner")
        #expect(descriptor.controller?.rawValue == "controller")
        #expect(descriptor.custodian?.rawValue == "custodian")
        #expect(descriptor.beneficiaries.map(\.rawValue) == ["beneficiary"])
        #expect(descriptor.isUnstated == false)
    }

    /// One principal in several roles is representable — the roles being separate does not mean they
    /// must differ.
    @Test("one principal may hold several roles")
    func onePrincipalMayHoldSeveralRoles() throws {
        let founder = try Self.principal("founder")
        let descriptor = OwnershipDescriptor(
            creator: founder,
            owner: founder,
            controller: founder,
            custodian: founder,
            beneficiaries: [founder]
        )

        #expect(descriptor.creator == descriptor.owner)
        #expect(descriptor.beneficiaries == [founder])
    }

    @Test("all fields may be absent")
    func allFieldsMayBeAbsent() {
        let descriptor = OwnershipDescriptor()

        #expect(descriptor.creator == nil)
        #expect(descriptor.owner == nil)
        #expect(descriptor.controller == nil)
        #expect(descriptor.custodian == nil)
        #expect(descriptor.beneficiaries.isEmpty)
        #expect(descriptor.isUnstated)
    }

    @Test("beneficiaries preserve insertion order")
    func beneficiariesPreserveInsertionOrder() throws {
        let ordered = [
            try Self.principal("third"),
            try Self.principal("first"),
            try Self.principal("second")
        ]
        let descriptor = OwnershipDescriptor(beneficiaries: ordered)

        #expect(descriptor.beneficiaries == ordered)
        #expect(descriptor.beneficiaries.map(\.rawValue) == ["third", "first", "second"])
    }

    @Test("duplicate beneficiaries normalize to the first occurrence")
    func duplicateBeneficiariesNormalize() throws {
        let alpha = try Self.principal("alpha")
        let beta = try Self.principal("beta")
        let descriptor = OwnershipDescriptor(beneficiaries: [alpha, beta, alpha, beta, alpha])

        #expect(descriptor.beneficiaries == [alpha, beta])
    }

    /// The normalization has to hold on the decoding path too, which is the half a synthesized
    /// `Codable` would have skipped — and the half that receives values from outside this process.
    @Test("duplicate beneficiaries normalize when decoded")
    func duplicateBeneficiariesNormalizeWhenDecoded() throws {
        let json = #"{"beneficiaries":["alpha","beta","alpha"]}"#
        let decoded = try JSONDecoder().decode(OwnershipDescriptor.self, from: Data(json.utf8))

        #expect(decoded.beneficiaries.map(\.rawValue) == ["alpha", "beta"])
    }

    /// An empty principal is refused wherever it appears, nested roles included.
    @Test("a descriptor carrying an empty principal fails to decode")
    func emptyNestedPrincipalFailsToDecode() {
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(
                OwnershipDescriptor.self,
                from: Data(#"{"owner":""}"#.utf8)
            )
        }
    }

    @Test("a descriptor round-trips through Codable")
    func codableRoundTrip() throws {
        let descriptor = OwnershipDescriptor(
            creator: try Self.principal("creator"),
            owner: try Self.principal("owner"),
            controller: nil,
            custodian: try Self.principal("custodian"),
            beneficiaries: [try Self.principal("b1"), try Self.principal("b2")]
        )
        let data = try JSONEncoder().encode(descriptor)
        let decoded = try JSONDecoder().decode(OwnershipDescriptor.self, from: data)

        #expect(decoded == descriptor)
        #expect(decoded.controller == nil)
    }

    @Test("an unstated descriptor round-trips as an empty object")
    func unstatedDescriptorRoundTrips() throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let json = String(data: try encoder.encode(OwnershipDescriptor()), encoding: .utf8)

        #expect(json == "{}")
        #expect(
            try JSONDecoder().decode(OwnershipDescriptor.self, from: Data("{}".utf8)).isUnstated
        )
    }

    /// Encoding order has to be deterministic, because a descriptor may end up inside something that
    /// is hashed. Keys sort; the beneficiary array keeps insertion order rather than sorting, since
    /// the order is part of the stated relationship.
    @Test("encoding is deterministic and beneficiary order is not sorted away")
    func encodingIsDeterministic() throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let descriptor = OwnershipDescriptor(
            creator: try Self.principal("c"),
            owner: try Self.principal("o"),
            beneficiaries: [try Self.principal("z"), try Self.principal("a")]
        )
        let encoded = try encoder.encode(descriptor)
        let reencoded = try encoder.encode(descriptor)
        let json = String(data: encoded, encoding: .utf8)

        #expect(json == #"{"beneficiaries":["z","a"],"creator":"c","owner":"o"}"#)
        #expect(encoded == reencoded)
    }

    @Test("equal descriptors hash equally")
    func hashingFollowsEquality() throws {
        let first = OwnershipDescriptor(owner: try Self.principal("owner"))
        let same = OwnershipDescriptor(owner: try Self.principal("owner"))
        let other = OwnershipDescriptor(controller: try Self.principal("owner"))

        #expect(first == same)
        #expect(first.hashValue == same.hashValue)
        #expect(Set([first, same, other]).count == 2)
    }

    /// Ownership metadata grants no authority and carries no economics, and that is checked
    /// structurally rather than trusted to review.
    ///
    /// Reflection over the members is crude, but it is the only mechanism that notices a member being
    /// *added*. The failure this guards against is not someone writing `func isAuthorized()` today; it
    /// is a later change growing a convenience — a `permissions` set, an `ownershipPercentage`, a
    /// `resolve()` that walks a chain of custody — and nobody noticing that the descriptor has stopped
    /// being a statement and started being a decision.
    @Test("the descriptor exposes only stated relationships")
    func descriptorExposesOnlyStatedRelationships() throws {
        let members = Set(
            Mirror(reflecting: OwnershipDescriptor(owner: try Self.principal("owner")))
                .children
                .compactMap(\.label)
        )

        #expect(members == ["creator", "owner", "controller", "custodian", "beneficiaries"])
    }
}
