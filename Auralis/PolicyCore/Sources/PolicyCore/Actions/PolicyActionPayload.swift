/// The concrete operation a ``PolicyControlledAction`` operates on.
///
/// `PolicyControlledAction` names the *class* of action (sign a message, approve spending, …); this
/// carries the actual bytes/parameters the wallet must act on. Kept dependency-free (stringly-typed,
/// no WalletConnectorKit types) so `PolicyCore` stays a leaf: it flattens to and from
/// `ActionProposal.parameters` (`[String: String]`), which survives the escalate → approve → resume
/// round-trip unchanged, so the executor that finally runs after approval sees the same payload the
/// user reviewed.
public enum PolicyActionPayload: Equatable, Sendable {
    /// EIP-191 `personal_sign` over human-readable `text`, from `address` on `chainID` (CAIP-2 / hex).
    case signMessage(text: String, address: String, chainID: String? = nil)
    /// An ERC-20 approval: allow `spender` to move up to `amount` of `token`, authorized by `owner`
    /// on `chainID`.
    ///
    /// `amount` is in the token's **base units** (decimal or `0x` hex), never display units — the same
    /// convention `draftTransaction` uses for `value` in wei. This is load-bearing: the value is
    /// ABI-encoded verbatim into the `approve` calldata, so a producer that passes display units
    /// ("100" meaning 100 USDC) approves 100 base units, off by 10^decimals. A producer that holds a
    /// display amount must multiply by the token's decimals before building this payload.
    case approveSpending(token: String, spender: String, amount: String, owner: String, chainID: String)
    /// A raw `eth_sendTransaction` request.
    case draftTransaction(from: String, to: String?, value: String, data: String, chainID: String)
    /// A named plugin/tool invocation with opaque string parameters.
    case runPlugin(pluginID: String, parameters: [String: String])

    /// The address the action acts *from* — used to route to the wallet that controls it. Empty for
    /// actions with no acting address (e.g. `runPlugin`).
    public var actingAddress: String {
        switch self {
        case let .signMessage(_, address, _): return address
        case let .approveSpending(_, _, _, owner, _): return owner
        case let .draftTransaction(from, _, _, _, _): return from
        case .runPlugin: return ""
        }
    }

    /// The action class this payload is valid for. A gate can assert the payload matches the action.
    public var action: PolicyControlledAction {
        switch self {
        case .signMessage: return .signMessage
        case .approveSpending: return .approveSpending
        case .draftTransaction: return .draftTransaction
        case .runPlugin: return .runPlugin
        }
    }

    // MARK: - Flattening for ActionProposal.parameters

    private enum Key {
        static let kind = "payload.kind"
        static let text = "payload.text"
        static let address = "payload.address"
        static let chainID = "payload.chainID"
        static let token = "payload.token"
        static let spender = "payload.spender"
        static let amount = "payload.amount"
        static let owner = "payload.owner"
        static let from = "payload.from"
        static let to = "payload.to"
        static let value = "payload.value"
        static let data = "payload.data"
        static let pluginID = "payload.pluginID"
        /// Prefix under which `runPlugin` parameters are nested so they can't collide with the fixed keys.
        static let pluginParamPrefix = "payload.plugin."
    }

    /// Flattens to `[String: String]` for carrying on `ActionProposal.parameters`.
    public var parameters: [String: String] {
        switch self {
        case let .signMessage(text, address, chainID):
            var out = [Key.kind: action.rawValue, Key.text: text, Key.address: address]
            out[Key.chainID] = chainID
            return out
        case let .approveSpending(token, spender, amount, owner, chainID):
            return [
                Key.kind: action.rawValue,
                Key.token: token,
                Key.spender: spender,
                Key.amount: amount,
                Key.owner: owner,
                Key.chainID: chainID
            ]
        case let .draftTransaction(from, to, value, data, chainID):
            var out = [
                Key.kind: action.rawValue,
                Key.from: from,
                Key.value: value,
                Key.data: data,
                Key.chainID: chainID
            ]
            out[Key.to] = to
            return out
        case let .runPlugin(pluginID, parameters):
            var out = [Key.kind: action.rawValue, Key.pluginID: pluginID]
            for (key, value) in parameters {
                out[Key.pluginParamPrefix + key] = value
            }
            return out
        }
    }

    /// Reconstructs a payload from flattened `ActionProposal.parameters`, or `nil` if the required
    /// fields for the encoded kind are missing (fail-closed: a malformed payload is not executed).
    public init?(parameters: [String: String]) {
        guard let kind = parameters[Key.kind],
              let action = PolicyControlledAction(rawValue: kind) else {
            return nil
        }
        switch action {
        case .signMessage:
            guard let text = parameters[Key.text], let address = parameters[Key.address] else { return nil }
            self = .signMessage(text: text, address: address, chainID: parameters[Key.chainID])
        case .approveSpending:
            guard let token = parameters[Key.token],
                  let spender = parameters[Key.spender],
                  let amount = parameters[Key.amount],
                  let owner = parameters[Key.owner],
                  let chainID = parameters[Key.chainID] else { return nil }
            self = .approveSpending(token: token, spender: spender, amount: amount, owner: owner, chainID: chainID)
        case .draftTransaction:
            guard let from = parameters[Key.from],
                  let value = parameters[Key.value],
                  let data = parameters[Key.data],
                  let chainID = parameters[Key.chainID] else { return nil }
            self = .draftTransaction(from: from, to: parameters[Key.to], value: value, data: data, chainID: chainID)
        case .runPlugin:
            guard let pluginID = parameters[Key.pluginID] else { return nil }
            var pluginParams: [String: String] = [:]
            for (key, value) in parameters where key.hasPrefix(Key.pluginParamPrefix) {
                pluginParams[String(key.dropFirst(Key.pluginParamPrefix.count))] = value
            }
            self = .runPlugin(pluginID: pluginID, parameters: pluginParams)
        }
    }
}
