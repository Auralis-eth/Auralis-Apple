import AuralisFoundation
import Foundation
import AuralisRuntime

/// The severity a ``RiskBanner`` communicates. Derived from ``ActionImpactClass`` so the banner and
/// the governance layer read the same blast-radius vocabulary rather than re-deriving it in the UI.
public enum TrustedUIRiskLevel: String, CaseIterable, Sendable, Equatable {
    case informational
    case low
    case medium
    case high

    /// The severity of an impact class taken at face value — no floor is applied, because an impact
    /// class on its own carries nothing to apply one from.
    ///
    /// Use ``init(proposal:)`` wherever a capability is in hand. This initializer can only believe
    /// the class it is handed, and on a governed surface that class was written by the actor being
    /// governed.
    public init(impact: ActionImpactClass) {
        switch impact {
        case .readOnly: self = .informational
        case .reversibleWrite: self = .low
        case .externalImpact: self = .medium
        case .highRisk: self = .high
        }
    }

    /// The severity to show for a *proposal*: its declared impact raised to the floor its capability
    /// makes unavoidable.
    ///
    /// `ActionProposal.impact` is self-declared by the proposing actor, and nothing between the
    /// proposal and the banner checks it against the capability beside it. A proposal naming
    /// `approveSpending` while declaring `.readOnly` rendered a grey `info.circle` "Read-only"
    /// banner — so the one element on ``ApprovalSheet`` that states blast radius told a person that
    /// nothing would change, on the screen where they authorise funds moving. Every other governed
    /// surface already floors the claim: `CapabilityImpactMapping.minimumImpact(for:)` is written
    /// for exactly this, `PlanStepProposal.makeProposal` takes the same `max`, and
    /// ``ActionImpactClass`` is `Comparable` so that the `max` can be taken at all.
    ///
    /// `max`, not replacement: a proposal is free to declare itself *more* dangerous than its
    /// capability requires, and the floor must not talk it back down.
    ///
    /// `minimumImpact`, never `defaultImpact` — two functions with the same signature and different
    /// meanings. `defaultImpact` is the impact of *executing* the capability, and using it as a
    /// floor would render a genuinely read-only `runPlugin` inspection as an external effect and
    /// send it to the approval inbox.
    public init(proposal: ActionProposal) {
        let floor = CapabilityImpactMapping.minimumImpact(for: proposal.capability)
        self.init(impact: max(proposal.impact, floor))
    }

    /// Short, user-facing label.
    public var title: String {
        switch self {
        case .informational: return "Read-only"
        case .low: return "Reversible"
        case .medium: return "External effect"
        case .high: return "High risk"
        }
    }
}

/// Whether the lease folded into a ``PermissionCardModel`` actually authorises anything right now.
///
/// A lease is revocable and time-boxed, and a revoked one keeps its future `expiresAt`, so "a lease
/// exists" and "the capability is granted" are different statements. Only ``granted`` is authority.
public enum PermissionLeaseStatus: String, CaseIterable, Sendable, Equatable {
    /// Live authority: started, unrevoked, unexpired.
    case granted
    /// Revoked by hand before its expiry.
    case revoked
    /// Ran out on its own.
    case expired
    /// Granted for a window that has not opened yet.
    case scheduled

    /// Whether this status authorises the capability at the moment the model was built.
    public var authorizesNow: Bool { self == .granted }

    fileprivate var verb: String {
        switch self {
        case .granted: return "expires"
        case .revoked: return "revoked"
        case .expired: return "expired"
        case .scheduled: return "starts"
        }
    }
}

/// The content a ``PermissionCard`` renders for a capability the runtime wants to inspect or grant.
public struct PermissionCardModel: Equatable, Sendable {
    public let capability: CapabilityID
    public let title: String
    public let summary: String
    public let category: String
    /// Present when a lease was supplied at all; describes it *and its status*. Read
    /// ``leaseStatus`` — not the presence of this string — to know whether authority is live.
    public let leaseSummary: String?
    /// `nil` when no lease was supplied for the capability.
    public let leaseStatus: PermissionLeaseStatus?

