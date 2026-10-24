import AuralisPrimaryModels
import Foundation
import PolicyCore
import ReceiptsCore
import RuntimeCore
import Testing

private actor SpyReceiptStore: ReceiptStore {
    private(set) var drafts: [ReceiptDraft] = []

    func append(_ receipt: ReceiptDraft) async throws -> ReceiptRecord {
        drafts.append(receipt)
        return ReceiptRecord(
            id: UUID(),
            sequenceID: drafts.count,
            createdAt: receipt.createdAt,
            actor: receipt.actor,
            actorDetail: receipt.actorDetail,
            authorityDetail: receipt.authorityDetail,
            mode: receipt.mode,
            trigger: receipt.trigger,
            scope: receipt.scope,
            summary: receipt.summary,
            provenance: receipt.provenance,
            isSuccess: receipt.isSuccess,
            correlationID: receipt.correlationID,
            details: receipt.details
        )
    }

    func latest(limit: Int) async throws -> [ReceiptRecord] { [] }
    func receipts(forCorrelationID correlationID: String, limit: Int) async throws -> [ReceiptRecord] { [] }
    func exportAll() async throws -> Data { Data() }
    func resetAll() async throws { }

    func appendedDrafts() -> [ReceiptDraft] { drafts }
}

struct PolicyCoreTests {
    @Test("observe mode denies execution-style actions before future execution evidence is evaluated")
    @MainActor
    func observeModeDeniesExecutionActions() async {
        let result = await ActionPolicyGate.attempt(.draftTransaction, mode: .observe, actor: .human)

        #expect(result == PolicyGateResult(isAllowed: false, userMessage: "Not available in Observe mode"))
    }

    @Test("future execution controls deny signing actions without signing access first")
    func executionReadinessRequiresSigningAccess() {
        let result = PolicyExecutionReadiness.evaluate(
            action: .signMessage,
            evidence: .none
        )

        #expect(result == PolicyGateResult(isAllowed: false, userMessage: "Signing-capable account access is required"))
    }

    @Test("policy actions map to canonical capability identifiers")
    func policyActionsMapToCapabilities() {
        #expect(PolicyControlledAction.signMessage.capabilityID.rawValue == "sign_message")
        #expect(PolicyControlledAction.approveSpending.capabilityID.rawValue == "approve_spending")
        #expect(PolicyControlledAction.draftTransaction.capabilityID.rawValue == "draft_transaction")
        #expect(PolicyControlledAction.runPlugin.capabilityID.rawValue == "run_plugin")
    }

    @Test("policy action gate service accepts injected execution evidence outside Observe")
    @MainActor
    func policyActionGateServiceUsesInjectedEvidence() async {
        let store = SpyReceiptStore()
        let service = PolicyActionGateService(
            modeProvider: { .operate },
            executionEvidenceProvider: {
                PolicyExecutionEvidence(
                    signingAccessAvailable: true,
                    capabilityGrant: PolicyCapabilityGrant(capabilityID: PolicyControlledAction.signMessage.capabilityID.rawValue),
                    requesterProvenance: PolicyRequesterProvenance(requesterID: "test", displayName: "Test"),
                    userConfirmation: PolicyUserConfirmation(
                        confirmedSummary: "Sign message",
                        confirmationReceiptID: "confirmation-receipt"
                    ),
                    approvedReceiptID: "approved-receipt"
                )
            },
            receiptStore: store
        )

        let result = await service.attempt(.signMessage, actor: .human)
        let drafts = await store.appendedDrafts()

        #expect(result.isAllowed)
        #expect(drafts.first?.mode == .operate)
        #expect(drafts.first?.trigger == "policy.approved")
    }

    // --- Authority attribution (P0.5-601/602) ---

    @Test("a denied policy receipt records the standing policy as its authority")
    @MainActor
    func deniedPolicyReceiptCarriesAuthority() async throws {
        let store = SpyReceiptStore()

        _ = await ActionPolicyGate.attempt(
            .draftTransaction,
            mode: .observe,
            actor: ActorRef(kind: .operatorAgent, identifier: "operator.research"),
            receiptStore: store
        )

        let draft = try #require(await store.appendedDrafts().first)
        let authority = try #require(draft.authorityDetail)
        #expect(authority.source == "policyDefault")
        #expect(authority.capability == PolicyControlledAction.draftTransaction.capabilityID.rawValue)
        #expect(authority.reason == "Not available in Observe mode")
        // The actor must stay derived, not defaulted to a human.
        #expect(draft.actorDetail?.kind == "operator")
    }

    /// `CryptoMode.receiptMode` is `ReceiptMode(rawValue: rawValue) ?? .observe` — a cross-package
    /// coupling held together by a raw-string coincidence, behind a silent fallback, on the value
    /// stamped onto every receipt the runtime writes. Renaming either side's raw value re-introduces
    /// the defect that already shipped once (every Operate receipt claiming Observe) with the whole
    /// suite staying green, because nothing anywhere pinned it. Its two siblings `ActorKind` and
    /// `AuthorityRef.Source` both have frozen-raw-value tests; this had none.
    ///
    /// Both halves are needed. The mapping table catches a rename on one side, which breaks the
    /// lookup and falls back to `.observe`; the literals catch a *matched* rename on both sides,
    /// which keeps the lookup working and silently changes persisted receipt history.
    @Test("every crypto mode maps to its own receipt mode, and both sets of raw values are frozen")
    func cryptoModeToReceiptModeMappingIsFrozen() {
        let expected: [CryptoMode: ReceiptMode] = [
            .observe: .observe,
            .assist: .assist,
            .operate: .operate
        ]

        // A new CryptoMode case has to be given a receipt mode here, not left to the fallback.
        #expect(Set(expected.keys) == Set(CryptoMode.allCases))
        for mode in CryptoMode.allCases {
            #expect(mode.receiptMode == expected[mode], "\(mode) did not map to its own receipt mode")
        }

        #expect(CryptoMode.observe.rawValue == "Observe")
        #expect(CryptoMode.assist.rawValue == "Assist")
        #expect(CryptoMode.operate.rawValue == "Operate")
        #expect(ReceiptMode.observe.rawValue == "Observe")
        #expect(ReceiptMode.assist.rawValue == "Assist")
        #expect(ReceiptMode.operate.rawValue == "Operate")
    }

