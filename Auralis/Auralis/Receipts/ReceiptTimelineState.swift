struct ReceiptTimelineState: Equatable {
    static let allScopesValue = "all"
    static let pageSize = 25

    private(set) var scope: ReceiptTimelineScope
    var searchQuery: String = ""
    var statusFilter: ReceiptStatusFilter = .all
    var actorFilter: ReceiptActorFilter = .all
    var selectedScope: String = ReceiptTimelineState.allScopesValue
    private(set) var visibleLimit: Int = ReceiptTimelineState.pageSize

    init(scope: ReceiptTimelineScope) {
        self.scope = scope
    }

    mutating func applyScope(_ newScope: ReceiptTimelineScope) {
        guard scope != newScope else {
            return
        }

        scope = newScope
        clearFilters()
    }

    mutating func clearFilters() {
        searchQuery = ""
        statusFilter = .all
        actorFilter = .all
        selectedScope = Self.allScopesValue
        visibleLimit = Self.pageSize
    }

    mutating func resetPagination() {
        visibleLimit = Self.pageSize
    }

    mutating func loadNextPage() {
        visibleLimit += Self.pageSize
    }

    func snapshot(records: [ReceiptTimelineRecord]) -> ReceiptTimelineSnapshot {
        let scopedRecords = records.filter { $0.matches(scope) }
        let availableScopes = Array(Set(scopedRecords.map(\.scope))).sorted()
        let filtered = filteredRecords(from: scopedRecords)
        let visibleRecords = Array(filtered.prefix(visibleLimit))

        return ReceiptTimelineSnapshot(
            visibleRecords: visibleRecords,
            filteredCount: filtered.count,
            totalCount: scopedRecords.count,
            availableScopes: availableScopes,
            hasMore: filtered.count > visibleRecords.count
        )
    }

    var isUsingDefaultFilters: Bool {
        normalizedQuery.isEmpty
            && statusFilter == .all
            && actorFilter == .all
            && selectedScope == Self.allScopesValue
    }

    var filterSummary: String {
        [
            statusFilter.title,
            actorFilter.title,
            selectedScope == Self.allScopesValue ? "All Scopes" : selectedScope,
            normalizedQuery.isEmpty ? "No Search" : "Search: \(searchQuery)"
        ]
        .joined(separator: " • ")
    }

    private var normalizedQuery: String {
        searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private func filteredRecords(from records: [ReceiptTimelineRecord]) -> [ReceiptTimelineRecord] {
        records.filter { record in
            matches(record: record)
        }
    }

    private func matches(record: ReceiptTimelineRecord) -> Bool {
        if statusFilter == .success, !record.isSuccess {
            return false
        }

        if statusFilter == .failed, record.isSuccess {
            return false
        }

        if actorFilter == .user, record.actor != .user {
            return false
        }

        if actorFilter == .system, record.actor != .system {
            return false
        }

        if selectedScope != Self.allScopesValue, record.scope != selectedScope {
            return false
        }

        guard !normalizedQuery.isEmpty else {
            return true
        }

        return record.searchIndex.contains(normalizedQuery)
    }
}
