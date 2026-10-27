/// How much weight one check's verdict carries.
///
/// Split out from the original `passed: Bool` because the warning tier had nowhere to live. A check
/// that observed something a person should see before authorizing — an address that is well-formed
/// but carries no EIP-55 checksum — could only report it as `passed: true` plus a `detail` string.
/// Nothing downstream could act on that: both consumers branch on `passed`, so the note reached the
/// worklog and Mission Control rendered it as a clean green checkmark with grey subtext.
public enum DeterministicCheckSeverity: String, Equatable, Sendable, Codable, CaseIterable {
    /// The check passed with nothing to report.
    case pass
    /// The check passed, but observed something worth surfacing before the action is authorized.
    /// Deliberately non-blocking — callers decide whether to escalate.
    case warning
    /// The check failed. Blocks execution.
    case failure
}

/// The result of running one deterministic check against a proposal.
public struct DeterministicCheckResult: Equatable, Sendable, Codable {
    public let checkID: String
    public let severity: DeterministicCheckSeverity
    public let detail: String?

    /// Whether this result permits execution. Warnings pass; only ``DeterministicCheckSeverity/failure``
    /// blocks.
    ///
    /// Derived rather than stored so the two can never disagree in a persisted record.
    public var passed: Bool { severity != .failure }

    public init(checkID: String, severity: DeterministicCheckSeverity, detail: String? = nil) {
        self.checkID = checkID
        self.severity = severity
        self.detail = detail
    }

    /// Boolean convenience for the checks that have no warning tier — most of them.
    public init(checkID: String, passed: Bool, detail: String? = nil) {
        self.init(checkID: checkID, severity: passed ? .pass : .failure, detail: detail)
    }

    // Explicit keys because this type is persisted: it rides in `WorkflowWorklogEvent.checksEvaluated`,
    // so a synthesized-and-then-renamed property would silently change the on-disk shape.
    private enum CodingKeys: String, CodingKey {
        case checkID
        case passed
        case severity
        case detail
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        checkID = try container.decode(String.self, forKey: .checkID)
        detail = try container.decodeIfPresent(String.self, forKey: .detail)
        // `severity` is the newer field. Worklog entries written before the warning tier existed
        // carry only `passed`, so they decode as the shape they were written under — a bare
        // pass/fail — rather than failing and degrading the whole entry to `.unknown`.
        //
        // A severity this build does not recognize falls back the same way. `decodeIfPresent` only
        // returns `nil` for an absent or null key — an unknown *raw value* throws — so without the
        // `try?` a future tier (say `advisory`) would fail this initializer and degrade the entire
        // `checksEvaluated` entry to `.unknown`, losing every result in it, while a readable
        // `passed` key sat right beside it. Forward tolerance is the same L-09 posture as backward.
        if let severity = try? container.decodeIfPresent(DeterministicCheckSeverity.self, forKey: .severity) {
            self.severity = severity
        } else {
            self.severity = try container.decode(Bool.self, forKey: .passed) ? .pass : .failure
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(checkID, forKey: .checkID)
        try container.encode(severity, forKey: .severity)
        // Written alongside `severity` so a reader predating the warning tier still sees the verdict
        // instead of finding no key it recognizes and treating the result as a pass.
        try container.encode(passed, forKey: .passed)
        try container.encodeIfPresent(detail, forKey: .detail)
    }
}

/// A pure, side-effect-free rule that either passes or fails for a given ``ActionProposal``.
///
/// Deterministic checks are the *objective* half of governance: address well-formedness, chain
/// scope, freshness, schema validity. They never make judgment calls — that is the Judge's job. A
/// check must be deterministic so its verdict can be reproduced from a receipt/worklog.
public protocol DeterministicCheck: Sendable {
    var id: String { get }
    func evaluate(_ proposal: ActionProposal) async -> DeterministicCheckResult
}

/// A check built from a synchronous closure — convenient for wrapping existing validators
/// (address normalization, chain allowlists, ENS) without a bespoke type each time.
public struct ClosureCheck: DeterministicCheck {
    public let id: String
    private let rule: @Sendable (ActionProposal) -> DeterministicCheckResult

    public init(id: String, rule: @escaping @Sendable (ActionProposal) -> DeterministicCheckResult) {
        self.id = id
        self.rule = rule
    }

    public func evaluate(_ proposal: ActionProposal) async -> DeterministicCheckResult {
        rule(proposal)
    }
}
