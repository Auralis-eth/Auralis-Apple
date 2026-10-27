import AuralisReceipts
import AuralisFoundation
import AuralisPolicy
import AuralisRuntime
import RuntimeKit
import SocialCore
import SwiftUI
import TrustedUIKit

/// P1-102 — Workflow Timeline: one row per correlated workflow with its coarse state and last update.
struct MissionControlTimelineView: View {
    @Bindable var model: MissionControlHomeModel

    var body: some View {
        // `agentSessionSummaries` and `timelineReasoning(for:)` each walk the full worklog and receipt
        // set. SwiftUI builds every row's `NavigationLink` destination eagerly, so calling them per row
        // made the Timeline quadratic in the workflow count. Derive once per body pass and index by ID.
        let summaries = model.filteredWorkflowSummaries
        let sessionSummariesByID = model.agentSessionSummariesByID
        let reasoningByID = Dictionary(
            summaries.map { ($0.id, model.timelineReasoning(for: $0.id)) },
            uniquingKeysWith: { first, _ in first }
        )
        return List {
            Section("Filters") {
                Picker("Status", selection: $model.workflowStatusFilter) {
                    ForEach(WorkflowStateFilter.allCases) { filter in
                        Text(filter.rawValue).tag(filter)
                    }
                }
                Picker("Account", selection: $model.workflowAccountFilter) {
                    Text("All accounts").tag(String?.none)
                    ForEach(model.workflowAccounts, id: \.self) { account in
                        Text(account).tag(String?.some(account))
                    }
                }
                .accessibilityIdentifier(MissionControlA11yID.timelineAccountFilter)
                Picker("Playbook", selection: $model.workflowPlaybookFilter) {
                    Text("All playbooks").tag(String?.none)
                    ForEach(model.workflowPlaybooks, id: \.self) { playbook in
                        Text(playbook).tag(String?.some(playbook))
                    }
                }
                .accessibilityIdentifier(MissionControlA11yID.timelinePlaybookFilter)
                TextField("Filter by workflow ID", text: $model.workflowSearchText)
                    .autocorrectionDisabled()
            }

            if summaries.isEmpty {
                Text("No workflows yet.")
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier(MissionControlA11yID.timelineEmpty)
            } else {
                ForEach(summaries) { summary in
                    workflowRow(
                        summary,
                        sessionSummary: sessionSummariesByID[summary.id],
                        reasoning: reasoningByID[summary.id]
                    )
                }
            }
        }
        .accessibilityIdentifier(MissionControlA11yID.timeline)
    }

