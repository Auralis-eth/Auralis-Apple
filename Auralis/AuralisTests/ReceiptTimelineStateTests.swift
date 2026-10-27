@testable import Auralis
import AuralisCrypto
import Foundation
import AuralisReceipts
import Testing

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
        #expect(secondSnapshot.hasMore == false)
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
                actor: .system,
                trigger: "nft.fetch.succeeded",
                scope: "networking",
                summary: "Fetched Base NFT page successfully",
                provenance: "on_chain",
                isSuccess: true,
                correlationID: "refresh-3",
                details: ReceiptPayload(values: [
                    "accountAddress": .string(activeScope.accountAddress),
                    "chain": .string(Chain.baseMainnet.rawValue)
                ]),
                accountAddress: activeScope.accountAddress.lowercased(),
                chainRawValue: Chain.baseMainnet.rawValue
            ),
            makeRecord(
                sequenceID: 4,
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
        #expect(snapshot.visibleRecords.map(\.sequenceID) == [1, 4])
        #expect(snapshot.availableScopes == ["clipboard", "networking"])
    }

    @Test("receipt presentation builds human-readable audit sections and artifact-producing postflight")
    func receiptPresentationBuildsReadableSections() {
        let artifactID = UUID(uuidString: "44444444-4444-4444-4444-444444444444")!
        let relatedArtifactID = UUID(uuidString: "55555555-5555-5555-5555-555555555555")!
        let nestedArtifactID = UUID(uuidString: "66666666-6666-6666-6666-666666666666")!
        let record = makeRecord(
            sequenceID: 40,
            actor: .system,
            trigger: "tool.executed",
            scope: "runtime",
            summary: "Executed operator",
            provenance: "runtime",
            isSuccess: true,
            correlationID: "operator-40",
            details: ReceiptPayload(values: [
                "requestedIntent": .string("Create a wallet risk report"),
                "interpretedPlan": .array([.string("Collect balances"), .string("Write report")]),
                "approvalID": .string("approval-40"),
                "actionName": .string("operator.riskReport"),
                "output": .object(["summary": .string("Report created")]),
                "policyReason": .string("Read-only artifact generation is allowed."),
                "capability": .string("artifact.write"),
                "artifactID": .string(artifactID.uuidString),
                "artifactIDs": .array([
                    .string(artifactID.uuidString),
                    .string(relatedArtifactID.uuidString)
                ]),
                "relatedArtifacts": .array([
                    .object(["id": .string(nestedArtifactID.uuidString)])
                ]),
                "changeSummary": .string("Created a report artifact.")
            ])
        )

        let presentation = ReceiptPresentation(receipt: record)
        let sections = Dictionary(uniqueKeysWithValues: presentation.sections.map { ($0.title, $0.rows) })

        #expect(presentation.outcome == .artifactProducing)
        #expect(presentation.artifactIDs == [artifactID, relatedArtifactID, nestedArtifactID])
        #expect(sections["Requested Intent"]?.contains { $0.value == "Create a wallet risk report" } == true)
        #expect(sections["Interpreted Plan"]?.contains { $0.value.contains("Collect balances") } == true)
        #expect(sections["Approvals"]?.contains { $0.value == "approval-40" } == true)
        #expect(sections["Actions"]?.contains { $0.value == "operator.riskReport" } == true)
        #expect(sections["Outputs"]?.contains { $0.value.contains("Report created") } == true)
        #expect(sections["Policy Reasons"]?.contains { $0.value.contains("Read-only") } == true)
        #expect(sections["Related Capabilities"]?.contains { $0.value == "artifact.write" } == true)
        #expect(presentation.changeRows.contains { $0.value == "Created a report artifact." })
        #expect(presentation.searchableText.contains("artifact.write"))
    }

    @Test("receipt presentation distinguishes draft, no-op, and blocked postflight outcomes")
    func receiptPresentationDistinguishesPostflightOutcomes() {
        let draft = ReceiptPresentation(receipt: makeRecord(
            sequenceID: 41,
            actor: .system,
            trigger: "tool.draftPrepared",
            scope: "runtime",
            summary: "Prepared draft",
            provenance: "runtime",
            isSuccess: true,
            correlationID: "operator-41",
            details: ReceiptPayload(values: ["receiptDraftID": .string("draft-41")])
        ))
        let noOp = ReceiptPresentation(receipt: makeRecord(
            sequenceID: 42,
            actor: .system,
            trigger: "account.selected",
            scope: "accounts",
            summary: "Selected account",
            provenance: "user_provided",
            isSuccess: true,
            correlationID: "operator-42",
            details: ReceiptPayload(values: ["outcome": .string("no-op")])
        ))
        let blocked = ReceiptPresentation(receipt: makeRecord(
            sequenceID: 43,
            actor: .system,
            trigger: "tool.blocked",
            scope: "runtime",
            summary: "Blocked signing",
            provenance: "policy",
            isSuccess: false,
            correlationID: "operator-43",
            details: ReceiptPayload(values: ["policyReason": .string("Observe mode blocks signing.")])
        ))

        #expect(draft.outcome == .draftOnly)
        #expect(draft.changeRows == [
            ReceiptContentRow(label: "Draft", value: "Prepared for review; no artifact was committed.")
        ])
        #expect(noOp.outcome == .noOp)
        #expect(blocked.outcome == .blocked)
        #expect(blocked.changeRows == [
            ReceiptContentRow(label: "Stopped", value: "Observe mode blocks signing.")
        ])
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
