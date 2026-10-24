import Foundation
@testable import RuntimeCore
import Testing

@Suite("Worklog health and validation")
struct WorklogHealthTests {
    @Test("invalid execution durations are rejected and degrade health", arguments: [
        Double.nan,
        Double.infinity,
        -0.001
    ])
    func invalidDurationIsRejected(duration: Double) async {
        let worklog = InMemoryWorklog()
        let result = await worklog.record(WorkflowStepLog(
            correlationID: "invalid-duration",
            toolID: "tool",
            event: .executed(artifactID: UUID(), durationSeconds: duration),
            actor: .system
        ))

        #expect(result.failure?.operation == .encode)
        #expect(await worklog.allSteps().isEmpty)
        let health = await worklog.health()
        #expect(health.isDegraded)
        #expect(health.failedOperationCount == 1)
    }

    @Test("a successful retry clears degraded health")
    func successfulRetryClearsHealth() async {
        let worklog = InMemoryWorklog()
        _ = await worklog.record(WorkflowStepLog(
            correlationID: "retry",
            toolID: "tool",
            event: .executed(artifactID: UUID(), durationSeconds: .nan),
            actor: .system
        ))

        let result = await worklog.record(WorkflowStepLog(
            correlationID: "retry",
            toolID: "tool",
            event: .executed(artifactID: UUID(), durationSeconds: 0.25),
            actor: .system
        ))

        #expect(result == .recorded)
        #expect(await worklog.health().isDegraded == false)
        #expect(await worklog.allSteps().count == 1)
    }
}
