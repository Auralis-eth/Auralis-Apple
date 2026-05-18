import AuralisPrimaryModels
import Foundation
import SwiftData
import SwiftUI
import AuraUI
import UIKit

// SwiftLint currently misclassifies these file-scope receipt snapshot helpers as overly nested.
private struct ReceiptTimelineReceiptSnapshot: Equatable {
    let id: UUID
    let sequenceID: Int
    let createdAt: Date
    let summary: String
    let scope: String
    let isSuccess: Bool
}

private struct ReceiptTimelineRefreshKey: Equatable {
    let timelineState: ReceiptTimelineState
    let receipts: [ReceiptTimelineReceiptSnapshot]
}

struct ReceiptsRootView: View {
    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion
    @Environment(\.modelContext) private var modelContext

    let currentAddress: String
    let currentChain: Chain

    @State private var timelineState: ReceiptTimelineState
    @State private var snapshot: ReceiptTimelineSnapshot = .empty
    @State private var storedReceipts: [StoredReceipt] = []

    private var haptics: AuraHaptics {
        AuraHaptics(accessibilityReduceMotion: accessibilityReduceMotion)
    }

    private var refreshKey: ReceiptTimelineRefreshKey {
        ReceiptTimelineRefreshKey(
            timelineState: timelineState,
            receipts: storedReceipts.map {
                ReceiptTimelineReceiptSnapshot(
                    id: $0.id,
                    sequenceID: $0.sequenceID,
                    createdAt: $0.createdAt,
                    summary: $0.summary,
                    scope: $0.scope,
                    isSuccess: $0.isSuccess
                )
            }
        )
    }

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
        .refreshable {
            haptics.impact(.light)
            refreshSnapshot()
        }
        .searchable(
            text: $timelineState.searchQuery,
            placement: .navigationBarDrawer(displayMode: .always),
            prompt: "Search summary, scope, correlation, payload"
        )
        .accessibilityIdentifier("receipts.root")
        .task(id: refreshKey) {
            refreshSnapshot()
        }
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

    private func refreshSnapshot() {
        reloadStoredReceipts()
        let records = storedReceipts.map(ReceiptTimelineRecord.init)
        snapshot = timelineState.snapshot(records: records)
    }

    private func reloadStoredReceipts() {
        do {
            storedReceipts = try modelContext.fetch(Self.makeStoredReceiptsDescriptor(for: timelineState.scope))
        } catch {
            storedReceipts = []
        }
    }

    private static func makeStoredReceiptsDescriptor(
        for scope: ReceiptTimelineScope
    ) -> FetchDescriptor<StoredReceipt> {
        let normalizedAccountAddress = AuralisEthereumAddress.normalized(scope.accountAddress)

        if let normalizedAccountAddress, !normalizedAccountAddress.isEmpty {
            return FetchDescriptor(
                predicate: #Predicate<StoredReceipt> { receipt in
                    receipt.accountAddress == normalizedAccountAddress
                },
                sortBy: [
                    SortDescriptor(\StoredReceipt.createdAt, order: .reverse),
                    SortDescriptor(\StoredReceipt.sequenceID, order: .reverse)
                ]
            )
        }

        return FetchDescriptor(
            sortBy: [
                SortDescriptor(\StoredReceipt.createdAt, order: .reverse),
                SortDescriptor(\StoredReceipt.sequenceID, order: .reverse)
            ]
        )
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
