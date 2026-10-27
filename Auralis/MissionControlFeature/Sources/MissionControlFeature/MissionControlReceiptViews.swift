import AuralisPrimaryModels
import ReceiptsCore
import AuralisRuntime
import SwiftUI
import TrustedUIKit

/// P1-301 — Receipt Browser v1: searchable, scope-filterable list over the durable receipt store,
/// each row opening a full ``MissionControlReceiptDetailView``.
struct MissionControlReceiptsView: View {
    @Bindable var model: MissionControlHomeModel

    var body: some View {
        // Both are derivations over the whole receipt store, so read each exactly once per body pass:
        // `filteredReceipts` builds a presentation per receipt, and `trustedUIRegistry` indexes every
        // receipt. Re-reading them per row (or per `isEmpty` check) made the browser quadratic.
        let receipts = model.filteredReceipts
        let registry = model.trustedUIRegistry
        return List {
            Section {
                Picker("Scope", selection: $model.receiptScopeFilter) {
                    Text("All scopes").tag(String?.none)
                    ForEach(model.receiptScopes, id: \.self) { scope in
                        Text(scope).tag(String?.some(scope))
                    }
                }
                .accessibilityIdentifier(MissionControlA11yID.receiptsScopeFilter)

                Picker("Outcome", selection: $model.receiptOutcomeFilter) {
                    ForEach(MissionControlHomeModel.ReceiptOutcomeFilter.allCases) { filter in
                        Text(filter.rawValue).tag(filter)
                    }
                }
                .accessibilityIdentifier(MissionControlA11yID.receiptsOutcomeFilter)
            }

            Section("Receipts") {
                if receipts.isEmpty {
                    Text("No receipts match.")
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier(MissionControlA11yID.receiptsBrowserEmpty)
                } else {
                    ForEach(receipts) { receipt in
                        NavigationLink {
                            MissionControlReceiptDetailView(receipt: receipt, model: model)
                        } label: {
                            row(receipt, registry: registry)
                        }
                    }
                }
            }
        }
        .searchable(text: $model.receiptSearchText, prompt: "Search receipts")
        .task { await model.loadBrowserReceipts() }
        .accessibilityIdentifier(MissionControlA11yID.receiptsBrowser)
    }

    @ViewBuilder
    private func row(_ receipt: ReceiptRecord, registry: TrustedUIComponentRegistry) -> some View {
        TrustedUISurface(
            request: .reviewReceipt(receiptID: receipt.id),
            registry: registry
        )
    }
}

/// P1-302 / P1-303 — Receipt Detail with a postflight change summary, integrity, payload, and the
/// correlated event timeline.
struct MissionControlReceiptDetailView: View {
    let receipt: ReceiptRecord
    let model: MissionControlHomeModel

    var body: some View {
        let presentation = model.presentation(for: receipt)
        List {
            Section {
                TrustedUISurface(
                    request: .reviewReceipt(receiptID: receipt.id),
                    registry: model.trustedUIRegistry
                )
            }

            Section("Summary") {
                Text(receipt.summary)
                LabeledContent("Outcome", value: presentation.outcome.rawValue)
                LabeledContent("Result", value: receipt.isSuccess ? "Success" : "Denied")
            }

            Section("Attribution") {
                LabeledContent("Scope", value: receipt.scope)
                LabeledContent("Trigger", value: receipt.trigger)
                // Structured attribution (P0.5-601/602): who acted, under what authority, through
                // what workflow. Falls back to the coarse actor for pre-column receipts.
                LabeledContent("Actor", value: ReceiptAttributionDisplay.actorLabel(for: receipt))
                if let inference = ReceiptAttributionDisplay.inferenceLabel(for: receipt) {
                    LabeledContent("Inference", value: inference)
                }
                if let authority = ReceiptAttributionDisplay.authorityLabel(for: receipt) {
                    LabeledContent("Authority", value: authority)
                }
                if let reason = ReceiptAttributionDisplay.authorityReason(for: receipt) {
                    LabeledContent("Authority reason", value: reason)
                }
                LabeledContent("Mode", value: receipt.mode.rawValue)
                LabeledContent("Provenance", value: receipt.provenance)
                LabeledContent("Recorded", value: receipt.createdAt.formatted())
                if let correlationID = receipt.correlationID {
                    LabeledContent("Correlation", value: correlationID)
                }
            }

            Section("Integrity") {
                LabeledContent("Sequence", value: "\(receipt.sequenceID)")
                integrityRow("Payload hash", receipt.payloadHash)
                integrityRow("Chain hash", receipt.chainHash)
            }

            if !receipt.details.values.isEmpty {
                Section("Details") {
                    ForEach(presentation.sections) { section in
                        VStack(alignment: .leading, spacing: 8) {
                            Text(section.title)
                                .font(.headline)
                            ForEach(section.rows) { row in
                                detailRow(row)
                            }
                        }
                        .accessibilityElement(children: .contain)
                    }
                }
            }

            Section("What changed") {
                ForEach(presentation.changeRows) { row in
                    detailRow(row)
                }
            }

            let artifactIDs = model.artifactIDs(from: receipt)
            if !artifactIDs.isEmpty {
                Section("Related artifacts") {
                    ForEach(artifactIDs, id: \.self) { artifactID in
                        if let artifact = model.artifact(id: artifactID) {
                            NavigationLink {
                                MissionControlArtifactDetailView(artifact: artifact, model: model)
                            } label: {
                                Text(artifact.title)
                            }
                            .accessibilityIdentifier(MissionControlA11yID.receiptArtifactLink)
                        } else {
                            LabeledContent("Artifact ID", value: artifactID.uuidString)
                                .accessibilityIdentifier(MissionControlA11yID.receiptArtifactID)
                        }
                    }
                }
            }

            let events = model.events(forReceipt: receipt)
            if !events.isEmpty {
                Section("Timeline") {
                    ForEach(events) { envelope in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(MissionControlEventText.describe(envelope.event))
                            Text(envelope.timestamp, style: .time)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        .accessibilityElement(children: .combine)
                    }
                }
            }
        }
        .navigationTitle("Receipt")
        .task { await model.loadArtifacts() }
        .accessibilityIdentifier(MissionControlA11yID.receiptDetail)
    }

    @ViewBuilder
    private func integrityRow(_ label: String, _ hash: String) -> some View {
        LabeledContent(label, value: hash.isEmpty ? "—" : String(hash.prefix(12)) + "…")
            .font(.caption)
            .monospaced()
    }

    @ViewBuilder
    private func detailRow(_ row: MissionControlHomeModel.ReceiptDetailRow) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(row.label)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(row.value)
                .font(.subheadline)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }
}
