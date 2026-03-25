import Foundation
import SwiftUI
import SwiftData

struct ReceiptTimelineScope: Equatable, Sendable {
    let accountAddress: String
    let chain: Chain

    var displayLabel: String {
        let addressLabel = accountAddress.isEmpty ? "No active account" : accountAddress.displayAddress
        return "\(addressLabel) • \(chain.routingDisplayName)"
    }
}

enum ReceiptStatusFilter: String, CaseIterable, Identifiable, Sendable {
    case all
    case success
    case failed

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all:
            return "All Statuses"
        case .success:
            return "Successful"
        case .failed:
            return "Failed"
        }
    }
}

enum ReceiptActorFilter: String, CaseIterable, Identifiable, Sendable {
    case all
    case user
    case system

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all:
            return "All Actors"
        case .user:
            return "User"
        case .system:
            return "System"
        }
    }
}

struct ReceiptTimelineRecord: Identifiable, Equatable, Sendable {
    let id: UUID
    let sequenceID: Int
    let createdAt: Date
    let actor: ReceiptActor
    let mode: ReceiptMode
    let trigger: String
    let scope: String
    let summary: String
    let provenance: String
    let isSuccess: Bool
    let correlationID: String?
    let details: ReceiptPayload
    let accountAddress: String?
    let chainRawValue: String?
    let selectedChainRawValues: [String]

    init(
        id: UUID,
        sequenceID: Int,
        createdAt: Date,
        actor: ReceiptActor,
        mode: ReceiptMode,
        trigger: String,
        scope: String,
        summary: String,
        provenance: String,
        isSuccess: Bool,
        correlationID: String?,
        details: ReceiptPayload,
        accountAddress: String? = nil,
        chainRawValue: String? = nil,
        selectedChainRawValues: [String] = []
    ) {
        self.id = id
        self.sequenceID = sequenceID
        self.createdAt = createdAt
        self.actor = actor
        self.mode = mode
        self.trigger = trigger
        self.scope = scope
        self.summary = summary
        self.provenance = provenance
        self.isSuccess = isSuccess
        self.correlationID = correlationID
        self.details = details
        self.accountAddress = accountAddress
        self.chainRawValue = chainRawValue
        self.selectedChainRawValues = selectedChainRawValues
    }

    init(storedReceipt: StoredReceipt) {
        let payload = (try? storedReceipt.decodedPayload()) ?? ReceiptPayload(values: [:])

        self.id = storedReceipt.id
        self.sequenceID = storedReceipt.sequenceID
        self.createdAt = storedReceipt.createdAt
        self.actor = storedReceipt.actor
        self.mode = storedReceipt.mode
        self.trigger = storedReceipt.trigger
        self.scope = storedReceipt.scope
        self.summary = storedReceipt.summary
        self.provenance = storedReceipt.provenance
        self.isSuccess = storedReceipt.isSuccess
        self.correlationID = storedReceipt.correlationID
        self.details = payload
        self.accountAddress = storedReceipt.accountAddress ?? payload.timelineAccountAddress
        self.chainRawValue = storedReceipt.chainRawValue ?? payload.timelineChainRawValue
        self.selectedChainRawValues = payload.timelineSelectedChainRawValues
    }

    var statusTitle: String {
        isSuccess ? "Success" : "Failed"
    }

    var actorTitle: String {
        actor.rawValue.capitalized
    }

    var searchIndex: String {
        [
            summary,
            trigger,
            scope,
            provenance,
            correlationID ?? "",
            flattenedDetails(details.values)
        ]
        .joined(separator: " ")
        .lowercased()
    }

    func matches(_ scope: ReceiptTimelineScope) -> Bool {
        let normalizedScopeAddress = scope.accountAddress.extractedEthereumAddress?.lowercased()

        if let accountAddress {
            guard accountAddress == normalizedScopeAddress else {
                return false
            }
        }

        if let chainRawValue {
            guard chainRawValue == scope.chain.rawValue else {
                return false
            }
        }

        if !selectedChainRawValues.isEmpty {
            guard selectedChainRawValues.contains(scope.chain.rawValue) else {
                return false
            }
        }

        return true
    }

