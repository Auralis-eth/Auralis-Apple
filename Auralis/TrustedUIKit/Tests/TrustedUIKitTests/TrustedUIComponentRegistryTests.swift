import CapabilitiesCore
import Foundation
import RuntimeCore
import Testing
@testable import TrustedUIKit

@Suite("TrustedUIComponentRegistry — governed mapping")
struct TrustedUIComponentRegistryMappingTests {

    private func proposal(impact: ActionImpactClass = .highRisk) -> ActionProposal {
        ActionProposal(actor: .human, intent: "sign a message", capability: .signMessage, impact: impact)
    }

    @Test("every request case maps to a fixed component kind")
    func requestMapsToComponent() {
        let registry = TrustedUIComponentRegistry()
        let approval = ApprovalRequest(proposal: proposal(), prompt: "Approve?")

        #expect(registry.componentKind(for: .approveAction(approval)) == .approvalSheet)
        #expect(registry.componentKind(for: .editDraft(proposalID: UUID())) == .draftEditor)
        #expect(registry.componentKind(for: .inspectCapability(.signMessage)) == .permissionCard)
        #expect(registry.componentKind(for: .reviewReceipt(receiptID: UUID())) == .receiptCard)
        #expect(registry.componentKind(for: .inspectContextBundle(ContextBundle(fields: []))) == .contextBundleCard)
        #expect(registry.componentKind(for: .presentSuggestion(TrustedUISuggestion(title: "t", detail: "d"))) == .suggestionCard)
        #expect(registry.componentKind(for: .presentRiskBanner(.highRisk)) == .riskBanner)
    }

    @Test("catalog covers exactly the declared component kinds")
    func catalogIsComplete() {
        let catalogKinds = Set(TrustedUIComponentRegistry.catalog.map(\.kind))
        #expect(catalogKinds == Set(TrustedUIComponentRegistry.ComponentKind.allCases))
        #expect(TrustedUIComponentRegistry.catalog.count == TrustedUIComponentRegistry.ComponentKind.allCases.count)
    }
}

@Suite("TrustedUIComponentRegistry — resolution")
struct TrustedUIComponentRegistryResolutionTests {

    @Test("receipt resolver hydrates the summary and returns nil when unknown")
    func receiptResolution() {
        let known = UUID()
        let summary = TrustedUIReceiptSummary(
            id: known, title: "Signed message", subtitle: "wallet",
            actorLabel: "You", timestamp: .now, fields: []
        )
        let registry = TrustedUIComponentRegistry(receiptResolver: { $0 == known ? summary : nil })

        #expect(registry.receiptSummary(for: known) == summary)
        #expect(registry.receiptSummary(for: UUID()) == nil)
    }

    @Test("draft resolver hydrates the summary and returns nil when unknown")
    func draftResolution() {
        let known = UUID()
        let draft = TrustedUIDraftSummary(id: known, title: "Draft", body: "hello")
        let registry = TrustedUIComponentRegistry(draftResolver: { $0 == known ? draft : nil })

        #expect(registry.draftSummary(for: known) == draft)
        #expect(registry.draftSummary(for: UUID()) == nil)
        #expect(registry.isResolvable(.editDraft(proposalID: known)))
        #expect(!registry.isResolvable(.editDraft(proposalID: UUID())))
    }

    @Test("unresolved receipt and draft requests fail closed")
    func unresolvedRequestsFailClosed() {
        let registry = TrustedUIComponentRegistry()

        #expect(!registry.isResolvable(.reviewReceipt(receiptID: UUID())))
        #expect(!registry.isResolvable(.editDraft(proposalID: UUID())))
        #expect(registry.isResolvable(.inspectCapability(.signMessage)))
    }

    @Test("draft commits dispatch only for a resolved draft")
    func draftCommitDispatch() {
        let known = UUID()
        let summary = TrustedUIDraftSummary(id: known, title: "Draft", body: "old")
        let registry = TrustedUIComponentRegistry(draftResolver: { $0 == known ? summary : nil })
        var commits: [(UUID, String)] = []

        registry.performDraftCommit(proposalID: UUID(), body: "ignored") { commits.append(($0, $1)) }
        registry.performDraftCommit(proposalID: known, body: "updated") { commits.append(($0, $1)) }

        #expect(commits.count == 1)
        #expect(commits.first?.0 == known)
        #expect(commits.first?.1 == "updated")
    }

