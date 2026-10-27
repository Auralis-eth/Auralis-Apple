/// The outcome of registering a check, so an ID collision is a fact the caller can act on.
public enum DeterministicCheckRegistration: Equatable, Sendable {
    case registered
    /// A different check already owns this ID; the incumbent was kept.
    case conflict(id: String)

    public var succeeded: Bool {
        self == .registered
    }
}

/// Central registry of deterministic checks, resolved by ID.
///
/// Consolidates the checks that are scattered across the app today (address validation, chain
/// allowlists, ENS, freshness) behind one lookup surface so proposals can name the checks they
/// require and the runtime can run exactly those. The record-shape checks (`receipt.schema`,
/// `artifact.schema`) register here too, from `RuntimeKit`, which is the lowest point in the graph
/// that can see the receipt and artifact schemas.
///
/// Security posture: an unregistered check **fails closed**. A proposal that names a check the
/// registry does not know about is treated as failing, never as passing.
public actor DeterministicCheckRegistry {
    private var checks: [String: any DeterministicCheck] = [:]

    public init() { }

    /// Registers `check` under its own ID, keeping any incumbent on collision.
    ///
    /// Last-writer-wins would make this the one governance registry that fails *open* on a
    /// collision: two check sets are registered back to back at host bootstrap, so a future ID
    /// clash between them would silently replace one governance check with a different one while
    /// every tool that required the original ID still reported a pass. `ToolRegistry.register`
    /// reports conflicts for the same reason, and bootstrap preconditions on the result.
    @discardableResult
    public func register(_ check: any DeterministicCheck) -> DeterministicCheckRegistration {
        // Strictly first-writer-wins, with no same-type exemption: ``ClosureCheck`` is a single type
        // that can carry any behaviour, so "same type means same check" would wave through exactly
        // the substitution this guards against.
        guard checks[check.id] == nil else {
            return .conflict(id: check.id)
        }
        checks[check.id] = check
        return .registered
    }

    public func check(id: String) -> (any DeterministicCheck)? {
        checks[id]
    }

    /// Every registered check ID.
    ///
    /// Exists for the "no dead check" contract, which needs to enumerate what is registered rather
    /// than confirm a hand-written list resolves: a check registered here but required by no tool
    /// would otherwise sit in the registry and never run, with nothing to catch it.
    public var registeredCheckIDs: Set<String> {
        Set(checks.keys)
    }

    /// Evaluates the named checks in order. Unknown IDs produce a failed result (fail-closed).
    public func evaluate(ids: [String], for proposal: ActionProposal) async -> [DeterministicCheckResult] {
        var results: [DeterministicCheckResult] = []
        results.reserveCapacity(ids.count)
        for id in ids {
            if let check = checks[id] {
                let result = await check.evaluate(proposal)
                guard result.checkID == id else {
                    results.append(
                        DeterministicCheckResult(
                            checkID: id,
                            passed: false,
                            detail: "check returned mismatched result ID"
                        )
                    )
                    continue
                }
                results.append(result)
            } else {
                results.append(
                    DeterministicCheckResult(checkID: id, passed: false, detail: "unregistered check")
                )
            }
        }
        return results
    }
}

public extension Array where Element == DeterministicCheckResult {
    /// Whether every result passed. An empty set vacuously passes.
    var allPassed: Bool {
        allSatisfy(\.passed)
    }

    /// The first failing result, if any.
    var firstFailure: DeterministicCheckResult? {
        first { !$0.passed }
    }

    /// Results that passed but observed something worth surfacing before authorization.
    ///
    /// The actionable half of the severity axis: a caller that escalates to a human can name these
    /// in the prompt, and Mission Control can render them as warnings rather than clean passes.
    var warnings: [DeterministicCheckResult] {
        filter { $0.severity == .warning }
    }
}