    public init(
        capability: CapabilityID,
        title: String,
        summary: String,
        category: String,
        leaseSummary: String? = nil,
        leaseStatus: PermissionLeaseStatus? = nil
    ) {
        self.capability = capability
        self.title = title
        self.summary = summary
        self.category = category
        self.leaseSummary = leaseSummary
        self.leaseStatus = leaseStatus
    }

    /// Build from the canonical capability metadata, optionally folding in a lease.
    ///
    /// The lease is classified rather than assumed live. This previously rendered every supplied
    /// lease as `"<scope> — expires <relative expiresAt>"`, which reads as a current grant for two
    /// leases that grant nothing: one revoked five minutes ago still carries its original future
    /// `expiresAt`, so the card said "Account scope — expires in 20 min" for authority that had
    /// already been withdrawn; and a future-dated lease read as live before its window opened. The
    /// expired case merely garbled into "expires 2 min. ago".
    ///
    /// The holder is named too. "Account scope" says what the grant reaches, not who holds it, and
    /// on a card whose job is stating scope those are both halves of the same question.
    public init(capability: CapabilityID, lease: CapabilityLease? = nil, now: Date = .now) {
        let descriptor = CapabilityRegistry.descriptor(for: capability)
        self.capability = capability
        self.title = descriptor.title
        self.summary = descriptor.summary
        self.category = "\(descriptor.category)"
        guard let lease else {
            self.leaseSummary = nil
            self.leaseStatus = nil
            return
        }
        let status = Self.status(of: lease, at: now)
        self.leaseStatus = status
        self.leaseSummary = "\(lease.scope.displayTitle) · \(lease.grantedTo.attributionLabel) · "
            + "\(status.verb) \(Self.relative(Self.moment(of: lease, for: status), to: now))"
    }

    /// The instant the summary's verb refers to: when it ends, when it was withdrawn, or when it
    /// begins.
    private static func moment(of lease: CapabilityLease, for status: PermissionLeaseStatus) -> Date {
        switch status {
        case .revoked: return lease.revokedAt ?? lease.expiresAt
        case .scheduled: return lease.grantedAt
        case .granted, .expired: return lease.expiresAt
        }
    }

    /// Mirrors `CapabilityLease.isActive(at:)`, which treats a revocation timestamp in the future
    /// as not yet in effect — so the revoked branch tests the same `now >= revokedAt` boundary
    /// rather than the mere presence of the column.
    private static func status(of lease: CapabilityLease, at now: Date) -> PermissionLeaseStatus {
        if let revokedAt = lease.revokedAt, now >= revokedAt { return .revoked }
        if now < lease.grantedAt { return .scheduled }
        if now >= lease.expiresAt { return .expired }
        return .granted
    }

    private static func relative(_ date: Date, to now: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter.localizedString(for: date, relativeTo: now)
    }
}

/// The content a ``SuggestionCard`` renders for a proactive, non-blocking suggestion.
public struct SuggestionCardModel: Identifiable, Equatable, Sendable {
    public let id: UUID
    public let title: String
    public let detail: String
    public let actionLabel: String?

    public init(id: UUID = UUID(), title: String, detail: String, actionLabel: String? = nil) {
        self.id = id
        self.title = title
        self.detail = detail
        self.actionLabel = actionLabel
    }

    /// Build the display model from the runtime-level ``TrustedUISuggestion`` carried by a
    /// ``TrustedUIRequest``.
    public init(_ suggestion: TrustedUISuggestion) {
        self.id = suggestion.id
        self.title = suggestion.title
        self.detail = suggestion.detail
        self.actionLabel = suggestion.actionLabel
    }
}

/// A resolved, display-ready summary of a receipt. The registry keeps ``TrustedUIRequest`` free of
/// the receipt/storage packages; the presenting layer supplies a resolver that turns a `receiptID`
/// into this value.
public struct TrustedUIReceiptSummary: Identifiable, Equatable, Sendable {
    public let id: UUID
    public let title: String
    public let subtitle: String
    public let actorLabel: String
    public let timestamp: Date
    /// Ordered key/value rows, already sanitized for display.
    public let fields: [Field]

