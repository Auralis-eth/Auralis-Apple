import CapabilitiesCore

/// The set of capabilities the user has explicitly promoted to unattended ("autopilot")
/// execution — the "later, for trusted routines only" rung of the ladder.
///
/// Being on this list is necessary but never sufficient: a trusted capability still has
/// to clear the policy gate every time. Trust only removes the per-run confirmation tap;
/// it never removes the policy check. An empty allowlist (``none``) means everything that
/// changes state asks first, which is the safe default.
public struct TrustedRoutineAllowlist: Equatable, Sendable {
    public let capabilities: Set<CapabilityID>

    public init(_ capabilities: Set<CapabilityID> = []) {
        self.capabilities = capabilities
    }

    /// Nothing is trusted for unattended execution.
    public static let none = TrustedRoutineAllowlist()

    public func trusts(_ capability: CapabilityID) -> Bool {
        capabilities.contains(capability)
    }
}
