import AuralisReceipts
import OperatorsFeature
import AuralisRuntime
import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

/// P1-701..703 — Operators: run bounded operators through the governed pipeline. Non-crypto ones
/// execute and produce an artifact; the crypto operator is blocked in Observe (visible denial).
struct MissionControlOperatorsView: View {
    @Bindable var model: MissionControlHomeModel

    var body: some View {
        List {
            Section("Inputs") {
                TextField("Research query", text: $model.operatorQueryInput)
                    .accessibilityIdentifier("mc.operators.queryInput")
                Picker("Watch network", selection: $model.operatorWatchChainInput) {
                    Text("Ethereum").tag("eth-mainnet")
                    Text("Base").tag("base-mainnet")
                    Text("Arbitrum").tag("arb-mainnet")
                    Text("Optimism").tag("opt-mainnet")
                    Text("Polygon").tag("polygon-mainnet")
                }
                HStack {
                    TextField("Watch address (0x…)", text: $model.operatorWatchAddressInput)
#if os(iOS)
                        .textInputAutocapitalization(.never)
#endif
                        .autocorrectionDisabled()
                        .accessibilityIdentifier(MissionControlA11yID.operatorWatchInput)
                    Button("Add") { model.addOperatorWatchTarget() }
                        .disabled(model.operatorWatchAddressInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        .accessibilityIdentifier(MissionControlA11yID.operatorWatchAdd)
                }
                if model.operatorWatchlist.isEmpty {
                    Text("No saved watch targets.")
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier(MissionControlA11yID.operatorWatchlistEmpty)
                } else {
                    ForEach(model.operatorWatchlist) { target in
                        LabeledContent(target.displayName, value: target.chain)
                            .accessibilityElement(children: .combine)
                    }
                    .onDelete(perform: model.removeOperatorWatchTargets)
                }
                LabeledContent("Identity to review", value: model.activeIdentityID ?? "No active identity")
                    .accessibilityIdentifier(MissionControlA11yID.operatorIdentityScope)
                // Not "Research and identity review use your local receipt ledger." That is true only
                // because this screen happens never to give those kinds a watchlist:
                // `LiveOnChainOperatorDataSource` branches on the *watchlist*, not the operator kind,
                // so any operator carrying one reaches the network. The same overclaim was removed
                // from the composed artifacts themselves this round; leaving it on the screen that
                // launches them would have put the contradiction back one layer out.
                Text("Operators read from the local receipt ledger and may add bounded, read-only network snapshots for any account you are watching. No operator can sign or submit a transaction.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            if model.operatorTools.isEmpty {
                Text("No operators registered.")
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier(MissionControlA11yID.operatorsEmpty)
            } else {
                ForEach(model.operatorTools) { tool in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(tool.title)
                        Text("\(tool.capability.rawValue) • \(tool.impact.rawValue)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        if let outcome = model.operatorOutcomes[tool.id] {
                            Text(outcome)
                                .font(.caption2)
                                .foregroundStyle(outcome.hasPrefix("Executed") ? .green : .orange)
                                .accessibilityIdentifier(MissionControlA11yID.operatorOutcome(tool.id))
                        }
                        Button("Run") { Task { await model.runOperator(toolID: tool.id) } }
                            .buttonStyle(.borderedProminent)
                            .font(.caption)
                            .disabled(model.isPaused || !model.canRunOperator(toolID: tool.id))
                            .accessibilityIdentifier(MissionControlA11yID.operatorRun(tool.id))
                        if tool.id == OperatorCatalog.onChainWatchID {
                            Button("Escalate prepared action") {
                                Task { await model.escalateFirstWatchFinding() }
                            }
                            .font(.caption)
                            .disabled(model.isPaused || !model.canRunOperator(toolID: tool.id))
                            .accessibilityIdentifier(MissionControlA11yID.operatorEscalate)
                        }
                        NavigationLink {
                            MissionControlToolProposalPreviewView(tool: tool, model: model)
                        } label: {
                            Text("Inspect proposal")
                                .font(.caption)
                        }
                    }
                }
            }
        }
        .task { await model.loadOperators() }
        .accessibilityIdentifier(MissionControlA11yID.operators)
    }
}

struct MissionControlToolProposalPreviewView: View {
    let tool: ToolDefinition
    let model: MissionControlHomeModel

