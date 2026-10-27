import AuralisPrimaryModels
import Foundation
import AuralisPolicy
import AuralisRuntime

/// Performs cleared ``PolicyControlledAction``s against the connected wallet — the real effect that turns
/// an approved Operate-mode action into a signature or on-chain transaction.
///
/// This replaces `RuntimeKit`'s fail-closed `UnconfiguredPolicyActionExecutor` in the shipping app. It only runs *after* the
/// governed pipeline has cleared the action (Observe blocks, Assist/Operate escalate for approval, and the
/// executor is invoked on approval-resume), so it never itself decides policy — it reconstructs the payload
/// the user reviewed from `proposal.parameters` and asks the connected signer to perform it.
///
/// Fails closed: no connected signer, a missing/malformed payload, or an unsupported action all throw, so
/// the pipeline records a `.failed` outcome and receipt rather than a false success.
struct WalletActionExecutor: ToolExecuting {
    enum ExecutionError: LocalizedError, Equatable {
        case noConnectedWallet
        case missingPayload
        case unsupported(PolicyControlledAction)
        case addressChecksumMismatch(field: String, address: String)
        case authorizationMismatch

        var errorDescription: String? {
            switch self {
            case .noConnectedWallet:
                return "Connect a signing-capable wallet before running this action."
            case .missingPayload:
                return "This action is missing the details needed to execute it."
            case let .unsupported(action):
                return "“\(action.title)” cannot be executed automatically yet."
            case let .addressChecksumMismatch(field, address):
                return "The \(field) address “\(address)” fails its EIP-55 checksum. "
                    + "It may have been mistyped or altered — the action was not performed."
            case .authorizationMismatch:
                return "This action's approval does not match the action being performed. "
                    + "Nothing was signed or submitted."
            }
        }
    }

    /// Resolves the signer that owns a given address at execution time (see ``WalletSignerBox``): the in-app
    /// self-custodial signer for Auralis addresses, the external connector signer otherwise.
    private let signerProvider: @Sendable @MainActor (String) -> (any WalletActionSigning)?

    init(signerProvider: @escaping @Sendable @MainActor (String) -> (any WalletActionSigning)? = { WalletSignerBox.shared.signer(for: $0) }) {
        self.signerProvider = signerProvider
    }

    func execute(
        _ tool: ToolDefinition,
        proposal: ActionProposal,
        authorization: ToolExecutionAuthorization
    ) async throws -> ToolCallArtifact {
        // `ToolExecutionAuthorization` is unforgeable — only AuralisRuntime can mint one — so holding it is
        // the proof that governance cleared *something*. What it does not prove on its own is that it
        // cleared *this* call, so the capability is checked against the tool and proposal it arrived
        // with. Cheap, and it turns the "only runs after the pipeline cleared it" invariant from a
        // comment into something enforced at the point of effect.
        guard authorization.toolID == tool.id, authorization.proposalID == proposal.id else {
            throw ExecutionError.authorizationMismatch
        }
        guard let payload = PolicyActionPayload(parameters: proposal.parameters) else {
            throw ExecutionError.missingPayload
        }
        // Resolve and use the signer entirely on the main actor so the @MainActor signer never crosses an
        // actor boundary.
        return try await perform(payload: payload, toolID: tool.id)
    }

    /// Internal rather than private so tests can drive the full payload → signer → artifact path.
    /// `execute` cannot be called from the app's test target: minting a `ToolExecutionAuthorization`
    /// is AuralisRuntime-only by design, and widening that to make the executor testable would trade away
    /// the unforgeability the capability exists to provide.
    @MainActor
    func perform(payload: PolicyActionPayload, toolID tool: String) async throws -> ToolCallArtifact {
        guard let signer = signerProvider(payload.actingAddress) else {
            throw ExecutionError.noConnectedWallet
        }

        try Self.validateAddressChecksums(in: payload)

        switch payload {
        case let .signMessage(text, address, chainID):
            let signature = try await signer.signPersonalMessage(text, address: address, chainID: chainID)
            return ToolCallArtifact(
                toolID: tool,
                summary: "Signed message from \(Self.shortAddress(address))",
                outputFields: ["signature": signature, "address": address]
            )

        case let .draftTransaction(from, to, value, data, chainID):
            let hash = try await signer.sendTransaction(from: from, to: to, value: value, data: data, chainID: chainID)
            return ToolCallArtifact(
                toolID: tool,
                summary: "Submitted transaction from \(Self.shortAddress(from))",
                outputFields: ["transactionHash": hash, "from": from]
            )

        case let .approveSpending(token, spender, amount, owner, chainID):
            // ABI-encode `approve(spender, amount)` and route through the same governed send seam as a raw
            // transaction. `ERC20ApproveCallData` refuses unbounded (max-uint256) approvals, so a cleared
            // action can only ever submit the exact allowance the user reviewed.
            let data = try ERC20ApproveCallData.encode(spender: spender, amount: amount)
            let hash = try await signer.sendTransaction(from: owner, to: token, value: "0x0", data: data, chainID: chainID)
            return ToolCallArtifact(
                toolID: tool,
                // "base units" is stated explicitly because `amount` is the raw ABI value, not a display
                // amount — rendering it bare would read as "100 USDC" when it means 0.0001 USDC.
                summary: "Approved \(Self.shortAddress(spender)) to spend \(amount) base units of "
                    + "\(Self.shortAddress(token))",
                outputFields: [
                    "transactionHash": hash,
                    "token": token,
                    "spender": spender,
                    "amount": amount
                ]
            )

        // Plugin invocation needs a plugin host (a separate subsystem, not a wallet operation); fail
        // closed rather than pretend success.
        case .runPlugin:
            throw ExecutionError.unsupported(payload.action)
        }
    }

    /// Rejects any address in `payload` whose mixed-case spelling fails its EIP-55 checksum.
    ///
    /// Checked here rather than in `ERC20ApproveCallData` for two reasons: that encoder is deliberately
    /// dependency-free (EIP-55 needs keccak256), and validating only the `spender` there would have left
    /// `token`, `owner`, `from`, and `to` unchecked — an inconsistency worse than the gap. This covers
    /// every address on every payload kind, at the one point where all of them are in hand.
    ///
    /// `.unchecksummed` deliberately passes: a single-case address carries no checksum to verify, and
    /// lowercase is the form most tooling emits. Only `.invalid` — mixed-case that does *not* match —
    /// is refused, which is the transposed/altered-character case the checksum exists to catch.
    /// `.malformed` is left to the signer's own shape guards, which name the offending field.
    private static func validateAddressChecksums(in payload: PolicyActionPayload) throws {
        let fields: [(String, String?)]
        switch payload {
        case let .signMessage(_, address, _):
            fields = [("signing", address)]
        case let .draftTransaction(from, to, _, _, _):
            fields = [("sender", from), ("recipient", to)]
        case let .approveSpending(token, spender, _, owner, _):
            fields = [("token", token), ("spender", spender), ("owner", owner)]
        case .runPlugin:
            fields = []
        }

        for (name, value) in fields {
            guard let value else { continue }
            if AuralisEthereumAddress.checksumState(of: value) == .invalid {
                throw ExecutionError.addressChecksumMismatch(field: name, address: value)
            }
        }
    }

    private static func shortAddress(_ address: String) -> String {
        guard address.count > 10 else { return address }
        return "\(address.prefix(6))…\(address.suffix(4))"
    }
}
