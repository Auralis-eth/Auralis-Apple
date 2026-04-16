import SwiftUI

struct ReceiptPayloadNestedHeader: View {
    let label: String
    let depth: Int
    let kind: String

    var body: some View {
        HStack(spacing: 8) {
            Text(label)
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color.textSecondary)

            Text(kind)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(Color.textSecondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.white.opacity(0.08), in: Capsule())
        }
        .padding(.leading, CGFloat(depth) * 6)
    }
}
