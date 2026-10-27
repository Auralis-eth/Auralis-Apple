import AuralisRuntime
import RuntimeKit
import SwiftUI

/// The user-facing trigger for an autopilot goal run (P1-AGENT-101).
///
/// A natural-language "ask" surface: the user states a goal, Auralis plans it on device and runs the
/// steps it is cleared to run, pausing at the first step that needs approval. The plan and per-step
/// outcome are shown inline; the planner's reasoning (considered/rejected) and the real token/model
/// telemetry land on the shared worklog + receipts, so they appear in the Agent Activity Timeline.
///
/// Reusable on purpose: Mission Control embeds it as its "Run a Goal" section, and the app presents
/// the same view as a standalone "Ask Auralis" screen — both driving the one governed entry point,
/// ``RuntimeHost/runAutopilotGoal(_:surface:correlationID:)``.
public struct MissionControlRunGoalView: View {
    private let host: RuntimeHost
    private let surface: String
    private let onCompleted: (@MainActor () async -> Void)?

    @State private var goalText: String = ""
    @State private var isRunning = false
    @State private var planSummary: String?
    @State private var stepRows: [StepRow] = []
    @State private var resultBanner: ResultBanner?
    @FocusState private var isEditorFocused: Bool

    public init(
        host: RuntimeHost,
        surface: String = "mission-control.run-goal",
        onCompleted: (@MainActor () async -> Void)? = nil
    ) {
        self.host = host
        self.surface = surface
        self.onCompleted = onCompleted
    }

    public var body: some View {
        Form {
            Section {
                TextField("What should Auralis do?", text: $goalText, axis: .vertical)
                    .lineLimit(1...4)
                    .focused($isEditorFocused)
                    .disabled(isRunning)
                    .accessibilityIdentifier("missionControl.runGoal.field")

                Button {
                    Task { await run() }
                } label: {
                    HStack(spacing: 8) {
                        if isRunning { ProgressView() }
                        Text(isRunning ? "Running…" : "Run on Autopilot")
                    }
                }
                .disabled(trimmedGoal.isEmpty || isRunning || host.isPaused)
                .accessibilityIdentifier("missionControl.runGoal.run")
            } header: {
                Text("Run a Goal")
            } footer: {
                // The kill switch is stated up front rather than left to the refusal banner. The host
                // refuses a paused run regardless (see `RuntimeHost.runAutopilotGoal`), so this is
                // about telling a person *before* they compose a goal instead of after.
                if host.isPaused {
                    Text(host.pauseReason ?? "Operator activity is paused.")
                        .accessibilityIdentifier("missionControl.runGoal.pausedNotice")
                } else {
                    Text("Auralis plans your goal on device and runs the safe steps. Anything that changes state pauses for your approval. The reasoning and token usage show up in the Timeline.")
                }
            }

            if let resultBanner {
                Section { resultBannerView(resultBanner) }
            }

            if let planSummary {
                Section("Plan") {
                    Text(planSummary).font(.callout)
                    ForEach(stepRows) { row in
                        stepRowView(row)
                    }
                }
            }
        }
        .navigationTitle("Run a Goal")
    }

    private var trimmedGoal: String {
        goalText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    @MainActor
    private func run() async {
        let goal = trimmedGoal
        // `host.isPaused` as well as the button's `disabled`, because the two can disagree: the flag
        // is observable state that can flip between the tap and this running, and this view is also
        // presented standalone as "Ask Auralis".
        guard !goal.isEmpty, !isRunning, !host.isPaused else { return }
        isRunning = true
        isEditorFocused = false
        defer { isRunning = false }

        // Idempotent — makes sure operators are registered before a step might route to one.
        await host.bootstrap()
        let outcome = await host.runAutopilotGoal(goal, surface: surface)
        planSummary = outcome.plan.summary
        stepRows = Self.makeRows(result: outcome.result)
        resultBanner = Self.makeBanner(from: outcome.result)
        // Refresh the timeline/receipts so the fresh deliberation + telemetry are visible immediately.
        await onCompleted?()
    }

    @ViewBuilder
    private func resultBannerView(_ banner: ResultBanner) -> some View {
        Label {
            Text(banner.text)
        } icon: {
            Image(systemName: banner.systemImage)
                .foregroundStyle(banner.tint)
        }
        .font(.callout)
    }

    @ViewBuilder
    private func stepRowView(_ row: StepRow) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: row.status.systemImage)
                .foregroundStyle(row.status.tint)
                .accessibilityLabel(row.status.label)
            VStack(alignment: .leading, spacing: 2) {
                Text(row.title).font(.callout.weight(.medium))
                Text("\(row.kind) · \(row.status.label)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Mapping (kept free of SwiftUI so it is trivially testable)

    struct StepRow: Identifiable {
        let id: UUID
        let title: String
        let kind: String
        let status: StepStatus
    }

    enum StepStatus {
        case ran, pausedForConfirmation, blocked, skipped, failed

        var label: String {
            switch self {
            case .ran: return "Ran"
            case .pausedForConfirmation: return "Needs your approval"
            case .blocked: return "Blocked"
            case .skipped: return "Skipped"
            case .failed: return "Failed"
            }
        }

        var systemImage: String {
            switch self {
            case .ran: return "checkmark.circle.fill"
            case .pausedForConfirmation: return "hand.raised.circle.fill"
            case .blocked: return "nosign"
            case .skipped: return "minus.circle"
            case .failed: return "xmark.octagon.fill"
            }
        }

        var tint: Color {
            switch self {
            case .ran: return .green
            case .pausedForConfirmation: return .orange
            case .blocked, .failed: return .red
            case .skipped: return .secondary
            }
        }
    }

    struct ResultBanner {
        let text: String
        let systemImage: String
        let tint: Color
    }

    /// Rows come from the *result*, not the plan: every planned step has a report, and the report
    /// carries the step it ran plus its outcome. Taking the plan as well invited the two to disagree.
    static func makeRows(result: OrchestrationResult) -> [StepRow] {
        result.reports.map { report in
            StepRow(
                id: report.step.id,
                title: report.step.title,
                kind: report.step.kind.rawValue.capitalized,
                status: status(from: report.status)
            )
        }
    }

    static func status(from status: StepReport.Status) -> StepStatus {
        switch status {
        case .ran: return .ran
        case .pausedForConfirmation: return .pausedForConfirmation
        case .blocked: return .blocked
        case .skipped: return .skipped
        case .failed: return .failed
        }
    }

    static func makeBanner(from result: OrchestrationResult) -> ResultBanner {
        if let pending = result.pendingConfirmation {
            return ResultBanner(
                text: "Paused for your approval: “\(pending.title)”. Review it in Approvals.",
                systemImage: "hand.raised.circle.fill",
                tint: .orange
            )
        }
        if result.isComplete {
            return ResultBanner(text: "All steps ran on autopilot.", systemImage: "checkmark.seal.fill", tint: .green)
        }
        if result.reports.contains(where: { if case .failed = $0.status { return true } else { return false } }) {
            return ResultBanner(text: "A step failed — see the run below.", systemImage: "xmark.octagon.fill", tint: .red)
        }
        if result.reports.contains(where: { $0.status == .blocked }) {
            return ResultBanner(text: "A step was blocked in this mode.", systemImage: "nosign", tint: .red)
        }
        return ResultBanner(text: "Ran the cleared steps.", systemImage: "checkmark.circle", tint: .green)
    }
}
