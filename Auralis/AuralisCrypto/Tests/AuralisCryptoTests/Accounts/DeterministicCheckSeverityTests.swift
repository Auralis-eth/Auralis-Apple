import Foundation
@testable import AuralisCrypto
@testable import AuralisRuntime
import Testing

private struct AllowingPolicy: ToolPolicyEvaluating {
    func evaluate(_ proposal: ActionProposal, checkResults: [DeterministicCheckResult]) async -> JudgeDecision {
        .allow
    }
}

private struct AllowingJudge: Judge {
    func judge(_ proposal: ActionProposal, checkResults: [DeterministicCheckResult]) async -> JudgeDecision {
        .allow
    }
}

/// Stands in for a policy or judge that raises its own approval prompt, as `StandingToolPolicy`
/// does — built from the standing policy alone, with no sight of `checkResults`.
private struct EscalatingGate: ToolPolicyEvaluating, Judge {
    static let prompt = "Approve “Sign a message”?"

    func evaluate(_ proposal: ActionProposal, checkResults: [DeterministicCheckResult]) async -> JudgeDecision {
        escalate(proposal)
    }

    func judge(_ proposal: ActionProposal, checkResults: [DeterministicCheckResult]) async -> JudgeDecision {
        escalate(proposal)
    }

    private func escalate(_ proposal: ActionProposal) -> JudgeDecision {
        .escalate(approvalRequest: ApprovalRequest(proposal: proposal, prompt: Self.prompt))
    }
}

private extension JudgeDecision {
    var escalatedRequest: ApprovalRequest? {
        guard case let .escalate(request) = self else { return nil }
        return request
    }
}

/// Covers the severity axis on ``DeterministicCheckResult`` (P0.5-801).
///
/// The axis exists so the warning tier is reachable: before it, a check that observed something an
/// approver should see could only report `passed: true` plus a `detail` string, which no caller
/// could branch on.
@Suite("Deterministic check severity")
struct DeterministicCheckSeverityTests {
    private static let checksummedAddress = "0xd8dA6BF26964aF9D7eEd9e03E53415D37aA96045"

    private func proposal(_ parameters: [String: String]) -> ActionProposal {
        ActionProposal(actor: .system, intent: "x", capability: .audioPlayback, impact: .readOnly, parameters: parameters)
    }

    @Test("a warning passes but is not a clean pass")
    func warningPassesWithoutMasqueradingAsPass() {
        let warning = DeterministicCheckResult(checkID: "c", severity: .warning, detail: "note")

        #expect(warning.passed)
        #expect(warning.severity == .warning)
        #expect([warning].allPassed)
        #expect([warning].firstFailure == nil)
        #expect([warning].warnings == [warning])
    }

    @Test("the boolean convenience initializer maps onto the two blocking-relevant severities")
    func booleanInitializerMapsToSeverity() {
        #expect(DeterministicCheckResult(checkID: "c", passed: true).severity == .pass)
        #expect(DeterministicCheckResult(checkID: "c", passed: false).severity == .failure)
    }

    @Test("only a failure is collected as a failure", arguments: [
        (DeterministicCheckSeverity.pass, false),
        (DeterministicCheckSeverity.warning, false),
        (DeterministicCheckSeverity.failure, true)
    ])
    func onlyFailureBlocks(severity: DeterministicCheckSeverity, blocks: Bool) {
        let results = [DeterministicCheckResult(checkID: "c", severity: severity)]

        #expect(results.allPassed == !blocks)
        #expect((results.firstFailure != nil) == blocks)
    }

    @Test("an unchecksummed address is a warning, not a silent pass")
    func unchecksummedAddressIsAWarning() async {
        let result = await AddressFormatCheck()
            .evaluate(proposal(["address": Self.checksummedAddress.lowercased()]))

        #expect(result.severity == .warning)
        #expect(result.passed)
        #expect(result.detail == "address is well-formed but unchecksummed")
    }

