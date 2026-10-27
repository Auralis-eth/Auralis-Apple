import AuralisReceipts
import AuralisRuntime
import AuralisAppShell
import SwiftUI

/// Human-readable text for a runtime event, shared across the Mission Control surfaces.
public enum MissionControlEventText {
    public static func describe(_ event: WorkflowEvent) -> String {
        switch event {
        case let .sessionStarted(_, goal): return "Session started: \(goal)"
        case let .sessionEnded(_, status): return "Session ended: \(status.rawValue)"
        case let .plannerStarted(goal): return "Planner started: \(goal)"
        case let .plannerCompleted(selectedCount, rejectedCount):
            return "Planner completed: \(selectedCount) selected, \(rejectedCount) rejected"
        case let .plannerFailed(reason): return "Planner failed: \(reason)"
        case let .policyDecision(message): return message
        case .workflowStarted: return "Workflow started"
        case let .workflowBlocked(reason): return "Blocked: \(reason)"
        case .approvalRequired: return "Approval required"
        case .receiptCreated: return "Receipt created"
        case .artifactCreated: return "Artifact created"
        case let .checkFailed(id, reason): return "Check failed (\(id)): \(reason)"
        case let .capabilityRevoked(capability): return "Capability revoked: \(String(describing: capability))"
        case let .capabilityLeaseGranted(lease): return "Capability granted: \(lease.capability.rawValue)"
        case let .capabilityLeaseExpired(capability): return "Capability expired: \(capability.rawValue)"
        case let .contextRefreshed(key): return "Context refreshed: \(key)"
        case let .memoryTouched(kind, key): return "\(kind.rawValue): \(key)"
        case let .executionUpdate(message): return message
        case let .unknown(caseName, _):
            // Names the event honestly rather than inventing a description for it, the same way an
            // unrecognized `ActorRef` renders as "Unrecognized actor (…)".
            return "Unrecognized event (\(caseName))"
        }
    }
}

/// P1-204 — Global paused banner. Shown above every Mission Control section while the kill switch is
/// engaged, so the paused state is visible throughout, along with its reason and a resume path.
struct MissionControlPausedBanner: View {
    @Bindable var model: MissionControlHomeModel

    var body: some View {
        if model.isPaused {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "pause.circle.fill")
                    .foregroundStyle(.orange)
                    .font(.title3)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Operator activity is paused")
                        .font(.subheadline.weight(.semibold))
                    Text(model.pauseReason ?? "New governed work will not start until you resume.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .accessibilityElement(children: .combine)
                Spacer()
                Button("Resume") { Task { await model.resumeOperator() } }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .accessibilityIdentifier(MissionControlA11yID.resumeButton)
            }
            .padding(12)
            .background(.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
            .padding(.horizontal)
            .padding(.top, 8)
            .accessibilityIdentifier(MissionControlA11yID.pausedBanner)
        }
    }
}

/// Surfaces the runtime's sticky degraded-audit-evidence signal: at least one receipt could not be
/// written, so the trace behind some completed work is incomplete.
///
/// A banner rather than an alert, and deliberately so. The playbook alert next to it reports that an
/// action the person just took failed, which is transient and belongs in a modal. This reports a
/// *permanent gap in the ledger* — the receipt is not coming back — so it has to stay on screen
/// while the person decides what to do about it, not be dismissed by the next tap. Reads
/// ``RuntimeHost/receiptPersistenceError`` directly because the host is `@Observable`; mirroring it
/// into the model would only add a second place for the two to disagree.
struct MissionControlDegradedEvidenceBanner: View {
    let model: MissionControlHomeModel

    var body: some View {
        if let message = model.host.receiptPersistenceError {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "exclamationmark.shield.fill")
                    .foregroundStyle(.red)
                    .font(.title3)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Audit evidence is incomplete")
                        .font(.subheadline.weight(.semibold))
                    Text(detail(message))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .accessibilityElement(children: .combine)
                Spacer()
                // Acknowledging dismisses the banner only; it does not repair the gap, which is why
                // the runtime requires it to be explicit rather than clearing on the next success.
                Button("Acknowledge") { model.host.acknowledgeReceiptPersistenceFailure() }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .accessibilityIdentifier(MissionControlA11yID.receiptPersistenceAcknowledge)
            }
            .padding(12)
            .background(.red.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
            .padding(.horizontal)
            .padding(.top, 8)
            .accessibilityIdentifier(MissionControlA11yID.receiptPersistenceError)
        }
    }

    private func detail(_ message: String) -> String {
        let count = model.host.missingReceiptCount
        guard count > 1 else { return message }
        return "\(message) \(count) receipts are missing."
    }
}