    @ViewBuilder
    private func workflowRow(
        _ summary: WorkflowSummary,
        sessionSummary: MissionControlHomeModel.AgentSessionSummary?,
        reasoning: MissionControlHomeModel.TimelineReasoning?
    ) -> some View {
        HStack(alignment: .center, spacing: 12) {
            NavigationLink {
                MissionControlAgentSessionDetailView(
                    summary: sessionSummary,
                    correlationID: summary.id,
                    model: model
                )
            } label: {
                HStack {
                    Label(summary.state.label, systemImage: summary.state.systemImage)
                        .labelStyle(.iconOnly)
                        .foregroundStyle(color(for: summary.state))
                        .accessibilityLabel(summary.state.label)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(summary.playbook)
                            .font(.callout)
                            .lineLimit(2)
                        Text("\(summary.state.label) • \(summary.eventCount) events • \(summary.account)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        // P1-AGENT-101 — surface the reasoning (considered/rejected, duration, inference)
                        // on the row itself, not only in the drill-in session detail.
                        if let reasoningLine = reasoning?.summaryLine {
                            Text(reasoningLine)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                                .accessibilityIdentifier(MissionControlA11yID.timelineReasoning(summary.id))
                        }
                        Text(summary.id)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                        Text("Next: \(summary.nextStep)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text(summary.lastUpdated, style: .time)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            if model.canStopWorkflow(summary) {
                Button("Stop", role: .destructive) {
                    Task { await model.stopWorkflow(id: summary.id) }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .accessibilityIdentifier(MissionControlA11yID.workflowStopButton(summary.id))
            }
        }
    }

    private func color(for state: WorkflowState) -> Color {
        switch state {
        case .queued: return .gray
        case .running: return .blue
        case .waiting: return .orange
        case .blocked: return .red
        case .completed: return .green
        case .failed: return .pink
        }
    }
}

/// Agent/session inspector: makes the long-running session model visible from runtime worklogs.
struct MissionControlAgentSessionDetailView: View {
    let summary: MissionControlHomeModel.AgentSessionSummary?
    let correlationID: String
    let model: MissionControlHomeModel
    @State private var worklogExport: MissionControlWorklogExportFile?
    @State private var worklogExportError: MissionControlWorklogExportAlert?

    var body: some View {
        List {
            Section("Session") {
                LabeledContent("Correlation", value: correlationID)
                if let summary {
                    LabeledContent("Goal", value: summary.goal)
                    LabeledContent("State", value: summary.state.label)
                    LabeledContent("Receipts", value: "\(summary.receiptCount)")
                    LabeledContent("Approvals", value: "\(summary.approvalCount)")
                    LabeledContent("Artifacts", value: "\(summary.artifactCount)")
                    // P1-101 — token/model/runtime metadata and local vs remote inference, made visible.
                    LabeledContent("Model", value: summary.inference.modelLabel)
                        .accessibilityIdentifier(MissionControlA11yID.sessionModel)
                    LabeledContent("Inference", value: summary.inference.localityLabel)
                        .accessibilityIdentifier(MissionControlA11yID.sessionInference)
                    LabeledContent("Privacy impact", value: summary.inference.privacyImpactLabel)
                    LabeledContent("Execution time", value: summary.inference.durationLabel)
                    LabeledContent("Tokens", value: summary.inference.tokensLabel)
                        .accessibilityIdentifier(MissionControlA11yID.sessionTokens)
                    // P1-AI-103 — model hops (invocations) and distinct models, for multi-agent observability.
                    LabeledContent("Model hops", value: summary.inference.modelHopsLabel)
                        .accessibilityIdentifier(MissionControlA11yID.sessionModelHops)
                    LabeledContent("Models used", value: "\(summary.modelCount)")
                    LabeledContent("Estimated cost", value: summary.estimatedCostLabel)
                    if let startedAt = summary.startedAt {
                        LabeledContent("Started", value: startedAt.formatted(date: .abbreviated, time: .shortened))
                    }
                    if let endedAt = summary.endedAt {
                        LabeledContent("Ended", value: endedAt.formatted(date: .abbreviated, time: .shortened))
                    }
                }
            }

            if let summary, !summary.capabilities.isEmpty {
                Section("Capabilities") {
                    ForEach(summary.capabilities, id: \.self) { capability in
                        Text(capability)
                    }
                }
            }

            if let summary, !summary.memoryTouched.isEmpty {
                Section("Memory and context") {
                    ForEach(summary.memoryTouched, id: \.self) { item in
                        Text(item)
                    }
                }
            }

            if let summary, !summary.executionUpdates.isEmpty {
                Section("Execution updates") {
                    ForEach(summary.executionUpdates, id: \.self) { update in
                        Text(update)
                    }
                }
            }

            let relatedReceipts = model.browserReceipts.filter { $0.correlationID == correlationID }
            let postflightSummaries = relatedReceipts.map { receipt in
                (receipt: receipt, presentation: model.presentation(for: receipt))
            }
            if !relatedReceipts.isEmpty {
                Section("Receipts") {
                    ForEach(relatedReceipts) { receipt in
                        NavigationLink {
                            MissionControlReceiptDetailView(receipt: receipt, model: model)
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(receipt.summary).lineLimit(1)
                                Text(receipt.createdAt, style: .time)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            .accessibilityElement(children: .combine)
                        }
                    }
                }
            }

            if summary?.state == .completed, !postflightSummaries.isEmpty {
                Section("Postflight") {
                    ForEach(postflightSummaries, id: \.receipt.id) { item in
                        NavigationLink {
                            MissionControlReceiptDetailView(receipt: item.receipt, model: model)
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.presentation.outcome.rawValue)
                                Text(item.presentation.changeRows.map(\.value).joined(separator: "\n"))
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(3)
                            }
                            .accessibilityElement(children: .combine)
                        }
                    }
                }
            }

            let relatedArtifacts = relatedArtifacts(in: relatedReceipts)
            if !relatedArtifacts.isEmpty {
                Section("Artifacts") {
                    ForEach(relatedArtifacts) { artifact in
                        NavigationLink {
                            MissionControlArtifactDetailView(artifact: artifact, model: model)
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(artifact.title)
                                Text("\(artifact.type.rawValue) • v\(artifact.version)")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            .accessibilityElement(children: .combine)
                        }
                    }
                }
            }

            Section("Worklog") {
                let steps = model.worklogSteps(for: correlationID)
                if let failure = model.worklogStoreHealth.lastFailure {
                    Label {
                        Text("Worklog incomplete. \(failure.localizedDescription)")
                    } icon: {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .accessibilityHidden(true)
                    }
                    .foregroundStyle(.orange)
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier(MissionControlA11yID.worklogDegraded)
                }
                if steps.isEmpty {
                    Text(model.worklogStoreHealth.isDegraded
                        ? "No readable worklog entries are currently available for this session."
                        : "No worklog entries for this session.")
                        .foregroundStyle(.secondary)
                } else {
                    // The trace is the evidence behind this session's receipts, so it has to be able
                    // to leave the device — for a bug report, or a per-run report card.
                    Button("Export this workflow's trace") {
                        exportWorkflowTrace()
                    }
                    .accessibilityIdentifier(MissionControlA11yID.worklogWorkflowExport)
                    ForEach(steps) { step in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(worklogTitle(step.event))
                            // P1-101 — the planner's reasoning: what it considered and what it
                            // rejected, each with the rationale, not just the chosen action.
                            if case let .considered(candidates) = step.event {
                                ForEach(Array(candidates.enumerated()), id: \.offset) { _, candidate in
                                    candidateRow(candidate)
                                }
                            }
                            // P1-101 — the deterministic checks the pipeline evaluated: which passed,
                            // which failed, and why, not just the count.
                            if case let .checksEvaluated(results) = step.event {
                                ForEach(Array(results.enumerated()), id: \.offset) { _, result in
                                    checkRow(result)
                                }
                            }
                            // P0.5-602 — who acted, and under what authority. The trace persisted this
                            // per entry from the start but never showed it, so a worklog read as a list
                            // of anonymous events.
                            worklogAttributionRow(step)
                            Text(step.timestamp, style: .time)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        .accessibilityElement(children: .contain)
                    }
                }
            }
        }
        .navigationTitle("Session")
        .task {
            await model.loadBrowserReceipts()
            await model.loadArtifacts()
        }
        .sheet(item: $worklogExport) { payload in
            MissionControlWorklogShareView(payload: payload)
        }
        .alert("Worklog export failed", item: $worklogExportError) { _ in
            Button("OK", role: .cancel) { }
        } message: { error in
            Text(error.message)
        }
    }

    private func exportWorkflowTrace() {
        Task { @MainActor in
            do {
                worklogExport = try await model.exportWorklogTraceFile(forCorrelationID: correlationID)
            } catch {
                worklogExportError = .init(message: error.localizedDescription)
            }
        }
    }

    /// Distinct artifacts referenced by this session's receipts, resolved against the loaded store.
    private func relatedArtifacts(in receipts: [ReceiptRecord]) -> [Artifact] {
        var seen = Set<UUID>()
        var result: [Artifact] = []
        for receipt in receipts {
            for artifactID in model.artifactIDs(from: receipt) where seen.insert(artifactID).inserted {
                guard let artifact = model.artifact(id: artifactID) else { continue }
                result.append(artifact)
            }
        }
        return result
    }

    /// The attribution line for one worklog entry: who acted, where a model ran, and the authority the
    /// entry proceeded under. Authority is absent on pre-authority entries (a proposal recorded, checks
    /// run) and that absence is meaningful, so nothing is shown rather than a placeholder.
    @ViewBuilder
    private func worklogAttributionRow(_ step: WorkflowStepLog) -> some View {
        let actorLabel = ReceiptAttributionDisplay.actorLabel(for: step.actor)
        let inferenceLabel = ReceiptAttributionDisplay.inferenceLabel(for: step.actor)
        let authorityLabel = ReceiptAttributionDisplay.authorityLabel(for: step.authority)
        let detail = [inferenceLabel, authorityLabel].compactMap { $0 }.joined(separator: " • ")

        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Image(systemName: "person.badge.key")
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            Text(detail.isEmpty ? actorLabel : "\(actorLabel) • \(detail)")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            detail.isEmpty
                ? "Attributed to \(actorLabel)"
                : "Attributed to \(actorLabel). \(detail)"
        )
        .accessibilityIdentifier("missionControl.worklog.attribution")
    }

    @ViewBuilder
    private func candidateRow(_ candidate: ConsideredCandidate) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Image(systemName: candidate.wasSelected ? "checkmark.circle.fill" : "xmark.circle")
                .foregroundStyle(candidate.wasSelected ? .green : .secondary)
                .accessibilityLabel(candidate.wasSelected ? "Selected" : "Rejected")
            VStack(alignment: .leading, spacing: 1) {
                Text(candidate.title)
                    .font(.caption)
                Text(candidate.rationale)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private func checkRow(_ result: DeterministicCheckResult) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            // Three-way on severity, not two-way on `passed`: a warning is a pass, so rendering it
            // as a green checkmark told the reader the opposite of what the detail line said.
            Image(systemName: checkSymbol(result.severity))
                .foregroundStyle(checkTint(result.severity))
                .accessibilityLabel(checkAccessibilityLabel(result.severity))
            VStack(alignment: .leading, spacing: 1) {
                Text(result.checkID)
                    .font(.caption)
                if let detail = result.detail, !detail.isEmpty {
                    Text(detail)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func checkSymbol(_ severity: DeterministicCheckSeverity) -> String {
        switch severity {
        case .pass: "checkmark.circle.fill"
        case .warning: "exclamationmark.triangle.fill"
        case .failure: "xmark.octagon.fill"
        }
    }

    private func checkTint(_ severity: DeterministicCheckSeverity) -> Color {
        switch severity {
        case .pass: .green
        case .warning: .orange
        case .failure: .red
        }
    }

    private func checkAccessibilityLabel(_ severity: DeterministicCheckSeverity) -> String {
        switch severity {
        case .pass: "Passed"
        case .warning: "Passed with warning"
        case .failure: "Failed"
        }
    }

    private func worklogTitle(_ event: WorkflowWorklogEvent) -> String {
        switch event {
        case let .considered(candidates):
            let selected = candidates.filter(\.wasSelected).count
            return "Considered \(candidates.count) option(s) — \(selected) selected, \(candidates.count - selected) rejected"
        case let .proposed(proposal):
            return "Proposed: \(proposal.intent)"
        case let .checksEvaluated(results):
            let failed = results.filter { !$0.passed }.count
            let warned = results.warnings.count
            let suffix: String
            if failed > 0 {
                suffix = "\(failed) failed"
            } else if warned > 0 {
                suffix = "all passed, \(warned) with warnings"
            } else {
                suffix = "all passed"
            }
            return "Checks evaluated: \(results.count) — \(suffix)"
        case let .decided(decision):
            return "Judge: \(decisionLabel(decision))"
        case let .executed(_, duration):
            return "Executed in \(String(format: "%.2f", duration))s"
        case let .blocked(reason):
            return "Blocked: \(reason)"
        case let .failed(reason):
            return "Failed: \(reason)"
        case let .routinePhase(phase, detail):
            guard let detail, !detail.isEmpty else { return phase.displayTitle }
            return "\(phase.displayTitle): \(detail)"
        case let .unknown(caseName, _):
            // Named rather than hidden: the entry is real evidence that something ran, and saying
            // so is more honest than an empty row the operator cannot account for.
            return "Unrecognized step “\(caseName)” — recorded by a newer version"
        }
    }

    private func decisionLabel(_ decision: JudgeDecision) -> String {
        switch decision {
        case .allow:
            return "allowed"
        case let .block(reason):
            return "blocked: \(reason)"
        case let .revise(instructions):
            return "revise: \(instructions)"
        case let .escalate(request):
            return "approval needed: \(request.prompt)"
        }
    }
}

/// Context Bundle Inspector: visible governed operating context plus contract validation.
struct MissionControlContextView: View {
    @Bindable var model: MissionControlHomeModel
    @State private var worklogExport: MissionControlWorklogExportFile?
    @State private var worklogExportError: MissionControlWorklogExportAlert?

    var body: some View {
        List {
            // One derivation feeds the contract state, the violations, and the bundle card below.
            // Reading the three accessors separately built (and re-walked) the ledger three times.
            let inspection = model.contextInspection

            Section("Contract") {
                // Same three-way distinction as Home: a console that has not loaded yet is not the
                // same finding as a contract the loaded context violates.
                Label(
                    inspection.freshness == .fresh ? "Satisfied" : inspection.freshness.label,
                    systemImage: inspection.freshness.systemImage
                )
                .foregroundStyle(Self.tint(for: inspection.freshness))
                if inspection.validation.violations.isEmpty {
                    Text("All required context fields satisfy the declared contract.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(inspection.validation.violations, id: \.self) { violation in
                        Text(violation)
                    }
                }
            }

            Section("Bundle fields") {
                TrustedUISurface(
                    request: .inspectContextBundle(inspection.bundle),
                    registry: model.trustedUIRegistry,
                    referenceDate: model.pinnedRenderingDate
                )
            }

            // The whole trace, byte-stable, as one file. This is what evals and operator report cards
            // consume: the inspector shows the current bundle, the export is the history it came from,
            // in a form that can be diffed between runs off-device.
            Section("Trace export") {
                Button("Export full worklog trace") {
                    exportFullTrace()
                }
                .accessibilityIdentifier(MissionControlA11yID.worklogExport)
                Text(model.contextMemorySummary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityIdentifier(MissionControlA11yID.context)
        // The bundle is derived from leases/receipts/worklog captured at the last console load; refresh
        // the volatile inputs so the inspector reflects current authority and receipts on (re)entry.
        .task {
            await model.refreshLeases()
            await model.loadBrowserReceipts()
        }
        .sheet(item: $worklogExport) { payload in
            MissionControlWorklogShareView(payload: payload)
        }
        .alert("Worklog export failed", item: $worklogExportError) { _ in
            Button("OK", role: .cancel) { }
        } message: { error in
            Text(error.message)
        }
    }

    private func exportFullTrace() {
        Task { @MainActor in
            do {
                worklogExport = try await model.exportWorklogTraceFile()
            } catch {
                worklogExportError = .init(message: error.localizedDescription)
            }
        }
    }

    private static func tint(for freshness: MissionControlHomeModel.ContextFreshnessState) -> Color {
        switch freshness {
        case .fresh: return .green
        case .notLoadedYet: return .secondary
        case .needsAttention: return .orange
        }
    }
}

/// Identifiable wrapper so an export failure can drive an optional-item alert binding.
struct MissionControlWorklogExportAlert: Identifiable {
    let id = UUID()
    let message: String
}

/// Hand-off surface for a written worklog snapshot. Read-only: unlike an artifact export there is no
/// lifecycle to record — the trace is evidence, not a work product with an approval state.
private struct MissionControlWorklogShareView: View {
    let payload: MissionControlWorklogExportFile

    var body: some View {
        NavigationStack {
            List {
                Section("Ready to share") {
                    ShareLink("Share worklog trace", item: payload.url)
                    LabeledContent("File", value: payload.filename)
                    LabeledContent("Entries", value: "\(payload.stepCount)")
                    LabeledContent("Workflows", value: "\(payload.workflowCount)")
                    LabeledContent(
                        "Size",
                        value: payload.byteCount.formatted(.byteCount(style: .file))
                    )
                    Text(payload.summary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
            }
            .navigationTitle(payload.title)
        }
    }
}

/// Identifiable wrapper so a shared session can drive a `.sheet(item:)` while the detail view always
/// re-reads the live session by id (mutations reflect immediately after each `loadCoordination()`).
private struct SelectedSharedSession: Identifiable, Equatable {
    let id: UUID
}

/// Shared session and ritual coordination (P1-SOCIAL-101/102). Sessions are openable and editable:
/// tap one to add participants, share receipts/artifacts/playbooks, and run collaborative approvals.
struct MissionControlSessionsView: View {
    @Bindable var model: MissionControlHomeModel
    @State private var selected: SelectedSharedSession?

    var body: some View {
        List {
            Section("Shared sessions") {
                Button("Open shared session") {
                    Task { await model.openSharedSession() }
                }
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier(MissionControlA11yID.sessionsOpen)

                if model.sharedSessions.isEmpty {
                    Text("No shared sessions yet.")
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier(MissionControlA11yID.sessionsEmpty)
                } else {
                    ForEach(model.sharedSessions) { session in
                        Button {
                            selected = SelectedSharedSession(id: session.id)
                        } label: {
                            sessionRow(session)
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier(MissionControlA11yID.sessionRow(session.id.uuidString))
                    }
                }
            }

            Section("Rituals") {
                if model.rituals.isEmpty {
                    Text("No rituals installed.")
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier(MissionControlA11yID.ritualsEmpty)
                } else {
                    ForEach(model.rituals) { ritual in
                        VStack(alignment: .leading, spacing: 8) {
                            Text(ritual.name)
                                .font(.headline)
                            Text(ritual.summary)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                            Text(ritualScheduleDescription(ritual))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text("Expected steps: \(ritual.playbookIDs.joined(separator: ", "))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                            if let availability = model.ritualAvailability[ritual.id], !availability.isAvailable {
                                Text(availability.unavailablePlaybookIDs.isEmpty
                                     ? "Unavailable: no executable steps are installed."
                                     : "Missing steps: \(availability.unavailablePlaybookIDs.joined(separator: ", "))")
                                    .font(.caption)
                                    .foregroundStyle(.orange)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            if let report = model.ritualRunReports[ritual.id] {
                                Text(ritualStatusDescription(report))
                                    .font(.caption)
                                    .foregroundStyle(report.status == .failed ? .red : .secondary)
                                    .accessibilityIdentifier(MissionControlA11yID.ritualStatus(ritual.id))
                            }
                            Toggle("Enable \(ritual.name)", isOn: Binding(
                                get: { ritual.isEnabled },
                                set: { enabled in
                                    Task { await model.setRitualEnabled(id: ritual.id, enabled: enabled) }
                                }
                            ))
                            .accessibilityIdentifier(MissionControlA11yID.ritualEnabled(ritual.id))
                            Button("Run \(ritual.name)") {
                                Task { await model.runRitual(id: ritual.id) }
                            }
                            .buttonStyle(.bordered)
                            .disabled(model.isPaused || model.ritualAvailability[ritual.id]?.canRun == false)
                            .accessibilityIdentifier(MissionControlA11yID.ritualRun(ritual.id))
                        }
                        .accessibilityElement(children: .contain)
                        .accessibilityIdentifier(MissionControlA11yID.ritualRow(ritual.id))
                    }
                }
            }
        }
        .task { await model.loadCoordination() }
        .accessibilityIdentifier(MissionControlA11yID.sessions)
        .sheet(item: $selected) { selection in
            NavigationStack {
                SharedSessionDetailView(model: model, sessionID: selection.id)
            }
        }
    }

    private func ritualScheduleDescription(_ ritual: RitualDefinition) -> String {
        if let schedule = ritual.calendarSchedule {
            let time = String(format: "%02d:%02d", schedule.hour, schedule.minute)
            if schedule.frequency == .weekly {
                return "Weekly on weekday \(schedule.weekday ?? 2) at \(time) (\(schedule.timeZoneIdentifier))"
            }
            return "Daily at \(time) (\(schedule.timeZoneIdentifier))"
        }
        return ritual.trigger == .manual ? "Manual" : "Event or maintenance triggered"
    }

    private func ritualStatusDescription(_ report: RuntimeHost.RitualRunReport) -> String {
        var value = "Last attempt: \(report.status.rawValue). \(report.records.count) step(s) ran."
        if report.unavailablePlaybookIDs.isEmpty == false {
            value += " Unavailable: \(report.unavailablePlaybookIDs.joined(separator: ", "))."
        }
        return value
    }

    private func sessionRow(_ session: SharedSession) -> some View {
        let pendingApprovals = session.approvals.filter { $0.resolution == .pending }.count
        return HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(session.title)
                Text("\(session.participants.count) participant(s) • \(session.isActive ? "active" : "ended")")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                if pendingApprovals > 0 {
                    Text("\(pendingApprovals) approval(s) awaiting votes")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                }
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

/// Editable detail for one shared session (P1-SOCIAL-101): participants, shared context, and
/// collaborative approvals wired to the runtime approval flow.
struct SharedSessionDetailView: View {
    @Bindable var model: MissionControlHomeModel
    let sessionID: UUID
    @Environment(\.dismiss) private var dismiss

    @State private var newParticipantName: String = ""
    @State private var newParticipantRole: SharedRole = .collaborator
    @State private var requiredApprovals: Int = 2
    @State private var agentContextTitle = ""
    @State private var agentContextSummary = ""
    @State private var isConfirmingSessionEnd = false

    private var session: SharedSession? { model.sharedSession(id: sessionID) }

    var body: some View {
        Group {
            if let session {
                List {
                    statusSection(session)
                    participantsSection(session)
                    sharedContextSection(session)
                    syncAndQueueSection(session)
                    ritualRunsSection(session)
                    approvalsSection(session)
                }
            } else {
                ContentUnavailableView("Session ended", systemImage: "person.2.slash")
            }
        }
        .navigationTitle(session?.title ?? "Shared session")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") { dismiss() }
            }
        }
    }

    // MARK: Status

    @ViewBuilder
    private func statusSection(_ session: SharedSession) -> some View {
        Section {
            LabeledContent("Status", value: session.isActive ? "Active" : "Ended")
            LabeledContent("Correlation", value: session.correlationID)
                .lineLimit(1)
            if session.isActive {
                Button("End session", role: .destructive) {
                    isConfirmingSessionEnd = true
                }
                .accessibilityIdentifier(MissionControlA11yID.sessionEnd)
                .confirmationDialog(
                    "End this shared session?",
                    isPresented: $isConfirmingSessionEnd,
                    titleVisibility: .visible
                ) {
                    Button("End session", role: .destructive) {
                        Task { await model.endSharedSession(sessionID) }
                    }
                    Button("Cancel", role: .cancel) { }
                } message: {
                    Text("Participants will no longer be able to add shared context, vote, or change the queue.")
                }
            }
        }
    }

    // MARK: Participants

    @ViewBuilder
    private func participantsSection(_ session: SharedSession) -> some View {
        Section("Participants") {
            ForEach(session.participants) { participant in
                HStack {
                    Text(displayName(participant.actor))
                    Spacer()
                    Text(participant.role.rawValue.capitalized)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            if session.isActive {
                HStack {
                    TextField("Name", text: $newParticipantName)
                        .accessibilityIdentifier(MissionControlA11yID.sessionParticipantName)
                    Picker("Role", selection: $newParticipantRole) {
                        ForEach(SharedRole.allCases, id: \.self) { role in
                            Text(role.rawValue.capitalized).tag(role)
                        }
                    }
                    .labelsHidden()
                    .accessibilityIdentifier(MissionControlA11yID.sessionParticipantRole)
                    Button("Add") {
                        Task {
                            await model.addParticipant(toSession: sessionID, name: newParticipantName, role: newParticipantRole)
                            newParticipantName = ""
                        }
                    }
                    .disabled(newParticipantName.trimmingCharacters(in: .whitespaces).isEmpty)
                    .accessibilityIdentifier(MissionControlA11yID.sessionParticipantAdd)
                }
            }
        }
    }

    // MARK: Shared context

    @ViewBuilder
    private func sharedContextSection(_ session: SharedSession) -> some View {
        Section("Shared context") {
            LabeledContent("Receipts", value: "\(session.sharedReceiptIDs.count)")
            LabeledContent("Artifacts", value: "\(session.sharedArtifactIDs.count)")
            LabeledContent("Workflows", value: "\(session.sharedPlaybookIDs.count)")
            LabeledContent("Agent context", value: "\(session.sharedAgentContexts.count)")

            ForEach(session.sharedAgentContexts) { context in
                VStack(alignment: .leading, spacing: 4) {
                    Text(context.title)
                        .font(.subheadline)
                    Text(context.summary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("Source: \(context.provenance)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier(MissionControlA11yID.sessionAgentContextRow(context.id.uuidString))
            }

            if session.isActive {
                Menu("Share a receipt") {
                    ForEach(model.recentReceipts.prefix(15)) { receipt in
                        Button(receipt.summary) {
                            Task { await model.shareReceipt(receipt.id, toSession: sessionID) }
                        }
                    }
                }
                .disabled(model.recentReceipts.isEmpty)
                .accessibilityIdentifier(MissionControlA11yID.sessionShareReceipt)

                Menu("Share an artifact") {
                    ForEach(model.artifacts.prefix(15)) { artifact in
                        Button(artifact.title) {
                            Task { await model.shareArtifact(artifact.id, toSession: sessionID) }
                        }
                    }
                }
                .disabled(model.artifacts.isEmpty)
                .accessibilityIdentifier(MissionControlA11yID.sessionShareArtifact)

                Menu("Share a workflow") {
                    ForEach(model.coordinationPlaybooks) { playbook in
                        Button(playbook.name) {
                            Task { await model.sharePlaybook(playbook.id, toSession: sessionID) }
                        }
                    }
                }
                .disabled(model.coordinationPlaybooks.isEmpty)
                .accessibilityIdentifier(MissionControlA11yID.sessionShareWorkflow)

                TextField("Context title", text: $agentContextTitle)
                    .accessibilityIdentifier(MissionControlA11yID.sessionAgentContextTitle)
                TextField("Shareable context summary", text: $agentContextSummary, axis: .vertical)
                    .lineLimit(2...6)
                    .accessibilityIdentifier(MissionControlA11yID.sessionAgentContextSummary)
                Button("Share agent context") {
                    let title = agentContextTitle
                    let summary = agentContextSummary
                    Task {
                        await model.shareAgentContext(title: title, summary: summary, toSession: sessionID)
                        agentContextTitle = ""
                        agentContextSummary = ""
                    }
                }
                .disabled(
                    agentContextTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    || agentContextSummary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                )
                .accessibilityIdentifier(MissionControlA11yID.sessionShareAgentContext)
            }
        }
    }

    // MARK: Sync, queue, and ritual state

    @ViewBuilder
    private func syncAndQueueSection(_ session: SharedSession) -> some View {
        let summary = model.coordinationSyncSummary(sessionID: session.id)
        Section("Sync and queue") {
            LabeledContent("Sync", value: summary?.syncLabel ?? "Local only")
                .accessibilityIdentifier(MissionControlA11yID.sessionSyncStatus)
            LabeledContent("Pending outbound", value: "\(summary?.pendingOutboundCount ?? 0)")
            LabeledContent("Queue items", value: "\(summary?.queueItemCount ?? 0)")
            LabeledContent("Queue proposals", value: "\(summary?.queueProposalCount ?? 0)")
                .accessibilityIdentifier(MissionControlA11yID.sessionQueueStatus)
            Text("Queue state syncs decisions, not live playback clocks.")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func ritualRunsSection(_ session: SharedSession) -> some View {
        let runs = model.coordinationSyncSummary(sessionID: session.id)?.ritualRuns ?? []
        Section("Ritual runs") {
            if runs.isEmpty {
                Text("No synced ritual runs yet.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(runs) { run in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(run.ritualID)
                            .font(.subheadline)
                        Text("\(run.status.rawValue.capitalized) • \(run.artifactIDs.count) artifact(s) • \(run.receiptIDs.count) receipt(s)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .accessibilityElement(children: .combine)
                }
            }
        }
        .accessibilityIdentifier(MissionControlA11yID.sessionRitualStatus)
    }

    // MARK: Collaborative approvals

    @ViewBuilder
    private func approvalsSection(_ session: SharedSession) -> some View {
        Section("Collaborative approvals") {
            if session.approvals.isEmpty {
                Text("No collaborative approvals yet.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(session.approvals) { approval in
                    approvalRow(session: session, approval: approval)
                }
            }

            if session.isActive {
                let voters = session.participants.filter { $0.role.canVote }
                Stepper("Required approvals: \(requiredApprovals)", value: $requiredApprovals, in: 1...max(1, voters.count))
                    .accessibilityIdentifier(MissionControlA11yID.sessionApprovalRequiredCount)
                Menu("Open collaborative approval") {
                    ForEach(model.pendingApprovals) { request in
                        Button(request.prompt) {
                            Task {
                                await model.openCollaborativeApproval(
                                    sessionID: sessionID,
                                    request: request,
                                    requiredApprovals: requiredApprovals
                                )
                            }
                        }
                    }
                }
                .disabled(model.pendingApprovals.isEmpty)
                .accessibilityIdentifier(MissionControlA11yID.sessionApprovalOpen)
            }
        }
    }

    @ViewBuilder
    private func approvalRow(session: SharedSession, approval: CollaborativeApproval) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(approval.prompt)
                .font(.subheadline)
            Text("\(approval.approvalCount)/\(approval.requiredApprovals) approvals • \(approval.rejectionCount) against • \(approval.resolution.rawValue)")
                .font(.caption2)
                .foregroundStyle(resolutionColor(approval.resolution))

            if session.isActive, approval.resolution == .pending {
                let voters = session.participants.filter { $0.role.canVote }
                ForEach(voters) { participant in
                    HStack {
                        Text(displayName(participant.actor))
                            .font(.caption)
                        Spacer()
                        Button("Approve") {
                            Task {
                                await model.voteOnCollaborativeApproval(
                                    sessionID: sessionID, approvalID: approval.id,
                                    participant: participant.actor, approved: true
                                )
                            }
                        }
                        .buttonStyle(.borderless)
                        .accessibilityIdentifier(MissionControlA11yID.sessionApprovalApprove(approval.id.uuidString))
                        Button("Reject", role: .destructive) {
                            Task {
                                await model.voteOnCollaborativeApproval(
                                    sessionID: sessionID, approvalID: approval.id,
                                    participant: participant.actor, approved: false
                                )
                            }
                        }
                        .buttonStyle(.borderless)
                        .accessibilityIdentifier(MissionControlA11yID.sessionApprovalReject(approval.id.uuidString))
                    }
                }
            }
        }
    }

    private func resolutionColor(_ resolution: ApprovalResolution) -> Color {
        switch resolution {
        case .approved: return .green
        case .rejected: return .red
        case .pending: return .secondary
        }
    }

    private func displayName(_ actor: ActorRef) -> String { actor.displayLabel }
}

/// P1-103 — Activity Feed: high-signal state changes only, grouped by session, categorized, and
/// linking out to receipt detail.
struct MissionControlActivityView: View {
    @Bindable var model: MissionControlHomeModel

    var body: some View {
        List {
            if model.groupedActivityFeed.isEmpty {
                Text("No notable activity yet.")
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier(MissionControlA11yID.activityFeedEmpty)
            } else {
                ForEach(model.groupedActivityFeed) { group in
                    Section(group.title) {
                        ForEach(group.events) { envelope in
                            eventRow(envelope)
                        }
                    }
                }
            }
        }
        .accessibilityIdentifier(MissionControlA11yID.activityFeed)
        .task { await model.loadBrowserReceipts() }
    }

    @ViewBuilder
    private func eventRow(_ envelope: WorkflowEventEnvelope) -> some View {
        if let receipt = model.receipt(forEvent: envelope) {
            NavigationLink {
                MissionControlReceiptDetailView(receipt: receipt, model: model)
            } label: {
                rowContent(envelope)
            }
        } else {
            rowContent(envelope)
        }
    }

    @ViewBuilder
    private func rowContent(_ envelope: WorkflowEventEnvelope) -> some View {
        let category = MissionControlHomeModel.category(for: envelope.event)
        VStack(alignment: .leading, spacing: 4) {
            Label(category.rawValue, systemImage: category.systemImage)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(MissionControlEventText.describe(envelope.event))
            Text(envelope.timestamp, style: .time)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }
}

/// P1-201/203 — Approval Inbox with a policy summary header.
struct MissionControlApprovalsView: View {
    @Bindable var model: MissionControlHomeModel

    var body: some View {
        List {
            // P1-203 — Policy summary: counts plus plain-language cards tagged hard vs semantic.
            Section("Policy summary") {
                let summary = model.policySummary
                LabeledContent("Allowed", value: "\(summary.allowed)")
                LabeledContent("Blocked", value: "\(summary.blocked)")
                LabeledContent("Escalated", value: "\(summary.escalated)")
            }

            if !model.policyOutcomeCards.isEmpty {
                Section("Why steps were blocked or gated") {
                    ForEach(model.policyOutcomeCards) { card in
                        MissionControlPolicyOutcomeRow(card: card)
                    }
                }
                .accessibilityIdentifier(MissionControlA11yID.policyCards)
            }

            Section("Approvals needed") {
                if model.pendingApprovals.isEmpty {
                    Text("Nothing awaiting approval.")
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier(MissionControlA11yID.approvalsEmpty)
                } else {
                    ForEach(model.pendingApprovals) { request in
                        NavigationLink {
                            MissionControlProposalDetailView(request: request, model: model)
                        } label: {
                            approvalRow(request)
                        }
                    }
                }
            }
        }
        .accessibilityIdentifier("missionControl.approvals")
        .task { await model.loadBrowserReceipts() }
        .task { await model.loadArtifacts() }
    }

    @ViewBuilder
    private func approvalRow(_ request: ApprovalRequest) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(request.prompt).font(.callout)
            // Trusted risk component (P0.5-502) derived from the proposal's impact class.
            RiskBanner(impact: request.proposal.impact)
                .accessibilityIdentifier(MissionControlA11yID.approvalRisk(request.id.uuidString))
            Text(model.capabilityTitle(request.proposal.capability))
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(model.approvalReason(for: request))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

/// P1-203 — A plain-language policy outcome card, tagged hard vs semantic policy.
struct MissionControlPolicyOutcomeRow: View {
    let card: MissionControlHomeModel.PolicyOutcomeCard

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Label(card.status.rawValue, systemImage: card.status.systemImage)
                    .font(.caption.weight(.semibold))
                Spacer()
                Text(card.kind.rawValue)
                    .font(.caption2.weight(.semibold))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(.quaternary, in: Capsule())
            }
            Text(card.title).font(.callout)
            Text(card.explanation)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }
}

struct MissionControlProposalDetailView: View {
    let request: ApprovalRequest
    let model: MissionControlHomeModel

    var body: some View {
        List {
            // P0.5-502 — the proposal, its risk (RiskBanner), and the approve/deny/defer controls
            // render through the trusted component registry (ApprovalSheet) instead of a parallel
            // ad-hoc surface. MC keeps its richer linked-context and proposal-diff sections below.
            Section {
                TrustedUISurface(
                    request: .approveAction(request),
                    registry: model.trustedUIRegistry,
                    // Resolve the request the sheet actually dispatched, not the one this view
                    // captured. They are the same today, but the registry re-asserts the pairing
                    // and that guarantee is worth consuming rather than re-deriving here.
                    onApprovalDecision: { dispatched, outcome in
                        Task { await model.resolve(dispatched, outcome: outcome) }
                    }
                )
                .listRowInsets(EdgeInsets())
            }

            // P1-201 — "why approval is needed", stated in plain language.
            Section("Why approval is needed") {
                Text(model.approvalReason(for: request))
            }

            // P1-201 — links to the plan, the receipt draft(s), and any affected artifact.
            Section("Linked context") {
                if let correlationID = request.proposal.correlationID {
                    NavigationLink {
                        MissionControlAgentSessionDetailView(
                            summary: model.agentSessionSummary(id: correlationID),
                            correlationID: correlationID,
                            model: model
                        )
                    } label: {
                        Label("Open plan / session", systemImage: "list.bullet.rectangle")
                    }
                    .accessibilityIdentifier(MissionControlA11yID.approvalPlanLink)
                } else {
                    Label("No plan linked to this proposal.", systemImage: "list.bullet.rectangle")
                        .foregroundStyle(.secondary)
                }

                let receipts = model.receipts(forApproval: request)
                if receipts.isEmpty {
                    Label("No receipt draft yet.", systemImage: "doc.text")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(receipts) { receipt in
                        NavigationLink {
                            MissionControlReceiptDetailView(receipt: receipt, model: model)
                        } label: {
                            Label(receipt.summary, systemImage: "doc.text")
                                .lineLimit(1)
                        }
                        .accessibilityIdentifier(MissionControlA11yID.approvalReceiptLink)
                    }
                }

                let artifacts = model.artifacts(forApproval: request)
                if artifacts.isEmpty {
                    Label("No affected artifact.", systemImage: "archivebox")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(artifacts) { artifact in
                        NavigationLink {
                            MissionControlArtifactDetailView(artifact: artifact, model: model)
                        } label: {
                            Label(artifact.title, systemImage: "archivebox")
                                .lineLimit(1)
                        }
                        .accessibilityIdentifier(MissionControlA11yID.approvalArtifactLink)
                    }
                }
            }

            Section("Proposal diff") {
                ForEach(model.proposalDiffRows(for: request.proposal)) { row in
                    MissionControlDiffRow(row: row)
                }
            }

            // P1-AGENT-103 — real on-chain dry-run: what actually happens if this runs now, beyond
            // the declared-impact metadata above.
            Section("Transaction simulation") {
                MissionControlSimulationView(
                    state: model.proposalSimulationState(for: request.proposal),
                    freshness: model.proposalSimulationFreshness(for: request.proposal)
                )
            }
            .accessibilityIdentifier(MissionControlA11yID.proposalSimulation)
        }
        .navigationTitle("Proposal")
        .task {
            await model.loadBrowserReceipts()
            await model.loadArtifacts()
        }
        .task(id: request.proposal.id) {
            await model.simulateProposal(request.proposal)
        }
    }
}

/// Renders the on-chain dry-run for a proposal: revert/gas/asset-delta when available, and a plain
/// explanation when the proposal isn't a chain transaction or simulation isn't configured. (P1-AGENT-103)
struct MissionControlSimulationView: View {
    let state: MissionControlHomeModel.ProposalSimulationState?
    /// "Simulated <relative>" note, so the predicted movements never read as live facts. (P1-AGENT-103)
    var freshness: String?

    var body: some View {
        switch state {
        case .none, .some(.running):
            HStack(spacing: 8) {
                ProgressView()
                Text("Simulating against current chain state…")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .combine)
        case let .some(.finished(simulation)):
            finished(simulation)
        }
    }

    @ViewBuilder
    private func finished(_ simulation: ProposalSimulation) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            switch simulation.status {
            case .success:
                Label("Simulated successfully — would not revert", systemImage: "checkmark.seal")
                    .foregroundStyle(.green)
            case let .reverted(reason):
                Label("Would revert", systemImage: "xmark.octagon")
                    .foregroundStyle(.red)
                Text(reason)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            case .notApplicable:
                Label("No on-chain transaction to simulate", systemImage: "minus.circle")
                    .foregroundStyle(.secondary)
            case let .unavailable(reason):
                Label("Simulation unavailable", systemImage: "wifi.exclamationmark")
                    .foregroundStyle(.orange)
                Text(reason)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if let chainName = simulation.chainName {
                LabeledContent("Network", value: chainName)
                    .font(.caption)
                if simulation.chainAssumed {
                    Text("Assumed — the proposal didn't specify a network")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                }
            }
            if let gasUsed = simulation.gasUsed {
                LabeledContent("Gas (simulated)", value: gasUsed)
                    .font(.caption)
            }
            if let cost = simulation.estimatedGasCostEth {
                LabeledContent("Estimated gas cost", value: "~\(cost) ETH")
                    .font(.caption)
            }

            if !simulation.assetChanges.isEmpty {
                Divider()
                Text("Predicted balance changes")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                ForEach(simulation.assetChanges) { change in
                    assetRow(change)
                }
            }

            // Freshness: a dry-run reflects chain state at the moment it ran, not now.
            if let freshness {
                Text("\(freshness) — reflects chain state at that time.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier(MissionControlA11yID.proposalSimulationFreshness)
            }
        }
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private func assetRow(_ change: ProposalAssetChange) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Image(systemName: Self.icon(for: change.direction))
                .foregroundStyle(Self.tint(for: change.direction))
                .accessibilityLabel(Self.directionLabel(for: change.direction))
            Text("\(Self.sign(for: change.direction))\(change.amount) \(change.symbol)")
                .font(.caption.monospacedDigit())
            if let counterparty = change.counterparty {
                Spacer()
                Text(counterparty)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private static func icon(for direction: ProposalAssetChange.Direction) -> String {
        switch direction {
        case .outgoing: return "arrow.up.right"
        case .incoming: return "arrow.down.left"
        case .unknown: return "arrow.left.arrow.right"
        }
    }

    private static func tint(for direction: ProposalAssetChange.Direction) -> Color {
        switch direction {
        case .outgoing: return .red
        case .incoming: return .green
        case .unknown: return .secondary
        }
    }

    private static func sign(for direction: ProposalAssetChange.Direction) -> String {
        switch direction {
        case .outgoing: return "−"
        case .incoming: return "+"
        case .unknown: return ""
        }
    }

    private static func directionLabel(for direction: ProposalAssetChange.Direction) -> String {
        switch direction {
        case .outgoing: return "Outgoing"
        case .incoming: return "Incoming"
        case .unknown: return "Direction unknown"
        }
    }
}

struct MissionControlDiffRow: View {
    let row: MissionControlHomeModel.ProposalDiffRow

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(row.label)
                .font(.headline)
            LabeledContent("Before", value: row.before)
            LabeledContent("After", value: row.after)
            LabeledContent("Risk", value: row.risk)
        }
        .accessibilityElement(children: .combine)
    }
}

/// P1-202 — Capability Inspector: active leases grouped by the four authority scopes, each showing
/// what it grants (reason), its duration, and a revoke control.
struct MissionControlCapabilitiesView: View {
    @Bindable var model: MissionControlHomeModel
    @State private var grantCapability: CapabilityID = .playlistManagement
    @State private var grantActorKind: ActorKind = .workflow
    @State private var grantActorIdentifier = "planner"
    @State private var grantDurationMinutes = 20
    @State private var grantReason = ""
    @State private var restrictionDraft: RestrictionDraftKind = .walletAccess
    @State private var restrictionCapability: CapabilityID = .draftTransaction
    @State private var restrictionActorKind: ActorKind = .workflow
    @State private var restrictionAppliesToActor = false
    @State private var restrictionActorIdentifier = "planner"
    @State private var restrictionDurationMinutes = 20
    @State private var restrictionExpires = true
    @State private var restrictionReason = ""

    var body: some View {
        List {
            Section("Grant capability") {
                Picker("Capability", selection: $grantCapability) {
                    ForEach(CapabilityID.allCases, id: \.self) { capability in
                        Text(model.capabilityTitle(capability)).tag(capability)
                    }
                }
                Picker("Actor", selection: $grantActorKind) {
                    ForEach(ActorKind.allCases, id: \.self) { kind in
                        Text(kind.displayTitle).tag(kind)
                    }
                }
                TextField("Actor ID", text: $grantActorIdentifier)
                    .accessibilityIdentifier(MissionControlA11yID.capabilityGrantActorID)
                Stepper("Duration: \(grantDurationMinutes) min", value: $grantDurationMinutes, in: 1...240)
                TextField("Reason", text: $grantReason, axis: .vertical)
                    .lineLimit(2...4)
                    .accessibilityIdentifier(MissionControlA11yID.capabilityGrantReason)
                Button("Grant capability") {
                    Task { await grantCapabilityLease() }
                }
                .accessibilityIdentifier(MissionControlA11yID.capabilityGrantButton)
            }

            Section("Deny capability") {
                Picker("Restriction", selection: $restrictionDraft) {
                    ForEach(RestrictionDraftKind.allCases) { draft in
                        Text(draft.title).tag(draft)
                    }
                }
                if restrictionDraft == .specificCapability {
                    Picker("Capability", selection: $restrictionCapability) {
                        ForEach(CapabilityID.allCases, id: \.self) { capability in
                            Text(model.capabilityTitle(capability)).tag(capability)
                        }
                    }
                }
                Toggle("Limit to one actor", isOn: $restrictionAppliesToActor)
                if restrictionAppliesToActor {
                    Picker("Actor", selection: $restrictionActorKind) {
                        ForEach(ActorKind.allCases, id: \.self) { kind in
                            Text(kind.displayTitle).tag(kind)
                        }
                    }
                    TextField("Actor ID", text: $restrictionActorIdentifier)
                        .accessibilityIdentifier(MissionControlA11yID.capabilityRestrictionActorID)
                }
                Toggle("Expires", isOn: $restrictionExpires)
                if restrictionExpires {
                    Stepper("Duration: \(restrictionDurationMinutes) min", value: $restrictionDurationMinutes, in: 1...240)
                }
                TextField("Reason", text: $restrictionReason, axis: .vertical)
                    .lineLimit(2...4)
                    .accessibilityIdentifier(MissionControlA11yID.capabilityRestrictionReason)
                Button("Deny capability", role: .destructive) {
                    Task { await denyCapability() }
                }
                .accessibilityIdentifier(MissionControlA11yID.capabilityDenyButton)
            }

            if model.activeLeases.isEmpty && model.activeRestrictions.isEmpty {
                Text("No active leases or restrictions. Capabilities are granted just-in-time and expire automatically.")
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier(MissionControlA11yID.capabilitiesEmpty)
            } else {
                ForEach(MissionControlHomeModel.CapabilityScope.allCases, id: \.self) { scope in
                    let leases = model.leases(inScope: scope)
                    if !leases.isEmpty {
                        Section {
                            ForEach(leases) { lease in
                                leaseRow(lease)
                            }
                        } header: {
                            Label(scope.rawValue, systemImage: scope.systemImage)
                        } footer: {
                            Text(scope.explanation)
                        }
                    }
                }
                if !model.activeRestrictions.isEmpty {
                    Section {
                        ForEach(model.activeRestrictions) { restriction in
                            restrictionRow(restriction)
                        }
                    } header: {
                        Label("Restrictions", systemImage: "hand.raised")
                    } footer: {
                        Text("Explicit denials override matching capability leases until they expire or are revoked.")
                    }
                }
            }
        }
        .task { await model.refreshLeases() }
        .accessibilityIdentifier(MissionControlA11yID.capabilities)
    }

    private func grantCapabilityLease() async {
        await model.grantLease(
            capability: grantCapability,
            actorKind: grantActorKind,
            actorIdentifier: grantActorIdentifier,
            reason: grantReason,
            durationMinutes: grantDurationMinutes
        )
        grantReason = ""
    }

    private func denyCapability() async {
        await model.denyCapability(
            restrictionDraft.kind(capability: restrictionCapability),
            actorKind: restrictionAppliesToActor ? restrictionActorKind : nil,
            actorIdentifier: restrictionActorIdentifier,
            reason: restrictionReason,
            durationMinutes: restrictionExpires ? restrictionDurationMinutes : nil
        )
        restrictionReason = ""
    }

    @ViewBuilder
    private func leaseRow(_ lease: CapabilityLease) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            TrustedUISurface(
                request: .inspectCapability(lease.capability),
                registry: model.trustedUIRegistry
            )
            // Attribution goes through ReceiptAttributionDisplay (P0.5-601/602) so a lease reads
            // "Operator — daily.brief" rather than the Swift case name `operatorAgent`.
            Text("granted to \(ReceiptAttributionDisplay.actorLabel(for: lease.grantedTo)) • \(model.durationText(for: lease))")
                .font(.caption2)
                .foregroundStyle(.secondary)
            Button("Revoke", role: .destructive) {
                Task { await model.revokeLease(id: lease.id) }
            }
            .buttonStyle(.bordered)
            .font(.caption)
        }
    }

    @ViewBuilder
    private func restrictionRow(_ restriction: CapabilityRestriction) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(restriction.kind.displayTitle)
                .font(.headline)
            Text(restriction.reason)
                .font(.caption)
                .foregroundStyle(.secondary)
            if let expiresAt = restriction.expiresAt {
                Text("expires \(model.relativeText(expiresAt))")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Button("Revoke", role: .destructive) {
                Task { await model.revokeRestriction(id: restriction.id) }
            }
            .buttonStyle(.bordered)
            .font(.caption)
        }
        .accessibilityElement(children: .combine)
    }
}

private enum RestrictionDraftKind: String, CaseIterable, Identifiable {
    case walletAccess
    case externalNetwork
    case specificCapability

    var id: String { rawValue }

    var title: String {
        switch self {
        case .walletAccess: return "No wallet access"
        case .externalNetwork: return "No external network"
        case .specificCapability: return "Specific capability"
        }
    }

    func kind(capability: CapabilityID) -> CapabilityRestrictionKind {
        switch self {
        case .walletAccess: return .walletAccess
        case .externalNetwork: return .externalNetwork
        case .specificCapability: return .capability(capability)
        }
    }
}

/// P1-104 — Mode Surface: crypto-scoped posture, made explicit. Observe / Assist / Operate are all
/// exposed and selectable while wallet execution remains governed by policy controls.
struct MissionControlModeView: View {
    @Bindable var model: MissionControlHomeModel

    var body: some View {
        List {
            Section("Crypto") {
                Picker("Current mode", selection: Binding(
                    get: { model.cryptoMode },
                    set: { model.cryptoMode = $0 }
                )) {
                    ForEach(CryptoMode.allCases, id: \.self) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .accessibilityIdentifier(MissionControlA11yID.modePicker)

                Text("Wallet capabilities are governed by the selected mode and still require the matching policy evidence before high-risk execution.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section("Operator surfaces") {
                ForEach(CryptoMode.allCases, id: \.self) { surface in
                    surfaceRow(surface)
                }
            }
            .accessibilityIdentifier(MissionControlA11yID.modeSurfaces)

            Section("Crypto actions") {
                ForEach(model.cryptoActionDispositions) { disposition in
                    VStack(alignment: .leading, spacing: 2) {
                        Label(disposition.id, systemImage: disposition.systemImage)
                            .foregroundStyle(disposition.isAvailable ? .primary : .secondary)
                        Text(disposition.availability)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .accessibilityElement(children: .combine)
                }
            }

            Section("Everything else") {
                Label("Full operation (create, read, update, delete)", systemImage: "checkmark.seal")
                    .foregroundStyle(.green)
                Text("Music, artifacts, playbooks, and local preferences operate without the crypto gate.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityIdentifier(MissionControlA11yID.mode)
    }

    @ViewBuilder
    private func surfaceRow(_ surface: CryptoMode) -> some View {
        let isCurrent = surface == model.cryptoMode
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Label(surface.rawValue, systemImage: systemImage(for: surface))
                    .fontWeight(isCurrent ? .semibold : .regular)
                Spacer()
                Text(isCurrent ? "Active" : status(for: surface))
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(isCurrent ? .green : statusColor(for: surface))
            }
            Text(surface.description)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }

    private func status(for mode: CryptoMode) -> String {
        switch mode {
        case .observe:
            return "Read-only"
        case .assist:
            return "Approval-gated"
        case .operate:
            return "Evidence-gated"
        }
    }

    private func statusColor(for mode: CryptoMode) -> Color {
        switch mode {
        case .observe:
            return .secondary
        case .assist, .operate:
            return .orange
        }
    }

    private func systemImage(for mode: CryptoMode) -> String {
        switch mode {
        case .observe: return "eye"
        case .assist: return "sparkles"
        case .operate: return "bolt"
        }
    }
}
