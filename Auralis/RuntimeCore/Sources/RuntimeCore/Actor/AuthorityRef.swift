import AuralisFoundation
import Foundation

/// Where an action's permission came from — the "under what authority" leg of actor attribution
/// (P0.5-601/602), alongside `ActorRef` ("who acted") and the correlation id ("through what
/// workflow").
///
/// A `CapabilityLeaseRegistry` check answers *whether* an actor may act, and then throws the answer
/// away. That leaves persisted history unable to explain why something was allowed: an auditor
/// reading a receipt can see a routine moved money but not which grant let it. `AuthorityRef` is the
/// durable record of that decision, captured at the moment the check passed.
public struct AuthorityRef: Equatable, Hashable, Sendable, Codable {
    /// How the action came to be permitted.
    public enum Source: String, Codable, CaseIterable, Sendable {
        /// An explicit, time-boxed ``CapabilityLease`` granted to the acting actor.
        case lease
        /// A person approved this action directly, so their decision is the authority.
        case humanApproval
        /// Permitted by the app's standing policy for the current mode, with no lease involved —
        /// read-only work, for example.
        case policyDefault
    }

    public let source: Source
    /// The lease that authorized the action, when `source == .lease`.
    public let leaseID: UUID?
    /// The capability the authority covers.
    public let capability: CapabilityID?
    /// The authority surface the grant was scoped to, when a lease supplied it.
    public let scope: CapabilityLeaseScope?
    /// The operator-facing reason recorded on the grant, so the receipt can show *why* it was given.
    public let reason: String?
    /// When the authorizing grant expires, so history shows how time-boxed the permission was.
    public let expiresAt: Date?

    public init(
        source: Source,
        leaseID: UUID? = nil,
        capability: CapabilityID? = nil,
        scope: CapabilityLeaseScope? = nil,
        reason: String? = nil,
        expiresAt: Date? = nil
    ) {
        self.source = source
        self.leaseID = leaseID
        self.capability = capability
        self.scope = scope
        self.reason = reason
        self.expiresAt = expiresAt
    }

    /// The authority represented by an active capability lease.
    public init(lease: CapabilityLease) {
        self.init(
            source: .lease,
            leaseID: lease.id,
            capability: lease.capability,
            scope: lease.scope,
            reason: lease.reason,
            expiresAt: lease.expiresAt
        )
    }

    /// A person's direct approval of a specific action.
    public static func humanApproval(capability: CapabilityID? = nil, reason: String? = nil) -> AuthorityRef {
        AuthorityRef(source: .humanApproval, capability: capability, reason: reason)
    }

    /// Standing policy permitted the action; no lease was required.
    public static func policyDefault(capability: CapabilityID? = nil, reason: String? = nil) -> AuthorityRef {
        AuthorityRef(source: .policyDefault, capability: capability, reason: reason)
    }

    /// Decodes an optional authority column, degrading a value this build cannot read to `nil`
    /// instead of failing the whole record.
    ///
    /// ``Source`` is a raw-value enum with synthesized decoding, so a fourth source written by a
    /// newer build throws — and every type that persists an authority (``WorkflowStepLog``,
    /// ``AgentSession``, `SchedulingCore.ExecutionRecord`) is stored as a JSON blob read back
    /// through `compactMap`. A hard throw would therefore erase the entire worklog entry, session,
    /// or run over one unreadable field, which is the failure mode ``ActorRef/init(from:)``
    /// deliberately avoids for the actor column.
    ///
    /// The degrade is to `nil` — "no authority recorded" — and never to an invented one, for the
    /// same reason ``init(receiptAuthorityDetail:)`` is failable: asserting that *something*
    /// permitted an action when this build cannot tell what would be a false audit claim. Callers
    /// already render a missing authority as "not recorded", so history stays readable and honest.
    public static func decodedIfPresent<Key: CodingKey>(
        from container: KeyedDecodingContainer<Key>,
        forKey key: Key
    ) -> AuthorityRef? {
        try? container.decodeIfPresent(AuthorityRef.self, forKey: key)
    }

    /// A short, user-facing description of the authority for trust surfaces.
    public var displaySummary: String {
        switch source {
        case .lease:
            let capabilityLabel = capability?.rawValue ?? "capability"
            return "Capability lease for \(capabilityLabel)"
        case .humanApproval:
            return "Approved by you"
        case .policyDefault:
            return "Allowed by standing policy"
        }
    }
}
