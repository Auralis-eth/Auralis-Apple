import Foundation
import AuralisRuntime

/// The concrete deterministic checks the runtime ships with (P0.5-802). All are pure and operate on
/// `ActionProposal.parameters`, so they're reproducible from a receipt and require no network or heavy
/// dependencies. (ENS *resolution* — as opposed to name-format validation — is an async concern handled
/// elsewhere, not a deterministic check.)
///
/// The record-shape checks (`receipt.schema`, `artifact.schema`) live in `AuralisAppShell` instead, because
/// the schemas they validate sit above this package in the dependency graph.
/// One chain/address/ENS triple that the target-shaped checks validate.
///
/// Every field is optional because the three checks are independent: a proposal may name a chain
/// and no address, or an ENS name and no address, and each named value still has to be valid. An
/// earlier version required `address` to be present before it would build a target at all, so a
/// proposal carrying `chain` or `ens` without an `address` decoded to *zero* targets and both
/// `chain.inScope` and `ens.format` returned "nothing to check" — a fail-open in two governance
/// checks that only stayed unreachable because the two tools requiring them also require an address.
private struct CheckTarget {
    let chain: String?
    let address: String?
    let ens: String?

    var namesNothing: Bool { chain == nil && address == nil && ens == nil }
}

/// The serialized watchlist entry shape.
///
/// Deliberately stricter than ``CheckTarget``: `chain` and `address` are required, so an entry that
/// omits either is a malformed watchlist rather than an entry with nothing to check. Decoding those
/// into `nil` would hand `chain.inScope` an empty list and wave the entry through.
private struct WatchlistEntry: Decodable {
    let chain: String
    let address: String
    let ens: String?
}

private enum CheckTargetDecodeError: Error {
    case malformedWatchlist
}

private enum CheckTargets {
    static func decode(from proposal: ActionProposal) -> Result<[CheckTarget], CheckTargetDecodeError> {
        if let encoded = proposal.parameters["watchlist"] {
            guard let data = encoded.data(using: .utf8),
                  let entries = try? JSONDecoder().decode([WatchlistEntry].self, from: data) else {
                return .failure(.malformedWatchlist)
            }
            return .success(entries.map { CheckTarget(chain: $0.chain, address: $0.address, ens: $0.ens) })
        }
        let target = CheckTarget(
            chain: proposal.parameters["chain"],
            address: proposal.parameters["address"],
            ens: proposal.parameters["ens"]
        )
        return .success(target.namesNothing ? [] : [target])
    }
}

/// Validates `parameters["address"]` is a well-formed Ethereum address *and*, when it carries an
/// EIP-55 checksum, that the checksum is correct (when present).
///
/// The checksum is the whole reason this check exists as something more than the input schema.
/// `ToolSchemaField.Kind.address` already rejects anything that isn't 40 hex characters, so a
/// shape-only check here would be pure duplication — and would wave through the one error class
/// checksums were designed to catch: a mistyped or truncated-and-repaired address that is still
/// perfectly well-formed hex. That address goes on to reach `draftTransaction`, which is high-risk.
public struct AddressFormatCheck: DeterministicCheck {
    public let id = StandardCheckID.addressFormat
    public init() { }

    public func evaluate(_ proposal: ActionProposal) async -> DeterministicCheckResult {
        guard case let .success(targets) = CheckTargets.decode(from: proposal) else {
            return .init(checkID: id, passed: false, detail: "watchlist is not valid JSON")
        }
        let addresses = targets.compactMap(\.address)
        guard !addresses.isEmpty else {
            return .init(checkID: id, passed: true, detail: "no address to check")
        }
        var containsUnchecksummedAddress = false
        for address in addresses {
            switch AuralisEthereumAddress.checksumState(of: address) {
            case .malformed:
                return .init(checkID: id, passed: false, detail: "malformed address")
            case .invalid:
                return .init(checkID: id, passed: false, detail: "address failed its EIP-55 checksum")
            case .unchecksummed:
                containsUnchecksummedAddress = true
            case .valid:
                continue
            }
        }
        return .init(
            checkID: id,
            severity: containsUnchecksummedAddress ? .warning : .pass,
            detail: containsUnchecksummedAddress ? "address is well-formed but unchecksummed" : nil
        )
    }
}

/// Validates `parameters["ens"]` is a well-formed `.eth` name (when present).
///
/// Conservative by design, and ASCII-only. Full ENSIP-15 normalization (script mixing, confusable
/// sets, emoji sequences) is well beyond a pure deterministic check, so this accepts a restricted
/// subset and refuses everything else rather than approximating the standard. That direction
/// matters: a permissive Unicode rule admits homoglyph names — `vitalik` with a Cyrillic `а` is a
/// different name that renders identically — and the failure mode of a name-confusion attack on a
/// governance surface is much worse than a legitimate Unicode name needing manual approval.
public struct ENSNameFormatCheck: DeterministicCheck {
    public let id = StandardCheckID.ensNameFormat

