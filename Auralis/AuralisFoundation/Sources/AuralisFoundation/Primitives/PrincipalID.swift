import Foundation

/// A stable, non-empty, opaque identifier for something that can hold an ownership relationship.
///
/// **The raw value carries no semantics.** Consumers may compare it, store it, serialize it, and pass
/// it between boundaries. They must not parse it to infer whether the principal is a person, an agent,
/// an organization, a wallet, a blockchain address, a DID, a protocol, a network, or anything else.
///
/// That restriction is the whole design, not a caveat on it. A raw value that is allowed to be
/// interpreted becomes an unversioned, unvalidated type system: every consumer reimplements the
/// parsing slightly differently, authorization and presentation start branching on spellings, and the
/// set of recognized shapes can then never be extended without auditing every reader. Keeping the
/// value opaque means a new kind of principal costs nothing anywhere.
///
/// The luggage-tag rule is the memorable form: a tag helps the system keep track of the bag. It does
/// not authorize opening the bag, describe its owner, or reveal where they live. Authority,
/// presentation, and domain meaning all come from explicit surrounding context.
///
/// ## What this is not
///
/// It does not replace `RuntimeCore.ActorRef`, which is the runtime's answer to *who acted* and is a
/// deliberately richer, separately validated model. This type answers a narrower question: which
/// principals stand in which stated relationships to a resource. Any bridge between the two must be
/// explicit, and must not invent a principal when stable identity is unavailable — a fabricated
/// identifier is worse than an absent one, because an absent one is visibly absent.
///
/// It is also not a registry. Nothing here resolves an identifier to a profile, a key, a capability,
/// or a legal entity, and nothing here asserts that two identifiers naming the same real-world party
/// are related.
///
/// ## Producer contract
///
/// Identity producers are responsible for assigning values that are **stable** (the same principal
/// gets the same identifier across launches and devices) and **collision-resistant within their
/// domain**. This type cannot check either property — that is exactly what being opaque costs — so the
/// obligation sits with whoever mints the value.
public struct PrincipalID: RawRepresentable, Hashable, Codable, Sendable, CustomStringConvertible {
    /// Preserved exactly as supplied. Phase 1 performs no case folding, trimming, address
    /// normalization, DID parsing, namespace extraction, or blockchain validation, so two principals
    /// are equal only when their complete raw values are equal.
    public let rawValue: String

    /// - Returns: `nil` for an empty raw value, which is the one shape that cannot identify anything.
    ///
    /// Failable rather than trapping, because this initializer is on the decoding path for untrusted
    /// data — see ``init(from:)``. A `precondition` there would turn a malformed document into a
    /// process abort.
    ///
    /// **Only emptiness is rejected.** A whitespace-only value is accepted, and that is a decision
    /// rather than an oversight: rejecting it means validating the *trimmed* form while storing the
    /// *raw* form, so `init` and ``rawValue`` would disagree about what the value is, and `" a"` and
    /// `"a "` would remain distinct principals while `" "` alone was special-cased. Since nothing here
    /// trims, nothing here may validate as though it had.
    public init?(rawValue: String) {
        guard rawValue.isEmpty == false else {
            return nil
        }
        self.rawValue = rawValue
    }

    public var description: String { rawValue }

    // MARK: - Codable

    /// Hand-written, and that is load-bearing.
    ///
    /// A synthesized `Codable` conformance bypasses every bound an initializer establishes — it writes
    /// the stored property directly — so the empty value this type refuses to construct would have
    /// been freely *decodable*. The same mistake has been made elsewhere in this repository and the
    /// fix was the same: validate at the storage boundary, not only at the convenient one.
    ///
    /// Encoded as a single value rather than a keyed container, so an identifier serializes as the
    /// bare string it is. That keeps archives readable and keeps the encoded form stable if this type
    /// ever gains a computed member.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        let rawValue = try container.decode(String.self)
        guard let principal = PrincipalID(rawValue: rawValue) else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "A principal identifier must not be empty."
            )
        }
        self = principal
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}