    private func flattenedDetails(_ object: [String: ReceiptJSONValue]) -> String {
        object
            .sorted(by: { $0.key < $1.key })
            .map { key, value in
                "\(key) \(flattenedValue(value))"
            }
            .joined(separator: " ")
    }

    private func flattenedValue(_ value: ReceiptJSONValue) -> String {
        switch value {
        case .string(let string):
            return string
        case .number(let number):
            return number.formatted()
        case .bool(let bool):
            return bool ? "true" : "false"
        case .null:
            return "null"
        case .object(let object):
            return flattenedDetails(object)
        case .array(let values):
            return values.map(flattenedValue).joined(separator: " ")
        }
    }
}

struct ReceiptTimelineSnapshot: Equatable {
    let visibleRecords: [ReceiptTimelineRecord]
    let filteredCount: Int
    let totalCount: Int
    let availableScopes: [String]
    let hasMore: Bool
}

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

struct ReceiptsRootView: View {
    @Query(
        sort: [
            SortDescriptor(\StoredReceipt.createdAt, order: .reverse),
            SortDescriptor(\StoredReceipt.sequenceID, order: .reverse)
        ]
    ) private var storedReceipts: [StoredReceipt]

    let currentAddress: String
    let currentChain: Chain

    @State private var timelineState: ReceiptTimelineState

    init(currentAddress: String, currentChain: Chain) {
        self.currentAddress = currentAddress
        self.currentChain = currentChain
        _timelineState = State(
            initialValue: ReceiptTimelineState(
                scope: ReceiptTimelineScope(
                    accountAddress: currentAddress,
                    chain: currentChain
                )
            )
        )
    }

    private var records: [ReceiptTimelineRecord] {
        storedReceipts.map(ReceiptTimelineRecord.init)
    }

    private var snapshot: ReceiptTimelineSnapshot {
        timelineState.snapshot(records: records)
    }

    var body: some View {
        AuraScenicScreen(horizontalPadding: 12, verticalPadding: 12) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    ReceiptTimelineScopeCard(
                        scope: timelineState.scope,
                        totalCount: snapshot.totalCount,
                        filteredCount: snapshot.filteredCount,
                        filterSummary: timelineState.filterSummary,
                        isUsingDefaultFilters: timelineState.isUsingDefaultFilters
                    )

                    ReceiptTimelineFilterCard(
                        timelineState: $timelineState,
                        availableScopes: snapshot.availableScopes
                    )

                    content
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .navigationTitle("Receipts")
        .navigationBarTitleDisplayMode(.large)
        .searchable(
            text: $timelineState.searchQuery,
            placement: .navigationBarDrawer(displayMode: .always),
            prompt: "Search summary, scope, correlation, payload"
        )
        .accessibilityIdentifier("receipts.root")
        .onChange(of: currentAddress) { _, newValue in
            timelineState.applyScope(
                ReceiptTimelineScope(accountAddress: newValue, chain: currentChain)
            )
        }
        .onChange(of: currentChain) { _, newValue in
            timelineState.applyScope(
                ReceiptTimelineScope(accountAddress: currentAddress, chain: newValue)
            )
        }
        .onChange(of: timelineState.searchQuery) { _, _ in
            timelineState.resetPagination()
        }
        .onChange(of: timelineState.statusFilter) { _, _ in
            timelineState.resetPagination()
        }
        .onChange(of: timelineState.actorFilter) { _, _ in
            timelineState.resetPagination()
        }
        .onChange(of: timelineState.selectedScope) { _, _ in
            timelineState.resetPagination()
        }
    }

    @ViewBuilder
    private var content: some View {
        if snapshot.totalCount == 0 {
            ReceiptTimelineEmptyStateView(scope: timelineState.scope)
        } else if snapshot.filteredCount == 0 {
            AuraEmptyState(
                eyebrow: "Receipts",
                title: "No Receipts Match This View",
                message: "Nothing in \(timelineState.scope.displayLabel) matches the current filters. Clear them and return to the full timeline.",
                systemImage: "line.3.horizontal.decrease.circle",
                tone: .neutral,
                primaryAction: AuraFeedbackAction(
                    title: "Clear Filters",
                    systemImage: "arrow.uturn.backward.circle"
                ) {
                    timelineState.clearFilters()
                }
            )
        } else {
            LazyVStack(spacing: 12) {
                ForEach(snapshot.visibleRecords) { record in
                    NavigationLink(value: ReceiptRoute(id: record.id.uuidString)) {
                        ReceiptTimelineRow(record: record)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("receipts.row.\(record.id.uuidString)")
                }

                if snapshot.hasMore {
                    HStack {
                        Spacer()

                        AuraActionButton("Load More", systemImage: "arrow.down.circle", style: .surface) {
                            timelineState.loadNextPage()
                        }

                        Spacer()
                    }
                    .padding(.top, 4)
                }
            }
        }
    }
}

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

private struct ReceiptTimelineScopeCard: View {
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

private struct ReceiptTimelineFilterCard: View {
    @Binding var timelineState: ReceiptTimelineState
    let availableScopes: [String]

