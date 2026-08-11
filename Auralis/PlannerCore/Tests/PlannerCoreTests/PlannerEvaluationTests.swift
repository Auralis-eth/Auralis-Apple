import CapabilitiesCore
import Testing
@testable import PlannerCore

#if canImport(Evaluations) && canImport(FoundationModels)
import Evaluations
import FoundationModels

/// Scores how well the planner selects the right capabilities for a goal.
///
/// The subject runs the real FoundationModels-backed ``ModelGoalPlanner`` when the device
/// model is available, and falls back to ``DeterministicGoalPlanner`` otherwise — so the
/// same suite grades the shipping instruction strings on device and still runs (against
/// the template baseline) in CI and the simulator, where the model is unavailable.
///
/// `CapabilityCoverage` is the fraction of a sample's expected capabilities that the
/// produced plan actually includes.
@available(iOS 27.0, macOS 27.0, *)
struct PlannerCapabilitySelectionEvaluation: Evaluation {
    let capabilityCoverage = Metric("CapabilityCoverage")

    let dataset = ArrayLoader(samples: [
        ModelSample(
            prompt: "organize my music library",
            expected: ["music_library_classification", "auto_organization"]
        ),
        ModelSample(
            prompt: "make me a playlist of my chill tracks",
            expected: ["playlist_management"]
        ),
        ModelSample(
            prompt: "export my whole library so I can back it up",
            expected: ["music_export"]
        ),
        ModelSample(
            prompt: "tip this artist some ETH",
            expected: ["draft_transaction"]
        ),
    ])

    func subject(from sample: ModelSample<[String]>) async throws -> ModelSubject<[String]> {
        let planner = Self.planner()
        let plan = await planner.makePlan(for: PlanningGoal(text: String(describing: sample.prompt)))
        return ModelSubject(value: plan.capabilities.map(\.rawValue))
    }

    var evaluators: Evaluators {
        Evaluator { sample, subject in
            guard let expected = sample.expected, !expected.isEmpty else {
                return capabilityCoverage.ignore()
            }
            let expectedIDs = Set(expected)
            let returnedIDs = Set(subject.value)
            let coverage = Double(expectedIDs.intersection(returnedIDs).count) / Double(expectedIDs.count)
            return capabilityCoverage.scoring(coverage)
        }
    }

    func aggregateMetrics(using aggregator: inout MetricsAggregator) {
        aggregator.computeMean(of: capabilityCoverage)
    }

    /// The real model planner when the device supports it, else the deterministic baseline.
    private static func planner() -> any GoalPlanning {
        if case .available = SystemLanguageModel.default.availability {
            return ModelGoalPlanner()
        }
        return DeterministicGoalPlanner()
    }
}

struct PlannerEvaluationTests {
    @Test("planner capability selection meets the coverage baseline")
    func coverageMeetsBaseline() async throws {
        guard #available(iOS 27.0, macOS 27.0, *) else { return }

        let evaluation = PlannerCapabilitySelectionEvaluation()
        let result = try await evaluation.run(info: ["dataset": "planner-capability-seed-v1"])
        let coverageMean = result.aggregateValue(.mean(of: evaluation.capabilityCoverage))
        #expect(coverageMean >= 0.75, "Capability coverage should be at least 75% across seed goals")
    }
}
#endif
