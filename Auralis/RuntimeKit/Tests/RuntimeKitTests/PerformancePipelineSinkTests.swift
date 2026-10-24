import PerformanceCore
import RuntimeCore
import Testing

@testable import RuntimeKit

@Suite("Performance pipeline sink")
struct PerformancePipelineSinkTests {
    @Test
    func mapsOnlyPolicyBlocksIntoPolicyBlockRate() async {
        let store = PerformanceStore()
        let sink = PerformancePipelineSink(store: store)

        await sink.record(PerformanceSignal(
            toolID: "policy.tool",
            capability: .runPlugin,
            outcome: .blocked,
            durationSeconds: 0.1,
            blockSource: .policy
        ))
        await sink.record(PerformanceSignal(
            toolID: "other.tool",
            capability: .runPlugin,
            outcome: .blocked,
            durationSeconds: 0.1,
            blockSource: .other
        ))

        #expect(await store.health(forPlaybook: "policy.tool").policyBlockRate == 1)
        #expect(await store.health(forPlaybook: "other.tool").policyBlockRate == 0)
    }
}