    /// DNS's practical name ceiling, which ENS inherits.
    private static let maximumNameLength = 255

    public init() { }

    public func evaluate(_ proposal: ActionProposal) async -> DeterministicCheckResult {
        guard case let .success(targets) = CheckTargets.decode(from: proposal) else {
            return .init(checkID: id, passed: false, detail: "watchlist is not valid JSON")
        }
        let names = targets.compactMap(\.ens)
        guard !names.isEmpty else {
            return .init(checkID: id, passed: true, detail: "no ENS name to check")
        }
        for name in names {
            let normalized = name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard !normalized.isEmpty else {
                return .init(checkID: id, passed: false, detail: "ENS name is empty")
            }
            guard normalized.count <= Self.maximumNameLength else {
                return .init(checkID: id, passed: false, detail: "ENS name exceeds \(Self.maximumNameLength) characters")
            }
            guard normalized.hasSuffix(".eth") else {
                return .init(checkID: id, passed: false, detail: "ENS name must end in .eth")
            }
            let labels = normalized.dropLast(".eth".count).split(separator: ".", omittingEmptySubsequences: false)
            guard !labels.isEmpty, !labels.contains(where: \.isEmpty) else {
                return .init(checkID: id, passed: false, detail: "ENS labels must not be empty")
            }
            for label in labels {
                guard label.allSatisfy(Self.isPermittedLabelCharacter) else {
                    return .init(
                        checkID: id,
                        passed: false,
                        detail: "ENS labels accept only a-z, 0-9, and hyphens"
                    )
                }
                guard label.first != "-", label.last != "-" else {
                    return .init(checkID: id, passed: false, detail: "ENS labels must not start or end with a hyphen")
                }
            }
        }
        return .init(checkID: id, passed: true)
    }

    private static func isPermittedLabelCharacter(_ character: Character) -> Bool {
        guard let ascii = character.asciiValue else { return false }
        switch ascii {
        case UInt8(ascii: "a")...UInt8(ascii: "z"),
             UInt8(ascii: "0")...UInt8(ascii: "9"),
             UInt8(ascii: "-"):
            return true
        default:
            return false
        }
    }
}

/// Validates `parameters["chain"]` names a chain inside the configured scope (when present).
///
/// Resolves through ``ChainScopeReference``, so a CAIP-2 reference, a bare chain ID, a ``Chain`` raw
/// value, and a friendly alias for the same chain all reach the same verdict. Previously this
/// compared the raw string against a set of friendly names, which meant `eip155:1` and `eth-mainnet`
/// were both "out of scope" while `ethereum` was in it.
public struct ChainScopeCheck: DeterministicCheck {
    public let id = StandardCheckID.chainInScope
    private let allowed: Set<Chain>

    public init(allowed: Set<Chain>) { self.allowed = allowed }

    public func evaluate(_ proposal: ActionProposal) async -> DeterministicCheckResult {
        guard case let .success(targets) = CheckTargets.decode(from: proposal) else {
            return .init(checkID: id, passed: false, detail: "watchlist is not valid JSON")
        }
        // A present-but-empty `chain` stays in this list and fails closed as unresolvable; only a
        // genuinely absent chain means there is nothing to place in scope.
        let references = targets.compactMap(\.chain)
        guard !references.isEmpty else {
            return .init(checkID: id, passed: true, detail: "no chain to check")
        }
        for reference in references {
            guard let chain = ChainScopeReference.resolve(reference) else {
                return .init(checkID: id, passed: false, detail: "unrecognized chain reference")
            }
            guard allowed.contains(chain) else {
                return .init(checkID: id, passed: false, detail: "chain out of scope: \(chain.rawValue)")
            }
        }
        return .init(checkID: id, passed: true)
    }
}

/// Validates recorded context freshness using only timestamps carried by the proposal.
public struct ContextFreshnessCheck: DeterministicCheck {
    public let id = StandardCheckID.contextFresh
    private let maxAge: TimeInterval
    public init(maxAge: TimeInterval) {
        self.maxAge = maxAge
    }