    @Test("a fully checksummed address passes with nothing to report")
    func checksummedAddressIsACleanPass() async {
        let result = await AddressFormatCheck().evaluate(proposal(["address": Self.checksummedAddress]))

        #expect(result.severity == .pass)
        #expect(result.detail == nil)
    }

    // MARK: - Persistence

    @Test("every severity round-trips through the persisted shape", arguments: DeterministicCheckSeverity.allCases)
    func severityRoundTrips(severity: DeterministicCheckSeverity) throws {
        let original = DeterministicCheckResult(checkID: "address.format", severity: severity, detail: "d")
        let decoded = try JSONDecoder().decode(
            DeterministicCheckResult.self,
            from: JSONEncoder().encode(original)
        )

        #expect(decoded == original)
        #expect(decoded.severity == severity)
    }

    /// A record written before the severity axis existed carries only `passed`. It has to decode as
    /// the shape it was written under — a bare pass/fail — rather than throwing and degrading the
    /// whole worklog entry to `.unknown`.
    @Test("a legacy record with no severity key decodes from passed", arguments: [true, false])
    func legacyRecordDecodesFromPassed(passed: Bool) throws {
        let legacy = Data(#"{"checkID":"address.format","passed":\#(passed),"detail":"d"}"#.utf8)

        let decoded = try JSONDecoder().decode(DeterministicCheckResult.self, from: legacy)

        #expect(decoded.passed == passed)
        #expect(decoded.severity == (passed ? .pass : .failure))
        #expect(decoded.checkID == "address.format")
    }

    /// The forward half of the same tolerance: a build that adds a fourth tier writes a severity this
    /// build cannot name. Falling back to `passed` keeps the result readable; throwing would degrade
    /// the entire `checksEvaluated` entry to `.unknown` and lose every other result in it.
    @Test("an unrecognized severity falls back to the bare passed flag", arguments: [true, false])
    func unknownSeverityDecodesFromPassed(passed: Bool) throws {
        let future = Data(
            #"{"checkID":"address.format","passed":\#(passed),"severity":"advisory","detail":"d"}"#.utf8
        )

        let decoded = try JSONDecoder().decode(DeterministicCheckResult.self, from: future)

        #expect(decoded.passed == passed)
        #expect(decoded.severity == (passed ? .pass : .failure))
        #expect(decoded.detail == "d")
    }

    /// `passed` is written alongside `severity` so a reader predating the axis still sees the verdict
    /// instead of finding no key it recognizes.
    @Test("the encoded shape still carries a bare passed flag for older readers")
    func encodedShapeRemainsReadableByOlderReaders() throws {
        let warning = DeterministicCheckResult(checkID: "c", severity: .warning, detail: "note")

        let object = try JSONSerialization.jsonObject(
            with: JSONEncoder().encode(warning)
        ) as? [String: Any]

        #expect(object?["passed"] as? Bool == true)
        #expect(object?["severity"] as? String == "warning")
    }

    // MARK: - Reaching the approver

    /// A warning is only worth raising if it reaches the person who authorizes the action. This is
    /// the end of the axis: check → result severity → approval prompt.
    @Test("a warning is named in the approval prompt")
    func warningReachesTheApprovalPrompt() async throws {
        let registry = DeterministicCheckRegistry()
        await registry.register(AddressFormatCheck())
        let hook = StandardBeforeToolCallHook(
            checks: registry,
            policy: AllowingPolicy(),
            judge: AllowingJudge()
        )
        let tool = ToolDefinition(
            id: "sign",
            title: "Sign",
            capability: .signMessage,
            impact: .highRisk,
            requiredCheckIDs: [StandardCheckID.addressFormat]
        )
        let candidate = ActionProposal(
            actor: .system,
            intent: "Sign a message",
            capability: .signMessage,
            impact: .highRisk,
            requiredApprovals: ["owner"],
            parameters: ["address": Self.checksummedAddress.lowercased()]
        )

        let result = await hook.evaluate(tool: tool, proposal: candidate, approvedEscalation: nil)

        #expect(result.checkResults.warnings.count == 1)
        let decision = try #require(result.decision.escalatedRequest)
        #expect(decision.prompt.contains("well-formed but unchecksummed"))
    }

    /// The prompt has to be reproducible: ``StandardBeforeToolCallHook`` matches a resumed approval
    /// by prompt equality, so a warning-derived prompt that drifted between raise and resume would
    /// silently refuse a valid approval.
    @Test("a clean pass leaves the prompt unadorned, and a warning prompt is stable across replays")
    func promptIsStableAcrossReplays() async throws {
        let registry = DeterministicCheckRegistry()
        await registry.register(AddressFormatCheck())
        let hook = StandardBeforeToolCallHook(
            checks: registry,
            policy: AllowingPolicy(),
            judge: AllowingJudge()
        )
        let tool = ToolDefinition(
            id: "sign",
            title: "Sign",
            capability: .signMessage,
            impact: .highRisk,
            requiredCheckIDs: [StandardCheckID.addressFormat]
        )
        func evaluate(address: String) async -> String? {
            let candidate = ActionProposal(
                actor: .system,
                intent: "Sign a message",
                capability: .signMessage,
                impact: .highRisk,
                requiredApprovals: ["owner"],
                parameters: ["address": address]
            )
            return await hook.evaluate(tool: tool, proposal: candidate, approvedEscalation: nil)
                .decision.escalatedRequest?.prompt
        }

        let clean = try #require(await evaluate(address: Self.checksummedAddress))
        #expect(clean.contains("Note:") == false)

        let warned = try #require(await evaluate(address: Self.checksummedAddress.lowercased()))
        let replay = try #require(await evaluate(address: Self.checksummedAddress.lowercased()))
        #expect(warned == replay)
    }

    // MARK: - Reaching the approver on a policy- or judge-raised escalation

    /// The `requiredApprovals` branch is not the only way an action reaches a human: the policy and
    /// the judge each raise their own prompt, and a high-risk crypto action goes through the judge.
    /// A warning has to be named on those paths too, or the approver signs without seeing it.
    @Test("a warning is named in an escalation the policy or judge raised itself", arguments: [true, false])
    func warningReachesAGateRaisedPrompt(escalateAtPolicy: Bool) async throws {
        let gate = EscalatingGate()
        let hook = StandardBeforeToolCallHook(
            checks: await Self.addressRegistry(),
            policy: escalateAtPolicy ? gate : AllowingPolicy(),
            judge: escalateAtPolicy ? AllowingJudge() : gate
        )

        let result = await hook.evaluate(
            tool: Self.signTool,
            proposal: Self.signProposal(address: Self.checksummedAddress.lowercased()),
            approvedEscalation: nil
        )

        #expect(result.checkResults.warnings.count == 1)
        let request = try #require(result.decision.escalatedRequest)
        #expect(request.prompt.contains("well-formed but unchecksummed"))
        #expect(request.prompt.hasPrefix(EscalatingGate.prompt))
    }

    @Test("a clean pass leaves a gate-raised prompt unadorned")
    func cleanPassLeavesAGateRaisedPromptAlone() async throws {
        let hook = StandardBeforeToolCallHook(
            checks: await Self.addressRegistry(),
            policy: AllowingPolicy(),
            judge: EscalatingGate()
        )

        let result = await hook.evaluate(
            tool: Self.signTool,
            proposal: Self.signProposal(address: Self.checksummedAddress),
            approvedEscalation: nil
        )

        #expect(try #require(result.decision.escalatedRequest).prompt == EscalatingGate.prompt)
    }

    /// The note is appended before the raise/resume prompt comparison, so an approval granted against
    /// the annotated prompt still resolves to `.allow`. Annotating after that comparison — or on only
    /// one side of it — would silently refuse a valid approval.
    @Test("an approval granted against an annotated prompt is honoured on resume")
    func annotatedPromptResumesAsAllowed() async throws {
        let hook = StandardBeforeToolCallHook(
            checks: await Self.addressRegistry(),
            policy: AllowingPolicy(),
            judge: EscalatingGate()
        )
        let candidate = Self.signProposal(address: Self.checksummedAddress.lowercased())
        let raised = try #require(
            await hook.evaluate(tool: Self.signTool, proposal: candidate, approvedEscalation: nil)
                .decision.escalatedRequest
        )

        let resumed = await hook.evaluate(
            tool: Self.signTool,
            proposal: candidate,
            approvedEscalation: raised
        )

        #expect(resumed.decision == .allow)
    }

