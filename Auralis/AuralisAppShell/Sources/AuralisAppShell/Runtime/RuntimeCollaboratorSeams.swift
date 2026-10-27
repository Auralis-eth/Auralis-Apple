import AuralisRuntime

// The seams that let the ritual/social surface live outside ``RuntimeHost``.
//
// `RuntimeHost+Coordination.swift` used to carry that surface as a second extension on the host,
// with a header comment saying so: "This is a file split, not a decomposition… Extracting a
// `RitualCoordinator` collaborator is the real fix and a larger, riskier change." These protocols
// are what make that extraction possible without the coordinator simply taking a `RuntimeHost`
// handle and reproducing the coupling one level down.
//
// Each names *one* thing the coordinator needs, so what it actually depends on is legible from its
// initializer and a test can supply a double for any of them.

/// The one governed way to run an installed playbook once.
///
/// A ritual is composed *of* routine runs, so the coordinator has to be able to start one — and it
/// must be this exact path, not a private re-implementation: ``RuntimeHost/runRoutine(id:trigger:actor:correlationID:)``
/// is where standing authority is refreshed, the execution record is written, the run is graded, and
/// the routine receipt is appended. A parallel path would be a second, ungoverned way to run a
/// playbook, which is the one thing this runtime is built to not have.
///
/// A protocol rather than a closure so the dependency is named at the boundary and a test can run
/// the coordinator against a recording double without constructing a host at all.
@MainActor
protocol RoutineRunning: AnyObject {
    @discardableResult
    func runRoutine(
        id: String,
        trigger: TriggerSource,
        actor: ActorRef?,
        correlationID: String?
    ) async -> ExecutionRecord
}

/// How a collaborator reports a persistence failure it cannot propagate to its caller.
///
/// Both of these surface on the host's observable banners — ``RuntimeHost/playbookPersistenceError``
/// and ``RuntimeHost/receiptPersistenceError`` — which is the point: a coordinator that logged its
/// own failures instead would leave Mission Control presenting a ritual run as fully evidenced while
/// the host knew nothing about the gap. Routed back rather than duplicated so there is one
/// degraded-evidence signal in the runtime, not two that can disagree.
@MainActor
protocol RuntimeDegradationReporting: AnyObject {
    func reportPlaybookPersistenceError(_ error: Error)
    func noteReceiptPersistenceFailure(correlationID: String?, goal: String, actor: ActorRef) async
}

/// Maps a playbook's declared trigger onto the scheduling engine's trigger source.
///
/// Pure, and therefore not a dependency at all. It was an instance method on ``RuntimeHost`` only so
/// that `runDueRoutines` and `runDueRituals` could share one copy; lifting it here means the
/// coordinator does not need a reference to the host to classify a trigger, and removes one entry
/// from what would otherwise be a longer dependency list.
enum PlaybookTriggerMapping {
    static func triggerSource(for trigger: PlaybookTrigger) -> TriggerSource {
        switch trigger {
        case .manual:
            return .manual
        case .schedule:
            return .schedule
        case .maintenance:
            return .maintenance
        case .event(.artifactStale):
            return .artifactStale
        case .event(.approvalPendingTooLong):
            return .approvalPendingTooLong
        }
    }
}