    var body: some View {
        AuraSurfaceCard(style: .regular, cornerRadius: 24, padding: 18) {
            VStack(alignment: .leading, spacing: 16) {
                Text("Filters")
                    .font(.headline)
                    .foregroundStyle(Color.textPrimary)

                VStack(alignment: .leading, spacing: 12) {
                    Picker("Status", selection: $timelineState.statusFilter) {
                        ForEach(ReceiptStatusFilter.allCases) { filter in
                            Text(filter.title).tag(filter)
                        }
                    }
                    .pickerStyle(.segmented)

                    HStack(spacing: 12) {
                        Picker("Actor", selection: $timelineState.actorFilter) {
                            ForEach(ReceiptActorFilter.allCases) { filter in
                                Text(filter.title).tag(filter)
                            }
                        }

                        Picker("Scope", selection: $timelineState.selectedScope) {
                            Text("All Scopes").tag(ReceiptTimelineState.allScopesValue)
                            ForEach(availableScopes, id: \.self) { scope in
                                Text(scope).tag(scope)
                            }
                        }
                    }
                    .pickerStyle(.menu)
                }
            }
        }
    }
}

private struct ReceiptTimelineRow: View {
    let record: ReceiptTimelineRecord

    var body: some View {
        AuraSurfaceCard(style: .regular, cornerRadius: 24, padding: 18) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(record.summary)
                            .font(.headline)
                            .foregroundStyle(Color.textPrimary)

                        Text(record.trigger)
                            .font(.subheadline)
                            .foregroundStyle(Color.textSecondary)
                    }

                    Spacer(minLength: 12)

                    VStack(alignment: .trailing, spacing: 6) {
                        AuraPill(
                            record.statusTitle,
                            systemImage: record.isSuccess ? "checkmark.circle.fill" : "exclamationmark.triangle.fill",
                            emphasis: record.isSuccess ? .success : .accent
                        )

                        Text(record.createdAt, style: .relative)
                            .font(.caption)
                            .foregroundStyle(Color.textSecondary)
                    }
                }

                HStack(spacing: 8) {
                    AuraPill(record.scope, systemImage: "square.stack.3d.up")
                    AuraPill(record.actorTitle, systemImage: record.actor == .user ? "person.fill" : "gearshape.fill")

                    if let correlationID = record.correlationID, !correlationID.isEmpty {
                        AuraPill(
                            String(correlationID.prefix(8)),
                            systemImage: "link",
                            emphasis: .accent,
                            accessibilityLabel: "Correlation \(correlationID)"
                        )
                    }
                }

                Text(record.provenance)
                    .font(.caption)
                    .foregroundStyle(Color.textSecondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct ReceiptTimelineEmptyStateView: View {
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

private struct ReceiptDetailSummaryCard: View {
    let receipt: ReceiptTimelineRecord

    var body: some View {
        AuraSurfaceCard(style: .soft, cornerRadius: 24, padding: 18) {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(receipt.summary)
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(Color.textPrimary)

                        Text(receipt.trigger)
                            .font(.subheadline)
                            .foregroundStyle(Color.textSecondary)
                    }

                    Spacer(minLength: 12)

                    AuraPill(
                        receipt.statusTitle,
                        systemImage: receipt.isSuccess ? "checkmark.circle.fill" : "exclamationmark.triangle.fill",
                        emphasis: receipt.isSuccess ? .success : .accent
                    )
                }

                VStack(alignment: .leading, spacing: 10) {
                    ReceiptDetailFact(label: "Scope", value: receipt.scope)
                    ReceiptDetailFact(label: "Actor", value: receipt.actorTitle)
                    ReceiptDetailFact(label: "Mode", value: receipt.mode.rawValue)
                    ReceiptDetailFact(label: "Provenance", value: receipt.provenance)
                    ReceiptDetailFact(label: "Sequence", value: String(receipt.sequenceID))
                    ReceiptDetailFact(
                        label: "Created",
                        value: receipt.createdAt.formatted(date: .abbreviated, time: .standard)
                    )

                    if let correlationID = receipt.correlationID, !correlationID.isEmpty {
                        ReceiptDetailFact(label: "Correlation ID", value: correlationID)
                    }
                }
            }
        }
    }
}

private struct ReceiptDetailFact: View {
    let label: String
    let value: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text(label)
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color.textSecondary)
                .frame(width: 92, alignment: .leading)

