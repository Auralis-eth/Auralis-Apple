import Foundation

/// Which principals stand in which *stated* relationships to a separately identified resource.
///
/// Five roles, independently optional, with no invariant requiring any two of them to be the same
/// principal. That is the entire point: creator, owner, controller, custodian and beneficiary are not
/// synonyms, and the cases worth modelling are precisely the ones where they come apart — a work
/// created by one party, owned by a second, operated by a third, held in custody by a fourth, and
/// yielding its benefit to a fifth. One principal holding several roles is common and perfectly
/// representable; it is simply not assumed.
///
/// ## What this is not
///
/// **It is metadata, not authority.** A descriptor saying a principal is the owner of something is a
/// statement, not a key. Nothing here answers a permission question, and no authorization decision may
/// read one: if a rule like "the owner may do X" is ever wanted, it belongs in `AuralisPolicy`, with
/// ownership as one input among several and the decision recorded on a receipt. See `OWNERSHIP.md`.
///
/// It is also not a free-standing registry, a proof of legal title, or an economic instrument. It
/// resolves nothing, inherits nothing, transfers nothing, and implies nothing about equity, tokens,
/// compensation or governance weight. The resource it describes is identified elsewhere — this type
/// deliberately does not carry a resource identifier, because that would make it a record *about* a
/// resource rather than metadata *attached to* one, and the two have very different lifecycles.
///
/// Ownership metadata stays optional for every existing resource in the app. Nothing requires one.
public struct OwnershipDescriptor: Hashable, Codable, Sendable {
    /// Who brought the resource into existence. Absent means *not stated*, which is different from
    /// *nobody* and very different from *us* — see `OWNERSHIP.md`, constraint 2.
    public let creator: PrincipalID?
    /// Who holds the resource.
    public let owner: PrincipalID?
    /// Who currently decides about it, which need not be the owner.
    public let controller: PrincipalID?
    /// Who holds it on another's behalf.
    public let custodian: PrincipalID?
    /// Who the resource yields its benefit to.
    ///
    /// **Ordered and unique.** Insertion order is preserved so equality and encoding are
    /// deterministic, and a principal appears at most once. Duplicates are normalized rather than
    /// rejected — the first occurrence is retained and later ones dropped — because a duplicate is an
    /// unambiguous statement of the same fact twice, and refusing it would mean a caller merging two
    /// beneficiary lists has to deduplicate before this type will accept the result.
    public let beneficiaries: [PrincipalID]

    public init(
        creator: PrincipalID? = nil,
        owner: PrincipalID? = nil,
        controller: PrincipalID? = nil,
        custodian: PrincipalID? = nil,
        beneficiaries: [PrincipalID] = []
    ) {
        self.creator = creator
        self.owner = owner
        self.controller = controller
        self.custodian = custodian
        self.beneficiaries = Self.orderedUnique(beneficiaries)
    }

    /// `true` when no relationship is stated at all.
    ///
    /// Useful for callers deciding whether a descriptor is worth storing or showing. Carries no
    /// meaning beyond "this says nothing"; in particular it is not a claim that the resource is
    /// unowned.
    public var isUnstated: Bool {
        creator == nil
            && owner == nil
            && controller == nil
            && custodian == nil
            && beneficiaries.isEmpty
    }

    /// The one normalization, shared by ``init(creator:owner:controller:custodian:beneficiaries:)``
    /// and ``init(from:)`` so the two cannot drift.
    ///
    /// `Set`-based membership rather than `contains`, so merging two long lists stays linear.
    private static func orderedUnique(_ principals: [PrincipalID]) -> [PrincipalID] {
        var seen = Set<PrincipalID>()
        return principals.filter { seen.insert($0).inserted }
    }

    // MARK: - Codable

    private enum CodingKeys: String, CodingKey {
        case creator
        case owner
        case controller
        case custodian
        case beneficiaries
    }

    /// Hand-written for the reason ``PrincipalID/init(from:)`` is: a synthesized conformance writes the
    /// stored properties directly and so bypasses every bound the initializer establishes. Here that
    /// would mean the ordered-*unique* invariant held for constructed values and not for decoded ones,
    /// which is the half that matters — decoded values are the ones that arrive from outside.
    ///
    /// An absent `beneficiaries` key decodes as empty rather than failing, so a descriptor encoded
    /// with no beneficiaries round-trips through the omitted-when-empty encoding below.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            creator: try container.decodeIfPresent(PrincipalID.self, forKey: .creator),
            owner: try container.decodeIfPresent(PrincipalID.self, forKey: .owner),
            controller: try container.decodeIfPresent(PrincipalID.self, forKey: .controller),
            custodian: try container.decodeIfPresent(PrincipalID.self, forKey: .custodian),
            beneficiaries: try container.decodeIfPresent([PrincipalID].self, forKey: .beneficiaries) ?? []
        )
    }

    /// Absent roles are *omitted*, not encoded as `null`, and an empty beneficiary list is omitted too.
    ///
    /// So a fully unstated descriptor encodes as `{}`. That is deliberate: ownership metadata is
    /// optional everywhere, so the overwhelmingly common value should cost nothing to carry, and a
    /// descriptor that gains a role later should not change the encoded bytes of every record that
    /// does not use it.
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(creator, forKey: .creator)
        try container.encodeIfPresent(owner, forKey: .owner)
        try container.encodeIfPresent(controller, forKey: .controller)
        try container.encodeIfPresent(custodian, forKey: .custodian)
        if beneficiaries.isEmpty == false {
            try container.encode(beneficiaries, forKey: .beneficiaries)
        }
    }
}
