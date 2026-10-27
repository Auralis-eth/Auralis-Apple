import AuralisFoundation
import Foundation
@_spi(RuntimeComposition) @_spi(RuntimeTesting) @_spi(ToolRegistration) @testable import RuntimeCore
import Testing

private struct AllowingHookJudge: Judge {
    func judge(
        _ proposal: ActionProposal,
        checkResults: [DeterministicCheckResult]
    ) async -> JudgeDecision {
        checkResults.allPassed ? .allow : .block(reason: "check failed")
    }
}

private struct HookTestExecutor: ToolExecuting {
    let artifactToolID: String

    func execute(
        _ tool: ToolDefinition,
        proposal: ActionProposal,
        authorization: ToolExecutionAuthorization
    ) async throws -> ToolCallArtifact {
        ToolCallArtifact(toolID: artifactToolID, summary: "done")
    }
}

private actor HookRecorder: AfterToolCallHook {
    private var contexts: [AfterToolCallContext] = []

    func emit(_ context: AfterToolCallContext) -> EvidenceEmissionReport {
        contexts.append(context)
        return EvidenceEmissionReport()
    }

    func recordedContexts() -> [AfterToolCallContext] {
        contexts
    }
}

private struct HookReceiptError: Error, LocalizedError {
    var errorDescription: String? { "receipt unavailable" }
}

private struct FailingHookReceiptEmitter: ReceiptEmitting {
    func emit(_ receipt: GovernedReceipt) async throws {
        throw HookReceiptError()
    }
}

private actor ReportingHook: AfterToolCallHook {
    private let failure: String
    private var invocationCount = 0

    init(failure: String) {
        self.failure = failure
    }

    func emit(_ context: AfterToolCallContext) -> EvidenceEmissionReport {
        invocationCount += 1
        return EvidenceEmissionReport(failures: [failure])
    }

    func count() -> Int {
        invocationCount
    }
}

@Suite("Tool hook contracts")
struct ToolHookContractTests {
    private let tool = ToolDefinition(
        id: "test.read",
        title: "Read",
        capability: .audioPlayback,
        impact: .readOnly
    )

    private var proposal: ActionProposal {
        ActionProposal(
            actor: .system,
            intent: "Read",
            capability: .audioPlayback,
            impact: .readOnly,
            correlationID: "hook-test"
        )
    }

    @Test
    func conflictingRegistrationDoesNotReplaceExistingDefinition() async {
        let registry = ToolRegistry()
        #expect(await registry.register(tool) == .registered)
        #expect(await registry.register(tool) == .alreadyRegistered)

        let conflicting = ToolDefinition(
            id: tool.id,
            title: "Write",
            capability: .audioPlayback,
            impact: .reversibleWrite
        )
        let result = await registry.register(conflicting)
        #expect(result == .conflict(existing: tool))
        #expect(await registry.tool(id: tool.id) == tool)
    }

    @Test
    func registryRejectsMalformedDefinitions() async {
        let registry = ToolRegistry()
        let malformed = ToolDefinition(
            id: "",
            title: "Malformed",
            capability: .audioPlayback,
            impact: .readOnly,
            inputSchema: ToolSchema(fields: [
                ToolSchemaField(name: "value", kind: .string),
                ToolSchemaField(name: "value", kind: .string)
            ]),
            requiredCheckIDs: ["same", "same"]
        )

        guard case let .invalid(problems) = await registry.register(malformed) else {
            Issue.record("Expected malformed definition to be rejected")
            return
        }
        #expect(problems.contains("tool ID must not be empty"))
        #expect(problems.contains("input schema field names must be unique"))
        #expect(await registry.allTools.isEmpty)
    }

    @Test
    func strictSchemaRejectsUnexpectedFieldsAndNonPrefixedAddresses() {
        let schema = ToolSchema(
            fields: [ToolSchemaField(name: "address", kind: .address)],
            allowsAdditionalFields: false
        )

        let problems = schema.validationProblems(against: [
            "address": "0000000000000000000000000000000000000000",
            "surprise": "value"
        ])

        #expect(problems.contains { $0.contains("0x-prefixed") })
        #expect(problems.contains("unexpected field “surprise”"))
    }