            Text(value)
                .font(.subheadline)
                .foregroundStyle(Color.textPrimary)
                .textSelection(.enabled)

            Spacer(minLength: 0)
        }
    }
}

private struct ReceiptRelatedReceiptsCard: View {
    let receipts: [ReceiptTimelineRecord]

    var body: some View {
        AuraSurfaceCard(style: .regular, cornerRadius: 24, padding: 18) {
            VStack(alignment: .leading, spacing: 12) {
                Text("Related Receipts")
                    .font(.headline)
                    .foregroundStyle(Color.textPrimary)

                ForEach(receipts) { receipt in
                    NavigationLink(value: ReceiptRoute(id: receipt.id.uuidString)) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(receipt.summary)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(Color.textPrimary)

                            Text("\(receipt.trigger) • \(receipt.createdAt.formatted(date: .omitted, time: .shortened))")
                                .font(.caption)
                                .foregroundStyle(Color.textSecondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

private struct ReceiptPayloadCard: View {
    let payload: ReceiptPayload

    var body: some View {
        AuraSurfaceCard(style: .regular, cornerRadius: 24, padding: 18) {
            VStack(alignment: .leading, spacing: 12) {
                Text("Payload")
                    .font(.headline)
                    .foregroundStyle(Color.textPrimary)

                if payload.values.isEmpty {
                    Text("No sanitized payload values were recorded for this receipt.")
                        .font(.subheadline)
                        .foregroundStyle(Color.textSecondary)
                } else {
                    ReceiptPayloadObjectView(values: payload.values, depth: 0)
                }
            }
        }
    }
}

private struct ReceiptPayloadObjectView: View {
    let values: [String: ReceiptJSONValue]
    let depth: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(values.keys.sorted(), id: \.self) { key in
                if let value = values[key] {
                    ReceiptPayloadValueView(label: key, value: value, depth: depth)
                }
            }
        }
    }
}

private struct ReceiptPayloadValueView: View {
    let label: String
    let value: ReceiptJSONValue
    let depth: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            switch value {
            case .object(let object):
                ReceiptPayloadNestedHeader(label: label, depth: depth, kind: "Object")
                ReceiptPayloadObjectView(values: object, depth: depth + 1)
                    .padding(.leading, 12)
            case .array(let values):
                ReceiptPayloadNestedHeader(label: label, depth: depth, kind: "Array")
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(Array(values.enumerated()), id: \.offset) { index, value in
                        ReceiptPayloadValueView(
                            label: "[\(index)]",
                            value: value,
                            depth: depth + 1
                        )
                    }
                }
                .padding(.leading, 12)
            default:
                HStack(alignment: .top, spacing: 12) {
                    Text(label)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.textSecondary)
                        .frame(width: 120, alignment: .leading)

                    Text(formattedScalar(value))
                        .font(.system(.subheadline, design: .monospaced))
                        .foregroundStyle(Color.textPrimary)
                        .textSelection(.enabled)

                    Spacer(minLength: 0)
                }
            }
        }
    }

    private func formattedScalar(_ value: ReceiptJSONValue) -> String {
        switch value {
        case .string(let string):
            return string
        case .number(let number):
            return number.formatted()
        case .bool(let bool):
            return bool ? "true" : "false"
        case .null:
            return "null"
        case .object, .array:
            return ""
        }
    }
}

private struct ReceiptPayloadNestedHeader: View {
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
