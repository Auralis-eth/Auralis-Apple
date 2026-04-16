struct ReceiptTimelineSnapshot: Equatable {
    let visibleRecords: [ReceiptTimelineRecord]
    let filteredCount: Int
    let totalCount: Int
    let availableScopes: [String]
    let hasMore: Bool
}
