import CapabilitiesCore
import Foundation
import RuntimeCore

/// An event that can trigger a routine. (P1-602)
public enum RoutineEventKind: String, Codable, CaseIterable, Sendable {
    case artifactStale
    case approvalPendingTooLong
}

/// The v0 flow class a playbook may perform. P1-500 v0 intentionally supports only read/prepare.
public enum PlaybookFlowKind: String, Codable, CaseIterable, Sendable {
    case read
    case prepare
    case execute

    public var isV0Allowed: Bool {
        switch self {
        case .read, .prepare: return true
        case .execute: return false
        }
    }
}

/// Whether a playbook is built into Auralis or authored by the user. (P1-502)
public enum PlaybookSource: String, Codable, CaseIterable, Sendable {
    case system
    case user
}

/// How a playbook is triggered. (P1-501 trigger/schedule)
public enum PlaybookTrigger: Equatable, Sendable, Codable {
    case manual
    case schedule(intervalSeconds: Double)
    case event(RoutineEventKind)
    case maintenance(intervalSeconds: Double)

    /// Classification for the Routine Manager UI (time-based / event-based / maintenance).
    public var classification: String {
        switch self {
        case .manual: return "manual"
        case .schedule: return "time-based"
        case .event: return "event-based"
        case .maintenance: return "maintenance"
        }
    }

    /// The interval an unschedulable declaration falls back to: hourly, the cadence the shipped
    /// system playbooks already use.
    public static let fallbackIntervalSeconds: Double = 3600

    /// This trigger with any interval that cannot be scheduled replaced by
    /// ``fallbackIntervalSeconds``.
    ///
    /// Zero, negative and non-finite intervals carry no cadence a scheduler can honour: zero and
    /// negative say "due again the instant it ran", and `NaN` loses every comparison, so a
    /// `next <= now` due-check reads as never due while a `next > now` one reads as always due.
    /// Either way the defect is data reaching the scheduler, so the guard sits here at the model
    /// layer — ``Playbook`` normalises on construction *and* on decode, which covers both the
    /// authoring path and a payload persisted before this check existed.
    ///
    /// Positive finite intervals pass through untouched. No minimum floor is imposed deliberately:
    /// a short interval is a declared cadence rather than corrupt data, and how aggressively to
    /// poll one is the consuming scheduler's policy to set, not this model's.
    public var normalized: PlaybookTrigger {
        switch self {
        case .manual, .event:
            return self
        case let .schedule(intervalSeconds):
            return .schedule(intervalSeconds: Self.schedulableInterval(intervalSeconds))
        case let .maintenance(intervalSeconds):
            return .maintenance(intervalSeconds: Self.schedulableInterval(intervalSeconds))
        }
    }

    private static func schedulableInterval(_ seconds: Double) -> Double {
        // `seconds > 0` alone would let `NaN` through: every comparison against it is false, so the
        // finiteness check has to come first and stand on its own.
        guard seconds.isFinite, seconds > 0 else { return fallbackIntervalSeconds }
        return seconds
    }
}

/// The authority envelope a playbook operates within. Per the crypto-scoped boundary (ADR-010),
/// wallet capabilities remain gated; a playbook must declare exactly which capabilities it uses.
public struct PlaybookAuthority: Equatable, Sendable, Codable {
    public let capabilities: [CapabilityID]
    public let allowedOutputs: [ArtifactOutputType]
    /// Number of pending approvals tolerated before the playbook escalates/pauses.
    public let approvalThreshold: Int
    /// Named approvals the user should expect before enabling this playbook.
    public let requiredApprovals: [String]

    public init(
        capabilities: [CapabilityID],
        allowedOutputs: [ArtifactOutputType],
        approvalThreshold: Int = 0,
        requiredApprovals: [String] = []
    ) {
        self.capabilities = capabilities
        self.allowedOutputs = allowedOutputs
        self.approvalThreshold = approvalThreshold
        self.requiredApprovals = requiredApprovals
    }

    /// Whether any capability in the envelope is crypto/wallet (so crypto flows stay read/prepare).
    public var touchesCrypto: Bool {
        capabilities.contains { CapabilityRegistry.descriptor(for: $0).category == .wallet }
    }

    private enum CodingKeys: String, CodingKey {
        case capabilities
        case allowedOutputs
        case approvalThreshold
        case requiredApprovals
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        capabilities = try container.decode([CapabilityID].self, forKey: .capabilities)
        allowedOutputs = try container.decode([ArtifactOutputType].self, forKey: .allowedOutputs)
        approvalThreshold = try container.decodeIfPresent(Int.self, forKey: .approvalThreshold) ?? 0
        requiredApprovals = try container.decodeIfPresent([String].self, forKey: .requiredApprovals) ?? []
    }
}

/// Install/visibility state in the Playbook Library. (P1-502)
public enum PlaybookInstallState: String, Codable, CaseIterable, Sendable {
    case available
    case installed
    case paused
    case draft
}