/// Surfaces a coordination store that quarantined an unreadable payload and has stopped accepting
/// writes, and offers the discard that is the only way out of it.
///
/// Separate from the degraded-evidence banner beside it because the two ask for different things.
/// That one reports a permanent gap and wants an acknowledgement; this one reports an *ongoing*
/// refusal that a person can actually clear — until they do, ritual enabled-state resets on every
/// launch and the privacy reset cannot erase what it is meant to. Destructive, so the confirmation
/// says what is discarded: quarantine exists because those bytes may be a readable snapshot from a
/// newer build, which is why the runtime will not overwrite them on its own.
struct MissionControlCoordinationQuarantineBanner: View {
    let model: MissionControlHomeModel
    @State private var confirmingDiscard = false

    var body: some View {
        if let message = model.host.coordinationPersistenceError {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "externaldrive.badge.exclamationmark")
                    .foregroundStyle(.orange)
                    .font(.title3)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Coordination data cannot be saved")
                        .font(.subheadline.weight(.semibold))
                    Text("\(message). Rituals and shared sessions will not persist until this is discarded.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .accessibilityElement(children: .combine)
                Spacer()
                Button("Discard") { confirmingDiscard = true }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .accessibilityIdentifier(MissionControlA11yID.coordinationPersistenceDiscard)
            }
            .padding(12)
            .background(.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
            .padding(.horizontal)
            .padding(.top, 8)
            .accessibilityIdentifier(MissionControlA11yID.coordinationPersistenceError)
            .confirmationDialog(
                "Discard unreadable coordination data?",
                isPresented: $confirmingDiscard,
                titleVisibility: .visible
            ) {
                Button("Discard", role: .destructive) {
                    Task { await model.host.discardQuarantinedCoordinationState() }
                }
                Button("Keep", role: .cancel) { }
            } message: {
                Text(
                    """
                    This deletes the saved shared sessions, ritual settings, and social event log \
                    that this version cannot read. Saving starts working again; the unreadable data \
                    is not recovered.
                    """
                )
            }
        }
    }
}

struct MissionControlDataQualityBanner: View {
    let issues: [String]

    var body: some View {
        if !issues.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(issues, id: \.self) { issue in
                    Label(issue, systemImage: "exclamationmark.triangle.fill")
                        .font(.footnote)
                        .foregroundStyle(.orange)
                        .accessibilityElement(children: .combine)
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
            .padding(.horizontal)
            .padding(.top, 8)
            .accessibilityIdentifier(MissionControlA11yID.dataQualityWarning)
        }
    }
}

/// Standalone Mission Control Home (used by the Settings sheet). The tab uses
/// ``MissionControlRootView`` which embeds ``MissionControlHomeContent`` directly.
public struct MissionControlHomeView: View {
    @State private var model: MissionControlHomeModel

    public init(model: MissionControlHomeModel) {
        _model = State(initialValue: model)
    }

    public var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                MissionControlPausedBanner(model: model)
                MissionControlDegradedEvidenceBanner(model: model)
                MissionControlCoordinationQuarantineBanner(model: model)
                MissionControlDataQualityBanner(issues: model.dataQualityIssues)
                MissionControlHomeContent(model: model)
            }
                .navigationTitle("Mission Control")
                .task { await model.loadConsoleAndObserveEvents() }
        }
        .missionControlApprovalPersistenceAlert(model: model)
    }

    /// Retained for existing callers/tests; delegates to the shared text helper.
    static func describe(_ event: WorkflowEvent) -> String {
        MissionControlEventText.describe(event)
    }
}

/// The P1-101 Home console content (no navigation container of its own).
struct MissionControlHomeContent: View {
    @Bindable var model: MissionControlHomeModel

