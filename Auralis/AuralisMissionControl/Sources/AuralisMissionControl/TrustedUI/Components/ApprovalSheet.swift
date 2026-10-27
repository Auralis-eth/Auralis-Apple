import Foundation
import AuralisRuntime
import SwiftUI

/// A trusted component that presents an ``ApprovalRequest`` for a human decision. Shows the proposal's
/// intent, its risk (via ``RiskBanner``), the required approvals/checks, and the acting party — then
/// returns a ``TrustedUIApprovalOutcome``. The operator cannot alter the chrome or the actions.
public struct ApprovalSheet: View {
    private let request: ApprovalRequest
    private let onDecision: (ApprovalRequest, TrustedUIApprovalOutcome) -> Void
    @State private var submissionGate = ApprovalSubmissionGate()

    /// `onDecision` is handed the request the decision was made *about*, not the outcome alone.
    ///
    /// An approval is an authority token: `ApprovalRegistry.consume(_:)` demands an exact match
    /// against the request it registered, and ``TrustedUIApprovalOutcome/judgeDecision`` exists so
    /// callers can feed the verdict straight back into the Judge/Policy pipeline. Dispatching a bare
    /// `.approved` names nothing, so a caller holding a multi-item inbox had only its own notion of
    /// "the current request" to bind it to — and this sheet keys its own latch on `request.id`
    /// precisely because requests do swap beneath it. An approve given for proposal A could then be
    /// consumed against proposal B. The two lower-stakes callbacks on the same factory,
    /// `onDraftCommit` and `onSuggestionAction`, both already carry their id.
    public init(
        request: ApprovalRequest,
        onDecision: @escaping (ApprovalRequest, TrustedUIApprovalOutcome) -> Void
    ) {
        self.request = request
        self.onDecision = onDecision
    }

    private var proposal: ActionProposal { request.proposal }

    public var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Approval required")
                    .font(.title3.weight(.semibold))
                Text(request.prompt)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            RiskBanner(level: Self.riskLevel(for: proposal))

            VStack(alignment: .leading, spacing: 10) {
                detailRow(label: "Intent", value: proposal.intent)
                detailRow(label: "Capability", value: proposal.capability.rawValue)
                detailRow(label: "Actor", value: Self.actorLabel(proposal.actor))
                if !proposal.requiredApprovals.isEmpty {
                    detailRow(label: "Approvals", value: proposal.requiredApprovals.joined(separator: ", "))
                }
                if !proposal.requiredCheckIDs.isEmpty {
                    detailRow(label: "Checks", value: proposal.requiredCheckIDs.joined(separator: ", "))
                }
            }

            parameterSection

            ViewThatFits(in: .horizontal) {
                HStack(spacing: 12) {
                    decisionButtons
                }
                VStack(spacing: 12) {
                    decisionButtons
                }
            }
            if let outcome = submissionGate.submittedOutcome(for: request.id) {
                submissionNotice(for: outcome)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        // `.contain`, as on every other card in this package. An identifier placed on a container
        // that is not itself an accessibility element propagates to every descendant element that
        // lacks one, so the sheet's identifier was landing on the two header texts and all five
        // detail rows as well as the sheet — seven elements answering to
        // `trustedui.approval.surface`. A UI test resolving it got an arbitrary static text rather
        // than the surface, and Voice Control offered seven identically named targets.
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(TrustedUIA11yID.approvalSurface)
    }

    /// States *which* outcome was dispatched.
    ///
    /// Every outcome used to read "Decision submitted", including `.deferred` — which
    /// ``TrustedUIApprovalOutcome`` documents as explicitly not a verdict: "the request stays
    /// pending. There is no governance verdict yet." The surface therefore told a person who had
    /// chosen to decide later that their decision was in, and said so in the same words it used
    /// for a real approval.
    @ViewBuilder
    private func submissionNotice(for outcome: TrustedUIApprovalOutcome) -> some View {
        switch outcome {
        case .approved:
            submissionLabel("Approval submitted", symbol: "checkmark.circle")
        case .denied:
            submissionLabel("Denial submitted", symbol: "xmark.circle")
        case .deferred:
            submissionLabel("Deferred — no decision recorded", symbol: "clock")
        }
    }