    public struct Field: Identifiable, Equatable, Sendable {
        /// The field key — **not unique within a summary.** Nothing rejects a resolver that emits
        /// the same key twice, so this must not be used as `ForEach` identity; colliding ids make
        /// SwiftUI drop rows, and a receipt that under-reports what it recorded is worse than an
        /// ugly one. ``ReceiptCard`` iterates positionally for that reason.
        public var id: String { key }
        public let key: String
        public let value: String

        public init(key: String, value: String) {
            self.key = key
            self.value = value
        }
    }

    public init(id: UUID, title: String, subtitle: String, actorLabel: String, timestamp: Date, fields: [Field]) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.actorLabel = actorLabel
        self.timestamp = timestamp
        self.fields = fields
    }
}

/// A resolved, editable draft summary for the `editDraft` request. Resolved from a `proposalID` by
/// the presenting layer.
public struct TrustedUIDraftSummary: Identifiable, Equatable, Sendable {
    public let id: UUID
    public let title: String
    public let body: String

    public init(id: UUID, title: String, body: String) {
        self.id = id
        self.title = title
        self.body = body
    }
}

/// The outcome a human returns from a trusted approval surface.
public enum TrustedUIApprovalOutcome: Equatable, Sendable {
    case approved
    case denied(reason: String)
    /// The human declined to decide now; the request stays pending. There is no governance verdict yet.
    case deferred

    /// Map onto the governance vocabulary so callers can feed the decision straight back into the
    /// Judge/Policy pipeline. `deferred` yields `nil` — no verdict has been reached.
    public var judgeDecision: JudgeDecision? {
        switch self {
        case .approved: return .allow
        case .denied(let reason): return .block(reason: reason)
        case .deferred: return nil
        }
    }
}

/// The governed display rule for context values. A trusted surface never renders `.sensitive`
/// material raw, regardless of what a workflow placed in the bundle.
public enum TrustedUIContextRedaction {
    public static let redactedPlaceholder = "••••••"
    /// Shown when a field carries no value at all — distinct from a value that is being withheld.
    public static let absentPlaceholder = "—"

    /// Decides what to show from the *payload*, not from the `dataClass` label beside it.
    ///
    /// Keying the rule on `dataClass` alone trusted the label to agree with the bytes, and on a
    /// decoded bundle it does not have to. `ContextField.init(from:)` only coerces a value to
    /// `.redacted` when the declared class is already `.sensitive`; a field that arrives over the
    /// wire as `{"dataClass": "publicIdentifier", "value": {"sensitiveReference": "vault://seed"}}`
    /// keeps both halves verbatim, and `stringValue` projects the vault handle straight onto the
    /// card. Switching on `ContextValue` makes the opaque reference unrenderable whatever class
    /// claims to describe it.
    ///
    /// `.redacted` and "no value" are also no longer the same glyph. Both used to read `—`, so a
    /// field whose value was deliberately withheld was indistinguishable from one the resolver
    /// never populated — on a surface whose whole job is making governed context visible, "nothing
    /// here" and "something here you may not see" are different facts.
    public static func displayValue(_ field: ContextField) -> String {
        switch field.value {
        case nil:
            return absentPlaceholder
        case .redacted, .sensitiveReference:
            return redactedPlaceholder
        case .text(let text):
            return field.dataClass == .sensitive ? redactedPlaceholder : text
        }
    }
}

/// A human-readable descriptor for one entry in the trusted-component catalog.
public struct TrustedUIComponentDescriptor: Equatable, Sendable {
    public let kind: TrustedUIComponentRegistry.ComponentKind
    public let title: String
    public let purpose: String

    public init(kind: TrustedUIComponentRegistry.ComponentKind, title: String, purpose: String) {
        self.kind = kind
        self.title = title
        self.purpose = purpose
    }
}
