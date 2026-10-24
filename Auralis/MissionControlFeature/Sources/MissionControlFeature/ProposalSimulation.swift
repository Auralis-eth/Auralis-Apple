import Foundation
import RuntimeCore

/// P1-AGENT-103 — the result of an on-chain *dry-run* of a proposed transaction, so the Proposal
/// Diff Viewer can show what would actually happen (revert / gas / balance-and-asset deltas) rather
/// than only the declared-impact metadata. This is the "transaction simulation" trust layer.
public struct ProposalSimulation: Equatable, Sendable {
    public enum Status: Equatable, Sendable {
        /// The transaction executed against current chain state without reverting.
        case success
        /// The transaction reverted; the associated string is the revert reason when the node
        /// returned one.
        case reverted(String)
        /// The proposal carries no concrete on-chain transaction to simulate (e.g. a read-only or
        /// non-crypto action). Nothing to dry-run — not an error.
        case notApplicable
        /// Simulation could not be performed (no configured provider/key, unsupported chain, or a
        /// transport error). The string explains why, in plain language.
        case unavailable(String)
    }

    public let status: Status
    /// Human-readable chain name the simulation ran against, when known.
    public let chainName: String?
    /// True when the proposal didn't specify a network and the simulation fell back to a default
    /// chain (Ethereum mainnet). Surfaced in the UI so an assumed network never reads as a fact.
    public let chainAssumed: Bool
    /// Gas the dry-run reported it would consume, in decimal gas units, when known.
    public let gasUsed: String?
    /// Rough native-token cost of `gasUsed` at the current gas price, formatted in ETH (e.g.
    /// "0.00042"), when a gas price could be fetched. An estimate — gas price moves before execution.
    public let estimatedGasCostEth: String?
    /// The asset movements the simulation predicts (native + tokens/NFTs), from the sender's
    /// perspective. Empty for a `notApplicable`/`unavailable`/pure-`success`-with-no-transfers run.
    public let assetChanges: [ProposalAssetChange]

    public init(
        status: Status,
        chainName: String? = nil,
        chainAssumed: Bool = false,
        gasUsed: String? = nil,
        estimatedGasCostEth: String? = nil,
        assetChanges: [ProposalAssetChange] = []
    ) {
        self.status = status
        self.chainName = chainName
        self.chainAssumed = chainAssumed
        self.gasUsed = gasUsed
        self.estimatedGasCostEth = estimatedGasCostEth
        self.assetChanges = assetChanges
    }
}

/// A single predicted asset movement from a transaction simulation.
public struct ProposalAssetChange: Identifiable, Equatable, Sendable {
    public enum Direction: Equatable, Sendable {
        case outgoing
        case incoming
        /// The simulation couldn't attribute a direction — typically because the proposal carried no
        /// sender address to compare against. Rendered neutrally so a movement is never mislabelled.
        case unknown
    }

    public let id: UUID
    public let direction: Direction
    /// Formatted amount as returned by the simulator (already decimal-adjusted), e.g. "0.25".
    public let amount: String
    /// Asset symbol (e.g. "ETH", "USDC"), or a short asset-type label when no symbol is known.
    public let symbol: String
    /// The counterparty address (recipient for outgoing, source for incoming), when known.
    public let counterparty: String?

    public init(
        id: UUID = UUID(),
        direction: Direction,
        amount: String,
        symbol: String,
        counterparty: String? = nil
    ) {
        self.id = id
        self.direction = direction
        self.amount = amount
        self.symbol = symbol
        self.counterparty = counterparty
    }
}

/// Runs an on-chain dry-run for a proposal. Implemented app-side against a live RPC provider; the
/// UI package depends only on this abstraction so it never links a chain SDK directly.
public protocol ProposalSimulating: Sendable {
    func simulate(_ proposal: ActionProposal) async -> ProposalSimulation
}

/// The concrete EVM transaction a proposal would submit, recovered from its stringly parameters.
///
/// A proposal only carries a simulatable transaction once it has a destination (`to`). This
/// extractor is deliberately liberal about parameter naming so it works across the deterministic and
/// model planners without coupling the UI to any single convention.
public struct EVMTransactionIntent: Equatable, Sendable {
    public let from: String?
    public let to: String
    /// Wei value as a 0x-prefixed hex quantity ("0x0" when none).
    public let valueHex: String
    /// Calldata as a 0x-prefixed hex string ("0x" when none).
    public let dataHex: String
    /// The raw chain key from the proposal (e.g. "ethereum", "base", "eth-mainnet"), when present.
    public let chainKey: String?

    public init(from: String?, to: String, valueHex: String, dataHex: String, chainKey: String?) {
        self.from = from
        self.to = to
        self.valueHex = valueHex
        self.dataHex = dataHex
        self.chainKey = chainKey
    }

