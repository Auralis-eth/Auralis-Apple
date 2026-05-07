import AuralisPrimaryModels
import SwiftData
import SwiftUI

struct ReceiptDetailView: View {
    @Environment(\.modelContext) private var modelContext

    let route: ReceiptRoute
    let scope: ReceiptTimelineScope

    @State private var receipt: ReceiptTimelineRecord?
    @State private var relatedReceipts: [ReceiptTimelineRecord] = []

    private var detailTaskID: ReceiptDetailTaskID {
        ReceiptDetailTaskID(routeID: route.id, scope: scope)
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
        .task(id: detailTaskID) {
            reloadReceipts()
        }
    }

    private func reloadReceipts() {
        guard let receiptID = UUID(uuidString: route.id) else {
            receipt = nil
            relatedReceipts = []
            return
        }

        do {
            let storedReceipt = try modelContext.fetch(
                Self.makeReceiptDescriptor(receiptID: receiptID, scope: scope)
            ).first

            guard let storedReceipt else {
                receipt = nil
                relatedReceipts = []
                return
            }

            let timelineRecord = ReceiptTimelineRecord(storedReceipt: storedReceipt)
            receipt = timelineRecord
            relatedReceipts = try loadRelatedReceipts(for: timelineRecord)
        } catch {
            receipt = nil
            relatedReceipts = []
        }
    }

    private func loadRelatedReceipts(for receipt: ReceiptTimelineRecord) throws -> [ReceiptTimelineRecord] {
        guard let correlationID = receipt.correlationID, !correlationID.isEmpty else {
            return []
        }

        return try modelContext.fetch(
            Self.makeRelatedReceiptsDescriptor(
                correlationID: correlationID,
                excludingReceiptID: receipt.id,
                scope: scope
            )
        )
        .map(ReceiptTimelineRecord.init)
    }

    private static func makeReceiptDescriptor(
        receiptID: UUID,
        scope: ReceiptTimelineScope
    ) -> FetchDescriptor<StoredReceipt> {
        let normalizedAccountAddress = scope.accountAddress.extractedEthereumAddress?.lowercased()

        if let normalizedAccountAddress, !normalizedAccountAddress.isEmpty {
            return FetchDescriptor(
                predicate: #Predicate<StoredReceipt> { storedReceipt in
                    storedReceipt.id == receiptID
                        && storedReceipt.accountAddress == normalizedAccountAddress
                }
            )
        }

        return FetchDescriptor(
            predicate: #Predicate<StoredReceipt> { storedReceipt in
                storedReceipt.id == receiptID
            }
        )
    }

    private static func makeRelatedReceiptsDescriptor(
        correlationID: String,
        excludingReceiptID: UUID,
        scope: ReceiptTimelineScope
    ) -> FetchDescriptor<StoredReceipt> {
        let normalizedAccountAddress = scope.accountAddress.extractedEthereumAddress?.lowercased()

        if let normalizedAccountAddress, !normalizedAccountAddress.isEmpty {
            return FetchDescriptor(
                predicate: #Predicate<StoredReceipt> { storedReceipt in
                    storedReceipt.correlationID == correlationID
                        && storedReceipt.id != excludingReceiptID
                        && storedReceipt.accountAddress == normalizedAccountAddress
                },
                sortBy: [
                    SortDescriptor(\StoredReceipt.createdAt, order: .reverse),
                    SortDescriptor(\StoredReceipt.sequenceID, order: .reverse)
                ]
            )
        }

        return FetchDescriptor(
            predicate: #Predicate<StoredReceipt> { storedReceipt in
                storedReceipt.correlationID == correlationID
                    && storedReceipt.id != excludingReceiptID
            },
            sortBy: [
                SortDescriptor(\StoredReceipt.createdAt, order: .reverse),
                SortDescriptor(\StoredReceipt.sequenceID, order: .reverse)
            ]
        )
    }
}

private struct ReceiptDetailTaskID: Equatable {
    let routeID: String
    let scope: ReceiptTimelineScope
}