    /// The same raise/resume property, but across the one parameter that legitimately *does* differ
    /// between the two runs.
    ///
    /// `approvalAware` compares proposals with `freshnessEvaluatedAt` stripped, because the boundary
    /// re-stamps it every run — so a warning note is only safe to append if it does not vary with
    /// that stamp. `annotatedPromptResumesAsAllowed` cannot catch a violation: it resumes the
    /// identical proposal, where even a stamp-derived note would match itself. This one re-stamps in
    /// between, which is what the pipeline actually does.
    @Test("an annotated prompt still resumes after the boundary re-stamps freshness")
    func annotatedPromptSurvivesFreshnessRestamping() async throws {
        let hook = StandardBeforeToolCallHook(
            checks: await Self.addressRegistry(),
            policy: AllowingPolicy(),
            judge: EscalatingGate()
        )
        let candidate = Self.signProposal(
            address: Self.checksummedAddress.lowercased(),
            extraParameters: [StandardCheckParameterKey.contextRefreshedAt: "1000000"]
        )
        let atRaise = candidate.stampingFreshnessEvaluation(at: Date(timeIntervalSince1970: 1_000_001))
        let atResume = candidate.stampingFreshnessEvaluation(at: Date(timeIntervalSince1970: 1_000_099))
        // Guards the test itself: if stamping ever stopped changing the proposal, this would silently
        // degrade into a duplicate of `annotatedPromptResumesAsAllowed`.
        #expect(atRaise != atResume)
        #expect(atRaise.withoutFreshnessEvaluationStamp == atResume.withoutFreshnessEvaluationStamp)

        let raised = try #require(
            await hook.evaluate(tool: Self.signTool, proposal: atRaise, approvedEscalation: nil)
                .decision.escalatedRequest
        )
        #expect(raised.prompt.contains("well-formed but unchecksummed"))

