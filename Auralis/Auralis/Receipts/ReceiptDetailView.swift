import SwiftData
import SwiftUI

struct ReceiptDetailView: View {
    let route: ReceiptRoute
    let scope: ReceiptTimelineScope

    @Query(
        sort: [
            SortDescriptor(\StoredReceipt.createdAt, order: .reverse),
            SortDescriptor(\StoredReceipt.sequenceID, order: .reverse)
        ]
    ) private var storedReceipts: [StoredReceipt]

    private var records: [ReceiptTimelineRecord] {
        storedReceipts
            .map(ReceiptTimelineRecord.init)
            .filter { $0.matches(scope) }
    }

    private var receipt: ReceiptTimelineRecord? {
        guard let receiptID = UUID(uuidString: route.id) else {
            return nil
        }

        return records.first(where: { $0.id == receiptID })
    }

    private var relatedReceipts: [ReceiptTimelineRecord] {
        guard let correlationID = receipt?.correlationID, !correlationID.isEmpty else {
            return []
        }

        return records.filter {
            $0.correlationID == correlationID && $0.id != receipt?.id
        }
    }

    var body: some View {
        Group {
            if let receipt {
                AuraScenicScreen(horizontalPadding: 12, verticalPadding: 12) {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 16) {
                            ReceiptDetailSummaryCard(receipt: receipt)

                            if !relatedReceipts.isEmpty {
                                ReceiptRelatedReceiptsCard(receipts: relatedReceipts)
                            }

                            ReceiptPayloadCard(payload: receipt.details)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .accessibilityIdentifier("receipts.detail")
            } else {
                AuraScenicScreen(contentAlignment: .center) {
                    AuraEmptyState(
                        eyebrow: "Receipts",
                        title: "Receipt Unavailable",
                        message: "The requested receipt could not be found in local storage.",
                        systemImage: "doc.text.magnifyingglass"
                    )
                }
                .accessibilityIdentifier("receipts.detail.unavailable")
            }
        }
        .navigationTitle("Receipt")
        .navigationBarTitleDisplayMode(.inline)
    }
}
