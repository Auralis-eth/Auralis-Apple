struct ReceiptTimelineSnapshot: Equatable {
    let visibleRecords: [ReceiptTimelineRecord]
    let filteredCount: Int
    let totalCount: Int
    let availableScopes: [String]
    let hasMore: Bool

    static let empty = ReceiptTimelineSnapshot(
        visibleRecords: [],
        filteredCount: 0,
        totalCount: 0,
        availableScopes: [],
        hasMore: false
    )
}
