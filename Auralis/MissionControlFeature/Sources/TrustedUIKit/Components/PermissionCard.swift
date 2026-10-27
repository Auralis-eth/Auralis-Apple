import AuralisFoundation
import RuntimeCore
import SwiftUI

/// A trusted component that describes a capability the runtime wants to inspect or grant. Renders the
/// canonical capability metadata plus any live lease. Renders no arbitrary operator-supplied content.
public struct PermissionCard: View {
    private let model: PermissionCardModel

    public init(model: PermissionCardModel) {
        self.model = model
    }

    public init(capability: CapabilityID, lease: CapabilityLease? = nil) {
        self.model = PermissionCardModel(capability: capability, lease: lease)
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "lock.shield")
                    .foregroundStyle(.tint)
                Text(model.title)
                    .font(.headline)
                Spacer(minLength: 0)
                Text(model.category)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Text(model.summary)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            if let leaseSummary = model.leaseSummary, let status = model.leaseStatus {
                leaseRow(leaseSummary, status: status)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        // `.contain`, not `.combine`. A combined root merges its children into one element and
        // discards their identifiers, so the lease row — the only part of this card that says
        // whether authority is live — would have no handle for a UI test to assert on, and the
        // whole card would read as a single undifferentiated blob of text.
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(TrustedUIA11yID.permissionCard)
    }

    /// States the lease's standing in words and in the symbol, never in the tint alone.
    private func leaseRow(_ summary: String, status: PermissionLeaseStatus) -> some View {
        Label("\(Self.statusTitle(status)) · \(summary)", systemImage: Self.statusSymbol(status))
            .font(.caption)
            .foregroundStyle(status.authorizesNow ? AnyShapeStyle(.secondary) : AnyShapeStyle(.red))
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Lease \(Self.statusTitle(status)). \(summary)")
            .accessibilityIdentifier(TrustedUIA11yID.permissionLease)
    }

    private static func statusTitle(_ status: PermissionLeaseStatus) -> String {
        switch status {
        case .granted: return "Granted"
        case .revoked: return "Revoked"
        case .expired: return "Expired"
        case .scheduled: return "Not yet active"
        }
    }

    private static func statusSymbol(_ status: PermissionLeaseStatus) -> String {
        switch status {
        case .granted: return "clock.arrow.circlepath"
        case .revoked: return "xmark.shield"
        case .expired: return "clock.badge.xmark"
        case .scheduled: return "clock.badge.questionmark"
        }
    }
}
