import AccountsCore
import AuralisPrimaryModels
import AuralisPolicy
import AuralisRuntime

public enum PolicyToolCheckID {
    public static let payloadValid = "policy.payload.valid"
    public static let chainAllowed = "policy.chain.allowed"
    public static let approvalBounded = "policy.approval.bounded"
    public static let addressChecksum = "policy.address.checksum"
}

struct PolicyPayloadCheck: DeterministicCheck {
    let id = PolicyToolCheckID.payloadValid

    func evaluate(_ proposal: ActionProposal) async -> DeterministicCheckResult {
        guard let payload = PolicyActionPayload(parameters: proposal.parameters) else {
            return .init(checkID: id, passed: false, detail: "payload cannot be decoded")
        }
        let action = payload.action
        let valid = action.capabilityID == proposal.capability
            && CapabilityImpactMapping.defaultImpact(for: action.capabilityID) == proposal.impact
        return .init(
            checkID: id,
            passed: valid,
            detail: valid ? nil : "payload kind does not match the proposal capability and impact"
        )
    }
}

/// Validates the chain ID carried on a decoded ``PolicyActionPayload`` against the governed chain scope.
///
/// Complements — rather than duplicates — `chain.inScope`: this one reads the *payload's* chain ID,
/// which is the value the wallet will actually sign against, while `chain.inScope` reads the
/// proposal's `chain` parameter. References resolve through ``ChainScopeReference`` so the two cannot
/// disagree about what a reference *denotes*, and both now draw their allowlist from the host's
/// ``StandardCheckConfiguration/allowedChains`` so they cannot disagree about *scope* either.
///
/// That second half used to be broken. This check hardcoded every non-Solana ``Chain`` (~30) while
/// `chain.inScope` shipped a three-chain allowlist, so one capability had two scopes depending on
/// entry point: `operator.onchain.prepareAction` refused Arbitrum while `policy.draftTransaction`
/// allowed it — and the wide allowlist was the one sitting on the signing path. Unifying on the
/// configured set resolves it in the fail-safe direction; a host that needs to sign on more chains
/// widens the scope explicitly at the composition root, where the decision is visible.
struct PolicyChainAllowlistCheck: DeterministicCheck {
    let id = PolicyToolCheckID.chainAllowed

    private let allowedChainIDs: Set<Int>

    init(allowed: Set<Chain>) {
        // Solana stays excluded regardless of scope: these payloads are EVM requests, and a Solana
        // chain's `chainId` is not an EIP-155 chain ID, so admitting one would let a non-EVM chain
        // match by numeric coincidence.
        allowedChainIDs = Set(
            allowed
                .filter { $0 != .solanaMainnet && $0 != .solanaDevnetTestnet }
                .map(\.chainId)
        )
    }

    func evaluate(_ proposal: ActionProposal) async -> DeterministicCheckResult {
        guard let payload = PolicyActionPayload(parameters: proposal.parameters) else {
            return .init(checkID: id, passed: false, detail: "payload cannot be decoded")
        }
        let rawChainID: String?
        switch payload {
        case let .signMessage(_, _, chainID): rawChainID = chainID
        case let .approveSpending(_, _, _, _, chainID): rawChainID = chainID
        case let .draftTransaction(_, _, _, _, chainID): rawChainID = chainID
        case .runPlugin: rawChainID = nil
        }
        guard let rawChainID else {
            return .init(checkID: id, passed: true, detail: "no chain required")
        }
        guard let chainID = ChainScopeReference.numericChainID(rawChainID) else {
            return .init(checkID: id, passed: false, detail: "invalid chain ID")
        }
        let allowed = allowedChainIDs.contains(chainID)
        return .init(checkID: id, passed: allowed, detail: allowed ? nil : "chain is outside the governed chain scope")
    }
}

/// Verifies the EIP-55 checksum on every address a decoded ``PolicyActionPayload`` carries.
///
/// Complements `address.format` exactly the way ``PolicyChainAllowlistCheck`` complements
/// `chain.inScope`. `address.format` reads `parameters["address"]` and `parameters["watchlist"]`,
/// which the wallet payloads never populate — they carry addresses under `payload.from`,
/// `payload.spender`, and friends. Requiring `address.format` on these tools would therefore pass
/// *vacuously* ("no address to check") while the signing path got nothing but the input schema's
/// shape rule: 40 hex characters, no checksum (``ToolSchemaField/Kind/address``). That leaves open
/// the one error class checksums exist to catch — a mistyped or truncated-and-repaired address that
/// is still perfectly well-formed hex — on `draftTransaction` and `approveSpending`, which are the
/// highest-impact actions in the app.
///
/// An unchecksummed (all-lower or all-upper) address passes with a note rather than failing. It
/// carries no checksum to verify, and dapps routinely send addresses in that form, so refusing them
/// would break live sessions without catching a single transposition.
struct PolicyAddressChecksumCheck: DeterministicCheck {
    let id = PolicyToolCheckID.addressChecksum

