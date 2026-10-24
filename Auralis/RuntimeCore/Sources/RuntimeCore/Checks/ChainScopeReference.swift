import AuralisPrimaryModels
import Foundation

/// The one place a chain reference on a proposal is turned into a ``Chain`` (P0.5-802).
///
/// Chain identity arrives in this codebase in four vocabularies — a ``Chain`` raw value
/// (`eth-mainnet`), a CAIP-2 reference (`eip155:1`), a bare decimal or hex chain ID (`1`, `0x1`),
/// and the friendly names the operator catalog seeds (`ethereum`) — and two separate deterministic
/// checks were each interpreting a different subset. That is how `chain.inScope` came to authorize
/// by *name* while `policy.chain.allowed` authorized by *chain ID*, so the same proposal could clear
/// one and never be shown to the other. Both now resolve through here, which means a chain either
/// resolves to a known `Chain` or it does not, and there is no third answer that depends on which
/// check happened to look at it.
public enum ChainScopeReference {
    /// Resolves `raw` to a chain, or `nil` when it names nothing this build knows.
    ///
    /// Fails closed by construction: an unrecognized reference resolves to `nil`, and every caller
    /// treats `nil` as out of scope rather than as unconstrained.
    public static func resolve(_ raw: String) -> Chain? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !trimmed.isEmpty else { return nil }

        if let chain = Chain(rawValue: trimmed) {
            return chain
        }
        if let chain = alias(for: trimmed) {
            return chain
        }
        if let chainID = numericChainID(trimmed) {
            return Chain.allCases.first { $0.chainId == chainID }
        }
        return nil
    }

    /// The numeric chain ID a CAIP-2 / decimal / hex reference denotes, or `nil` if it isn't one.
    public static func numericChainID(_ raw: String) -> Int? {
        var value = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        // Also accept a full CAIP-2 account reference's chain part (`eip155:1:0x…` → `1`).
        if value.hasPrefix("eip155:") {
            value = String(value.dropFirst("eip155:".count))
            if let separator = value.firstIndex(of: ":") {
                value = String(value[value.startIndex..<separator])
            }
        }
        if value.hasPrefix("0x") {
            return Int(value.dropFirst(2), radix: 16)
        }
        return Int(value)
    }

    /// Friendly names that predate canonical ``Chain`` raw values on proposal parameters.
    ///
    /// Kept because the shipped operator catalog seeds `chain: "ethereum"`, and the checks must keep
    /// resolving what production already sends. New parameters should use a `Chain` raw value.
    private static func alias(for value: String) -> Chain? {
        switch value {
        case "ethereum", "eth", "mainnet": return .ethMainnet
        case "sepolia", "eth-sepolia-testnet": return .ethSepoliaTestnet
        case "base": return .baseMainnet
        case "base-sepolia-testnet": return .baseSepoliaTestnet
        // `arbitrum-one`, `op`, and `matic` arrive from the fifth copy of this table, which lived in
        // `AlchemyProposalSimulator` and is now deleted. They are folded in rather than dropped
        // because a simulator that resolved a chain the policy could not would have been the
        // *wider* half — the dry-run reporting on a chain the governed path then refused.
        case "arbitrum", "arb", "arbitrum-one": return .arbMainnet
        case "optimism", "opt", "op": return .optMainnet
        case "polygon", "matic": return .polygonMainnet
        default: return nil
        }
    }
}
