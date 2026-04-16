import SwiftUI

struct ReceiptDetailFact: View {
    let label: String
    let value: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text(label)
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color.textSecondary)
                .frame(width: 92, alignment: .leading)

            Text(value)
                .font(.subheadline)
                .foregroundStyle(Color.textPrimary)
                .textSelection(.enabled)

            Spacer(minLength: 0)
        }
    }
}
