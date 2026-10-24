import ArtifactCore
import AuralisPrimaryModels
import CapabilitiesCore
import Foundation
import PlaybookCore
import PolicyCore
import ReceiptsCore
import RuntimeCore
@testable import RuntimeKit
import SchedulingCore
import Testing

/// Minimal in-memory receipt store, newest-first like the real one.
private actor GateReceiptStore: ReceiptStore {
    private var records: [ReceiptRecord] = []

    func append(_ receipt: ReceiptDraft) async throws -> ReceiptRecord {
        let record = ReceiptRecord(
            id: UUID(), sequenceID: records.count + 1, createdAt: receipt.createdAt,
            actor: receipt.actor, actorDetail: receipt.actorDetail,
            authorityDetail: receipt.authorityDetail, mode: receipt.mode, trigger: receipt.trigger,
            scope: receipt.scope, summary: receipt.summary, provenance: receipt.provenance,
            isSuccess: receipt.isSuccess, correlationID: receipt.correlationID, details: receipt.details
        )
        records.insert(record, at: 0)
        return record
    }

    func latest(limit: Int) async throws -> [ReceiptRecord] { Array(records.prefix(limit)) }
    func receipts(forCorrelationID correlationID: String, limit: Int) async throws -> [ReceiptRecord] {
        Array(records.filter { $0.correlationID == correlationID }.prefix(limit))
    }
    func exportAll() async throws -> Data { Data() }
    func resetAll() async throws { records.removeAll() }
}

/// Reports the effect a cleared policy action would have had, so the gate's allowed path is
/// observable without a wallet.
private struct RecordingPolicyActionExecutor: ToolExecuting {
    let outputs: [String: String]

    func execute(
        _ tool: ToolDefinition,
        proposal: ActionProposal,
        authorization: ToolExecutionAuthorization
    ) async throws -> ToolCallArtifact {
        ToolCallArtifact(toolID: tool.id, summary: "performed \(tool.id)", outputFields: outputs)
    }
}

/// `PipelineBackedPolicyGate` is the adapter every app-side `PolicyControlledAction` passes through
/// on its way into the governed pipeline, and it had no tests at all — the outcome mapping that
/// decides what a wallet caller is told was unpinned.
@Suite("Policy gate adapter")
@MainActor
struct PipelineBackedPolicyGateTests {
    private static let address = "0x0000000000000000000000000000000000000001"

    private func makeHost(
        mode: CryptoMode,
        executor: any ToolExecuting = UnconfiguredPolicyActionExecutor()
    ) -> RuntimeHost {
        RuntimeHost(
            receiptStore: GateReceiptStore(),
            operators: RuntimeOperatorStack(policyActionExecutor: executor),
            governance: RuntimeGovernanceOptions(
                standardCheckConfiguration: StandardCheckConfiguration(allowedChains: .init([.ethMainnet]))
            ),
            identity: RuntimeIdentityHooks(cryptoModeProvider: { mode })
        )
    }

    private var signPayload: PolicyActionPayload {
        .signMessage(text: "hello", address: Self.address, chainID: "1")
    }

    /// Observe is the crypto posture that refuses to act, so the gate must report the refusal rather
    /// than a permission it does not have.
    @Test("a crypto action in Observe is refused with the reason the pipeline gave")
    func cryptoActionInObserveIsRefused() async {
        let gate = PipelineBackedPolicyGate(host: makeHost(mode: .observe))

        let result = await gate.attempt(
            .signMessage,
            payload: signPayload,
            actor: .human
        )

        #expect(result.isAllowed == false)
        #expect(result.userMessage.isEmpty == false)
        #expect(result.outputs.isEmpty)

        // And it has to be *readable*. This message is rendered verbatim in the "Policy decision"
        // alert, and non-emptiness was the whole bar it had to clear while it read "PolicyCore
        // denied sign_message in Observe mode." — a module name and a schema identifier, both
        // shown to a person. The escalation branch next door always used the action's title.
        #expect(result.userMessage.contains(PolicyControlledAction.signMessage.title))
        #expect(!result.userMessage.contains(PolicyControlledAction.signMessage.rawValue))
        #expect(!result.userMessage.contains("PolicyCore"))
    }

    /// The escalation path is the one most easily confused with a denial: `PolicyGateResult` has no
    /// "awaiting approval" channel, so the gate surfaces the approval *prompt* as the message. This
    /// pins that the prompt is what reaches the caller — not an empty string, and not a generic
    /// block reason — because that text is the only thing telling a person to go and approve.
    @Test("an escalated action surfaces the approval prompt as its message")
    func escalatedActionSurfacesItsPrompt() async {
        let host = makeHost(mode: .assist)
        let gate = PipelineBackedPolicyGate(host: host)

        let result = await gate.attempt(
            .signMessage,
            payload: signPayload,
            actor: .human
        )

        #expect(result.isAllowed == false)
        #expect(result.userMessage.isEmpty == false)
        // The pipeline registered a real approval for Mission Control to pick up, so the caller's
        // "not allowed" is a deferral rather than a dead end.
        #expect(await host.approvalRegistry.oldestPendingDate() != nil)
    }

