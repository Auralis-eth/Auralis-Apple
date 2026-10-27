import AuralisCrypto
import Foundation
import AuralisMissionControl
import AuralisRuntime

/// P1-AGENT-103 — real on-chain dry-run of a proposed EVM transaction via Alchemy's
/// `alchemy_simulateAssetChanges`, which returns whether the transaction would revert, the gas it
/// would consume, and the balance/asset movements it would cause. This turns the Proposal Diff
/// Viewer from a declared-impact preview into an actual transaction simulation.
///
/// Resolves its RPC endpoint through the same `ProviderConfigurationResolving` seam the rest of the
/// app uses, so it inherits key handling and per-chain routing. Degrades to a plain "unavailable"
/// result (never a crash) when no key/endpoint is configured or the network is unreachable.
struct AlchemyProposalSimulator: ProposalSimulating {
    private let configurationResolver: any ProviderConfigurationResolving
    private let session: URLSession

    init(
        configurationResolver: any ProviderConfigurationResolving = LiveProviderConfigurationResolver(),
        session: URLSession = .shared
    ) {
        self.configurationResolver = configurationResolver
        self.session = session
    }

    func simulate(_ proposal: ActionProposal) async -> ProposalSimulation {
        guard let intent = EVMTransactionIntent.from(proposal: proposal) else {
            return ProposalSimulation(status: .notApplicable)
        }
        // The proposal didn't name a network, so the chain below is a default, not a stated fact.
        // Trimmed to match `resolveChain`, which also trims — otherwise a whitespace-only chain key
        // reported the Ethereum-mainnet default as a stated fact rather than an assumption.
        let chainAssumed = (intent.chainKey?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
        guard let chain = Self.resolveChain(intent.chainKey) else {
            return ProposalSimulation(
                status: .unavailable("Couldn't resolve a supported EVM network for this proposal.")
            )
        }

        let rpcURL: URL
        do {
            let configuration = try configurationResolver.configuration(for: chain)
            guard let url = configuration.alchemyRPCURL else {
                return ProposalSimulation(
                    status: .unavailable(
                        "On-chain simulation isn't configured for \(chain.routingDisplayName). Add an Alchemy API key to enable it."
                    ),
                    chainName: chain.networkName
                )
            }
            rpcURL = url
        } catch {
            return ProposalSimulation(
                status: .unavailable("Couldn't resolve an RPC endpoint for \(chain.routingDisplayName)."),
                chainName: chain.networkName
            )
        }

        do {
            return try await run(intent: intent, chain: chain, rpcURL: rpcURL, chainAssumed: chainAssumed)
        } catch {
            return ProposalSimulation(
                status: .unavailable("Couldn't reach the simulation endpoint."),
                chainName: chain.networkName,
                chainAssumed: chainAssumed
            )
        }
    }

    private func run(
        intent: EVMTransactionIntent,
        chain: Chain,
        rpcURL: URL,
        chainAssumed: Bool
    ) async throws -> ProposalSimulation {
        var request = URLRequest(url: rpcURL)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(
            RPCRequest(
                method: "alchemy_simulateAssetChanges",
                params: [TxParam(from: intent.from, to: intent.to, value: intent.valueHex, data: intent.dataHex)]
            )
        )

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            return ProposalSimulation(
                status: .unavailable("The simulation endpoint returned an error."),
                chainName: chain.networkName,
                chainAssumed: chainAssumed
            )
        }

        let decoded = try JSONDecoder().decode(RPCResponse.self, from: data)
        if let rpcError = decoded.error {
            return ProposalSimulation(
                status: .unavailable(Self.trimmed(rpcError.message)),
                chainName: chain.networkName,
                chainAssumed: chainAssumed
            )
        }
        guard let result = decoded.result else {
            return ProposalSimulation(
                status: .unavailable("Simulation returned no result."),
                chainName: chain.networkName,
                chainAssumed: chainAssumed
            )
        }

        let gasUsed = Self.decimalGas(result.gasUsed)
        // Best-effort native-token cost estimate: gasUsed × current gas price. Never fails the
        // simulation — a nil price just omits the cost line.
        let gasCost = await estimatedGasCostEth(gasUsedDecimal: gasUsed, rpcURL: rpcURL)

        if let revert = result.error?.message, !revert.isEmpty {
            return ProposalSimulation(
                status: .reverted(Self.trimmed(revert)),
                chainName: chain.networkName,
                chainAssumed: chainAssumed,
                gasUsed: gasUsed,
                estimatedGasCostEth: gasCost
            )
        }

        let changes = (result.changes ?? []).compactMap { Self.mapChange($0, sender: intent.from) }
        return ProposalSimulation(
            status: .success,
            chainName: chain.networkName,
            chainAssumed: chainAssumed,
            gasUsed: gasUsed,
            estimatedGasCostEth: gasCost,
            assetChanges: changes
        )
    }

    /// Fetches the current gas price via `eth_gasPrice` and multiplies by `gasUsedDecimal` to get a
    /// rough native-token (ETH) cost. Returns nil when either value is missing or the call fails.
    private func estimatedGasCostEth(gasUsedDecimal: String?, rpcURL: URL) async -> String? {
        guard let gasUsedDecimal, let gasUsed = UInt64(gasUsedDecimal) else { return nil }
        guard let gasPriceWei = await gasPriceWei(rpcURL: rpcURL) else { return nil }
        return Self.formatEth(gasUnits: gasUsed, gasPriceWei: gasPriceWei)
    }