    func evaluate(_ proposal: ActionProposal) async -> DeterministicCheckResult {
        guard let payload = PolicyActionPayload(parameters: proposal.parameters) else {
            return .init(checkID: id, passed: false, detail: "payload cannot be decoded")
        }
        // Field/value pairs rather than bare values, so a failure can name the offending field
        // without ever writing the address itself into the permanent record.
        let addresses: [(field: String, value: String)]
        switch payload {
        case let .signMessage(_, address, _):
            addresses = [("payload.address", address)]
        case let .approveSpending(token, spender, _, owner, _):
            addresses = [
                ("payload.token", token),
                ("payload.spender", spender),
                ("payload.owner", owner)
            ]
        case let .draftTransaction(from, to, _, _, _):
            // `to` is legitimately absent for a contract creation, so a nil recipient is not a
            // missing address. An empty-but-present one still has to be well formed.
            addresses = [("payload.from", from)] + (to.map { [("payload.to", $0)] } ?? [])
        case .runPlugin:
            return .init(checkID: id, passed: true, detail: "no address required")
        }

        var unchecksummedFields: [String] = []
        for (field, value) in addresses {
            switch AuralisEthereumAddress.checksumState(of: value) {
            case .malformed:
                return .init(checkID: id, passed: false, detail: "\(field) is not a well-formed address")
            case .invalid:
                return .init(checkID: id, passed: false, detail: "\(field) failed its EIP-55 checksum")
            case .unchecksummed:
                unchecksummedFields.append(field)
            case .valid:
                continue
            }
        }
        return .init(
            checkID: id,
            severity: unchecksummedFields.isEmpty ? .pass : .warning,
            detail: unchecksummedFields.isEmpty
                ? nil
                : "well-formed but unchecksummed: \(unchecksummedFields.joined(separator: ", "))"
        )
    }
}

/// Refuses an ERC-20 approval that is either zero or effectively unlimited.
///
/// Comparison is on the approval's *value*, not its spelling, and that distinction is the whole
/// check. ``ToolSchemaField/Kind/unsignedQuantity`` admits hexadecimal of any length and decimal
/// with leading zeros, so 2²⁵⁶−1 can arrive as `0xff…ff` (64 digits), as `0x00ff…ff`, or as its
/// decimal form with a zero in front — all the same number. Matching the two canonical spellings
/// exactly, as this once did, let every padded variant through as "bounded": an infinite approval
/// cleared by the one check that exists to refuse it, on the highest-impact action in the app.
///
/// Values *above* 2²⁵⁶−1 are refused on the same branch. They cannot be represented on-chain, so
/// they are malformed rather than merely large, and treating them as bounded would reopen the same
/// hole one digit further along.
struct BoundedApprovalCheck: DeterministicCheck {
    let id = PolicyToolCheckID.approvalBounded

    /// 2²⁵⁶−1, in each base, with no leading zeros — the form ``significantDigits(of:)`` produces.
    private static let maximumUInt256Decimal = "115792089237316195423570985008687907853269984665640564039457584007913129639935"
    private static let maximumUInt256Hex = String(repeating: "f", count: 64)

    func evaluate(_ proposal: ActionProposal) async -> DeterministicCheckResult {
        guard let payload = PolicyActionPayload(parameters: proposal.parameters) else {
            return .init(checkID: id, passed: false, detail: "payload cannot be decoded")
        }
        guard case let .approveSpending(_, _, amount, _, _) = payload else {
            return .init(checkID: id, passed: false, detail: "bounded approval check requires an approval payload")
        }
        let normalized = amount.lowercased()
        let isHex = normalized.hasPrefix("0x")
        let significant = Self.significantDigits(of: isHex ? String(normalized.dropFirst(2)) : normalized)
        // No significant digits left means every digit was a zero (or there were none at all, which
        // the input schema rejects but this check must not assume).
        let isZero = significant.isEmpty
        let maximum = isHex ? Self.maximumUInt256Hex : Self.maximumUInt256Decimal
        // Same-length numeric strings with no leading zeros order lexicographically the way they
        // order numerically, in both bases — ASCII puts `0`–`9` below `a`–`f`.
        let isUnlimited = significant.count > maximum.count
            || (significant.count == maximum.count && significant >= maximum)
        let bounded = isZero == false && isUnlimited == false
        return .init(
            checkID: id,
            passed: bounded,
            detail: bounded ? nil : "approval amount must be positive and may not be unlimited"
        )
    }

    private static func significantDigits(of digits: String) -> String {
        String(digits.drop(while: { $0 == "0" }))
    }
}

extension DeterministicCheckRegistry {
    /// - Parameters:
    ///   - configuration: The governed chain scope, shared with `registerStandardChecks` so the
    ///     payload-level and parameter-level chain checks cannot diverge.
    /// - Returns: The IDs that collided with an already-registered check of a different type.
    @discardableResult
    func registerPolicyToolChecks(
        _ configuration: StandardCheckConfiguration = .default
    ) async -> [String] {
        let checks: [any DeterministicCheck] = [
            PolicyPayloadCheck(),
            PolicyChainAllowlistCheck(allowed: configuration.allowedChains),
            PolicyAddressChecksumCheck(),
            BoundedApprovalCheck()
        ]
        return checks.compactMap { check in
            guard case let .conflict(id) = register(check) else { return nil }
            return id
        }
    }
}
