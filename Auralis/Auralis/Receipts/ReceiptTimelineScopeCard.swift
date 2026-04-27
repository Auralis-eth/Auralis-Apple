import SwiftUI

struct ReceiptTimelineScopeCard: View {
    let scope: ReceiptTimelineScope
    let totalCount: Int
    let filteredCount: Int
    let filterSummary: String
    let isUsingDefaultFilters: Bool

    var body: some View {
        AuraSurfaceCard(style: .soft, cornerRadius: 24, padding: 18) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Timeline")
                            .font(.headline)
                            .foregroundStyle(Color.textPrimary)

                        Text(scope.displayLabel)
                            .font(.subheadline)
                            .foregroundStyle(Color.textSecondary)
                    }

                    Spacer(minLength: 12)

                    AuraPill(
                        isUsingDefaultFilters ? "Default View" : "Filtered View",
                        systemImage: isUsingDefaultFilters ? "line.3.horizontal.decrease.circle" : "line.3.horizontal.decrease.circle.fill",
                        emphasis: isUsingDefaultFilters ? .neutral : .accent
                    )
                }

                Text("\(filteredCount) of \(totalCount) receipts visible")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.textSecondary)

                Text(filterSummary)
                    .font(.caption)
                    .foregroundStyle(Color.textSecondary)
            }
        }
    }
}
