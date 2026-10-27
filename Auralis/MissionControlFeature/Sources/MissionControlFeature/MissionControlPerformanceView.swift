import AuralisRuntime
import SwiftUI

/// P1-604 — Performance Dashboard: per-playbook health + recent execution records. Descriptive only;
/// no authority ever escalates from these numbers (P1-603).
struct MissionControlPerformanceView: View {
    @Bindable var model: MissionControlHomeModel

    var body: some View {
        List {
            Section("Playbook health") {
                if model.performanceHealth.isEmpty {
                    Text("No runs recorded yet. Run a routine to populate health metrics.")
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier(MissionControlA11yID.performanceEmpty)
                } else {
                    ForEach(model.performanceHealth, id: \.playbookID) { health in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(health.playbookID)
                            Label(classificationLabel(health.classification), systemImage: classificationIcon(health.classification))
                                .font(.caption)
                                .foregroundStyle(classificationStyle(health.classification))
                            Text("\(health.totalRuns) runs • \(percent(health.successRate)) success • \(seconds(health.averageLatencySeconds)) avg")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            Text(approvalSummary(health))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            Text("intervention \(percent(health.interventionRate)) • policy blocked \(percent(health.policyBlockRate)) • all blocked \(percent(health.blockRate)) • failures \(health.failureCount)")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            failurePatterns(health.failurePatterns)
                        }
                        .accessibilityElement(children: .combine)
                        .accessibilityIdentifier(MissionControlA11yID.performanceHealthRow(health.playbookID))
                    }
                }
            }

            Section("Recent runs") {
                if model.recentExecutions.isEmpty {
                    Text("No runs yet.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(model.recentExecutions) { record in
                        runRow(record, receiptA11yID: MissionControlA11yID.performanceRunReceiptLink)
                    }
                }
            }

            Section("Failure and block history") {
                if model.unsuccessfulExecutions.isEmpty {
                    Text("No failures or blocks recorded.")
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier(MissionControlA11yID.performanceFailuresEmpty)
                } else {
                    ForEach(model.unsuccessfulExecutions) { record in
                        runRow(record, receiptA11yID: MissionControlA11yID.performanceFailureReceiptLink)
                    }
                }
            }
        }
        .task { await model.loadPerformance() }
        .accessibilityIdentifier(MissionControlA11yID.performance)
    }

    /// One execution row. When the run wrote a receipt it becomes a deep link into the full receipt
    /// detail (P1-604 "Dashboard links to receipts and failure history"); otherwise it's plain text.
    @ViewBuilder
    private func runRow(_ record: ExecutionRecord, receiptA11yID: String) -> some View {
        if let receipt = model.receipt(forExecution: record) {
            NavigationLink {
                MissionControlReceiptDetailView(receipt: receipt, model: model)
            } label: {
                runLabel(record)
            }
            .accessibilityIdentifier(receiptA11yID)
        } else {
            runLabel(record)
        }
    }

    @ViewBuilder
    private func runLabel(_ record: ExecutionRecord) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("\(record.playbookID) — \(record.outcome.rawValue)")
            Text("\(record.triggerSource.rawValue) • \(record.startedAt, style: .time)")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }

    /// Recurring-failure signatures under a playbook's health row. Recurring ones (seen more than once)
    /// are flagged so a persistently flaky reason stands out from a one-off. (P1-603 failure patterns)
    @ViewBuilder
    private func failurePatterns(_ patterns: [FailurePattern]) -> some View {
        ForEach(patterns) { pattern in
            Text("↳ \(pattern.occurrences)× \(pattern.key)\(pattern.isRecurring ? " (recurring)" : "")")
                .font(.caption2)
                .foregroundStyle(pattern.isRecurring ? .red : .secondary)
                .accessibilityIdentifier(MissionControlA11yID.performanceFailurePattern)
        }
    }

    private func percent(_ value: Double) -> String {
        "\(Int((value * 100).rounded()))%"
    }

    private func seconds(_ value: Double) -> String {
        String(format: "%.2fs", value)
    }

    private func approvalSummary(_ health: PlaybookHealth) -> String {
        guard health.resolvedApprovalCount > 0 else { return "approval — no resolved decisions" }
        return "approval \(percent(health.approvalRate)) of \(health.resolvedApprovalCount) resolved"
    }

    private func classificationLabel(_ classification: PlaybookHealthClassification) -> String {
        switch classification {
        case .insufficientData: "Not enough data"
        case .stable: "Stable"
        case .needsAttention: "Needs attention"
        case .flaky: "Flaky"
        }
    }

    private func classificationIcon(_ classification: PlaybookHealthClassification) -> String {
        switch classification {
        case .insufficientData: "questionmark.circle"
        case .stable: "checkmark.circle.fill"
        case .needsAttention: "exclamationmark.triangle.fill"
        case .flaky: "xmark.octagon.fill"
        }
    }

    private func classificationStyle(_ classification: PlaybookHealthClassification) -> Color {
        switch classification {
        case .insufficientData: .secondary
        case .stable: .green
        case .needsAttention: .orange
        case .flaky: .red
        }
    }
}
