import AuralisRuntime
import SwiftUI

/// A trusted component that communicates the blast radius of an action. Used standalone and inside
/// ``ApprovalSheet``. The color/label are derived from ``ActionImpactClass`` via ``TrustedUIRiskLevel``.
public struct RiskBanner: View {
    private let level: TrustedUIRiskLevel

    /// Deliberately **not** public: a caller outside this package holding an arbitrary
    /// ``TrustedUIRiskLevel`` could state any severity it liked, which is precisely the gap the
    /// capability floor closes on the other two initializers. The only legitimate use is inside the
    /// package, where the level has already been derived from a proposal — ``ApprovalSheet`` does
    /// exactly that. An app-layer caller has a proposal or an impact class, never a bare level.
    init(level: TrustedUIRiskLevel) {
        self.level = level
    }

    /// For the standalone banner, where the caller genuinely has only an impact class.
    ///
    /// No capability is available here, so no floor can be applied and the value is rendered as
    /// given. Prefer ``init(proposal:)`` whenever a proposal exists; this overload is honest only
    /// because `TrustedUIRequest.presentRiskBanner` carries an impact and nothing else.
    public init(impact: ActionImpactClass) {
        self.level = TrustedUIRiskLevel(impact: impact)
    }

    /// Preferred over ``init(impact:)`` whenever the caller holds the proposal: the proposal carries
    /// the capability, so the self-declared impact can be floored by what that capability makes
    /// possible instead of being rendered verbatim. See ``TrustedUIRiskLevel/init(proposal:)``.
    public init(proposal: ActionProposal) {
        self.level = TrustedUIRiskLevel(proposal: proposal)
    }

    public var body: some View {
        HStack(spacing: 8) {
            Image(systemName: iconName)
                .font(.footnote.weight(.semibold))
            Text(level.title)
                .font(.footnote.weight(.semibold))
            Spacer(minLength: 0)
        }
        .foregroundStyle(tint)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Risk level: \(level.title)")
        // `presentRiskBanner` renders this standalone, and inside `ApprovalSheet` it is the only
        // element stating blast radius. Without an identifier a UI test can assert that an approval
        // was *offered* but not that it was offered as high risk — the assertion that matters.
        .accessibilityIdentifier(TrustedUIA11yID.riskBanner)
    }

    private var tint: Color {
        switch level {
        case .informational: return .secondary
        case .low: return .green
        case .medium: return .orange
        case .high: return .red
        }
    }

    private var iconName: String {
        switch level {
        case .informational: return "info.circle"
        case .low: return "checkmark.shield"
        case .medium: return "exclamationmark.triangle"
        case .high: return "exclamationmark.octagon"
        }
    }
}