/// A persistent, reusable unit of operator work. (P1-501)
public struct Playbook: Identifiable, Equatable, Sendable, Codable {
    public let id: String
    public let name: String
    public let summary: String
    public let trigger: PlaybookTrigger
    public let authority: PlaybookAuthority
    public let completionCondition: String
    public let receiptFormat: String
    public let failureEscalationPath: String
    public let supportedFlows: [PlaybookFlowKind]
    public let source: PlaybookSource
    /// The complete operating-context declaration authored with this workflow.
    public let contextContract: ContextBundleContract
    /// What a successful run of this playbook looks like, graded by `EvalCore` after each run.
    ///
    /// Optional because ``completionCondition`` already states the same thing in prose for the
    /// library UI, and a playbook without machine-checkable criteria is a legitimate state — it just
    /// grades inconclusive rather than passing. Per-playbook rather than one global spec so a brief
    /// and an on-chain watch are held to their own expectations.
    public let outcome: OutcomeSpec?
    public var installState: PlaybookInstallState

    public init(
        id: String,
        name: String,
        summary: String,
        trigger: PlaybookTrigger,
        authority: PlaybookAuthority,
        completionCondition: String,
        receiptFormat: String = "standard",
        failureEscalationPath: String = "approval-inbox",
        supportedFlows: [PlaybookFlowKind] = [.read, .prepare],
        source: PlaybookSource = .system,
        contextContract: ContextBundleContract,
        outcome: OutcomeSpec? = nil,
        installState: PlaybookInstallState = .available
    ) {
        self.id = id
        self.name = name
        self.summary = summary
        // See `PlaybookTrigger.normalized`: an interval that cannot be scheduled never becomes a
        // stored property, so no consumer has to re-check one.
        self.trigger = trigger.normalized
        self.authority = authority
        self.completionCondition = completionCondition
        self.receiptFormat = receiptFormat
        self.failureEscalationPath = failureEscalationPath
        self.supportedFlows = supportedFlows
        self.source = source
        self.contextContract = contextContract
        self.outcome = outcome
        self.installState = installState
    }

    /// P1-501 v0 guard: playbooks can read or prepare, but cannot execute external effects.
    public var supportsV0ReadPrepareOnly: Bool {
        !supportedFlows.isEmpty && supportedFlows.allSatisfy(\.isV0Allowed)
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case summary
        case trigger
        case authority
        case completionCondition
        case receiptFormat
        case failureEscalationPath
        case supportedFlows
        case source
        case contextContract
        case outcome
        case installState
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        summary = try container.decode(String.self, forKey: .summary)
        // Normalised on the way in as well as in `init`: a payload persisted before this guard
        // existed can still hold a zero or non-finite interval.
        trigger = try container.decode(PlaybookTrigger.self, forKey: .trigger).normalized
        authority = try container.decode(PlaybookAuthority.self, forKey: .authority)
        completionCondition = try container.decode(String.self, forKey: .completionCondition)
        receiptFormat = try container.decodeIfPresent(String.self, forKey: .receiptFormat) ?? "standard"
        failureEscalationPath = try container.decodeIfPresent(String.self, forKey: .failureEscalationPath) ?? "approval-inbox"
        supportedFlows = try container.decodeIfPresent([PlaybookFlowKind].self, forKey: .supportedFlows) ?? [.read, .prepare]
        source = try container.decodeIfPresent(PlaybookSource.self, forKey: .source) ?? .system
        contextContract = try container.decodeIfPresent(ContextBundleContract.self, forKey: .contextContract)
            ?? Self.legacyContextContract(identifier: id)
        // Absent on every playbook persisted before eval criteria existed, and on user-authored ones
        // that declare none. Grading then reports inconclusive, which is the honest reading: nobody
        // said what success meant here.
        outcome = try container.decodeIfPresent(OutcomeSpec.self, forKey: .outcome)
        installState = try container.decodeIfPresent(PlaybookInstallState.self, forKey: .installState) ?? .available
    }

    /// Decode-only compatibility for workflows persisted before contracts became part of the model.
    /// New source construction cannot omit the declaration because the public initializer requires it.
    private static func legacyContextContract(identifier: String) -> ContextBundleContract {
        ContextBundleContract(
            identifier: "legacy.playbook.\(identifier)",
            requirements: [
                ContextFieldRequirement(key: "playbook", allowedDataClasses: [.publicIdentifier], maxAge: 300, authoritativeSource: .playbookDefinition, missingFieldBehavior: .fail),
                ContextFieldRequirement(key: "playbook.name", allowedDataClasses: [.publicIdentifier], maxAge: 300, authoritativeSource: .playbookDefinition, missingFieldBehavior: .fail),
                ContextFieldRequirement(key: "playbook.source", allowedDataClasses: [.derived], maxAge: 300, authoritativeSource: .playbookDefinition, missingFieldBehavior: .fail),
                ContextFieldRequirement(key: "playbook.trigger", allowedDataClasses: [.derived], maxAge: 300, authoritativeSource: .playbookDefinition, missingFieldBehavior: .fail),
                ContextFieldRequirement(key: "playbook.flows", allowedDataClasses: [.derived], maxAge: 300, authoritativeSource: .playbookDefinition, missingFieldBehavior: .fail)
            ],
            missingFieldBehavior: .fail,
            additionalFieldBehavior: .reject
        )
    }
}
