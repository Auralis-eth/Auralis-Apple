import SwiftUI
import AuraUI

struct ReceiptDetailFact: View {
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            labelView
            valueView
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityValue(value)
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .topLeading)
        .contentShape(Rectangle())
    }

    private var labelView: some View {
        Text(label)
            .font(.body)
            .fontWeight(.semibold)
            .foregroundStyle(Color.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityHidden(true)
    }

    private var valueView: some View {
        Text(value)
            .font(.body)
            .foregroundStyle(Color.textPrimary)
            .textSelection(.enabled)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityHidden(true)
    }
}