    /// `summary` is the Observe-mode *unavailability* explanation, and the approved path stamped it
    /// onto the receipt unconditionally — so a successful Operate signature recorded
    /// `isSuccess: true`, `mode: .operate`, and "Signing messages is not available in Observe mode."
    /// on the same row. Dead code while `.observe` was `ReceiptMode`'s only case; reachable now.
    @Test("an approved receipt's summary describes the mode it was approved in")
    @MainActor
    func approvedPolicyReceiptSummaryMatchesItsMode() async throws {
        let store = SpyReceiptStore()

        _ = await ActionPolicyGate.attempt(
            .signMessage,
            mode: .operate,
            actor: .human,
            executionEvidence: PolicyExecutionEvidence(
                signingAccessAvailable: true,
                capabilityGrant: PolicyCapabilityGrant(
                    capabilityID: PolicyControlledAction.signMessage.capabilityID.rawValue
                ),
                requesterProvenance: PolicyRequesterProvenance(requesterID: "test", displayName: "Test"),
                userConfirmation: PolicyUserConfirmation(
                    confirmedSummary: "Sign message",
                    confirmationReceiptID: "confirmation-receipt"
                ),
                approvedReceiptID: "approved-receipt"
            ),
            receiptStore: store
        )

        let draft = try #require(await store.appendedDrafts().first)
        #expect(draft.mode == .operate)
        #expect(draft.isSuccess)
        #expect(draft.summary == "Sign Message was allowed by standing policy in Operate mode.")
        #expect(
            !draft.summary.contains("not available"),
            "an approved receipt summary denied the action it recorded as successful"
        )
    }

    /// The Observe denial is the one case `summary` is written for, so it is kept verbatim there —
    /// the mode-derived wording must not replace prose that already names the capability.
    @Test("an Observe denial keeps the action's own unavailability wording")
    @MainActor
    func observeDenialKeepsTheActionSummary() async throws {
        let store = SpyReceiptStore()

        _ = await ActionPolicyGate.attempt(
            .signMessage,
            mode: .observe,
            actor: .human,
            receiptStore: store
        )

        let draft = try #require(await store.appendedDrafts().first)
        #expect(draft.summary == PolicyControlledAction.signMessage.summary)
        #expect(draft.isSuccess == false)
    }

    /// The readiness branch refuses an action in Assist or Operate — the modes where acting is
    /// possible — and returned without writing anything, while the Observe denial two branches down
    /// always left a receipt. A refusal with no audit trail is the gap: the user is told no, and
    /// nothing records that they were.
    @Test("a readiness denial outside Observe leaves a receipt")
    @MainActor
    func readinessDenialWritesAReceipt() async throws {
        let store = SpyReceiptStore()

        let result = await ActionPolicyGate.attempt(
            .signMessage,
            mode: .operate,
            actor: ActorRef(kind: .operatorAgent, identifier: "operator.research"),
            executionEvidence: .none,
            receiptStore: store
        )

        #expect(result.isAllowed == false)

        let draft = try #require(await store.appendedDrafts().first, "a readiness denial wrote no receipt")
        #expect(draft.trigger == "policy.denied")
        #expect(draft.isSuccess == false)
        #expect(draft.mode == .operate)
        // The reason the readiness check gave, not a generic refusal.
        #expect(draft.authorityDetail?.reason == result.userMessage)
        // And the actor stays derived rather than defaulted to a person.
        #expect(draft.actorDetail?.kind == "operator")
    }

    @Test("an approved high-risk policy receipt records its authority too")
    @MainActor
    func approvedPolicyReceiptCarriesAuthority() async throws {
        let store = SpyReceiptStore()
        let service = PolicyActionGateService(
            modeProvider: { .operate },
            executionEvidenceProvider: {
                PolicyExecutionEvidence(
                    signingAccessAvailable: true,
                    capabilityGrant: PolicyCapabilityGrant(
                        capabilityID: PolicyControlledAction.signMessage.capabilityID.rawValue
                    ),
                    requesterProvenance: PolicyRequesterProvenance(requesterID: "test", displayName: "Test"),
                    userConfirmation: PolicyUserConfirmation(
                        confirmedSummary: "Sign message",
                        confirmationReceiptID: "confirmation-receipt"
                    ),
                    approvedReceiptID: "approved-receipt"
                )
            },
            receiptStore: store
        )

        _ = await service.attempt(.signMessage, actor: .human)

        let draft = try #require(await store.appendedDrafts().first)
        let authority = try #require(draft.authorityDetail)
        #expect(authority.source == "policyDefault")
        #expect(authority.capability == PolicyControlledAction.signMessage.capabilityID.rawValue)
        #expect(authority.reason?.isEmpty == false)
    }
}
