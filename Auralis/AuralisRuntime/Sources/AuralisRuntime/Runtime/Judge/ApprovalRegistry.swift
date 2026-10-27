import Foundation

/// Process-local custody for approval requests emitted by the governed boundary.
///
/// A caller cannot manufacture an ``ApprovalRequest`` and use it as authority: resumption succeeds
/// only for the exact request previously registered by the pipeline, and consuming it is atomic and
/// one-shot. Execution authority deliberately does not survive a process restart.
public actor ApprovalRegistry {
    private struct PendingApproval: Sendable {
        let request: ApprovalRequest
        let toolID: String
        let registeredAt: Date
    }

    private var pendingByID: [UUID: PendingApproval] = [:]

    public init() { }

    public func register(_ request: ApprovalRequest, toolID: String, at registeredAt: Date = .now) {
        pendingByID[request.id] = PendingApproval(
            request: request,
            toolID: toolID,
            registeredAt: registeredAt
        )
    }

    /// Returns the bound tool only when the complete request still matches pending custody.
    public func toolID(for request: ApprovalRequest) -> String? {
        guard let pending = pendingByID[request.id], pending.request == request else { return nil }
        return pending.toolID
    }

    /// Atomically consumes an exact pending request and returns its bound tool identifier.
    public func consume(_ request: ApprovalRequest) -> String? {
        guard let pending = pendingByID[request.id], pending.request == request else { return nil }
        pendingByID.removeValue(forKey: request.id)
        return pending.toolID
    }

    /// The oldest request that still has executable, one-shot approval custody.
    ///
    /// This deliberately reports only process-local pending authority. Requests disappear when consumed
    /// and do not survive relaunch, matching the registry's fail-closed security contract.
    public func oldestPendingDate() -> Date? {
        pendingByID.values.map(\.registeredAt).min()
    }

    /// The newest request registered on or before `cutoff` that still has executable custody.
    ///
    /// Event schedulers use this as a monotonic signal: once a run has handled one overdue request,
    /// a later request crossing the same age threshold produces a newer timestamp even when the older
    /// request remains pending. Requests newer than the cutoff are intentionally excluded.
    public func latestPendingDate(onOrBefore cutoff: Date) -> Date? {
        pendingByID.values
            .map(\.registeredAt)
            .filter { $0 <= cutoff }
            .max()
    }

    /// Drops every pending approval, for the privacy reset (MC-Device-012).
    ///
    /// A pending approval holds the whole ``ActionProposal`` it was raised for — the address, amount,
    /// and calldata a person is being asked to confirm — which is exactly the material
    /// ``RuntimeHost/resetAllHistory()`` exists to erase. Nothing here is durable, so this is not
    /// about what survives relaunch; it is that a reset performed *while the app is running* left
    /// those proposals in memory and still executable through `resumeApprovedProposal`, so "delete
    /// all local data" could be followed by resuming an approval raised before it.
    ///
    /// Fails closed, like every other loss of authority in this registry: a dropped approval cannot
    /// be resumed, and the person is asked again.
    public func resetAll() {
        pendingByID.removeAll()
    }
}