    @Test("suggestion actions dispatch only when the schema declares an action")
    func suggestionActionDispatch() {
        let registry = TrustedUIComponentRegistry()
        let passive = TrustedUISuggestion(title: "Passive", detail: "No action")
        let actionable = TrustedUISuggestion(title: "Act", detail: "Has action", actionLabel: "Open")
        var actionIDs: [UUID] = []

        registry.performSuggestionAction(suggestion: passive) { actionIDs.append($0) }
        registry.performSuggestionAction(suggestion: actionable) { actionIDs.append($0) }

        #expect(actionIDs == [actionable.id])
    }

    /// `performDraftCommit`'s only guard is "does this proposal id resolve", which passes for both
    /// drafts in a swap and so cannot catch a body belonging to the wrong one. The id the factory
    /// stamps on the produced component is what keeps the two drafts' state apart.
    @Test("the factory gives each draft its own identity, so a swap is not an update")
    func draftEditorsAreIdentifiedByDraft() {
        let first = TrustedUIDraftSummary(id: UUID(), title: "Draft A", body: "alpha")
        let second = TrustedUIDraftSummary(id: UUID(), title: "Draft B", body: "beta")
        let drafts = [first.id: first, second.id: second]
        let registry = TrustedUIComponentRegistry(draftResolver: { drafts[$0] })

        let firstIdentity = registry.componentIdentity(for: .editDraft(proposalID: first.id))
        let secondIdentity = registry.componentIdentity(for: .editDraft(proposalID: second.id))

        #expect(firstIdentity == first.id)
        #expect(secondIdentity == second.id)
        #expect(firstIdentity != secondIdentity)
    }

    /// The approval sheet holds a submission latch in `@State` for the same reason, so it is stamped
    /// too. The stateless cards are deliberately left unidentified — reuse costs them nothing, and
    /// claiming identity we do not attach would make this function a worse description of the
    /// factory than no function at all.
    @Test("identity is attached to exactly the components that carry local state")
    func onlyStatefulComponentsAreIdentified() {
        let registry = TrustedUIComponentRegistry()
        let approval = ApprovalRequest(
            proposal: ActionProposal(actor: .human, intent: "sign", capability: .signMessage, impact: .highRisk),
            prompt: "Approve?"
        )

        #expect(registry.componentIdentity(for: .approveAction(approval)) == approval.id)
        #expect(registry.componentIdentity(for: .reviewReceipt(receiptID: UUID())) == nil)
        #expect(registry.componentIdentity(for: .inspectCapability(.signMessage)) == nil)
        #expect(registry.componentIdentity(for: .inspectContextBundle(ContextBundle(fields: []))) == nil)
        #expect(registry.componentIdentity(for: .presentSuggestion(TrustedUISuggestion(title: "t", detail: "d"))) == nil)
        #expect(registry.componentIdentity(for: .presentRiskBanner(.highRisk)) == nil)
    }

    /// An unresolvable draft produces an unavailable card, which holds nothing — but the request
    /// still needs a stable identity so two unresolvable drafts do not share one slot's state if the
    /// card ever gains any.
    @Test("an unresolvable draft falls back to the proposal id for identity")
    func unresolvableDraftIdentityFallsBackToProposalID() {
        let registry = TrustedUIComponentRegistry()
        let proposalID = UUID()

        #expect(registry.componentIdentity(for: .editDraft(proposalID: proposalID)) == proposalID)
    }

    @Test("permission model is built from canonical capability metadata")
    func permissionModelFromRegistry() {
        let registry = TrustedUIComponentRegistry()
        let model = registry.permissionModel(for: .signMessage)

        #expect(model.title == "Sign Message")
        #expect(model.leaseSummary == nil)
    }

    @Test("permission model folds in a live lease when the resolver has one")
    func permissionModelWithLease() {
        let lease = CapabilityLease(
            capability: .signMessage,
            grantedTo: .human,
            expiresAt: .now.addingTimeInterval(1200)
        )
        let registry = TrustedUIComponentRegistry(leaseResolver: { $0 == .signMessage ? lease : nil })
        let model = registry.permissionModel(for: .signMessage)

        #expect(model.leaseSummary != nil)
        #expect(model.leaseSummary?.contains(CapabilityLeaseScope.account.displayTitle) == true)
    }

    private func approvalRequest(intent: String) -> ApprovalRequest {
        ApprovalRequest(
            proposal: ActionProposal(
                actor: .human,
                intent: intent,
                capability: .approveSpending,
                impact: .highRisk,
                parameters: ["amount": "100"]
            ),
            prompt: "Approve \(intent)?"
        )
    }

