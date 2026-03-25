import Foundation
import Testing
@testable import Auralis

@Suite
struct ReceiptTimelineStateTests {
    @Test("scope changes reset search, filters, and pagination to the default view")
    func scopeChangeResetsState() {
        var state = ReceiptTimelineState(
            scope: ReceiptTimelineScope(
                accountAddress: "0x1111111111111111111111111111111111111111",
                chain: .ethMainnet
            )
        )

        state.searchQuery = "refresh"
        state.statusFilter = .failed
        state.actorFilter = .system
        state.selectedScope = "networking"
        state.loadNextPage()

        state.applyScope(
            ReceiptTimelineScope(
                accountAddress: "0x2222222222222222222222222222222222222222",
                chain: .baseMainnet
            )
        )

        #expect(state.searchQuery.isEmpty)
        #expect(state.statusFilter == .all)
        #expect(state.actorFilter == .all)
        #expect(state.selectedScope == ReceiptTimelineState.allScopesValue)
        #expect(state == ReceiptTimelineState(
            scope: ReceiptTimelineScope(
                accountAddress: "0x2222222222222222222222222222222222222222",
                chain: .baseMainnet
            )
        ))
    }

    @Test("snapshot filters by status, actor, scope, and payload-backed search fields")
    func snapshotAppliesFiltersAndSearch() {
        var state = ReceiptTimelineState(
            scope: ReceiptTimelineScope(
                accountAddress: "0x1111111111111111111111111111111111111111",
                chain: .ethMainnet
            )
        )
        state.statusFilter = .failed
        state.actorFilter = .system
        state.selectedScope = "networking"
        state.searchQuery = "refresh-2"

        let snapshot = state.snapshot(records: [
            makeRecord(
                sequenceID: 1,
                actor: .system,
                trigger: "nft.fetch.failed",
                scope: "networking",
                summary: "NFT fetch failed",
                provenance: "on_chain",
                isSuccess: false,
                correlationID: "refresh-2",
                details: ReceiptPayload(values: ["accountAddress": .string("0xabc")])
            ),
            makeRecord(
                sequenceID: 2,
                actor: .user,
                trigger: "account.selected",
                scope: "accounts",
                summary: "Selected active account",
                provenance: "user_provided",
                isSuccess: true,
                correlationID: "account-1",
                details: ReceiptPayload(values: ["address": .string("0xdef")])
            ),
            makeRecord(
                sequenceID: 3,
                actor: .system,
                trigger: "nft.fetch.failed",
                scope: "networking",
                summary: "NFT fetch failed",
                provenance: "on_chain",
                isSuccess: false,
                correlationID: "refresh-3",
                details: ReceiptPayload(values: ["accountAddress": .string("0x987")])
            )
        ])

        #expect(snapshot.filteredCount == 1)
        #expect(snapshot.visibleRecords.map(\.sequenceID) == [1])
        #expect(snapshot.availableScopes == ["accounts", "networking"])
    }

    @Test("snapshot keeps stable ordering and expands visible rows a page at a time")
    func snapshotSupportsPagination() {
        var state = ReceiptTimelineState(
            scope: ReceiptTimelineScope(
                accountAddress: "0x1111111111111111111111111111111111111111",
                chain: .ethMainnet
            )
        )

        let records = (1...30).map { index in
            makeRecord(
                sequenceID: index,
                actor: .system,
                trigger: "nft.refresh.started",
                scope: "networking",
                summary: "Started NFT refresh \(index)",
                provenance: "on_chain",
                isSuccess: true,
                correlationID: "refresh-\(index)",
                details: ReceiptPayload(values: [:])
            )
        }

        let firstSnapshot = state.snapshot(records: records)
        #expect(firstSnapshot.visibleRecords.count == ReceiptTimelineState.pageSize)
        #expect(firstSnapshot.hasMore)

        state.loadNextPage()
        let secondSnapshot = state.snapshot(records: records)
        #expect(secondSnapshot.visibleRecords.count == 30)
        #expect(!secondSnapshot.hasMore)
        #expect(secondSnapshot.visibleRecords.map(\.sequenceID) == Array(1...30))
    }

    @Test("snapshot only counts and renders receipts that match the active account and chain scope")
    func snapshotScopesRecordsToActiveWallet() {
        let activeScope = ReceiptTimelineScope(
            accountAddress: "0x1111111111111111111111111111111111111111",
            chain: .ethMainnet
        )
        let state = ReceiptTimelineState(scope: activeScope)

        let snapshot = state.snapshot(records: [
            makeRecord(
                sequenceID: 1,
                actor: .system,
                trigger: "nft.fetch.succeeded",
                scope: "networking",
                summary: "Fetched NFT page successfully",
                provenance: "on_chain",
                isSuccess: true,
                correlationID: "refresh-1",
                details: ReceiptPayload(values: [
                    "accountAddress": .string(activeScope.accountAddress),
                    "chain": .string(Chain.ethMainnet.rawValue)
                ]),
                accountAddress: activeScope.accountAddress.lowercased(),
                chainRawValue: Chain.ethMainnet.rawValue
            ),
            makeRecord(
                sequenceID: 2,
                actor: .system,
                trigger: "nft.fetch.succeeded",
                scope: "networking",
                summary: "Fetched NFT page successfully",
                provenance: "on_chain",
                isSuccess: true,
                correlationID: "refresh-2",
                details: ReceiptPayload(values: [
                    "accountAddress": .string("0x2222222222222222222222222222222222222222"),
                    "chain": .string(Chain.ethMainnet.rawValue)
                ]),
                accountAddress: "0x2222222222222222222222222222222222222222",
                chainRawValue: Chain.ethMainnet.rawValue
            ),
            makeRecord(
                sequenceID: 3,
                actor: .user,
                trigger: "copy.performed",
                scope: "clipboard",
                summary: "Copied value",
                provenance: "user_provided",
                isSuccess: true,
                correlationID: "copy-1",
                details: ReceiptPayload(values: [
                    "subject": .string("nft.id")
                ])
            )
        ])

        #expect(snapshot.totalCount == 2)
        #expect(snapshot.filteredCount == 2)
        #expect(snapshot.visibleRecords.map(\.sequenceID) == [1, 3])
        #expect(snapshot.availableScopes == ["clipboard", "networking"])
    }

    private func makeRecord(
        sequenceID: Int,
        actor: ReceiptActor,
        trigger: String,
        scope: String,
        summary: String,
        provenance: String,
        isSuccess: Bool,
        correlationID: String,
        details: ReceiptPayload,
        accountAddress: String? = nil,
        chainRawValue: String? = nil,
        selectedChainRawValues: [String] = []
    ) -> ReceiptTimelineRecord {
        ReceiptTimelineRecord(
            id: UUID(uuidString: "00000000-0000-0000-0000-\(String(format: "%012d", sequenceID))") ?? UUID(),
            sequenceID: sequenceID,
            createdAt: Date(timeIntervalSince1970: TimeInterval(1_000 + sequenceID)),
            actor: actor,
            mode: .observe,
            trigger: trigger,
            scope: scope,
            summary: summary,
            provenance: provenance,
            isSuccess: isSuccess,
            correlationID: correlationID,
            details: details,
            accountAddress: accountAddress,
            chainRawValue: chainRawValue,
            selectedChainRawValues: selectedChainRawValues
        )
    }
}