    private func submissionLabel(_ title: String, symbol: String) -> some View {
        Label(title, systemImage: symbol)
            .font(.caption)
            .foregroundStyle(.secondary)
            .accessibilityIdentifier(TrustedUIA11yID.approvalSubmitted)
    }

    /// The parameters the action would execute against — the address, chain, and amount a person is
    /// actually authorising.
    ///
    /// Everything else on this sheet is either prose or a category. `intent` is free text written by
    /// the very actor being governed, and `capability` names a *kind* of action, not its target. The
    /// values execution and the deterministic checks consume live in `proposal.parameters`, and the
    /// sheet did not render them at all: a proposal with
    /// `intent: "Send 0.1 ETH to Alice"` and `parameters: ["address": "0xattacker…", "amount": "100"]`
    /// presented as nothing but its own sentence, and the person approved the sentence while the
    /// pipeline executed the parameters.
    ///
    /// Every entry is shown, sorted by key and uncut. Filtering by an allowlist of "interesting"
    /// keys is how a parameter that matters goes missing, and truncating a value is how the tail of
    /// an address disappears — both reintroduce the defect in a quieter form.
    @ViewBuilder
    private var parameterSection: some View {
        let parameters = Self.parameterRows(proposal)
        VStack(alignment: .leading, spacing: 10) {
            detailLabel("This authorises")
            if parameters.isEmpty {
                Text("No parameters — this action names no target.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(parameters) { row in
                    detailRow(label: row.id, value: row.value)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(TrustedUIA11yID.approvalParameters)
    }

    private func detailRow(label: String, value: String) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .firstTextBaseline) {
                detailLabel(label)
                    .frame(minWidth: 90, alignment: .leading)
                Text(value)
                    .font(.subheadline)
                Spacer(minLength: 0)
            }
            VStack(alignment: .leading, spacing: 2) {
                detailLabel(label)
                Text(value)
                    .font(.subheadline)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        // Combined so VoiceOver reads "Capability, policy.approveSpending" as one element, matching
        // `RiskBanner`, `PermissionCard`, and `SuggestionCard`. Left uncombined, the five rows of the
        // app's highest-stakes trust surface become ten separate stops with each value detached from
        // the label that says what it is — the reading order a person relies on to know what they are
        // approving.
        .accessibilityElement(children: .combine)
    }

    private func detailLabel(_ label: String) -> some View {
        Text(label)
            .font(.caption)
            .foregroundStyle(.secondary)
    }

    @ViewBuilder
    private var decisionButtons: some View {
        decisionButton("Deny", outcome: .denied(reason: "Denied by user"), role: .destructive)
            .buttonStyle(.bordered)
            .accessibilityIdentifier(TrustedUIA11yID.approvalDeny)

        decisionButton("Defer", outcome: .deferred)
            .buttonStyle(.bordered)
            .accessibilityIdentifier(TrustedUIA11yID.approvalDefer)

        decisionButton("Approve", outcome: .approved)
            .buttonStyle(.borderedProminent)
            .accessibilityIdentifier(TrustedUIA11yID.approvalApprove)
    }

    private func decisionButton(
        _ title: String,
        outcome: TrustedUIApprovalOutcome,
        role: ButtonRole? = nil
    ) -> some View {
        Button(title, role: role) {
            submit(outcome)
        }
        .frame(maxWidth: .infinity, minHeight: 44)
        .disabled(submissionGate.hasSubmitted(for: request.id))
    }

    /// Dispatches the decision together with the request it was rendered for. The gate is claimed
    /// against the same `request.id`, so the request named here is by construction the one the body
    /// above described.
    private func submit(_ outcome: TrustedUIApprovalOutcome) {
        guard submissionGate.claimSubmission(for: request.id, outcome: outcome) else { return }
        onDecision(request, outcome)
    }

    /// One parameter as rendered. `id` is the parameter key, which is unique by construction —
    /// `ActionProposal.parameters` is a dictionary.
    /// `nonisolated` because it is pure value data, not view state. `ApprovalSheet` is a `View` and
    /// therefore `@MainActor`, and a nested type inherits that isolation — so handing one of these
    /// back to a non-isolated caller crosses an isolation boundary with a non-`Sendable` value,
    /// which traps at runtime rather than failing to compile.
    nonisolated struct ParameterRow: Identifiable, Equatable {
        let id: String
        let value: String
    }

    /// Every parameter, key-sorted, verbatim.
    ///
    /// Internal rather than private so a test can pin the two properties that make this section
    /// worth anything — that nothing is filtered out and nothing is shortened — without rendering
    /// the view. A later "tidy up the noisy keys" change is exactly the regression to catch.
    nonisolated static func parameterRows(_ proposal: ActionProposal) -> [ParameterRow] {
        proposal.parameters
            .map { ParameterRow(id: $0.key, value: $0.value) }
            .sorted { $0.id < $1.id }
    }

    /// The severity the sheet's ``RiskBanner`` shows — the proposal's declared impact raised to its
    /// capability's floor, never the declaration verbatim.
    ///
    /// This surface used to pass `proposal.impact` straight through, so a proposal naming
    /// `approveSpending` and declaring `.readOnly` presented a funds-affecting approval under a grey
    /// "Read-only" banner. Internal rather than private so a test can pin the floor on the exact
    /// value the banner renders: "``TrustedUIRiskLevel`` can floor" and "the sheet asks it to" are
    /// separate facts, and the defect was the second one.
    nonisolated static func riskLevel(for proposal: ActionProposal) -> TrustedUIRiskLevel {
        TrustedUIRiskLevel(proposal: proposal)
    }

    /// Always renders the actor's *kind* alongside its name, via `ActorRef.attributionLabel`.
    ///
    /// This used to return `displayName` on its own whenever there was one, which dropped the kind
    /// on exactly the refs that carry a name — so an automated routine named "Me" rendered as
    /// `Actor: Me` on the highest-stakes trust surface in the app. The receipt written *after* the
    /// decision was better attributed than the decision point, because `ReceiptAttributionDisplay`
    /// had always kept the kind. Both now go through the same formatter.
    /// Internal rather than private so a test can pin that this surface routes through the shared
    /// formatter. The defect it replaced was a local reimplementation that drifted from the one the
    /// receipt row used, so "it delegates" is the property worth asserting.
    static func actorLabel(_ actor: ActorRef) -> String {
        actor.attributionLabel
    }
}

/// A value-type latch that keeps an approval surface single-shot even when several taps arrive
/// before its presenting view disappears.
///
/// The latch is keyed to the *request* it was claimed for, and remembers the outcome.
///
/// It used to be a bare `Bool`. `ApprovalSheet` holds this in `@State`, and SwiftUI keeps `@State`
/// alive across a change of `request` whenever the sheet stays in the same structural position —
/// which is precisely what an approval queue does when it swaps the next escalation into the slot
/// the previous one just vacated. The unkeyed latch stayed closed across that swap, so the second
/// proposal rendered its own prompt and parameters with all three buttons disabled beneath a
/// "Decision submitted" line that described the *first* proposal: a still-pending approval that
/// could not be acted on and falsely reported itself as already decided.
struct ApprovalSubmissionGate {
    private struct Submission: Equatable {
        let requestID: UUID
        let outcome: TrustedUIApprovalOutcome
    }

    private var submission: Submission?

    /// Whether a decision has already been dispatched *for this request*.
    func hasSubmitted(for requestID: UUID) -> Bool {
        submission?.requestID == requestID
    }

    /// The outcome already dispatched for this request, or `nil` if it is still undecided.
    func submittedOutcome(for requestID: UUID) -> TrustedUIApprovalOutcome? {
        guard let submission, submission.requestID == requestID else { return nil }
        return submission.outcome
    }

    /// Claims the one dispatch allowed for `requestID`. Returns `false` if it was already claimed.
    mutating func claimSubmission(for requestID: UUID, outcome: TrustedUIApprovalOutcome) -> Bool {
        guard !hasSubmitted(for: requestID) else { return false }
        submission = Submission(requestID: requestID, outcome: outcome)
        return true
    }
}