    var body: some View {
        List {
            Section("Mode") {
                LabeledContent("Crypto") {
                    Text(model.cryptoModeLabel).foregroundStyle(.secondary)
                }
                Text("Wallet actions are gated in Observe. The rest of Auralis operates fully.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .accessibilityIdentifier(MissionControlA11yID.modeSection)

            Section("Console status") {
                let counts = model.consoleCounts
                LabeledContent("Queued", value: "\(counts.queued)")
                LabeledContent("Running", value: "\(counts.running)")
                LabeledContent("Waiting", value: "\(counts.waiting)")
                LabeledContent("Blocked", value: "\(counts.blocked)")
                LabeledContent("Completed", value: "\(counts.completed)")
                LabeledContent("Failed", value: "\(counts.failed)")
                LabeledContent("Approvals", value: "\(counts.approvals)")
                LabeledContent("Artifacts", value: "\(counts.artifacts)")
                Label(
                    model.hasUnhealthyRuntimeEventSubscribers
                        ? "Runtime event delivery needs attention"
                        : "Runtime event delivery is healthy",
                    systemImage: model.hasUnhealthyRuntimeEventSubscribers
                        ? "exclamationmark.triangle.fill"
                        : "checkmark.shield.fill"
                )
                .foregroundStyle(model.hasUnhealthyRuntimeEventSubscribers ? .orange : .green)
                ForEach(model.runtimeEventSubscriberHealth, id: \.subscriberID) { health in
                    LabeledContent(health.subscriberID) {
                        Text(health.isHealthy ? "Connected" : "Disconnected · \(health.droppedCount) dropped")
                            .foregroundStyle(health.isHealthy ? Color.secondary : Color.orange)
                    }
                    .accessibilityElement(children: .combine)
                }
            }

            Section("Freshness & context") {
                // One derivation for both the state label and the field rows: building the bundle
                // walks the whole receipt ledger, so it is read exactly once per body pass.
                let inspection = model.contextInspection
                Label(inspection.freshness.label, systemImage: inspection.freshness.systemImage)
                    .foregroundStyle(Self.tint(for: inspection.freshness))
                ForEach(inspection.bundle.fields, id: \.key) { field in
                    LabeledContent(field.key) {
                        // "—" for a source that has not been read: an age can only be shown for data
                        // that was actually loaded.
                        Text(field.lastRefreshed.map { model.relativeText($0) } ?? "—")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .accessibilityIdentifier(MissionControlA11yID.homeFreshness)

            Section("Controls") {
                Toggle("Pause all operator activity", isOn: $model.isPaused)
                    .accessibilityIdentifier(MissionControlA11yID.pauseToggle)
                if model.isPaused {
                    Label(model.pauseReason ?? "Paused — new governed work will not start.", systemImage: "pause.circle")
                        .foregroundStyle(.orange)
                    Button("Resume operator activity") { Task { await model.resumeOperator() } }
                        .accessibilityIdentifier(MissionControlA11yID.resumeButton)
                }
            }

            Section("Revoke capabilities") {
                if model.activeLeases.isEmpty && model.activeRestrictions.isEmpty {
                    Label("No active capability grants or restrictions to revoke.", systemImage: "key.slash")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(model.activeLeases) { lease in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(lease.capability.rawValue)
                                Text("expires \(model.relativeText(lease.expiresAt))")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button("Revoke", role: .destructive) {
                                Task { await model.revokeLease(id: lease.id) }
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                    ForEach(model.activeRestrictions) { restriction in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(restriction.kind.displayTitle)
                                Text(restriction.reason)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button("Revoke", role: .destructive) {
                                Task { await model.revokeRestriction(id: restriction.id) }
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                }
            }
            .accessibilityIdentifier(MissionControlA11yID.homeRevoke)

            Section("Live activity") {
                if model.liveEvents.isEmpty {
                    Text("No activity yet.")
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier(MissionControlA11yID.activityFeedEmpty)
                } else {
                    ForEach(model.liveEvents) { envelope in
                        eventRow(envelope)
                    }
                }
            }

            Section("Recent receipts") {
                if model.recentReceipts.isEmpty {
                    Text("No receipts yet.")
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier(MissionControlA11yID.receiptsBrowserEmpty)
                } else {
                    ForEach(model.recentReceipts) { receipt in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(receipt.summary)
                            Text("\(receipt.scope) • \(receipt.isSuccess ? "ok" : "denied")")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        .accessibilityElement(children: .combine)
                    }
                }
            }
        }
        .task { await model.refreshLeases() }
    }

    /// Not-yet-loaded reads as neutral, not as a warning — there is nothing for the operator to act
    /// on while the console is still hydrating.
    private static func tint(for freshness: MissionControlHomeModel.ContextFreshnessState) -> Color {
        switch freshness {
        case .fresh: return .green
        case .notLoadedYet: return .secondary
        case .needsAttention: return .orange
        }
    }

    @ViewBuilder
    private func eventRow(_ envelope: WorkflowEventEnvelope) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(MissionControlEventText.describe(envelope.event))
            Text(envelope.timestamp, style: .time)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }
}
