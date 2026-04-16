import SwiftUI

struct ReceiptRelatedReceiptsCard: View {
    let receipts: [ReceiptTimelineRecord]

    var body: some View {
        AuraSurfaceCard(style: .regular, cornerRadius: 24, padding: 18) {
            VStack(alignment: .leading, spacing: 12) {
                Text("Related Receipts")
                    .font(.headline)
                    .foregroundStyle(Color.textPrimary)

                ForEach(receipts) { receipt in
                    NavigationLink(value: ReceiptRoute(id: receipt.id.uuidString)) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(receipt.summary)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(Color.textPrimary)

                            Text("\(receipt.trigger) • \(receipt.createdAt.formatted(date: .omitted, time: .shortened))")
                                .font(.caption)
                                .foregroundStyle(Color.textSecondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}