    private var proposal: ActionProposal {
        ActionProposal(
            actor: ActorRef(kind: .operatorAgent, identifier: tool.id),
            intent: tool.title,
            capability: tool.capability,
            impact: tool.impact,
            requiredCheckIDs: tool.requiredCheckIDs,
            correlationID: "preview-\(tool.id)"
        )
    }

    var body: some View {
        List {
            Section("Tool") {
                LabeledContent("ID", value: tool.id)
                LabeledContent("Capability", value: tool.capability.rawValue)
                LabeledContent("Impact", value: tool.impact.rawValue)
                LabeledContent("Receipt", value: tool.requiresReceipt ? "Required" : "Optional")
            }

            Section("Proposal diff") {
                ForEach(model.proposalDiffRows(for: proposal)) { row in
                    MissionControlDiffRow(row: row)
                }
            }

            Section("Schemas") {
                LabeledContent("Inputs", value: schemaDescription(tool.inputSchema))
                LabeledContent("Outputs", value: schemaDescription(tool.outputSchema))
            }
        }
        .navigationTitle("Proposal Preview")
    }

    private func schemaDescription(_ schema: ToolSchema) -> String {
        guard !schema.fields.isEmpty else { return "No declared fields" }
        return schema.fields.map { field in
            "\(field.name): \(field.kind.rawValue)\(field.isRequired ? "" : "?")"
        }
        .joined(separator: ", ")
    }
}

/// P1-402/403 — Artifact Browser + detail. First-class work products produced by operators/routines.
struct MissionControlArtifactsView: View {
    @Bindable var model: MissionControlHomeModel

    var body: some View {
        List {
            Section {
                Picker("Type", selection: $model.artifactTypeFilter) {
                    Text("All types").tag(ArtifactType?.none)
                    ForEach(ArtifactType.allCases, id: \.self) { type in
                        Text(type.rawValue).tag(ArtifactType?.some(type))
                    }
                }
                .accessibilityIdentifier(MissionControlA11yID.artifactsTypeFilter)

                Picker("Recency", selection: $model.artifactRecencyFilter) {
                    ForEach(MissionControlHomeModel.ArtifactRecencyFilter.allCases) { filter in
                        Text(filter.rawValue).tag(filter)
                    }
                }
                .accessibilityIdentifier(MissionControlA11yID.artifactsRecencyFilter)

                Picker("Workflow", selection: $model.artifactWorkflowFilter) {
                    Text("All workflows").tag(String?.none)
                    ForEach(model.artifactWorkflows, id: \.self) { workflow in
                        Text(workflow).tag(String?.some(workflow))
                    }
                }
                .accessibilityIdentifier(MissionControlA11yID.artifactsWorkflowFilter)

                Picker("Account", selection: $model.artifactAccountFilter) {
                    Text("All accounts").tag(String?.none)
                    ForEach(model.artifactAccounts, id: \.self) { account in
                        Text(account).tag(String?.some(account))
                    }
                }
                .accessibilityIdentifier(MissionControlA11yID.artifactsAccountFilter)

                Text(model.artifactBrowserLoadedFullHistory ? "Full artifact history loaded" : "Showing latest artifact window")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier(MissionControlA11yID.artifactsHistoryScope)
            }

            if !model.artifactBrowserPlaybooks.isEmpty {
                Section("Playbook objects") {
                    ForEach(model.artifactBrowserPlaybooks) { playbook in
                        NavigationLink {
                            MissionControlPlaybookDetailView(playbook: playbook, model: model)
                        } label: {
                            playbookObjectRow(playbook)
                        }
                        .accessibilityIdentifier(MissionControlA11yID.artifactPlaybookObject(playbook.id))
                    }
                }
                .accessibilityIdentifier(MissionControlA11yID.artifactsPlaybookObjects)
            }

            if model.artifacts.isEmpty {
                Text("No artifacts yet. Run an operator or routine to produce one.")
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier(MissionControlA11yID.artifactsEmpty)
            } else if model.filteredArtifacts.isEmpty {
                Text("No artifacts match these filters.")
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier(MissionControlA11yID.artifactsEmpty)
            } else {
                ForEach(model.filteredArtifacts) { artifact in
                    NavigationLink {
                        MissionControlArtifactDetailView(artifact: artifact, model: model)
                    } label: {
                        let presentation = model.cardPresentation(for: artifact)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(presentation.title)
                            Text(presentation.metadata)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            Text(presentation.provenance)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            Text(presentation.status)
                                .font(.caption2.weight(.semibold))
                        }
                        .accessibilityElement(children: .combine)
                    }
                    .accessibilityIdentifier(MissionControlA11yID.artifactRow(artifact.id.uuidString))
                }
            }
        }
        .task {
            await model.loadPlaybooks()
            await model.loadArtifacts()
            await model.loadBrowserReceipts()
            // Complete history just loaded — resolve approvals against it instead of exporting and
            // decoding the whole receipt store again.
            await model.loadRuntimeHistory(reusingLoadedReceiptHistory: true)
        }
        .accessibilityIdentifier(MissionControlA11yID.artifacts)
    }

