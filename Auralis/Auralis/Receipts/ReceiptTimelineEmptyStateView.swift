import SwiftUI

struct ReceiptTimelineEmptyStateView: View {
    let scope: ReceiptTimelineScope

    var body: some View {
        AuraEmptyState(
            eyebrow: "Receipts",
            title: "No Receipts Recorded Yet",
            message: "Auralis has not recorded any local activity for \(scope.displayLabel) on this device yet.",
            systemImage: "doc.text.magnifyingglass"
        )
    }
}
