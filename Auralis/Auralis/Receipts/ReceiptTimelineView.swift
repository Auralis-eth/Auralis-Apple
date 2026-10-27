import AuralisPrimaryModels
import AuraUI
import Foundation
import AuralisReceipts
import SwiftData
import SwiftUI
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
            prompt: "Search status, trigger, chain, account, or receipt ID"
        )
        .accessibilityIdentifier(A11yID.Receipts.root)
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
        // Shares `ReceiptTimelineRecord.accountKey` with `matches(_:)` so the predicate and the
        // in-memory comparison cannot diverge. What this actually changes is the **non-address**
        // case: `AuralisEthereumAddress.normalized` returns `nil` for anything that is not 40 hex
        // digits, which dropped the account narrowing entirely and fell back to a full fetch, while
        // `accountKey` falls through to `trimmed.lowercased()` — exactly what the write side stored —
        // so an ENS-style or otherwise non-address account key now narrows correctly.
        //
        // It does **not** fix the unprefixed-address hole, and must not be read as having done so:
        // `accountKey` tries `AuralisEthereumAddress.normalized` *first* and returns it on success, so
        // for any valid 40-hex address — prefixed, unprefixed, or checksummed — it yields the same
        // `0x…` string the old call did. The write side is the asymmetric half and still is:
        // `ReceiptAccountAddress.resolve` stores `trimmed.lowercased()` and deliberately adds no
        // prefix, and `ReceiptPayload.timelineAccountAddress` is free-form and normalized nowhere. A
        // row stored unprefixed therefore remains invisible to this predicate, permanently, and no
        // post-fetch filter can recover it — a filter can only narrow. Latent today because every
        // production writer supplies a `0x`-prefixed address; tracked as **F-100**. Closing it means
        // normalizing on the write path, which touches a hashed column.
        let normalizedAccountAddress = ReceiptTimelineRecord.accountKey(scope.accountAddress)

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
                    NavigationLink {
                        ReceiptDetailView(
                            route: ReceiptRoute(id: record.id.uuidString),
                            scope: timelineState.scope
                        )
                    } label: {
                        ReceiptTimelineRow(record: record)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier(A11yID.Receipts.row(id: record.id.uuidString))
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