    @Test
    func schemaAllowsOnlyExplicitDynamicPrefixes() {
        let schema = ToolSchema(
            fields: [ToolSchemaField(name: "payload.pluginID", kind: .string)],
            allowsAdditionalFields: false,
            allowedAdditionalFieldPrefixes: ["payload.plugin."]
        )

        #expect(schema.validationProblems(against: [
            "payload.pluginID": "calendar",
            "payload.plugin.query": "today"
        ]).isEmpty)
        #expect(schema.validationProblems(against: [
            "payload.pluginID": "calendar",
            "unscoped": "today"
        ]).contains("unexpected field “unscoped”"))
    }

    @Test
    func afterHookReceivesSuccessfulArtifactLink() async {
        let registry = ToolRegistry()
        await registry.register(tool)
        let recorder = HookRecorder()
        let pipeline = GovernedToolPipeline.testing(
            registry: registry,
            checks: DeterministicCheckRegistry(),
            judge: AllowingHookJudge(),
            executor: HookTestExecutor(artifactToolID: tool.id),
            eventBus: RuntimeEventBus(),
            worklog: InMemoryWorklog(),
            receiptSink: InMemoryReceiptEmitter(),
            performanceSink: InMemoryPerformanceSignalEmitter(),
            afterToolCallHooks: [recorder]
        )

        let outcome = await pipeline.run(toolID: tool.id, proposal: proposal)
        guard case let .executed(artifact) = outcome else {
            Issue.record("Expected successful execution")
            return
        }
        let contexts = await recorder.recordedContexts()
        #expect(contexts.count == 1)
        #expect(contexts.first?.artifactID == artifact.id)
    }

    @Test
    func mismatchedArtifactIdentityFailsClosedAndNotifiesAfterHook() async {
        let registry = ToolRegistry()
        await registry.register(tool)
        let recorder = HookRecorder()
        let pipeline = GovernedToolPipeline.testing(
            registry: registry,
            checks: DeterministicCheckRegistry(),
            judge: AllowingHookJudge(),
            executor: HookTestExecutor(artifactToolID: "different.tool"),
            eventBus: RuntimeEventBus(),
            worklog: InMemoryWorklog(),
            receiptSink: InMemoryReceiptEmitter(),
            performanceSink: InMemoryPerformanceSignalEmitter(),
            afterToolCallHooks: [recorder]
        )

        let outcome = await pipeline.run(toolID: tool.id, proposal: proposal)
        guard case .failed = outcome else {
            Issue.record("Expected mismatched artifact identity to fail")
            return
        }
        #expect(await recorder.recordedContexts().count == 1)
    }

    @Test
    func receiptFailureStillRecordsPerformanceAndInvokesEveryObserver() async {
        let receiptRequiredTool = ToolDefinition(
            id: "test.write",
            title: "Write",
            capability: .audioPlayback,
            impact: .reversibleWrite,
            requiresReceipt: true
        )
        let writeProposal = ActionProposal(
            actor: .system,
            intent: "Write",
            capability: .audioPlayback,
            impact: .reversibleWrite,
            correlationID: "hook-failure-test"
        )
        let registry = ToolRegistry()
        await registry.register(receiptRequiredTool)
        let performance = InMemoryPerformanceSignalEmitter()
        let firstObserver = ReportingHook(failure: "first observer failed")
        let secondObserver = ReportingHook(failure: "second observer failed")
        let pipeline = GovernedToolPipeline.testing(
            registry: registry,
            checks: DeterministicCheckRegistry(),
            judge: AllowingHookJudge(),
            executor: HookTestExecutor(artifactToolID: receiptRequiredTool.id),
            eventBus: RuntimeEventBus(),
            worklog: InMemoryWorklog(),
            receiptSink: FailingHookReceiptEmitter(),
            performanceSink: performance,
            afterToolCallHooks: [firstObserver, secondObserver]
        )

        let outcome = await pipeline.run(toolID: receiptRequiredTool.id, proposal: writeProposal)

        guard case let .evidenceIncomplete(original, failures) = outcome else {
            Issue.record("Expected accumulated evidence failure")
            return
        }
        guard case .executed = original else {
            Issue.record("Expected the execution result to be preserved")
            return
        }
        #expect(failures.contains { $0.contains("receipt unavailable") })
        #expect(failures.contains("first observer failed"))
        #expect(failures.contains("second observer failed"))
        #expect(await performance.allSignals().count == 1)
        #expect(await firstObserver.count() == 1)
        #expect(await secondObserver.count() == 1)
    }
}