    /// The outcome used to arrive on its own, so nothing in the chain bound the decision to the
    /// proposal the person saw. `ApprovalRegistry.consume(_:)` demands an exact match against the
    /// request it registered, which means a caller holding a multi-item inbox had to supply the
    /// request from its own notion of "the current one" — and an approve given for proposal A could
    /// be consumed against proposal B.
    @Test("an approval decision names the request it was made about")
    func approvalDecisionCarriesItsRequest() {
        let registry = TrustedUIComponentRegistry()
        let rendered = approvalRequest(intent: "send 100 USDC")
        var dispatched: [(ApprovalRequest, TrustedUIApprovalOutcome)] = []

        registry.performApprovalDecision(
            rendered: rendered,
            dispatched: rendered,
            outcome: .approved
        ) { dispatched.append(($0, $1)) }

        #expect(dispatched.count == 1)
        #expect(dispatched.first?.0 == rendered)
        #expect(dispatched.first?.0.proposal.id == rendered.proposal.id)
        #expect(dispatched.first?.1 == .approved)
    }

    /// The re-assertion, matching how `performDraftCommit` re-resolves its id before dispatching. A
    /// sheet that outlived the request it was built for is the only way these two disagree, and that
    /// is exactly the case where forwarding would attribute one proposal's approval to another.
    @Test("a decision from a different request than the one rendered is not dispatched")
    func approvalDecisionForAnotherRequestIsRefused() {
        let registry = TrustedUIComponentRegistry()
        let rendered = approvalRequest(intent: "send 100 USDC")
        let other = approvalRequest(intent: "send 5000 USDC")
        var dispatched: [ApprovalRequest] = []

        registry.performApprovalDecision(
            rendered: rendered,
            dispatched: other,
            outcome: .approved
        ) { request, _ in dispatched.append(request) }

        #expect(dispatched.isEmpty)
    }

    /// Compared whole, not by `id`. A request keeping its identity while its proposal changes
    /// underneath is the substitution worth refusing — approving "send 100" must not authorise
    /// "send 5000" because the envelope's id matched.
    @Test("a same-id request carrying a different proposal is refused")
    func approvalDecisionWithSubstitutedProposalIsRefused() {
        let registry = TrustedUIComponentRegistry()
        let rendered = approvalRequest(intent: "send 100 USDC")
        let substituted = ApprovalRequest(
            id: rendered.id,
            proposal: ActionProposal(
                actor: .human,
                intent: "send 5000 USDC",
                capability: .approveSpending,
                impact: .highRisk,
                parameters: ["amount": "5000"]
            ),
            prompt: rendered.prompt
        )
        var dispatched: [ApprovalRequest] = []

        registry.performApprovalDecision(
            rendered: rendered,
            dispatched: substituted,
            outcome: .approved
        ) { request, _ in dispatched.append(request) }

        #expect(substituted.id == rendered.id)
        #expect(dispatched.isEmpty)
    }

    /// A denial or a deferral is as much a decision about a specific proposal as an approval is;
    /// losing the binding on the refusal path means a block gets recorded against the wrong action.
    @Test("every outcome keeps its request", arguments: [
        TrustedUIApprovalOutcome.approved,
        .denied(reason: "wrong address"),
        .deferred
    ])
    func everyOutcomeKeepsItsRequest(outcome: TrustedUIApprovalOutcome) {
        let registry = TrustedUIComponentRegistry()
        let rendered = approvalRequest(intent: "send 100 USDC")
        var dispatched: [(ApprovalRequest, TrustedUIApprovalOutcome)] = []

        registry.performApprovalDecision(
            rendered: rendered,
            dispatched: rendered,
            outcome: outcome
        ) { dispatched.append(($0, $1)) }

        #expect(dispatched.map(\.0) == [rendered])
        #expect(dispatched.first?.1 == outcome)
    }
}

/// `DraftEditorCard` holds its editable body in `@State`, which SwiftUI preserves when the card keeps
/// its structural position across a change of `summary` — an inbox moving the next draft into the slot
/// the previous one vacated. The body was a bare `String`, so it could not tell whose text it held:
/// the card showed draft B's title over draft A's body, and "Save draft" sent A's text to be stored
/// under B's id. `performDraftCommit`'s `draftResolver(B) != nil` guard passes, because B does exist.
@Suite("Draft edits never commit under another draft's id")
struct DraftEditingBufferTests {