    /// A cleared action has to pass its effect outputs back, or the wallet caller has no signature
    /// or transaction hash to show for a run that genuinely happened.
    @Test("a cleared action returns the executor's effect outputs")
    func clearedActionReturnsItsOutputs() async {
        let host = makeHost(
            mode: .operate,
            executor: RecordingPolicyActionExecutor(outputs: [
                "signature": "0xabc",
                "address": Self.address
            ])
        )
        let gate = PipelineBackedPolicyGate(host: host)

        let result = await gate.attempt(
            .signMessage,
            payload: signPayload,
            actor: .human
        )

        if result.isAllowed {
            #expect(result.outputs["signature"] == "0xabc")
        } else {
            // Operate may still escalate this action by standing policy; if so the caller must at
            // least be told why, never handed a silent empty refusal.
            #expect(result.userMessage.isEmpty == false)
        }
    }

    /// The policy boundary now accepts the canonical runtime actor directly. This pins that the
    /// governed proposal and its receipt preserve that identity without a receipt-DTO round trip.
    @Test("the caller's runtime actor reaches the receipt unchanged")
    func actorSurvivesThePolicyBoundary() async {
        let store = GateReceiptStore()
        let host = RuntimeHost(
            receiptStore: store,
            governance: RuntimeGovernanceOptions(
                standardCheckConfiguration: StandardCheckConfiguration(allowedChains: .init([.ethMainnet]))
            ),
            identity: RuntimeIdentityHooks(cryptoModeProvider: { .observe })
        )
        let agent = ActorRef(kind: .operatorAgent, identifier: "operator.test")

        _ = await PipelineBackedPolicyGate(host: host).attempt(
            .signMessage,
            payload: signPayload,
            actor: agent
        )

        let receipts = try? await store.latest(limit: 10)
        let written = try? #require(receipts?.first)
        #expect(written?.actorDetail?.identifier == agent.receiptActorDetail.identifier)
        #expect(written?.actorDetail?.kind == agent.receiptActorDetail.kind)
    }

