import AuralisReceipts
import AuralisFoundation
import AuralisRuntime
import SwiftUI

/// P1-502 / P1-504 — Playbook Library with user drafts, editing, install/pause/resume, and the
/// authority envelope shown before enabling.
struct MissionControlPlaybooksView: View {
    @Bindable var model: MissionControlHomeModel
    @State private var editorDraft: PlaybookEditorDraft?

    var body: some View {
        List {
            Section("Create") {
                Button {
                    editorDraft = .newUserDraft()
                } label: {
                    Label("New User Playbook", systemImage: "plus")
                }
                .accessibilityIdentifier(MissionControlA11yID.playbookCreate)
            }

            ForEach(PlaybookInstallState.allCases, id: \.self) { state in
                let playbooks = model.playbooks(inState: state)
                if !playbooks.isEmpty {
                    Section(title(for: state)) {
                        ForEach(playbooks) { playbook in
                            NavigationLink {
                                MissionControlPlaybookDetailView(playbook: playbook, model: model)
                            } label: {
                                MissionControlPlaybookRow(playbook: playbook)
                            }
                        }
                    }
                }
            }
        }
        .task { await model.loadPlaybooks() }
        .sheet(item: $editorDraft) { draft in
            MissionControlPlaybookEditorSheet(draft: draft, model: model)
        }
        .accessibilityIdentifier(MissionControlA11yID.playbooks)
    }

    private func title(for state: PlaybookInstallState) -> String {
        switch state {
        case .installed: return "Installed"
        case .available: return "Available"
        case .paused: return "Paused"
        case .draft: return "Drafts"
        }
    }
}

private struct MissionControlPlaybookRow: View {
    let playbook: Playbook

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(playbook.name)
                Spacer()
                Text(playbook.source.rawValue.capitalized)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            Text(playbook.summary)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(2)
            Text("\(playbook.trigger.classification) • \(playbook.supportedFlows.map(\.rawValue).joined(separator: ", "))")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }
}

/// P1-504 — Install/Configure: shows the authority envelope, outputs, required approvals, and v0 flow
/// policy before enabling.
struct MissionControlPlaybookDetailView: View {
    /// The value this view was constructed with — a fallback only. Read ``playbook`` instead.
    private let snapshot: Playbook
    let model: MissionControlHomeModel
    @State private var editorDraft: PlaybookEditorDraft?
    @State private var reviewPlaybook: Playbook?

    init(playbook: Playbook, model: MissionControlHomeModel) {
        snapshot = playbook
        self.model = model
    }

    /// The live playbook, not the value this view was constructed with. Pause/Resume/Enable all mutate
    /// the store and reload `model.playbooks`; rendering the construction-time snapshot left the button
    /// still reading "Pause" and the Paused banner absent until the operator navigated back.
    private var playbook: Playbook {
        model.playbook(id: snapshot.id) ?? snapshot
    }

