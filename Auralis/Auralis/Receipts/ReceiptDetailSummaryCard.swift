import SwiftUI

struct ReceiptDetailSummaryCard: View {
    let receipt: ReceiptTimelineRecord

    var body: some View {
        AuraSurfaceCard(style: .soft, cornerRadius: 24, padding: 18) {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(receipt.summary)
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(Color.textPrimary)

                        Text(receipt.trigger)
                            .font(.subheadline)
                            .foregroundStyle(Color.textSecondary)
                    }

                    Spacer(minLength: 12)

                    AuraPill(
                        receipt.statusTitle,
                        systemImage: receipt.isSuccess ? "checkmark.circle.fill" : "exclamationmark.triangle.fill",
                        emphasis: receipt.isSuccess ? .success : .accent
                    )
                }

                VStack(alignment: .leading, spacing: 10) {
                    ReceiptDetailFact(label: "Scope", value: receipt.scope)
                    ReceiptDetailFact(label: "Actor", value: receipt.actorTitle)
                    ReceiptDetailFact(label: "Mode", value: receipt.mode.rawValue)
                    ReceiptDetailFact(label: "Provenance", value: receipt.provenance)
                    ReceiptDetailFact(label: "Sequence", value: String(receipt.sequenceID))
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
}
