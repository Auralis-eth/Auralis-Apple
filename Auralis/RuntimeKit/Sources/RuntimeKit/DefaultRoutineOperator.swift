import Foundation
import PlaybookCore
import RuntimeCore
import SchedulingCore

/// Assembles a governed ``ContextBundle`` from a playbook's own definition. This is deliberately
/// minimal — richer, source-attributed fields (worklog, holdings, …) are layered in per-operator —
/// but it is *real*: every field carries a data class, source, and refresh time, so a
/// ``ContextBundleContract`` can be enforced against it before the operator runs.
public struct DefaultContextProvider: ContextProviding {
    public init() { }

    public func gather(for playbook: Playbook) async -> ContextBundle {
        let now = Date()
        return ContextBundle(fields: [
            ContextField(
                key: "playbook",
                stringValue: playbook.id,
                dataClass: .publicIdentifier,
                source: .playbookDefinition,
                lastRefreshed: now
            ),
            ContextField(
                key: "playbook.name",
                stringValue: playbook.name,
                dataClass: .publicIdentifier,
                source: .playbookDefinition,
                lastRefreshed: now
            ),
            ContextField(
                key: "playbook.source",
                stringValue: playbook.source.rawValue,
                dataClass: .derived,
                source: .playbookDefinition,
                lastRefreshed: now
            ),
            ContextField(
                key: "playbook.trigger",
                stringValue: playbook.trigger.classification,
                dataClass: .derived,
                source: .playbookDefinition,
                lastRefreshed: now
            ),
            ContextField(
                key: "playbook.flows",
                stringValue: playbook.supportedFlows.map(\.rawValue).sorted().joined(separator: ","),
                dataClass: .derived,
                source: .playbookDefinition,
                lastRefreshed: now
            )
        ])
    }
}

/// The default routine operator: produces a first-class artifact summarizing the run. Read/prepare
/// only — it never performs a crypto action (the On-Chain Watch playbook escalates those). Real
/// domain operators replace this per-playbook in M7.
public struct DefaultRoutineOperator: RoutineOperator {
    public init() { }

    public func run(playbook: Playbook, context: GovernedContext) async -> RoutineRunResult {
        let type = playbook.authority.allowedOutputs.first ?? .brief
        let draft = RoutineArtifactDraft(
            type: type,
            title: "\(playbook.name) — \(type.rawValue)",
            creatorPlaybookID: playbook.id,
            actor: ActorRef(kind: .scheduledRoutine, identifier: playbook.id),
            content: "Prepared by the \(playbook.name) playbook. \(playbook.completionCondition)"
        )
        return RoutineRunResult(outcome: .success, artifact: draft)
    }
}
