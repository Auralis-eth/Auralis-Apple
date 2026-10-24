import EvalCore
import PerformanceCore
import SwiftUI

/// P2-EVAL — Operator report cards: each operator's run health joined with how its graded runs did
/// against the criteria its playbook declared.
///
/// Descriptive only. Nothing here escalates or removes authority; the same guardrail the performance
/// dashboard carries (P1-603) applies unchanged to grades.
struct MissionControlReportCardView: View {
    @Bindable var model: MissionControlHomeModel

    var body: some View {
        List {
            if model.reportCards.isEmpty {
                Section {
                    Text("No operator history yet. Run a routine to populate report cards.")
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier(MissionControlA11yID.reportCardsEmpty)
                }
            } else {
                ForEach(model.reportCards) { card in
                    Section(card.playbookID) {
                        gradeSummary(card)
                        healthSummary(card)
                        shortfalls(card)
                        traceSummary(card)
                        recommendations(card)
                    }
                }
            }
        }
        .task { await model.loadReportCards() }
        .accessibilityIdentifier(MissionControlA11yID.reportCards)
    }

    private func traceSummary(_ card: OperatorReportCard) -> some View {
        Text("Trace evidence: \(card.incompleteTraceCount) incomplete runs • \(card.unknownTraceEventCount) unknown events")
            .font(.caption2)
            .foregroundStyle(card.incompleteTraceCount > 0 ? .orange : .secondary)
            .accessibilityIdentifier(MissionControlA11yID.reportCardTraceHealth)
    }

    /// Recommendations still worth a person's attention for this operator.
    ///
    /// Superseded rows are excluded. The store keeps them deliberately — a review decision must
    /// survive the evidence that prompted it — but a new graded run retires the previous
    /// recommendation and proposes a fresh one, so rendering every row meant the card accumulated
    /// a permanent, growing wall of "Superseded" entries with no action attached to any of them.
    @ViewBuilder
    private func recommendations(_ card: OperatorReportCard) -> some View {
        ForEach(model.improvementRecommendations.filter {
            $0.operatorID == card.playbookID && $0.state != .superseded
        }) { recommendation in
            VStack(alignment: .leading, spacing: 8) {
                Text(recommendation.summary)
                    .font(.caption)
                Text("\(recommendation.state.rawValue.capitalized) • \(percent(recommendation.confidence)) confidence")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                if recommendation.state == .proposed {
                    HStack {
                        Button("Accept") {
                            Task { await model.reviewRecommendation(recommendation, accept: true) }
                        }
                        .buttonStyle(.borderedProminent)
                        Button("Reject") {
                            Task { await model.reviewRecommendation(recommendation, accept: false) }
                        }
                        .buttonStyle(.bordered)
                    }
                } else if recommendation.state == .accepted {
                    Button("Mark Applied") {
                        Task { await model.markRecommendationApplied(recommendation) }
                    }
                    .buttonStyle(.bordered)
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier(MissionControlA11yID.improvementRecommendation)
        }
    }

    /// The eval line. Kept visually distinct from run health below because the two answer different
    /// questions: health is "did it run", grades are "did it do what it was supposed to".
    @ViewBuilder
    private func gradeSummary(_ card: OperatorReportCard) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            if let passRate = card.passRate {
                Text("\(percent(passRate)) of graded runs passed")
            } else if card.gradedRunCount == 0 {
                // Not a failure state: the playbook simply declares no criteria, so there is nothing
                // to grade. Saying "0%" here would read as a broken operator.
                Text("Not graded — no success criteria declared")
                    .foregroundStyle(.secondary)
            } else {
                Text("No graded run reached a verdict")
                    .foregroundStyle(.secondary)
            }

            if card.gradedRunCount > 0 {
                Text(gradeDetail(card))
                    .font(.caption2)
                    .foregroundStyle(card.inconclusiveRunCount > 0 ? .orange : .secondary)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier(MissionControlA11yID.reportCard)
    }

    /// Surfaces the inconclusive count in words rather than leaving it implied by a missing
    /// percentage — an operator whose traces are unreadable is a distinct problem from one that fails,
    /// and it needs a different fix (logging, not the operator).
    private func gradeDetail(_ card: OperatorReportCard) -> String {
        let graded = "\(card.gradedRunCount) graded"
        guard card.inconclusiveRunCount > 0 else { return graded }
        return "\(graded) • \(card.inconclusiveRunCount) inconclusive (trace could not decide)"
    }

    @ViewBuilder
    private func healthSummary(_ card: OperatorReportCard) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("\(card.health.totalRuns) runs • \(percent(card.health.successRate)) success • \(seconds(card.health.averageLatencySeconds)) avg")
                .font(.caption2)
                .foregroundStyle(.secondary)
            ForEach(card.recurringFailures) { pattern in
                Text("↳ \(pattern.occurrences)× \(pattern.key) (recurring)")
                    .font(.caption2)
                    .foregroundStyle(.red)
            }
        }
        .accessibilityElement(children: .combine)
    }

    /// The expectations this operator misses most — the line that makes a card actionable rather than
    /// just a score.
    @ViewBuilder
    private func shortfalls(_ card: OperatorReportCard) -> some View {
        ForEach(card.shortfalls) { shortfall in
            VStack(alignment: .leading, spacing: 2) {
                Text(shortfall.criterion.displayTitle)
                    .font(.caption)
                Text(shortfallDetail(shortfall))
                    .font(.caption2)
                    .foregroundStyle(shortfall.missCount > 0 ? .red : .orange)
            }
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier(MissionControlA11yID.reportCardShortfall)
        }
    }

    /// Misses and inconclusives are reported separately, never summed: one says the operator fell
    /// short, the other says we could not tell.
    private func shortfallDetail(_ shortfall: CriterionShortfall) -> String {
        var parts: [String] = []
        if shortfall.missCount > 0 { parts.append("missed \(shortfall.missCount)×") }
        if shortfall.inconclusiveCount > 0 {
            parts.append("unverifiable \(shortfall.inconclusiveCount)×")
        }
        return parts.joined(separator: " • ")
    }

    private func percent(_ value: Double) -> String {
        "\(Int((value * 100).rounded()))%"
    }

    private func seconds(_ value: Double) -> String {
        String(format: "%.2fs", value)
    }
}
