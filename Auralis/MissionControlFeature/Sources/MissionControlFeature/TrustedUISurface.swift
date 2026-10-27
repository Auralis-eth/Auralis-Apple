import AuralisFoundation
import RuntimeCore
import SwiftUI
@_exported import TrustedUIKit

/// The governed entry point for presenting a ``TrustedUIRequest`` from Mission Control / the app.
///
/// The runtime and operator packs can only hand the app a ``TrustedUIRequest``; this view routes it
/// through the ``TrustedUIComponentRegistry`` (P0.5-502), which is the single sanctioned factory that
/// maps a request onto an app-owned trusted component. There is no path here for a caller to inject
/// arbitrary UI — the registry's request→component mapping is closed.
///
/// Re-exports `TrustedUIKit` so the app can build requests and resolver-backed registries without a
/// separate import.
public struct TrustedUISurface: View {
    private let request: TrustedUIRequest
    private let registry: TrustedUIComponentRegistry
    /// Carries the `ApprovalRequest` alongside the outcome, because the approval *is* the authority
    /// token: `ApprovalRegistry.consume(_:)` matches the whole request, so a caller presenting an
    /// inbox needs to know which proposal the decision belongs to rather than re-pairing it from
    /// presentation state.
    private let onApprovalDecision: (ApprovalRequest, TrustedUIApprovalOutcome) -> Void
    private let onDraftCommit: (UUID, String) -> Void
    private let onSuggestionAction: (UUID) -> Void
    /// Forwarded to the registry as presentation configuration. `nil` leaves the rendered components
    /// on the live wall clock; callers that must render deterministically pin it.
    private let referenceDate: Date?

    public init(
        request: TrustedUIRequest,
        registry: TrustedUIComponentRegistry,
        referenceDate: Date? = nil,
        onApprovalDecision: @escaping (ApprovalRequest, TrustedUIApprovalOutcome) -> Void = { _, _ in },
        onDraftCommit: @escaping (UUID, String) -> Void = { _, _ in },
        onSuggestionAction: @escaping (UUID) -> Void = { _ in }
    ) {
        self.request = request
        self.registry = registry
        self.referenceDate = referenceDate
        self.onApprovalDecision = onApprovalDecision
        self.onDraftCommit = onDraftCommit
        self.onSuggestionAction = onSuggestionAction
    }

    public var body: some View {
        registry.view(
            for: request,
            referenceDate: referenceDate,
            onApprovalDecision: onApprovalDecision,
            onDraftCommit: onDraftCommit,
            onSuggestionAction: onSuggestionAction
        )
    }
}

#if DEBUG
#Preview("Trusted components") {
    let proposal = ActionProposal(
        actor: .human,
        intent: "Approve token spending for the swap",
        capability: .approveSpending,
        impact: .highRisk,
        requiredApprovals: ["treasury"],
        requiredCheckIDs: ["address.format"]
    )
    let request = ApprovalRequest(proposal: proposal, prompt: "Approve this spending action?")
    let registry = TrustedUIComponentRegistry()

    return ScrollView {
        VStack(spacing: 16) {
            TrustedUISurface(request: .approveAction(request), registry: registry)
            RiskBanner(impact: .externalImpact)
            PermissionCard(capability: .signMessage)
            ReceiptCard(summary: TrustedUIReceiptSummary(
                id: UUID(), title: "Signed message", subtitle: "wallet • Success",
                actorLabel: "You", timestamp: .now,
                fields: [.init(key: "Mode", value: "operate"), .init(key: "Trigger", value: "manual")]
            ))
            ContextBundleCard(bundle: ContextBundle(fields: [
                ContextField(key: "address", stringValue: "0xabc…", dataClass: .publicIdentifier, source: .chainProvider, lastRefreshed: .now),
                ContextField(key: "seed", stringValue: "super-secret", dataClass: .sensitive)
            ]))
        }
        .padding()
    }
}
#endif
