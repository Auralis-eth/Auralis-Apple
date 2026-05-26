import SwiftUI
import AuraUI

struct HomeReceiptPreviewRow: View {
    let item: HomeRecentActivityPreviewItem

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            AuraPill(
                item.statusTitle,
                systemImage: item.isSuccess ? "checkmark.circle.fill" : "xmark.octagon.fill",
                emphasis: item.isSuccess ? .success : .accent
            )
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                Text(item.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.textPrimary)
                    .multilineTextAlignment(.leading)

                Text(item.detailLine)
                    .font(.caption)
                    .foregroundStyle(Color.textSecondary)
                    .multilineTextAlignment(.leading)

                Text(item.contextLine)
                    .font(.caption)
                    .foregroundStyle(Color.textSecondary)
                    .multilineTextAlignment(.leading)
            }

            Spacer(minLength: 8)

            SystemImage("chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color.textSecondary)
                .accessibilityHidden(true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .auraAccessibleSummary(
            label: item.title,
            value: accessibilityValue,
            hint: String(localized: "Shows receipt details")
        )
    }

    private var accessibilityValue: String {
        [
            item.statusTitle,
            item.detailLine,
            item.contextLine
        ].joined(separator: ". ")
    }
}
