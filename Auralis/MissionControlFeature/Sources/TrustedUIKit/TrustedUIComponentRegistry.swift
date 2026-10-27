import AuralisFoundation
import Foundation
import RuntimeCore
import SwiftUI

/// The governed registry of trusted UI components (P0.5-502).
///
/// Operator packs and workflows cannot render arbitrary UI — they can only ask for a
/// ``TrustedUIRequest``. This registry is the single sanctioned factory that turns a request into a
/// concrete, app-owned component. The mapping from request → component is a *closed* switch, so the
/// set of renderable surfaces is fixed and auditable; there is no path for caller-supplied views.
///
/// Id-referenced requests (`reviewReceipt`, `editDraft`) are hydrated through resolvers the presenting
/// layer injects, which keeps this package free of the receipt/storage graph.
public struct TrustedUIComponentRegistry: Sendable {

    /// The fixed catalog of trusted components. Nothing outside this set can be produced.
    public enum ComponentKind: String, CaseIterable, Sendable {
        case permissionCard
        case suggestionCard
        case approvalSheet
        case receiptCard
        case riskBanner
        case contextBundleCard
        case draftEditor
    }

    public typealias ReceiptResolver = @Sendable (UUID) -> TrustedUIReceiptSummary?
    public typealias DraftResolver = @Sendable (UUID) -> TrustedUIDraftSummary?
    public typealias LeaseResolver = @Sendable (CapabilityID) -> CapabilityLease?

    private let receiptResolver: ReceiptResolver
    private let draftResolver: DraftResolver
    private let leaseResolver: LeaseResolver

    public init(
        receiptResolver: @escaping ReceiptResolver = { _ in nil },
        draftResolver: @escaping DraftResolver = { _ in nil },
        leaseResolver: @escaping LeaseResolver = { _ in nil }
    ) {
        self.receiptResolver = receiptResolver
        self.draftResolver = draftResolver
        self.leaseResolver = leaseResolver
    }

    // MARK: - Catalog

    /// Human-readable descriptor for every component in the catalog.
    public static let catalog: [TrustedUIComponentDescriptor] = [
        .init(kind: .permissionCard, title: "Permission Card", purpose: "Describe a capability to inspect or grant."),
        .init(kind: .suggestionCard, title: "Suggestion Card", purpose: "Present a proactive, non-blocking suggestion."),
        .init(kind: .approvalSheet, title: "Approval Sheet", purpose: "Collect a human decision on an action proposal."),
        .init(kind: .receiptCard, title: "Receipt Card", purpose: "Render a resolved, sanitized receipt summary."),
        .init(kind: .riskBanner, title: "Risk Banner", purpose: "Communicate the blast radius of an action."),
        .init(kind: .contextBundleCard, title: "Context Bundle Card", purpose: "Make governed context visible."),
        .init(kind: .draftEditor, title: "Draft Editor", purpose: "Edit a resolved draft before it proceeds.")
    ]

    /// The component a given request resolves to. Pure and total over ``TrustedUIRequest`` — the
    /// governance guarantee lives here.
    public func componentKind(for request: TrustedUIRequest) -> ComponentKind {
        switch request {
        case .approveAction: return .approvalSheet
        case .editDraft: return .draftEditor
        case .inspectCapability: return .permissionCard
        case .reviewReceipt: return .receiptCard
        case .inspectContextBundle: return .contextBundleCard
        case .presentSuggestion: return .suggestionCard
        case .presentRiskBanner: return .riskBanner
        }
    }

    // MARK: - Resolution (pure, testable)

    public func receiptSummary(for id: UUID) -> TrustedUIReceiptSummary? { receiptResolver(id) }
    public func draftSummary(for id: UUID) -> TrustedUIDraftSummary? { draftResolver(id) }
    public func isResolvable(_ request: TrustedUIRequest) -> Bool {
        switch request {
        case .editDraft(let id): return draftResolver(id) != nil
        case .reviewReceipt(let id): return receiptResolver(id) != nil
        default: return true
        }
    }

    public func performDraftCommit(
        proposalID: UUID,
        body: String,
        handler: (UUID, String) -> Void
    ) {
        guard draftResolver(proposalID) != nil else { return }
        handler(proposalID, body)
    }

    /// Re-asserts, before dispatching, that the decision came from the request this factory actually
    /// rendered — the approval analogue of ``performDraftCommit(proposalID:body:handler:)``
    /// re-resolving its id.
    ///
    /// An approval is an authority token, not a preference: `ApprovalRegistry.consume(_:)` demands
    /// an exact match against the request it registered. ``ApprovalSheet`` holds `request` and now
    /// names it when dispatching, so the two sides of this comparison come from different places —
    /// the request the factory was asked to render, and the request the sheet says it decided. They
    /// can only disagree if a stale sheet outlived the request that produced it, and that is the one
    /// case where silently forwarding the outcome would attribute an approval given for one proposal
    /// to another.
    ///
    /// Compared whole rather than by `id`: identity equality would accept a request whose proposal
    /// had been altered underneath the same id, which is precisely the substitution the registry is
    /// here to refuse.
    public func performApprovalDecision(
        rendered: ApprovalRequest,
        dispatched: ApprovalRequest,
        outcome: TrustedUIApprovalOutcome,
        handler: (ApprovalRequest, TrustedUIApprovalOutcome) -> Void
    ) {
        guard rendered == dispatched else {
            return
        }

        handler(dispatched, outcome)
    }

