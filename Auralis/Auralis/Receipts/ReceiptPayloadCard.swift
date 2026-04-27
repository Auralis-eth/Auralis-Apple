import SwiftUI

struct ReceiptPayloadCard: View {
    let payload: ReceiptPayload

    var body: some View {
        AuraSurfaceCard(style: .regular, cornerRadius: 24, padding: 18) {
            VStack(alignment: .leading, spacing: 12) {
                Text("Payload")
                    .font(.headline)
                    .foregroundStyle(Color.textPrimary)

                if payload.values.isEmpty {
                    Text("No sanitized payload values were recorded for this receipt.")
                        .font(.subheadline)
                        .foregroundStyle(Color.textSecondary)
                } else {
                    ReceiptPayloadObjectView(values: payload.values, depth: 0)
                }
            }
        }
    }
}
