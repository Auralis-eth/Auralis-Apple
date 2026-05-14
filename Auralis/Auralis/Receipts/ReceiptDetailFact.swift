import SwiftUI
import AuraUI

struct ReceiptDetailFact: View {
    let label: String
    let value: String
    @ScaledMetric(relativeTo: .body) private var labelColumnWidth = 92

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: 12) {
                labelView
                    .frame(minWidth: min(labelColumnWidth, 92), idealWidth: labelColumnWidth, maxWidth: labelColumnWidth, alignment: .leading)

                valueView

                Spacer(minLength: 0)
            }

            VStack(alignment: .leading, spacing: 6) {
                labelView
                valueView
            }
        }
    }

    private var labelView: some View {
        Text(label)
            .font(.caption.weight(.semibold))
            .foregroundStyle(Color.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var valueView: some View {
        Text(value)
            .font(.subheadline)
            .foregroundStyle(Color.textPrimary)
            .textSelection(.enabled)
            .fixedSize(horizontal: false, vertical: true)
    }
}