    var body: some View {
        List {
            Section("About") {
                Text(playbook.summary)
                LabeledContent("Source", value: playbook.source.rawValue.capitalized)
                LabeledContent("Trigger", value: playbook.trigger.classification)
                LabeledContent("Completes when", value: playbook.completionCondition)
            }

            Section("Allowed v0 flows") {
                ForEach(playbook.supportedFlows, id: \.self) { flow in
                    Label(flow.rawValue.capitalized, systemImage: flow.isV0Allowed ? "checkmark.seal" : "xmark.octagon")
                        .foregroundStyle(flow.isV0Allowed ? .green : .red)
                }
                if !playbook.supportsV0ReadPrepareOnly {
                    Text("This playbook cannot be enabled in v0 because execute flows are outside the read/prepare boundary.")
                        .font(.footnote)
                        .foregroundStyle(.red)
                }
            }

            Section("Authority envelope") {
                if playbook.authority.touchesCrypto {
                    Label("Touches crypto — wallet steps stay read-only and escalate.", systemImage: "lock.shield")
                        .foregroundStyle(.orange)
                }
                LabeledContent("Capabilities", value: joined(playbook.authority.capabilities.map(\.rawValue)))
                LabeledContent("Outputs", value: joined(playbook.authority.allowedOutputs.map(\.rawValue)))
                LabeledContent("Approval threshold", value: "\(playbook.authority.approvalThreshold)")
                LabeledContent("Required approvals", value: joined(playbook.authority.requiredApprovals))
            }

            Section("Receipts & escalation") {
                LabeledContent("Receipt format", value: playbook.receiptFormat)
                LabeledContent("Failure path", value: playbook.failureEscalationPath)
            }

            if playbook.installState == .paused {
                Section("Paused") {
                    Label("This playbook is paused — its routine will not run until resumed.", systemImage: "pause.circle")
                        .foregroundStyle(.orange)
                }
            }

            Section {
                actionButtons
            }
        }
        .navigationTitle(playbook.name)
        .sheet(item: $editorDraft) { draft in
            MissionControlPlaybookEditorSheet(draft: draft, model: model)
        }
        .sheet(item: $reviewPlaybook) { playbook in
            MissionControlPlaybookEnableReviewView(playbook: playbook, model: model)
        }
        .accessibilityIdentifier(MissionControlA11yID.playbookDetail)
    }

    @ViewBuilder
    private var actionButtons: some View {
        switch playbook.installState {
        case .available, .draft:
            Button("Review & Enable") {
                reviewPlaybook = playbook
            }
            .buttonStyle(.borderedProminent)
            .disabled(!playbook.supportsV0ReadPrepareOnly)
            if playbook.source == .user {
                Button("Edit") {
                    editorDraft = .editing(playbook)
                }
            }
        case .installed:
            Button("Pause") {
                Task { await model.setPlaybookState(id: playbook.id, to: .paused) }
            }
            if playbook.source == .user {
                Button("Edit") {
                    editorDraft = .editing(playbook)
                }
            }
        case .paused:
            Button("Resume") {
                Task { await model.setPlaybookState(id: playbook.id, to: .installed) }
            }
            .buttonStyle(.borderedProminent)
            if playbook.source == .user {
                Button("Edit") {
                    editorDraft = .editing(playbook)
                }
            }
        }
    }

    private func joined(_ values: [String]) -> String {
        values.isEmpty ? "None" : values.joined(separator: ", ")
    }
}

private struct MissionControlPlaybookEnableReviewView: View {
    let playbook: Playbook
    let model: MissionControlHomeModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section("Scope") {
                    Text(playbook.summary)
                    LabeledContent("Trigger", value: playbook.trigger.classification)
                    LabeledContent("Flows", value: playbook.supportedFlows.map(\.rawValue).joined(separator: ", "))
                    LabeledContent("Completion", value: playbook.completionCondition)
                }

                Section("Outputs") {
                    ForEach(playbook.authority.allowedOutputs, id: \.self) { output in
                        Text(output.rawValue)
                    }
                }

                Section("Required approvals") {
                    if playbook.authority.requiredApprovals.isEmpty {
                        Text("No named approvals required before routine output is prepared.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(playbook.authority.requiredApprovals, id: \.self) { approval in
                            Label(approval, systemImage: "checkmark.seal")
                        }
                    }
                    LabeledContent("Threshold", value: "\(playbook.authority.approvalThreshold)")
                }

                Section("Authority envelope") {
                    LabeledContent("Capabilities", value: playbook.authority.capabilities.map(\.rawValue).joined(separator: ", "))
                    LabeledContent("Failure path", value: playbook.failureEscalationPath)
                    if playbook.authority.touchesCrypto {
                        Label("Crypto actions stay read/prepare and escalate for approval.", systemImage: "lock.shield")
                            .foregroundStyle(.orange)
                    }
                }

                Section {
                    Button("Enable Playbook") {
                        Task {
                            await model.installPlaybook(id: playbook.id)
                            dismiss()
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!playbook.supportsV0ReadPrepareOnly)
                }
            }
            .navigationTitle("Review Setup")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}

