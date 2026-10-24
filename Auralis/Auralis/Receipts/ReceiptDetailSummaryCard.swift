import AuraUI
import SwiftUI

struct ReceiptDetailSummaryCard: View {
    let receipt: ReceiptTimelineRecord

    var body: some View {
        AuraSurfaceCard(style: .soft, cornerRadius: 24, padding: 18) {
            VStack(alignment: .leading, spacing: 16) {
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .top, spacing: 12) {
                        summaryDescription
                        Spacer(minLength: 12)
                        statusPill
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        summaryDescription
                        statusPill
                    }
                }

                VStack(alignment: .leading, spacing: 10) {
                    ReceiptDetailFact(label: "Scope", value: receipt.scope)
                    ReceiptDetailFact(label: "Actor", value: receipt.actorTitle)
                    // The "under what authority" leg (P0.5-602). Omitted rather than shown empty for
                    // receipts written before the column existed, so absence reads as "this predates
                    // the record" instead of "nothing authorized this".
                    if let authorityTitle = receipt.authorityTitle {
                        ReceiptDetailFact(label: "Authority", value: authorityTitle)
                    }
                    if let authorityReason = receipt.authorityReason {
                        ReceiptDetailFact(label: "Authority reason", value: authorityReason)
                    }
                    ReceiptDetailFact(label: "Mode", value: receipt.mode.rawValue)
                    ReceiptDetailFact(label: "Provenance", value: receipt.provenance)
                    ReceiptDetailFact(label: "Sequence", value: String(receipt.sequenceID))
                    ReceiptDetailFact(label: "Integrity", value: ReceiptIntegrityCopy.detailValue)
                    ReceiptDetailFact(
                        label: "Created",
                        value: receipt.createdAt.formatted(date: .abbreviated, time: .standard)
                    )

                    if let correlationID = receipt.correlationID, !correlationID.isEmpty {
                        ReceiptDetailFact(label: "Correlation ID", value: correlationID)
                    }
                }
            }
        }
    }

    private var summaryDescription: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(receipt.summary)
                .font(.title3)
                .fontWeight(.semibold)
                .foregroundStyle(Color.textPrimary)
                .lineLimit(nil)
                .fixedSize(horizontal: false, vertical: true)

            Text(receipt.triggerTitle)
                .font(.subheadline)
                .foregroundStyle(Color.textSecondary)
                .lineLimit(nil)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var statusPill: some View {
        AuraPill(
            receipt.statusTitle,
            systemImage: receipt.isSuccess ? "checkmark.circle.fill" : "exclamationmark.triangle.fill",
            emphasis: receipt.isSuccess ? .success : .accent
        )
    }
}