    /// The receipt for a wallet action has to name the deterministic checks it went through.
    ///
    /// `runPolicyAction` built its proposal without `requiredCheckIDs`, unlike `runOperator`. The
    /// checks always *ran* — `BeforeToolCallHook` evaluates the union of the tool's and the
    /// proposal's — but `ReceiptStoreSink` renders its "Pass checks:" plan line from the proposal, so
    /// `signMessage`, `approveSpending`, and `draftTransaction` wrote receipts naming none of them
    /// while every operator receipt listed its own. The readable receipt (P1-301) was least
    /// informative on the three highest-impact actions in the app.
    @Test("a policy action's receipt names the checks it passed")
    func policyActionReceiptNamesItsChecks() async throws {
        let store = GateReceiptStore()
        let host = RuntimeHost(
            receiptStore: store,
            governance: RuntimeGovernanceOptions(
                standardCheckConfiguration: StandardCheckConfiguration(allowedChains: .init([.ethMainnet]))
            ),
            identity: RuntimeIdentityHooks(cryptoModeProvider: { .observe })
        )

        _ = await host.runPolicyAction(.signMessage, actor: .human, payload: signPayload)

        let written = try #require(try await store.latest(limit: 10).first)
        guard case .array(let steps)? = written.details.values["interpretedPlan"] else {
            Issue.record("a policy action receipt should record an interpretedPlan")
            return
        }
        let checkLine = steps.compactMap { step -> String? in
            guard case let .string(text) = step, text.hasPrefix("Pass checks:") else { return nil }
            return text
        }.first
        let named = try #require(checkLine, "the receipt should name the checks the action passed")
        // The signing tool's own declared contract, so this tracks `PolicyActionCatalog` rather than
        // restating a list that could drift from it.
        let tool = try #require(PolicyActionCatalog.tools.first {
            $0.id == PolicyActionCatalog.toolID(for: .signMessage)
        })
        for checkID in tool.requiredCheckIDs {
            #expect(named.contains(checkID), "\(checkID) is missing from the receipt's plan")
        }
    }

    // MARK: - the payload-less (class-level) overload

    /// The overload `PolicyActionGating` documents as "evaluates the *class* of action with no
    /// concrete payload". It used to forward to the payload-bearing path with `payload: nil`, which
    /// could never satisfy `PolicyActionCatalog`'s strict input schemas — so it returned
    /// `.needsRevision` for every action in every mode, and `ProfileDetailView` showed the schema
    /// instructions ("missing required field “payload.kind”…") in its "Policy decision" alert.
    ///
    /// This pins the contract in both directions: a real policy sentence reaches the caller, and the
    /// schema-validation vocabulary never does.
    @Test(
        "the class-level overload answers with policy, not schema instructions",
        arguments: [CryptoMode.observe, .assist, .operate]
    )
    func classLevelAttemptReportsPolicy(mode: CryptoMode) async {
        let gate = PipelineBackedPolicyGate(host: makeHost(mode: mode))

        for action in PolicyControlledAction.allCases {
            let result = await gate.attempt(action, actor: .human)

            #expect(result.userMessage.isEmpty == false)
            #expect(result.outputs.isEmpty)
            #expect(result.userMessage.contains("payload.") == false)
            #expect(result.userMessage.contains("Revise the request") == false)
            #expect(result.userMessage.contains("missing required field") == false)
        }
    }

    /// Every `PolicyControlledAction` maps to a `.highRisk` or `.externalImpact` capability, and both
    /// require confirmation — so the class-level verdict is structurally never `.allow`. The
    /// permission-only overload is what `AutopilotAuthorizer` reads as authorization, so this is the
    /// invariant that keeps answering it without the pipeline fail-closed rather than permissive.
    @Test("no mode lets the class-level overload authorize a policy action")
    func classLevelAttemptNeverAuthorizes() async {
        for mode in [CryptoMode.observe, .assist, .operate] {
            let gate = PipelineBackedPolicyGate(host: makeHost(mode: mode))

            for action in PolicyControlledAction.allCases {
                let result = await gate.attempt(action, actor: .human)
                #expect(result.isAllowed == false, "\(action.rawValue) was authorized in \(mode.rawValue)")
            }
        }
    }

    /// A posture question must not leave governance state behind. An Approval Inbox entry minted from
    /// a payload-free proposal could only ever bounce on resume, and a receipt would record an attempt
    /// that never happened.
    @Test("asking the class-level question registers no approval and writes no receipt")
    func classLevelAttemptLeavesNoTrace() async throws {
        let store = GateReceiptStore()
        let host = RuntimeHost(
            receiptStore: store,
            governance: RuntimeGovernanceOptions(
                standardCheckConfiguration: StandardCheckConfiguration(allowedChains: .init([.ethMainnet]))
            ),
            identity: RuntimeIdentityHooks(cryptoModeProvider: { .assist })
        )
        let gate = PipelineBackedPolicyGate(host: host)
        // Bootstrap's own governance receipts (capability grants) land before the measurement, so the
        // baseline is taken after it rather than assumed empty.
        await host.bootstrap()
        let baseline = try await store.latest(limit: 256).count

        _ = await gate.attempt(.signMessage, actor: .human)

        #expect(await host.approvalRegistry.oldestPendingDate() == nil)
        #expect(try await store.latest(limit: 256).count == baseline)
    }

    /// The kill switch outranks standing policy. Reporting "approval required" while the pause gate is
    /// closed would point a person at a route that does not exist.
    @Test("a paused runtime refuses the class-level question with the pause reason")
    func classLevelAttemptRespectsThePause() async {
        let host = makeHost(mode: .operate)
        await host.setPaused(true, reason: "Paused for the test.")
        let gate = PipelineBackedPolicyGate(host: host)

        let result = await gate.attempt(.signMessage, actor: .human)

        #expect(result.isAllowed == false)
        #expect(result.userMessage == "Paused for the test.")
    }
}

/// The standing-policy adapter that decides allow / block / escalate before a tool runs. Untested
/// until now despite sitting on every governed call's critical path.
@Suite("PolicyCore tool evaluator")
struct PolicyCoreToolEvaluatorTests {
    private func proposal(
        capability: CapabilityID,
        impact: ActionImpactClass
    ) -> ActionProposal {
        ActionProposal(
            actor: .human,
            intent: "test",
            capability: capability,
            impact: impact,
            parameters: [:]
        )
    }

    /// Read-only, non-crypto work is what the app does constantly; if standing policy did not allow
    /// it outright every routine run would stall on an approval nobody asked for.
    @Test("read-only non-crypto work is allowed outright")
    func readOnlyNonCryptoIsAllowed() async {
        let evaluator = PolicyCoreToolEvaluator(cryptoMode: .observe)

        let decision = await evaluator.evaluate(
            proposal(capability: .audioPlayback, impact: .readOnly),
            checkResults: []
        )

        guard case .allow = decision else {
            Issue.record("expected .allow, got \(decision)")
            return
        }
    }