private struct MissionControlPlaybookEditorSheet: View {
    @State private var draft: PlaybookEditorDraft
    private let trustedDraftID: UUID
    let model: MissionControlHomeModel
    @Environment(\.dismiss) private var dismiss

    init(draft: PlaybookEditorDraft, model: MissionControlHomeModel) {
        _draft = State(initialValue: draft)
        trustedDraftID = UUID()
        self.model = model
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Identity") {
                    TextField("Name", text: $draft.name)
                    TrustedUISurface(
                        request: .editDraft(proposalID: trustedDraftID),
                        registry: draftRegistry,
                        onDraftCommit: { id, body in
                            guard id == trustedDraftID else { return }
                            draft.summary = body
                        }
                    )
                    TextField("Completion condition", text: $draft.completionCondition, axis: .vertical)
                        .lineLimit(2...4)
                }

                Section("Trigger") {
                    Picker("Trigger type", selection: $draft.triggerKind) {
                        ForEach(PlaybookEditorDraft.TriggerKind.allCases) { kind in
                            Text(kind.title).tag(kind)
                        }
                    }
                    if draft.triggerKind.requiresInterval {
                        Stepper("Every \(draft.intervalDays) day(s)", value: $draft.intervalDays, in: 1...30)
                    }
                    if draft.triggerKind == .event {
                        Picker("Event", selection: $draft.eventKind) {
                            ForEach(RoutineEventKind.allCases, id: \.self) { event in
                                Text(event.rawValue).tag(event)
                            }
                        }
                    }
                }

                Section("V0 flows") {
                    Toggle("Read", isOn: binding(for: .read, in: $draft.supportedFlows))
                    Toggle("Prepare", isOn: binding(for: .prepare, in: $draft.supportedFlows))
                    Text("Execute flows are intentionally unavailable for playbooks v0.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section("Capabilities") {
                    ForEach(CapabilityID.allCases, id: \.self) { capability in
                        Toggle(capability.rawValue, isOn: binding(for: capability, in: $draft.capabilities))
                    }
                }

                Section("Allowed outputs") {
                    ForEach(ArtifactType.allCases, id: \.self) { output in
                        Toggle(output.rawValue, isOn: binding(for: output, in: $draft.allowedOutputs))
                    }
                }

                Section("Approvals and receipts") {
                    Stepper("Approval threshold: \(draft.approvalThreshold)", value: $draft.approvalThreshold, in: 0...10)
                    TextField("Required approvals, comma-separated", text: $draft.requiredApprovalsText, axis: .vertical)
                        .lineLimit(1...3)
                    TextField("Receipt format", text: $draft.receiptFormat)
                    TextField("Failure or escalation path", text: $draft.failureEscalationPath)
                }
            }
            .navigationTitle(draft.isEditing ? "Edit Playbook" : "New Playbook")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(draft.isEditing ? "Save" : "Save Draft") {
                        save(state: draft.installState)
                    }
                    .disabled(!draft.isValid)
                }
            }
            .safeAreaInset(edge: .bottom) {
                Button("Save & Review") {
                    save(state: .available)
                }
                .buttonStyle(.borderedProminent)
                .disabled(!draft.isValid)
                .padding()
                .frame(maxWidth: .infinity)
                .background(.bar)
            }
        }
    }

    private var draftRegistry: TrustedUIComponentRegistry {
        let id = trustedDraftID
        let summary = TrustedUIDraftSummary(
            id: id,
            title: "Work removed from your plate",
            body: draft.summary
        )
        return TrustedUIComponentRegistry(draftResolver: { requestedID in
            requestedID == id ? summary : nil
        })
    }

    private func save(state: PlaybookInstallState) {
        Task {
            await model.saveUserPlaybook(draft.makePlaybook(installState: state))
            dismiss()
        }
    }

    private func binding<T: Hashable>(for value: T, in values: Binding<Set<T>>) -> Binding<Bool> {
        Binding(
            get: { values.wrappedValue.contains(value) },
            set: { isSelected in
                if isSelected {
                    values.wrappedValue.insert(value)
                } else {
                    values.wrappedValue.remove(value)
                }
            }
        )
    }
}

