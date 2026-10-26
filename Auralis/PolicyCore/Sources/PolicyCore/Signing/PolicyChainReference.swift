/// Opaque chain scope used by policy evidence and allowlists.
///
/// Policy compares the scope selected by composition; it does not parse provider-specific chain
/// enums or decide whether a chain exists. Crypto adapters convert their typed chain to this stable
/// raw reference at the boundary.
public struct PolicyChainReference: RawRepresentable, Hashable, Sendable {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }
}