    public func evaluate(_ proposal: ActionProposal) async -> DeterministicCheckResult {
        guard let raw = proposal.parameters[StandardCheckParameterKey.contextRefreshedAt] else {
            return .init(checkID: id, passed: false, detail: "missing context timestamp")
        }
        guard let epoch = TimeInterval(raw) else {
            return .init(checkID: id, passed: false, detail: "unparseable context timestamp")
        }
        guard let evaluatedRaw = proposal.parameters[StandardCheckParameterKey.freshnessEvaluatedAt],
              let evaluatedAt = TimeInterval(evaluatedRaw) else {
            return .init(checkID: id, passed: false, detail: "missing or unparseable freshness evaluation timestamp")
        }
        let age = evaluatedAt - epoch
        // A negative age means the context claims to have been refreshed in the future, which is a
        // clock or forgery problem rather than freshness — refuse it instead of treating it as fresh.
        guard age >= 0 else {
            return .init(checkID: id, passed: false, detail: "context timestamp is in the future")
        }
        guard age <= maxAge else {
            // Name the age, the window, and the remedy. This detail is the only thing the Approval
            // Inbox can show a person whose approval was refused, and "context is stale" told them
            // neither how stale nor what to do about it.
            return .init(
                checkID: id,
                passed: false,
                detail: "context is stale: \(Int(age.rounded()))s old, past the \(Int(maxAge.rounded()))s freshness window — re-run the action to gather current context"
            )
        }
        return .init(checkID: id, passed: true)
    }
}

/// Host-tunable knobs for the standard checks.
///
/// These were hardcoded at the registration site, which made the chain allowlist and the freshness
/// window unreachable from the composition root: a host could not narrow either one without editing
/// this package. The values are the defaults the runtime has been shipping.
public struct StandardCheckConfiguration: Equatable, Sendable {
    /// Chains a proposal may name. Deliberately narrower than every chain the app can *read* — this
    /// gates governed action, so it stays an explicit allowlist rather than "all known chains".
    ///
    /// This is the single source of chain scope for governance. Both `chain.inScope` (the proposal's
    /// `chain` parameter) and `policy.chain.allowed` (the chain ID the wallet will sign against) read
    /// it, so the two cannot admit different chain sets for the same capability. Widening it widens
    /// the signing path — that is the point of it being one explicit host decision.
    public var allowedChains: Set<Chain>
    /// How old `contextRefreshedAt` may be before a proposal is considered to be acting on stale
    /// context.
    ///
    /// The default suits an unattended host, where a proposal is raised and evaluated in one motion.
    /// A host that escalates proposals to a *human* inbox measures this across think time instead —
    /// `freshnessEvaluatedAt` is stamped when the approval is cleared, not when it was raised — so it
    /// should widen this to the latency it actually expects from a person. See the app's
    /// `RuntimeAssembly`.
    public var contextMaxAge: TimeInterval

    public init(
        allowedChains: Set<Chain> = [.ethMainnet, .ethSepoliaTestnet, .baseMainnet],
        contextMaxAge: TimeInterval = 300
    ) {
        self.allowedChains = allowedChains
        self.contextMaxAge = contextMaxAge
    }

    public static let `default` = StandardCheckConfiguration()

    /// Every EVM chain the app models — the scope a host with a real multi-chain wallet needs.
    ///
    /// Named here, next to the default it replaces, so the composition root states *which* scope it
    /// wants instead of open-coding a set literal that nothing tests. The default above is sized for
    /// a library caller with no signer; a host whose wallet can sign on ~26 chains and whose
    /// WalletConnect sessions span them would silently refuse most of its own traffic by inheriting it.
    ///
    /// Solana is excluded because governed action here is EVM: its `chainId` is not an EIP-155 chain
    /// ID. ``PolicyChainAllowlistCheck`` drops it again independently, so this is belt-and-braces.
    public static let allEVMChains: Set<Chain> = Set(
        Chain.allCases.filter { $0 != .solanaMainnet && $0 != .solanaDevnetTestnet }
    )
}

public extension DeterministicCheckRegistry {
    /// Registers the standard checks.
    ///
    /// - Parameters:
    ///   - configuration: Chain scope and freshness window. Defaults to the shipping values.
    /// - Returns: The IDs that collided with an already-registered check of a different type, so the
    ///   host can refuse to bootstrap rather than run with a check it didn't install.
    @discardableResult
    func registerStandardChecks(
        _ configuration: StandardCheckConfiguration = .default
    ) async -> [String] {
        let checks: [any DeterministicCheck] = [
            AddressFormatCheck(),
            ENSNameFormatCheck(),
            ChainScopeCheck(allowed: configuration.allowedChains),
            ContextFreshnessCheck(maxAge: configuration.contextMaxAge)
        ]
        return checks.compactMap { check in
            guard case let .conflict(id) = register(check) else { return nil }
            return id
        }
    }
}