    public func performSuggestionAction(
        suggestion: TrustedUISuggestion,
        handler: (UUID) -> Void
    ) {
        guard suggestion.actionLabel != nil else { return }
        handler(suggestion.id)
    }

    /// The explicit SwiftUI identity ``view(for:onApprovalDecision:onDraftCommit:onSuggestionAction:)``
    /// stamps on the component it produces, or `nil` for the components that hold no local state and
    /// for which reuse is therefore harmless.
    ///
    /// SwiftUI reuses a view's `@State` whenever a new value arrives at the same structural position,
    /// and the two components that *do* hold state — ``ApprovalSheet``'s submission latch and
    /// ``DraftEditorCard``'s editing buffer — are both reached only through this factory, which until
    /// now attached no identity at all. A queue swapping its next item into the slot the previous one
    /// vacated therefore handed the new request to the previous request's state. Both components also
    /// key their state to an id, but that is a per-component mitigation; identity here makes the swap
    /// a fresh installation rather than an update, which is the structural fix.
    ///
    /// The draft editor is keyed to the *resolved* draft, not to the `proposalID` that addressed it:
    /// the resolver is what decides which draft a proposal id names, and the body on screen is the
    /// resolved draft's. The `proposalID` fallback only applies where nothing resolves, in which case
    /// no editor is produced at all.
    ///
    /// Must agree with what `view(for:)` stamps — that is what the test on this function pins.
    public func componentIdentity(for request: TrustedUIRequest) -> UUID? {
        switch request {
        case .approveAction(let approvalRequest):
            return approvalRequest.id
        case .editDraft(let proposalID):
            return draftResolver(proposalID)?.id ?? proposalID
        case .inspectCapability,
             .reviewReceipt,
             .inspectContextBundle,
             .presentSuggestion,
             .presentRiskBanner:
            return nil
        }
    }
    public func permissionModel(for capability: CapabilityID) -> PermissionCardModel {
        PermissionCardModel(capability: capability, lease: leaseResolver(capability))
    }

    // MARK: - View factory

    /// Produce the trusted component for a request. This is the only sanctioned way for the app to
    /// render a ``TrustedUIRequest``.
    ///
    /// `onApprovalDecision` is handed the request the decision was made about, matching the two
    /// lower-stakes callbacks beside it, which have always carried their id. See
    /// ``performApprovalDecision(rendered:dispatched:outcome:handler:)`` for why an unnamed approval
    /// is unsafe.
    ///
    /// The two stateful components are stamped with ``componentIdentity(for:)`` so a request or draft
    /// swapped into the same slot gets its own state rather than inheriting its predecessor's.
    ///
    /// `referenceDate` is presentation configuration, not part of the request schema: an operator pack
    /// hands the runtime a ``TrustedUIRequest`` and must not get to choose the clock a trusted surface
    /// measures freshness against. Left `nil` the components read the live wall clock; a caller
    /// rendering deterministically (snapshot tests, previews) pins it.
    @MainActor
    @ViewBuilder
    public func view(
        for request: TrustedUIRequest,
        referenceDate: Date? = nil,
        onApprovalDecision: @escaping (ApprovalRequest, TrustedUIApprovalOutcome) -> Void = { _, _ in },
        onDraftCommit: @escaping (UUID, String) -> Void = { _, _ in },
        onSuggestionAction: @escaping (UUID) -> Void = { _ in }
    ) -> some View {
        switch request {
        case .approveAction(let approvalRequest):
            ApprovalSheet(request: approvalRequest) { dispatched, outcome in
                performApprovalDecision(
                    rendered: approvalRequest,
                    dispatched: dispatched,
                    outcome: outcome,
                    handler: onApprovalDecision
                )
            }
            .id(componentIdentity(for: request))

        case .editDraft(let proposalID):
            if let draft = draftResolver(proposalID) {
                DraftEditorCard(summary: draft) {
                    performDraftCommit(proposalID: proposalID, body: $0, handler: onDraftCommit)
                }
                // `draft.id` rather than `componentIdentity(for: request)`, which would re-run the
                // caller-supplied resolver to arrive at the same value; the two are defined to agree.
                .id(draft.id)
            } else {
                TrustedUIUnavailableCard(message: "This draft is no longer available.")
            }

        case .inspectCapability(let capabilityID):
            PermissionCard(model: permissionModel(for: capabilityID))

        case .reviewReceipt(let receiptID):
            if let summary = receiptResolver(receiptID) {
                ReceiptCard(summary: summary)
            } else {
                TrustedUIUnavailableCard(message: "This receipt is no longer available.")
            }

        case .inspectContextBundle(let bundle):
            ContextBundleCard(bundle: bundle, referenceDate: referenceDate)

        case .presentSuggestion(let suggestion):
            let model = SuggestionCardModel(suggestion)
            SuggestionCard(
                model: model,
                onAction: model.actionLabel == nil ? nil : {
                    performSuggestionAction(suggestion: suggestion, handler: onSuggestionAction)
                }
            )

        case .presentRiskBanner(let impact):
            RiskBanner(impact: impact)
        }
    }
}