        let resumed = await hook.evaluate(
            tool: Self.signTool,
            proposal: atResume,
            approvedEscalation: raised
        )

        #expect(resumed.decision == .allow)
    }

    // MARK: - Fixtures

    private static func addressRegistry() async -> DeterministicCheckRegistry {
        let registry = DeterministicCheckRegistry()
        await registry.register(AddressFormatCheck())
        return registry
    }

    private static let signTool = ToolDefinition(
        id: "sign",
        title: "Sign",
        capability: .signMessage,
        impact: .highRisk,
        requiredCheckIDs: [StandardCheckID.addressFormat]
    )

    /// No `requiredApprovals`, so the escalation can only have come from the policy or the judge.
    private static func signProposal(
        address: String,
        extraParameters: [String: String] = [:]
    ) -> ActionProposal {
        ActionProposal(
            actor: .system,
            intent: "Sign a message",
            capability: .signMessage,
            impact: .highRisk,
            parameters: extraParameters.merging(["address": address]) { _, explicit in explicit }
        )
    }

    @Test("severity wins over a disagreeing passed flag")
    func severityIsAuthoritativeOnDecode() throws {
        // Hand-written record where the two fields contradict each other. `severity` is the newer,
        // richer field, so it decides; `passed` is derived from it and cannot drift.
        let contradictory = Data(#"{"checkID":"c","passed":true,"severity":"failure"}"#.utf8)

        let decoded = try JSONDecoder().decode(DeterministicCheckResult.self, from: contradictory)

        #expect(decoded.severity == .failure)
        #expect(decoded.passed == false)
    }
}
