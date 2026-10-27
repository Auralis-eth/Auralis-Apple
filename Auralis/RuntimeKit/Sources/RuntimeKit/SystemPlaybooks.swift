import ArtifactCore
import AuralisFoundation
import Foundation
import PlaybookCore
import RuntimeCore

/// The built-in playbooks Mission Control seeds its library with. Non-crypto ones can operate;
/// the on-chain watch touches crypto and therefore stays read/prepare (escalates any wallet action).
public enum SystemPlaybooks {
    public static let all: [Playbook] = [
        Playbook(
            id: "research.brief",
            name: "Research Brief",
            summary: "Turns a query or watchlist into a written brief you can review.",
            trigger: .manual,
            authority: PlaybookAuthority(
                capabilities: [.runPlugin],
                allowedOutputs: [.brief, .report]
            ),
            completionCondition: "A brief artifact is produced.",
            contextContract: SystemPlaybookContracts.contract(for: "research.brief"),
            outcome: OutcomeSpec(
                summary: "A reviewable brief exists, produced without governance friction.",
                criteria: [
                    .producedArtifact,
                    .noFailedSteps,
                    .allDeterministicChecksPassed,
                    // Manual, user-initiated: someone is waiting on it, so it must feel prompt.
                    .completedWithin(seconds: 120),
                    .traceFullyLegible
                ],
                proseCriteria: ["The brief is worth reading, not just present."]
            ),
            installState: .installed
        ),
        Playbook(
            id: "music.autoOrganize",
            name: "Auto-Organize Library",
            summary: "Proposes playlist and metadata tidy-ups across your music library.",
            trigger: .schedule(intervalSeconds: 86_400),
            authority: PlaybookAuthority(
                capabilities: [.autoOrganization, .playlistManagement, .metadataOverride],
                allowedOutputs: [.planChecklist]
            ),
            completionCondition: "An organization plan is produced.",
            contextContract: SystemPlaybookContracts.contract(for: "music.autoOrganize"),
            outcome: OutcomeSpec(
                summary: "An organization plan is proposed unattended.",
                criteria: [
                    .producedArtifact,
                    .noFailedSteps,
                    // Runs daily on a schedule with nobody watching, so an escalation means the run
                    // silently stalled waiting for a tap that never came.
                    .judgeDidNotEscalate,
                    .reachedRoutinePhase(.completed),
                    .traceFullyLegible
                ]
            ),
            installState: .installed
        ),
        Playbook(
            id: "onchain.watch",
            name: "On-Chain Watch",
            summary: "Monitors watched accounts and prepares action-ready summaries. Crypto stays read-only.",
            trigger: .event(.artifactStale),
            authority: PlaybookAuthority(
                capabilities: [.draftTransaction],
                allowedOutputs: [.report],
                approvalThreshold: 1,
                requiredApprovals: ["wallet action review"]
            ),
            completionCondition: "A watch report is produced; any wallet action escalates for approval.",
            contextContract: SystemPlaybookContracts.contract(for: "onchain.watch"),
            outcome: OutcomeSpec(
                summary: "A watch report is produced while crypto stays read-only.",
                criteria: [
                    .producedArtifact,
                    .noFailedSteps,
                    .allDeterministicChecksPassed,
                    .traceFullyLegible
                ],
                proseCriteria: [
                    "Escalation is correct behaviour here, not a shortfall: this playbook touches crypto, so a wallet action *should* stop for approval. judgeDidNotEscalate is deliberately omitted — grading it would penalise the Observe boundary working as designed (ADR-010)."
                ]
            ),
            installState: .installed
        ),
        Playbook(
            id: "community.gathering",
            name: "Community Gathering",
            summary: "Prepares a shared agenda, participant prompts, and expected gathering outputs.",
            trigger: .manual,
            authority: PlaybookAuthority(
                capabilities: [.runPlugin],
                allowedOutputs: [.planChecklist]
            ),
            completionCondition: "A collaborative gathering agenda and output checklist are produced.",
            contextContract: SystemPlaybookContracts.contract(for: "community.gathering"),
            outcome: OutcomeSpec(
                summary: "A shared agenda and output checklist are produced.",
                criteria: [
                    .producedArtifact,
                    .noFailedSteps,
                    .noBlockedSteps,
                    .traceFullyLegible
                ]
            ),
            installState: .installed
        ),
        Playbook(
            id: "artifact.maintenance",
            name: "Artifact Maintenance",
            summary: "Finds stale draft artifacts and prepares cleanup recommendations.",
            trigger: .maintenance(intervalSeconds: 86_400),
            authority: PlaybookAuthority(
                capabilities: [.runPlugin],
                allowedOutputs: [.planChecklist]
            ),
            completionCondition: "A maintenance checklist is produced.",
            contextContract: SystemPlaybookContracts.contract(for: "artifact.maintenance"),
            outcome: OutcomeSpec(
                summary: "A cleanup checklist is produced by the unattended maintenance sweep.",
                criteria: [
                    .producedArtifact,
                    .noFailedSteps,
                    .judgeDidNotEscalate,
                    .reachedRoutinePhase(.completed),
                    .traceFullyLegible
                ]
            ),
            installState: .available
        )
    ]
}