private struct PlaybookEditorDraft: Identifiable {
    enum TriggerKind: String, CaseIterable, Identifiable {
        case manual
        case schedule
        case event
        case maintenance

        var id: String { rawValue }
        var title: String { rawValue.capitalized }
        var requiresInterval: Bool { self == .schedule || self == .maintenance }
    }

    let id: String
    let originalID: String?
    var name: String
    var summary: String
    var triggerKind: TriggerKind
    var eventKind: RoutineEventKind
    var intervalDays: Int
    var capabilities: Set<CapabilityID>
    var allowedOutputs: Set<ArtifactType>
    var supportedFlows: Set<PlaybookFlowKind>
    var approvalThreshold: Int
    var requiredApprovalsText: String
    var completionCondition: String
    var receiptFormat: String
    var failureEscalationPath: String
    var installState: PlaybookInstallState
    var contextContract: ContextBundleContract?

    var isEditing: Bool { originalID != nil }

    var isValid: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !completionCondition.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !capabilities.isEmpty &&
        !allowedOutputs.isEmpty &&
        !supportedFlows.isEmpty
    }

    static func newUserDraft() -> PlaybookEditorDraft {
        PlaybookEditorDraft(
            id: UUID().uuidString,
            originalID: nil,
            name: "",
            summary: "",
            triggerKind: .manual,
            eventKind: .artifactStale,
            intervalDays: 1,
            capabilities: [.runPlugin],
            allowedOutputs: [.brief],
            supportedFlows: [.read, .prepare],
            approvalThreshold: 0,
            requiredApprovalsText: "",
            completionCondition: "A reviewable artifact is prepared.",
            receiptFormat: "standard",
            failureEscalationPath: "approval-inbox",
            installState: .draft,
            contextContract: nil
        )
    }

    static func editing(_ playbook: Playbook) -> PlaybookEditorDraft {
        PlaybookEditorDraft(
            id: playbook.id,
            originalID: playbook.id,
            name: playbook.name,
            summary: playbook.summary,
            triggerKind: TriggerKind(playbook.trigger),
            eventKind: playbook.trigger.eventKind ?? .artifactStale,
            intervalDays: playbook.trigger.intervalDays ?? 1,
            capabilities: Set(playbook.authority.capabilities),
            allowedOutputs: Set(playbook.authority.allowedOutputs),
            supportedFlows: Set(playbook.supportedFlows.filter(\.isV0Allowed)),
            approvalThreshold: playbook.authority.approvalThreshold,
            requiredApprovalsText: playbook.authority.requiredApprovals.joined(separator: ", "),
            completionCondition: playbook.completionCondition,
            receiptFormat: playbook.receiptFormat,
            failureEscalationPath: playbook.failureEscalationPath,
            installState: playbook.installState,
            contextContract: playbook.contextContract
        )
    }

    func makePlaybook(installState: PlaybookInstallState) -> Playbook {
        let playbookID = originalID ?? "user.\(Self.slug(for: name)).\(id.prefix(8))"
        return Playbook(
            id: playbookID,
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            summary: summary.trimmingCharacters(in: .whitespacesAndNewlines),
            trigger: trigger,
            authority: PlaybookAuthority(
                capabilities: sorted(capabilities),
                allowedOutputs: sorted(allowedOutputs),
                approvalThreshold: approvalThreshold,
                requiredApprovals: requiredApprovals
            ),
            completionCondition: completionCondition.trimmingCharacters(in: .whitespacesAndNewlines),
            receiptFormat: receiptFormat.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty ?? "standard",
            failureEscalationPath: failureEscalationPath.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty ?? "approval-inbox",
            supportedFlows: sorted(supportedFlows).filter(\.isV0Allowed),
            source: .user,
            contextContract: contextContract ?? Self.defaultContextContract(for: playbookID),
            installState: installState
        )
    }

    private static func defaultContextContract(for playbookID: String) -> ContextBundleContract {
        ContextBundleContract(
            identifier: "user.playbook.\(playbookID)",
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

    private var trigger: PlaybookTrigger {
        switch triggerKind {
        case .manual:
            return .manual
        case .schedule:
            return .schedule(intervalSeconds: TimeInterval(intervalDays * 24 * 60 * 60))
        case .event:
            return .event(eventKind)
        case .maintenance:
            return .maintenance(intervalSeconds: TimeInterval(intervalDays * 24 * 60 * 60))
        }
    }

    private var requiredApprovals: [String] {
        requiredApprovalsText
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private func sorted<T: RawRepresentable & Hashable>(_ values: Set<T>) -> [T] where T.RawValue == String {
        values.sorted { $0.rawValue < $1.rawValue }
    }

    private static func slug(for name: String) -> String {
        let allowed = Set("abcdefghijklmnopqrstuvwxyz0123456789-")
        let slug = name
            .lowercased()
            .replacingOccurrences(of: " ", with: "-")
            .filter { allowed.contains($0) }
        return slug.isEmpty ? "playbook" : slug
    }
}

private extension PlaybookTrigger {
    var eventKind: RoutineEventKind? {
        if case let .event(kind) = self { return kind }
        return nil
    }

    var intervalDays: Int? {
        let seconds: Double
        switch self {
        case let .schedule(intervalSeconds), let .maintenance(intervalSeconds):
            seconds = intervalSeconds
        case .manual, .event:
            return nil
        }
        return max(1, Int((seconds / 86_400).rounded()))
    }
}

private extension PlaybookEditorDraft.TriggerKind {
    init(_ trigger: PlaybookTrigger) {
        switch trigger {
        case .manual:
            self = .manual
        case .schedule:
            self = .schedule
        case .event:
            self = .event
        case .maintenance:
            self = .maintenance
        }
    }
}

private extension String {
    var nonEmpty: String? {
        isEmpty ? nil : self
    }
}

/// P1-503 — Routine Manager v0: installed routines with run-now, pause/resume, and classification.
struct MissionControlRoutinesView: View {
    @Bindable var model: MissionControlHomeModel

    var body: some View {
        List {
            if model.routines.isEmpty {
                Text("No active routines. Install a playbook to see it here.")
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier(MissionControlA11yID.routinesEmpty)
            } else {
                ForEach(model.routines) { routine in
                    VStack(alignment: .leading, spacing: 4) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(routine.name)
                            Text("\(routine.trigger.classification) • \(routine.installState == .paused ? "paused" : "active")")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            if routine.installState == .paused {
                                Text("Paused — will not run until resumed.")
                                    .font(.caption2)
                                    .foregroundStyle(.orange)
                            }
                            Text(model.lastRunText(for: routine))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            Text(model.nextRunText(for: routine))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        .accessibilityElement(children: .combine)
                        HStack {
                            Button("Run now") { Task { await model.runRoutine(id: routine.id) } }
                                .buttonStyle(.borderedProminent)
                                .disabled(routine.installState == .paused || model.isPaused)
                            if routine.installState == .paused {
                                Button("Resume") { Task { await model.setPlaybookState(id: routine.id, to: .installed) } }
                                    .buttonStyle(.bordered)
                            } else {
                                Button("Pause") { Task { await model.setPlaybookState(id: routine.id, to: .paused) } }
                                    .buttonStyle(.bordered)
                            }
                        }
                        .font(.caption)
                    }
                }
            }
        }
        .task {
            await model.loadPlaybooks()
            await model.loadPerformance()
        }
        .accessibilityIdentifier(MissionControlA11yID.routines)
    }
}