    private func playbookObjectRow(_ playbook: Playbook) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(playbook.name)
            Text("playbook • \(playbook.installState.rawValue) • \(playbook.trigger.classification)")
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(playbook.summary)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
        .accessibilityElement(children: .combine)
    }
}

struct MissionControlArtifactDetailView: View {
    let artifact: Artifact
    let model: MissionControlHomeModel
    @State private var sharePayload: MissionControlArtifactExportFile?
    @State private var lifecycleError: MissionControlArtifactLifecycleErrorAlert?

    var body: some View {
        let currentArtifact = model.artifact(id: artifact.id) ?? artifact
        List {
            Section("Artifact") {
                LabeledContent("Type", value: currentArtifact.type.rawValue)
                LabeledContent("Version", value: "\(currentArtifact.version)")
                LabeledContent("State", value: currentArtifact.approvalState.rawValue)
                LabeledContent("Created", value: currentArtifact.createdAt.formatted())
                LabeledContent("Destination", value: currentArtifact.destination ?? "Not exported")
                LabeledContent("Export format", value: model.exportFormatLabel(for: currentArtifact))
            }
            Section("Provenance") {
                LabeledContent("Actor", value: ReceiptAttributionDisplay.actorLabel(for: currentArtifact.provenance.actor))
                LabeledContent("Creator", value: model.artifactCreatorLabel(for: currentArtifact))
                LabeledContent("Workflow", value: model.artifactWorkflowLabel(for: currentArtifact))
                LabeledContent("Account", value: model.artifactAccountLabel(for: currentArtifact))
                if let operatorID = currentArtifact.creatorOperatorID {
                    LabeledContent("Operator", value: operatorID)
                }
                if let playbook = model.playbook(for: currentArtifact) {
                    NavigationLink {
                        MissionControlPlaybookDetailView(playbook: playbook, model: model)
                    } label: {
                        LabeledContent("Playbook", value: playbook.name)
                    }
                } else if let playbookID = currentArtifact.creatorPlaybookID {
                    LabeledContent("Playbook", value: playbookID)
                }
                if let inference = currentArtifact.provenance.inference {
                    LabeledContent("Inference", value: inference.locality.rawValue)
                    LabeledContent("Provider", value: inference.provider ?? "unknown")
                    LabeledContent("Model class", value: inference.modelClass ?? "unknown")
                    LabeledContent("Privacy impact", value: inference.privacyImpact)
                }
            }
            let sourceWorkflows = model.artifactSourceCorrelationIDs(for: currentArtifact)
            if !sourceWorkflows.isEmpty {
                Section("Source workflow") {
                    ForEach(sourceWorkflows, id: \.self) { correlationID in
                        NavigationLink {
                            MissionControlAgentSessionDetailView(
                                summary: model.agentSessionSummary(id: correlationID),
                                correlationID: correlationID,
                                model: model
                            )
                        } label: {
                            LabeledContent("Correlation", value: correlationID)
                        }
                    }
                }
            }
            Section("Content") {
                Text(currentArtifact.content)
            }

            Section("Lifecycle") {
                if currentArtifact.approvalState == .draft {
                    Button("Approve artifact") {
                        approveArtifact(currentArtifact)
                    }
                    .accessibilityIdentifier(MissionControlA11yID.artifactApprove)
                }
                if currentArtifact.approvalState != .superseded {
                    Button("Mark superseded") {
                        markArtifactSuperseded(currentArtifact)
                    }
                    .accessibilityIdentifier(MissionControlA11yID.artifactSupersede)
                }
            }

            Section("Export") {
                Button("Export with provenance") {
                    exportArtifact(currentArtifact)
                }
                .accessibilityIdentifier(MissionControlA11yID.artifactExport)

                Text(model.exportPreview(for: currentArtifact))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(8)
                    .textSelection(.enabled)
            }

            let approvalReceipts = model.approvalReceipts(for: currentArtifact)
            if !approvalReceipts.isEmpty {
                Section("Related approvals") {
                    ForEach(approvalReceipts) { receipt in
                        NavigationLink {
                            MissionControlReceiptDetailView(receipt: receipt, model: model)
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(receipt.summary)
                                Text(receipt.createdAt, style: .time)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            .accessibilityElement(children: .combine)
                        }
                    }
                }
            }

            Section("Version history") {
                let versions = model.versions(for: currentArtifact)
                if versions.isEmpty {
                    Text("No version history loaded.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(versions) { version in
                        VStack(alignment: .leading, spacing: 2) {
                            Text("v\(version.version) • \(version.approvalState.rawValue)")
                            Text(version.createdAt, style: .date)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        .accessibilityElement(children: .combine)
                    }
                }
            }

            let comparisonRows = model.comparisonRows(for: model.versions(for: currentArtifact))
            if !comparisonRows.isEmpty {
                Section("Compare latest") {
                    ForEach(comparisonRows) { row in
                        MissionControlDiffRow(row: row)
                    }
                }
            }

            let relatedReceipts = model.receipts(for: currentArtifact)
            if !relatedReceipts.isEmpty {
                Section("Related receipts") {
                    ForEach(relatedReceipts) { receipt in
                        NavigationLink {
                            MissionControlReceiptDetailView(receipt: receipt, model: model)
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(receipt.summary)
                                Text(receipt.createdAt, style: .time)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle(currentArtifact.title)
        .task {
            await model.loadArtifacts()
            await model.loadArtifactVersions(for: currentArtifact)
            await model.loadBrowserReceipts()
            await model.loadRuntimeHistory(reusingLoadedReceiptHistory: true)
            await model.loadPlaybooks()
            model.prepareExportPreview(for: currentArtifact)
        }
        .sheet(item: $sharePayload) { payload in
            MissionControlArtifactShareView(payload: payload) {
                recordCompletedExport(for: payload.artifact)
            }
        }
        .alert("Artifact update failed", item: $lifecycleError) { _ in
            Button("OK", role: .cancel) { }
        } message: { error in
            Text(error.message)
        }
        .accessibilityIdentifier(MissionControlA11yID.artifactDetail)
    }

    private func approveArtifact(_ artifact: Artifact) {
        Task { @MainActor in
            do {
                _ = try await model.approveArtifact(artifact)
            } catch {
                lifecycleError = .init(message: "Auralis could not persist the approval receipt. \(error.localizedDescription)")
            }
        }
    }

    private func markArtifactSuperseded(_ artifact: Artifact) {
        Task { @MainActor in
            do {
                _ = try await model.markArtifactSuperseded(artifact)
            } catch {
                lifecycleError = .init(message: "Auralis could not persist the supersede receipt. \(error.localizedDescription)")
            }
        }
    }

    private func exportArtifact(_ artifact: Artifact) {
        do {
            sharePayload = try model.exportFile(for: artifact)
        } catch {
            lifecycleError = .init(message: "Auralis could not prepare the export file. \(error.localizedDescription)")
        }
    }

    private func recordCompletedExport(for artifact: Artifact) {
        Task { @MainActor in
            do {
                _ = try await model.markArtifactExported(artifact, destination: "Share sheet")
            } catch {
                lifecycleError = .init(message: "Auralis could not persist the export receipt. \(error.localizedDescription)")
            }
        }
    }
}

private struct MissionControlArtifactLifecycleErrorAlert: Identifiable {
    let id = UUID()
    let message: String
}

private struct MissionControlArtifactShareView: View {
    let payload: MissionControlArtifactExportFile
    let onCompleted: () -> Void

    var body: some View {
        #if canImport(UIKit)
        MissionControlArtifactActivityView(payload: payload, onCompleted: onCompleted)
        #else
        NavigationStack {
            List {
                Section("Ready to share") {
                    ShareLink("Share exported artifact", item: payload.url)
                    Button("Mark export complete") {
                        onCompleted()
                    }
                    LabeledContent("File", value: payload.filename)
                    LabeledContent("Format", value: payload.exportFormat)
                    Text(payload.preview)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(8)
                        .textSelection(.enabled)
                }
            }
            .navigationTitle(payload.title)
        }
        #endif
    }
}

#if canImport(UIKit)
private struct MissionControlArtifactActivityView: UIViewControllerRepresentable {
    let payload: MissionControlArtifactExportFile
    let onCompleted: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onCompleted: onCompleted)
    }

    func makeUIViewController(context: Context) -> UIActivityViewController {
        // The subject is supplied through `UIActivityItemSource`, the documented mechanism. The
        // previous `setValue(_:forKey: "subject")` reached into an undeclared UIKit property by KVC:
        // there is no public `subject` on `UIActivityViewController`, so the call was private-API
        // access that would raise `NSUnknownKeyException` the moment that ivar changed.
        let controller = UIActivityViewController(
            activityItems: [ArtifactExportActivityItem(url: payload.url, subject: payload.title)],
            applicationActivities: nil
        )
        controller.completionWithItemsHandler = { _, completed, _, activityError in
            guard completed, activityError == nil else { return }
            Task { @MainActor in
                context.coordinator.onCompleted()
            }
        }
        return controller
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) { }

    final class Coordinator {
        let onCompleted: () -> Void

        init(onCompleted: @escaping () -> Void) {
            self.onCompleted = onCompleted
        }
    }
}

/// Supplies the exported artifact file plus a subject line for activities that have one (Mail, and
/// anything else with a separate subject field).
private final class ArtifactExportActivityItem: NSObject, UIActivityItemSource {
    private let url: URL
    private let subject: String

    init(url: URL, subject: String) {
        self.url = url
        self.subject = subject
    }

    func activityViewControllerPlaceholderItem(_ activityViewController: UIActivityViewController) -> Any {
        url
    }

    func activityViewController(
        _ activityViewController: UIActivityViewController,
        itemForActivityType activityType: UIActivity.ActivityType?
    ) -> Any? {
        url
    }

    func activityViewController(
        _ activityViewController: UIActivityViewController,
        subjectForActivityType activityType: UIActivity.ActivityType?
    ) -> String {
        subject
    }
}
#endif