    private let first = TrustedUIDraftSummary(id: UUID(), title: "Draft A", body: "alpha")
    private let second = TrustedUIDraftSummary(id: UUID(), title: "Draft B", body: "beta")

    @Test("the buffer loads the draft it was built from")
    func bufferLoadsItsDraft() {
        let buffer = DraftEditingBuffer(first)

        #expect(buffer.draftID == first.id)
        #expect(buffer.text == first.body)
        #expect(buffer.committedText(for: first) == "alpha")
    }

    /// The swap. Edits made to A are discarded when B arrives, because they are not B's.
    @Test("a swap to another draft adopts that draft's body and drops the previous edits")
    func swapAdoptsTheNewDraft() {
        var buffer = DraftEditingBuffer(first)
        buffer.text = "alpha, edited but never saved"

        buffer.retarget(to: second)

        #expect(buffer.draftID == second.id)
        #expect(buffer.text == second.body)
        #expect(buffer.committedText(for: second) == "beta")
        #expect(!buffer.text.contains("alpha"))
    }

    /// The same update path fires whenever anything about the card changes, so re-pointing at the
    /// draft already loaded must be a no-op — reloading the stored body there would silently throw
    /// away whatever the person had typed.
    @Test("re-pointing at the same draft keeps the edits in progress")
    func sameDraftKeepsEdits() {
        var buffer = DraftEditingBuffer(first)
        buffer.text = "alpha, half typed"

        buffer.retarget(to: first)

        #expect(buffer.text == "alpha, half typed")
        #expect(buffer.committedText(for: first) == "alpha, half typed")
    }

    /// Defence in depth for the commit itself: if a buffer somehow reaches the button still holding
    /// the previous draft, the text committed is the new draft's own stored body — a no-op write —
    /// never the other draft's.
    @Test("committing against a draft the buffer does not hold returns that draft's own body")
    func commitNeverLeaksAnotherDraftsText() {
        var buffer = DraftEditingBuffer(first)
        buffer.text = "alpha, edited"

        #expect(buffer.committedText(for: second) == second.body)
        #expect(buffer.committedText(for: second) != "alpha, edited")
    }

    /// Two drafts that happen to share a title and body are still two drafts; identity is the id.
    @Test("identity is the draft id, not the text it happens to hold")
    func identityIsTheIDNotTheText() {
        let twin = TrustedUIDraftSummary(id: UUID(), title: first.title, body: first.body)
        var buffer = DraftEditingBuffer(first)
        buffer.text = "alpha, edited"

        buffer.retarget(to: twin)

        #expect(buffer.draftID == twin.id)
        #expect(buffer.text == twin.body)
    }
}

@Suite("Trusted UI value semantics")
struct TrustedUIValueTests {

    @Test("approval submission gate accepts exactly one decision per request")
    func approvalSubmissionIsSingleShot() {
        let request = UUID()
        var gate = ApprovalSubmissionGate()

        let firstClaim = gate.claimSubmission(for: request, outcome: .approved)
        let secondClaim = gate.claimSubmission(for: request, outcome: .denied(reason: "changed my mind"))

        #expect(firstClaim)
        #expect(!secondClaim)
        #expect(gate.hasSubmitted(for: request))
        // The losing claim must not overwrite the decision that was actually dispatched.
        #expect(gate.submittedOutcome(for: request) == .approved)
    }

    /// `ApprovalSheet` holds this gate in `@State`, which SwiftUI preserves when the sheet keeps its
    /// structural position across a change of `request` — an approval queue swapping the next
    /// escalation into the slot the previous one vacated. An unkeyed latch stayed closed, leaving a
    /// pending proposal rendered with every button disabled under a notice describing the previous
    /// proposal's decision.
    @Test("a decision on one request leaves the next request undecided and actionable")
    func gateDoesNotLatchAcrossRequests() {
        let decided = UUID()
        let pending = UUID()
        var gate = ApprovalSubmissionGate()

        let firstClaim = gate.claimSubmission(for: decided, outcome: .approved)

        #expect(firstClaim)
        #expect(gate.hasSubmitted(for: decided))
        #expect(!gate.hasSubmitted(for: pending))
        #expect(gate.submittedOutcome(for: pending) == nil)
        // The new request can still be decided, and decided differently.
        let secondClaim = gate.claimSubmission(for: pending, outcome: .denied(reason: "no"))
        #expect(secondClaim)
        #expect(gate.submittedOutcome(for: pending) == .denied(reason: "no"))
    }

