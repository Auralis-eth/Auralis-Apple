import SwiftUI
import AuraUI
#if canImport(UIKit)
import UIKit
#endif

struct ReceiptTimelineRow: View {
    let record: ReceiptTimelineRecord

    @ViewBuilder
    var body: some View {
        let row = AuraSurfaceCard(style: .regular, cornerRadius: 24, padding: 18) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(record.summary)
                            .font(.headline)
                            .foregroundStyle(Color.textPrimary)

                        Text(record.trigger)
                            .font(.subheadline)
                            .foregroundStyle(Color.textSecondary)
                    }

                    Spacer(minLength: 12)

                    VStack(alignment: .trailing, spacing: 6) {
                        AuraPill(
                            record.statusTitle,
                            systemImage: record.isSuccess ? "checkmark.circle.fill" : "exclamationmark.triangle.fill",
                            emphasis: record.isSuccess ? .success : .accent
                        )

                        Text(record.createdAt, style: .relative)
                            .font(.caption)
                            .foregroundStyle(Color.textSecondary)
                    }
                }

                HStack(spacing: 8) {
                    AuraPill(record.scope, systemImage: "square.stack.3d.up")
                    AuraPill(record.actorTitle, systemImage: record.actor == .user ? "person.fill" : "gearshape.fill")

                    if let accountTitle = record.accountTitle {
                        AuraPill(accountTitle, systemImage: "person.crop.circle")
                    }

                    if let chainTitle = record.chainTitle {
                        AuraPill(chainTitle, systemImage: "link")
                    }

                    if let correlationID = record.correlationID, !correlationID.isEmpty {
                        AuraPill(
                            String(correlationID.prefix(8)),
                            systemImage: "link",
                            emphasis: .accent,
                            accessibilityLabel: "Correlation \(correlationID)"
                        )
                    }
                }

                Text(record.provenance)
                    .font(.caption)
                    .foregroundStyle(Color.textSecondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(record.summary)
        .accessibilityValue(accessibilityValue)
        .accessibilityHint(String(localized: "Shows receipt details"))

        if hasCopyableCorrelationID {
            row.accessibilityAction(named: String(localized: "Copy correlation ID")) {
                copyCorrelationID()
            }
        } else {
            row
        }
    }

    private var accessibilityValue: String {
        "\(record.statusTitle). \(record.trigger). \(record.scope). \(record.provenance)"
    }

    private var hasCopyableCorrelationID: Bool {
        guard let correlationID = record.correlationID else {
            return false
        }

        return !correlationID.isEmpty
    }

    private func copyCorrelationID() {
        guard let correlationID = record.correlationID, !correlationID.isEmpty else {
            return
        }

        #if canImport(UIKit)
        UIPasteboard.general.string = correlationID
        #endif
        AuraAccessibilityAnnouncer.announce("Correlation ID copied")
    }
}