    private func gasPriceWei(rpcURL: URL) async -> UInt64? {
        var request = URLRequest(url: rpcURL)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        do {
            request.httpBody = try JSONEncoder().encode(GasPriceRequest())
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                return nil
            }
            let decoded = try JSONDecoder().decode(GasPriceResponse.self, from: data)
            guard let hex = decoded.result, hex.lowercased().hasPrefix("0x") else { return nil }
            return UInt64(hex.dropFirst(2), radix: 16)
        } catch {
            return nil
        }
    }

    /// Formats `gasUnits × gasPriceWei` (wei) as an ETH string. Uses `Double` since this is an
    /// intentionally approximate estimate, and trims trailing zeros.
    static func formatEth(gasUnits: UInt64, gasPriceWei: UInt64) -> String {
        let wei = Double(gasUnits) * Double(gasPriceWei)
        let eth = wei / 1e18
        // A non-zero fee must never render as zero. At 6 decimals every typical L2 cost (~1e-7 ETH)
        // formatted to "0.000000", which the trailing-zero trim then reduced to "0.0" — so every
        // Base/Arbitrum/Optimism simulation told the user the transaction was free. Below the display
        // precision, say so explicitly rather than rounding the fee away.
        guard eth > 0 else { return "0.0" }
        guard eth >= 0.000001 else { return "<0.000001" }
        let formatted = String(format: "%.6f", eth)
        // Trim trailing zeros but keep at least one decimal place.
        var trimmed = formatted
        while trimmed.hasSuffix("0") { trimmed.removeLast() }
        if trimmed.hasSuffix(".") { trimmed += "0" }
        return trimmed
    }

    // MARK: - Mapping

    /// Resolves a chain reference; defaults to Ethereum mainnet when a transaction target exists but
    /// no chain was specified.
    ///
    /// Delegates to ``ChainScopeReference/resolve(_:)``, which is the one place chain identity is
    /// decided. This was a fifth private copy of that alias table and it had drifted *wider* than
    /// the canonical one — it knew `op`, `matic`, and `arbitrum-one`, which the governed checks did
    /// not — so the simulator could dry-run and report on a chain that `chain.inScope` would then
    /// refuse. Those three aliases moved into `ChainScopeReference` rather than being dropped. The
    /// numeric forms this table spelled out (`"1"`, `"8453"`, `"42161"`, …) need no replacement:
    /// `resolve` already handles decimal, hex, and CAIP-2 chain IDs via `numericChainID`.
    static func resolveChain(_ key: String?) -> Chain? {
        guard let key, !key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return .ethMainnet
        }
        return ChainScopeReference.resolve(key)
    }

    static func decimalGas(_ hex: String?) -> String? {
        guard let hex, hex.lowercased().hasPrefix("0x"),
              let value = UInt64(hex.dropFirst(2), radix: 16) else { return nil }
        return String(value)
    }

    static func mapChange(_ change: SimChange, sender: String?) -> ProposalAssetChange? {
        guard let amount = change.amount, !amount.isEmpty else { return nil }
        let symbol = change.symbol ?? change.assetType ?? "asset"
        let direction: ProposalAssetChange.Direction
        // Without a known sender we can't say whether a movement is in- or outgoing; mark it unknown
        // rather than defaulting to "outgoing", which would be a wrong signal on a trust surface.
        // A change the sender is not a party to is `.unknown`, not `.outgoing`. The ternary this
        // replaces resolved *every* non-incoming change as outgoing, including the legs of a routed
        // swap, a transfer between two counterparties, and refund hops — rendering third-party asset
        // movement as money leaving the user, on the last trust surface before they sign.
        if let senderLower = sender?.lowercased(), !senderLower.isEmpty {
            if change.to?.lowercased() == senderLower {
                direction = .incoming
            } else if change.from?.lowercased() == senderLower {
                direction = .outgoing
            } else {
                direction = .unknown
            }
        } else {
            direction = .unknown
        }
        let counterparty: String?
        switch direction {
        case .incoming: counterparty = change.from
        case .outgoing: counterparty = change.to
        case .unknown: counterparty = change.to ?? change.from
        }
        return ProposalAssetChange(direction: direction, amount: amount, symbol: symbol, counterparty: counterparty)
    }

    private static func trimmed(_ message: String) -> String {
        let collapsed = message.trimmingCharacters(in: .whitespacesAndNewlines)
        return collapsed.count > 240 ? String(collapsed.prefix(240)) + "…" : collapsed
    }

    // MARK: - Wire types

    private struct RPCRequest: Encodable {
        let jsonrpc = "2.0"
        let id = 1
        let method: String
        let params: [TxParam]
    }

    private struct TxParam: Encodable {
        let from: String?
        let to: String
        let value: String
        let data: String
    }

    private struct GasPriceRequest: Encodable {
        let jsonrpc = "2.0"
        let id = 1
        let method = "eth_gasPrice"
        let params: [String] = []
    }

    private struct GasPriceResponse: Decodable {
        let result: String?
    }

    private struct RPCResponse: Decodable {
        let result: SimResult?
        let error: RPCError?
    }

    private struct RPCError: Decodable {
        let code: Int
        let message: String
    }

    private struct SimResult: Decodable {
        let changes: [SimChange]?
        let gasUsed: String?
        let error: SimError?
    }

    private struct SimError: Decodable {
        let message: String?
    }

    struct SimChange: Decodable {
        let assetType: String?
        let changeType: String?
        let from: String?
        let to: String?
        let amount: String?
        let symbol: String?
        let contractAddress: String?
    }
}
