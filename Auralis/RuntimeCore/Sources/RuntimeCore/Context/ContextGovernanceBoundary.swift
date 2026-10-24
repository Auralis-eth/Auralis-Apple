import Foundation

public struct ContextGovernanceFailure: Error, Equatable, Sendable {
    public let violations: [String]

    public init(violations: [String]) {
        self.violations = violations
    }
}

/// The mandatory validation gate shared by every workflow execution surface.
public protocol ContextGovernanceEnforcing: Sendable {
    func authorize(
        _ bundle: ContextBundle,
        against contract: ContextBundleContract,
        at validationDate: Date
    ) -> Result<GovernedContext, ContextGovernanceFailure>
}

/// Pure default implementation suitable for schedulers, agents, plugins, and tests.
public struct ContextGovernanceBoundary: ContextGovernanceEnforcing {
    public init() { }

    public func authorize(
        _ bundle: ContextBundle,
        against contract: ContextBundleContract,
        at validationDate: Date = .now
    ) -> Result<GovernedContext, ContextGovernanceFailure> {
        let validation = contract.validate(bundle, now: validationDate)
        guard validation.isSatisfied else {
            return .failure(ContextGovernanceFailure(violations: validation.violations))
        }
        return .success(
            GovernedContext(bundle: validation.approvedBundle, contract: contract, validatedAt: validationDate)
        )
    }
}