    /// The Observe boundary (ADR-010): a crypto capability that changes state must not resolve to
    /// `.allow` no matter how the rest of the proposal is shaped.
    @Test("a state-changing crypto capability never resolves to allow in Observe")
    func cryptoStateChangeIsNeverAllowedInObserve() async {
        let evaluator = PolicyCoreToolEvaluator(cryptoMode: .observe)

        let decision = await evaluator.evaluate(
            proposal(
                capability: PolicyControlledAction.draftTransaction.capabilityID,
                impact: CapabilityImpactMapping.defaultImpact(
                    for: PolicyControlledAction.draftTransaction.capabilityID
                )
            ),
            checkResults: []
        )

        if case .allow = decision {
            Issue.record("Observe allowed a state-changing crypto capability")
        }
    }

    /// An escalation has to carry the proposal it is about, or the approval a person clears in
    /// Mission Control cannot be resumed against the action they reviewed.
    @Test("an escalation carries the proposal it was raised for")
    func escalationCarriesItsProposal() async {
        let evaluator = PolicyCoreToolEvaluator(cryptoMode: .assist)
        let subject = proposal(
            capability: PolicyControlledAction.signMessage.capabilityID,
            impact: CapabilityImpactMapping.defaultImpact(
                for: PolicyControlledAction.signMessage.capabilityID
            )
        )

        let decision = await evaluator.evaluate(subject, checkResults: [])

        if case let .escalate(request) = decision {
            #expect(request.proposal.capability == subject.capability)
            #expect(request.prompt.isEmpty == false)
        } else if case .allow = decision {
            Issue.record("Assist allowed a confirm-first crypto action without approval")
        }
    }
}

/// The fallback operator every playbook without a domain operator runs through, so its artifact is
/// what most routine runs actually produce.
@Suite("Default routine operator")
struct DefaultRoutineOperatorTests {
    /// A real governed context, minted the only way anything outside `RuntimeCore` can: by running
    /// the provider's bundle through ``ContextGovernanceBoundary``. `GovernedContext`'s initializer
    /// is deliberately internal so the type is an unforgeable proof of validation — a test that
    /// reached around that would be testing a context the runtime would never hand the operator.
    private func governedContext(for playbook: Playbook) async throws -> GovernedContext {
        let bundle = await DefaultContextProvider().gather(for: playbook)
        return try ContextGovernanceBoundary()
            .authorize(bundle, against: playbook.contextContract, at: Date())
            .get()
    }

    private func playbook(
        allowedOutputs: [ArtifactType],
        name: String = "Test Playbook"
    ) -> Playbook {
        Playbook(
            id: "test.playbook",
            name: name,
            summary: "summary",
            trigger: .manual,
            authority: PlaybookAuthority(capabilities: [.runPlugin], allowedOutputs: allowedOutputs),
            completionCondition: "Something is produced.",
            contextContract: SystemPlaybookContracts.contract(for: "test.playbook"),
            installState: .installed
        )
    }

    /// The artifact has to be typed as something the playbook's own authority permits, or the run
    /// produces a work product it was never granted the right to create.
    @Test("the artifact takes the first output type the playbook's authority allows")
    func artifactHonoursDeclaredOutputType() async throws {
        let subject = playbook(allowedOutputs: [.report, .brief])
        let result = await DefaultRoutineOperator().run(
            playbook: subject,
            context: try await governedContext(for: subject)
        )

        #expect(result.outcome == .success)
        #expect(result.artifact?.type == .report)
    }

    /// A playbook that declares no outputs still has to produce something typed rather than crash
    /// or emit an untyped draft.
    @Test("a playbook declaring no outputs falls back to a brief")
    func undeclaredOutputFallsBackToBrief() async throws {
        let subject = playbook(allowedOutputs: [])
        let result = await DefaultRoutineOperator().run(
            playbook: subject,
            context: try await governedContext(for: subject)
        )

        #expect(result.artifact?.type == .brief)
    }

    /// The artifact is attributed to the routine that produced it (P0.5-602) — a scheduled run's
    /// work product must not read as though a person authored it.
    @Test("the artifact is attributed to the scheduled routine, not a person")
    func artifactIsAttributedToTheRoutine() async throws {
        let subject = playbook(allowedOutputs: [.brief])
        let result = await DefaultRoutineOperator().run(
            playbook: subject,
            context: try await governedContext(for: subject)
        )

        #expect(result.artifact?.provenance.actor.kind == .scheduledRoutine)
        #expect(result.artifact?.provenance.actor.identifier == "test.playbook")
        #expect(result.artifact?.creatorPlaybookID == "test.playbook")
    }
}
