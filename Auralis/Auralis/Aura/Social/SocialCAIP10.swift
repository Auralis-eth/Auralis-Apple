import Foundation

/// Builds and validates CAIP-10 account identifiers (`namespace:reference:address`) for Social v1
/// participant identity. The `eip155` form mirrors the parsing in `SocialWalletJoinVerifier`, so an
/// invite authored here round-trips through join verification.
enum SocialCAIP10 {
    /// A lowercase CAIP-10 for an EVM account, or `nil` when the address isn't a well-formed 20-byte hex
    /// address or the chain id is invalid — so a missing/observe-only wallet falls back rather than
    /// minting a bogus identity.
    static func eip155(address: String, chainID: Int) -> String? {
        let trimmed = address.trimmingCharacters(in: .whitespacesAndNewlines)
        guard chainID > 0, isEVMAddress(trimmed) else { return nil }
        return "eip155:\(chainID):\(trimmed.lowercased())"
    }

    /// Whether `value` is a `0x`-prefixed 20-byte (40 hex char) EVM address.
    ///
    /// ASCII hex only. `Character.isHexDigit` is Unicode-aware and returns `true` for the fullwidth
    /// forms (U+FF10–U+FF19, U+FF21–U+FF26, U+FF41–U+FF46), so `"0x"` followed by 40 fullwidth
    /// characters would have minted a CAIP-10 that is not an address at all.
    static func isEVMAddress(_ value: String) -> Bool {
        guard value.hasPrefix("0x"), value.count == 42 else { return false }
        return value.dropFirst(2).allSatisfy { $0.isASCII && $0.isHexDigit }
    }

    /// Whether `value` has the `namespace:reference:address` shape of a CAIP-10 account (vs. the local
    /// UUID fallback participant id), so join verification is only attempted for real on-chain accounts.
    ///
    /// Uses the same split policy as `WalletJoinAccount.init` — the parser that actually consumes the
    /// result — so the two cannot disagree. They previously differed on `omittingEmptySubsequences`:
    /// `"eip155::1:0xabc"` was refused here but parsed there as Ethereum with address `0xabc`.
    static func isCAIP10(_ value: String) -> Bool {
        let parts = split(value)
        return parts.count == 3 && parts.allSatisfy { !$0.isEmpty }
    }

    /// The single CAIP-10 split used by both this type and join verification.
    static func split(_ value: String) -> [String] {
        value.split(separator: ":", maxSplits: 2, omittingEmptySubsequences: false).map(String.init)
    }
}