    @Test("the gate reports back the outcome it dispatched", arguments: [
        TrustedUIApprovalOutcome.approved,
        .denied(reason: "not now"),
        .deferred
    ])
    func gateRecordsOutcome(outcome: TrustedUIApprovalOutcome) {
        let request = UUID()
        var gate = ApprovalSubmissionGate()

        let claimed = gate.claimSubmission(for: request, outcome: outcome)

        #expect(claimed)
        #expect(gate.submittedOutcome(for: request) == outcome)
    }

    /// `.deferred` is documented as *not* a verdict — the request stays pending. The sheet renders
    /// its notice from the recorded outcome, so deferring must stay distinguishable from deciding;
    /// every outcome previously rendered the same "Decision submitted" line.
    @Test("deferring is recorded as a deferral, not as a verdict")
    func deferralIsNotAVerdict() {
        let request = UUID()
        var gate = ApprovalSubmissionGate()

        let claimed = gate.claimSubmission(for: request, outcome: .deferred)

        #expect(claimed)
        let recorded = gate.submittedOutcome(for: request)
        #expect(recorded == .deferred)
        #expect(recorded != .approved)
        #expect(recorded?.judgeDecision == nil)
    }

    @Test("an untouched gate reports nothing submitted for any request")
    func untouchedGateIsOpen() {
        let gate = ApprovalSubmissionGate()

        #expect(!gate.hasSubmitted(for: UUID()))
        #expect(gate.submittedOutcome(for: UUID()) == nil)
    }

    @Test("risk level derives from impact class", arguments: [
        (ActionImpactClass.readOnly, TrustedUIRiskLevel.informational),
        (.reversibleWrite, .low),
        (.externalImpact, .medium),
        (.highRisk, .high)
    ])
    func riskLevelFromImpact(impact: ActionImpactClass, expected: TrustedUIRiskLevel) {
        #expect(TrustedUIRiskLevel(impact: impact) == expected)
    }

    @Test("approval outcome maps onto the governance verdict")
    func approvalOutcomeToJudgeDecision() {
        #expect(TrustedUIApprovalOutcome.approved.judgeDecision == .allow)
        #expect(TrustedUIApprovalOutcome.denied(reason: "no").judgeDecision == .block(reason: "no"))
        // Deferred is not a verdict — the request stays pending.
        #expect(TrustedUIApprovalOutcome.deferred.judgeDecision == nil)
    }

    /// The approval sheet is where a person decides, so it must say *what kind of party* is asking.
    /// Its actor row used to return `displayName` alone whenever there was one, so a scheduled
    /// routine that happened to be named "Me" rendered as `Actor: Me` — and the receipt written
    /// afterwards was better attributed than the decision it recorded.
    @Test("the actor row never drops the actor kind, even for a routine named like a person")
    func actorRowKeepsKindForDeceptivelyNamedRoutine() {
        let impersonating = ActorRef(
            kind: .scheduledRoutine,
            identifier: "routine.nightly",
            displayName: "Me"
        )

        let label = ApprovalSheet.actorLabel(impersonating)

        #expect(label != "Me")
        #expect(label == "Scheduled routine — Me")
        // Delegation, not a second local implementation: the drift between this surface and the
        // receipt row is the defect, so the two must share one formatter.
        #expect(label == impersonating.attributionLabel)
    }

    @Test("an actor with no name at all reads as its kind alone")
    func unnamedActorReadsAsKind() {
        #expect(ApprovalSheet.actorLabel(ActorRef(kind: .human)) == "Human")
        #expect(ApprovalSheet.actorLabel(ActorRef(kind: .operatorAgent, identifier: "op.brief")) == "Operator — op.brief")
    }

    @Test("context redaction hides sensitive values and passes others through")
    func contextRedaction() {
        let sensitive = ContextField(key: "seed", stringValue: "abc", dataClass: .sensitive)
        let publicField = ContextField(key: "addr", stringValue: "0x1", dataClass: .publicIdentifier)
        let missing = ContextField(key: "x", stringValue: nil, dataClass: .derived)

        #expect(TrustedUIContextRedaction.displayValue(sensitive) == TrustedUIContextRedaction.redactedPlaceholder)
        #expect(TrustedUIContextRedaction.displayValue(publicField) == "0x1")
        #expect(TrustedUIContextRedaction.displayValue(missing) == "—")
    }
}