    // The `payload.*` spellings are how a governed wallet action actually reaches here:
    // `RuntimeHost.runPolicyAction` builds its proposal from `PolicyActionPayload.parameters`, which
    // namespaces every field under `payload.` so it cannot collide with a plugin's own parameters.
    // Without these aliases the extractor matched none of them and the simulator reported
    // `.notApplicable` for exactly the transactions it exists to dry-run.
    //
    // `payload.token`/`payload.owner` are deliberately **absent**. An `approveSpending` payload carries
    // `token`, `spender`, and `amount` but no calldata — the `approve(address,uint256)` bytes are built
    // later, by the executor. Treating the token contract as a destination therefore produced an intent
    // with `valueHex: "0x0"` and `dataHex: "0x"`, and the simulator dutifully dry-ran *that*: a no-op
    // call to the token contract, rendered to the user as "succeeds, no asset changes" for an approval
    // whose real calldata was never simulated. A confident wrong answer on the last check before signing
    // is worse than no answer, so an approval stays `.notApplicable` until this layer can reconstruct
    // the calldata.
    private static let toKeys = [
        "to", "toAddress", "recipient", "contract", "contractAddress",
        "payload.to"
    ]
    private static let fromKeys = [
        "from", "fromAddress", "sender", "account", "address",
        "payload.from", "payload.address"
    ]
    private static let valueKeys = ["value", "valueWei", "amountWei", "wei", "payload.value"]
    private static let dataKeys = ["data", "calldata", "input", "payload.data"]
    private static let chainKeys = ["chain", "chainId", "network", "payload.chainID"]

    /// Recovers a transaction from a proposal's parameters, or `nil` when the proposal has no
    /// destination to send to (nothing to dry-run).
    public static func from(proposal: ActionProposal) -> EVMTransactionIntent? {
        let params = proposal.parameters
        guard let to = firstValue(in: params, keys: toKeys), !to.isEmpty else { return nil }

        let value = firstValue(in: params, keys: valueKeys).flatMap(normalizeHexQuantity) ?? "0x0"
        let data = firstValue(in: params, keys: dataKeys).map(normalizeHexData) ?? "0x"
        return EVMTransactionIntent(
            from: firstValue(in: params, keys: fromKeys),
            to: to,
            valueHex: value,
            dataHex: data,
            chainKey: firstValue(in: params, keys: chainKeys)
        )
    }

    private static func firstValue(in params: [String: String], keys: [String]) -> String? {
        for key in keys {
            if let value = params[key], !value.isEmpty { return value }
        }
        return nil
    }

    /// The network key a proposal names, checked across every accepted alias (`chain`, `chainId`,
    /// `network`), or nil when none is present. Shared with the Context Bundle Inspector so the
    /// "chains in scope" surface and the simulator agree on what network a proposal targets.
    public static func chainKey(from proposal: ActionProposal) -> String? {
        firstValue(in: proposal.parameters, keys: chainKeys)
    }

    /// Accepts a hex quantity as-is, or converts a plain decimal integer string to hex.
    ///
    /// Uses arbitrary-precision decimal→hex conversion (not `UInt64`) so a wei value above the
    /// 64-bit ceiling (~18.4 ETH) is represented faithfully rather than silently failing and being
    /// treated as `0x0` — a zero-value transfer would read as safe on the simulation trust surface.
    static func normalizeHexQuantity(_ raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespaces)
        if trimmed.lowercased().hasPrefix("0x") { return trimmed }
        return decimalStringToHexQuantity(trimmed)
    }

    /// Converts a non-negative decimal integer string of any length to a `0x` hex quantity by
    /// repeatedly dividing the decimal digits by 16 and collecting the remainders. Returns nil for
    /// empty input or anything that isn't ASCII decimal digits.
    static func decimalStringToHexQuantity(_ decimal: String) -> String? {
        guard !decimal.isEmpty else { return nil }
        var current = [Int]()
        current.reserveCapacity(decimal.count)
        for scalar in decimal.unicodeScalars {
            guard scalar.value >= 48, scalar.value <= 57 else { return nil }
            current.append(Int(scalar.value - 48))
        }
        // Normalize leading zeros; a value of zero short-circuits to "0x0".
        while current.count > 1, current.first == 0 { current.removeFirst() }
        if current == [0] { return "0x0" }

        let hexAlphabet = Array("0123456789abcdef")
        var nibbles = [Character]()
        while !(current.count == 1 && current.first == 0) {
            var remainder = 0
            var quotient = [Int]()
            quotient.reserveCapacity(current.count)
            for digit in current {
                let accumulated = remainder * 10 + digit
                quotient.append(accumulated / 16)
                remainder = accumulated % 16
            }
            while quotient.count > 1, quotient.first == 0 { quotient.removeFirst() }
            nibbles.append(hexAlphabet[remainder])
            current = quotient
        }
        return "0x" + String(nibbles.reversed())
    }

    /// Ensures calldata is 0x-prefixed.
    static func normalizeHexData(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespaces)
        return trimmed.lowercased().hasPrefix("0x") ? trimmed : "0x" + trimmed
    }
}
