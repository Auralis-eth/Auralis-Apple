import AuralisReceipts
import AuralisCrypto
import Foundation
import AuralisOperators
import AuralisPolicy
import AuralisRuntime
@testable import AuralisAppShell
import Testing

/// In-memory receipt store that can be seeded, so the receipt-backed data source can be exercised.
private actor SeededReceiptStore: ReceiptStore {
    private var records: [ReceiptRecord]

    init(records: [ReceiptRecord] = []) { self.records = records }

    func append(_ receipt: ReceiptDraft) async throws -> ReceiptRecord {
        let record = ReceiptRecord(
            id: UUID(), sequenceID: records.count + 1, createdAt: receipt.createdAt,
            actor: receipt.actor, actorDetail: receipt.actorDetail, authorityDetail: receipt.authorityDetail, mode: receipt.mode, trigger: receipt.trigger,
            scope: receipt.scope, summary: receipt.summary, provenance: receipt.provenance,
            isSuccess: receipt.isSuccess, correlationID: receipt.correlationID, details: receipt.details
        )
        records.insert(record, at: 0)
        return record
    }
    func latest(limit: Int) async throws -> [ReceiptRecord] { Array(records.prefix(limit)) }
    func receipts(forCorrelationID correlationID: String, limit: Int) async throws -> [ReceiptRecord] { [] }
    func exportAll() async throws -> Data { Data() }
    func resetAll() async throws { records.removeAll() }
}

/// Deterministic operator feed so run content can be asserted.
private struct StubDataSource: OperatorDataSource {
    let activity: [ObservedActivity]
    func recentActivity(matching request: OperatorRequest, limit: Int) async -> [ObservedActivity] { activity }
}

@MainActor
@Suite("Operators through RuntimeHost (crypto-scoped)")
struct OperatorRuntimeTests {
    private func makeHost(
        mode: CryptoMode = .observe,
        dataSource: any OperatorDataSource = EmptyOperatorDataSource(),
        activeIdentityID: String? = nil
    ) async -> RuntimeHost {
        let host = RuntimeHost(
            receiptStore: SeededReceiptStore(),
            stores: RuntimeHostStores(artifactStore: InMemoryArtifactStore()),
            operators: RuntimeOperatorStack(operatorDataSource: dataSource),
            identity: RuntimeIdentityHooks(
                activeIdentityProvider: { activeIdentityID },
                cryptoModeProvider: { mode }
            )
        )
        await host.bootstrap()
        return host
    }

    @Test
    func researchBriefRunsInObserveAndReflectsQuery() async {
        let feed = [ObservedActivity(title: "Export completed", detail: "receipts", occurredAt: .now)]
        let host = await makeHost(dataSource: StubDataSource(activity: feed))

        let outcome = await host.runResearchBrief(query: "export")
        guard case let .executed(artifact) = outcome else {
            Issue.record("expected research brief to execute, got \(outcome)")
            return
        }
        #expect(artifact.outputFields["findingCount"] == "1")
        let stored = try? await host.artifactStore.get(id: artifact.id)
        #expect(stored?.content.contains("export") == true)
    }

    @Test
    func researchBriefWithoutDefinedQueryIsBlockedByItsSchema() async {
        let host = await makeHost()
        guard case .blocked = await host.runResearchBrief(query: "   ") else {
            Issue.record("expected an empty research query to be blocked")
            return
        }
    }

    @Test
    func identityReviewRejectsAnyScopeOtherThanTheActiveIdentity() async {
        let active = "0x0000000000000000000000000000000000000001"
        let host = await makeHost(activeIdentityID: active)

        guard case .blocked = await host.runIdentityReview(
            identityID: "0x0000000000000000000000000000000000000002"
        ) else {
            Issue.record("expected a cross-identity review to be blocked")
            return
        }
        guard case .executed = await host.runIdentityReview(identityID: active) else {
            Issue.record("expected the active identity review to execute")
            return
        }
    }

    @Test
    func operatorRunCompletesSessionWithTraceableRuntimeAccounting() async throws {
        let feed = [ObservedActivity(title: "Export completed", detail: "receipts", occurredAt: .now)]
        let host = await makeHost(dataSource: StubDataSource(activity: feed))

        let outcome = await host.runResearchBrief(query: "export")
        guard case let .executed(artifact) = outcome else {
            Issue.record("expected research brief to execute, got \(outcome)")
            return
        }

        let session = try #require(await host.sessionStore.allSessions().first)
        #expect(session.status == .completed)
        #expect(session.endedAt != nil)
        #expect(session.goal == "Research Brief")
        #expect(session.capabilities == [.runPlugin])
        #expect(session.receiptIDs.isEmpty == false)
        #expect(session.artifactIDs == [artifact.id])
        // The Research Brief *permits* inference, but `OperatorExecutor` only calls a model on a
        // remote route and `makeHost` resolves a local one — so this run composed its body
        // deterministically and no model was invoked. `AgentSession.note(telemetry:)` has always
        // guarded on `usesInference` for exactly this case (P1-AI-103); the guard was simply being
        // handed `true` by telemetry that reported the *spec's* capability rather than the run's
        // behaviour. These assertions used to require a model hop and nonzero tokens here, which is
        // what made the lie look correct.
        #expect(session.modelsUsed.isEmpty)
        #expect(session.modelHops == 0)
        #expect(session.totalTokens == 0)
        #expect(session.estimatedCost == 0)
    }

    @Test
    func operatorRunGrantsTemporaryLeaseBeforeGovernedExecution() async {
        let host = await makeHost()

        let outcome = await host.runResearchBrief(query: "lease")
        guard case .executed = outcome else {
            Issue.record("expected research brief to execute with a just-in-time lease, got \(outcome)")
            return
        }

        let leases = await host.activeCapabilityLeases()
        #expect(leases.contains {
            $0.capability == .runPlugin
                && $0.grantedTo == ActorRef(kind: .operatorAgent, identifier: OperatorCatalog.researchBriefID)
        })
    }

    @Test
    func onChainWatchRunsInObserveAndDoesNotExecuteFunds() async {
        let host = await makeHost()
        let outcome = await host.runOnChainWatch(
            address: "0xd8dA6BF26964aF9D7eEd9e03E53415D37aA96045"
        )
        guard case .executed = outcome else {
            Issue.record("expected watch to execute (read-only) in Observe, got \(outcome)")
            return
        }
    }

    /// An unscoped watch is refused as `needsRevision`, not `blocked`: the tool's input schema
    /// declares `chain` and `address` as required, so `StandardBeforeToolCallHook` rejects it before
    /// any deterministic check runs. Both outcomes fail closed — nothing executes — but the
    /// distinction is load-bearing: a missing field is a revisable request, whereas `blocked` means a
    /// check or policy refused a well-formed one. Asserted on the specific case so the schema layer
    /// cannot stop catching this and have a governance block silently cover for it.
    @Test
    func onChainWatchWithoutATargetFailsClosed() async {
        let host = await makeHost()
        let outcome = await host.runOnChainWatch()

        guard case let .needsRevision(instructions) = outcome else {
            Issue.record("expected an unscoped watch to be refused as needsRevision, got \(outcome)")
            return
        }
        #expect(instructions.contains("chain"))
        #expect(instructions.contains("address"))
    }

    @Test
    func preparedActionIsBlockedInObserveAndEscalatesInAssist() async {
        let address = "0xd8dA6BF26964aF9D7eEd9e03E53415D37aA96045"

        let observeHost = await makeHost(mode: .observe)
        let blocked = await observeHost.runPreparedAction(chain: "ethereum", address: address, rationale: "review")
        guard case .blocked = blocked else {
            Issue.record("expected prepared action blocked in Observe, got \(blocked)")
            return
        }

        let assistHost = await makeHost(mode: .assist)
        let escalated = await assistHost.runPreparedAction(chain: "ethereum", address: address, rationale: "review")
        guard case .needsApproval = escalated else {
            Issue.record("expected prepared action to escalate in Assist, got \(escalated)")
            return
        }
        // No artifact was produced by the escalated/blocked crypto action.
        let produced = try? await assistHost.artifactStore.latest(limit: 10)
        #expect(produced?.isEmpty == true)
    }

    @Test
    func approvedPreparedActionGrantsLeaseAndResumesExecution() async {
        let address = "0xd8dA6BF26964aF9D7eEd9e03E53415D37aA96045"
        let host = await makeHost(mode: .assist)
        let escalated = await host.runPreparedAction(chain: "ethereum", address: address, rationale: "review")
        guard case let .needsApproval(request) = escalated else {
            Issue.record("expected prepared action to need approval, got \(escalated)")
            return
        }

        let resumed = await host.resumeApprovedProposal(request)
        guard case let .executed(artifact) = resumed else {
            Issue.record("expected approved prepared action to execute, got \(resumed)")
            return
        }

        #expect(artifact.toolID == OperatorCatalog.preparedActionID)
        let leases = await host.activeCapabilityLeases()
        #expect(leases.contains {
            $0.capability == .draftTransaction
                && $0.grantedTo == ActorRef(kind: .operatorAgent, identifier: OperatorCatalog.preparedActionID)
                && $0.sessionCorrelationID == request.proposal.correlationID
        })
    }
}

@Suite("ReceiptBackedOperatorDataSource")
struct ReceiptBackedOperatorDataSourceTests {
    private func record(
        summary: String,
        address: String?,
        chain: String?,
        identityID: String? = nil,
        success: Bool
    ) -> ReceiptRecord {
        var values: [String: ReceiptJSONValue] = [:]
        if let address { values["address"] = .string(address) }
        if let chain { values["chain"] = .string(chain) }
        if let identityID { values["identityID"] = .string(identityID) }
        return ReceiptRecord(
            id: UUID(), sequenceID: 1, createdAt: .now, actor: .system,
            actorDetail: nil, authorityDetail: nil, mode: .observe,
            trigger: "tool.executed", scope: "runtime", summary: summary, provenance: "local",
            isSuccess: success, correlationID: nil, details: ReceiptPayload(values: values)
        )
    }

    @Test
    func filtersByWatchlistAddress() async {
        let address = "0xd8dA6BF26964aF9D7eEd9e03E53415D37aA96045"
        let store = SeededReceiptStore(records: [
            record(summary: "Transfer", address: address, chain: "ethereum", success: true),
            record(summary: "Unrelated", address: "0x0000000000000000000000000000000000000001", chain: "ethereum", success: true)
        ])
        let source = ReceiptBackedOperatorDataSource(receiptStore: store)

        let matched = await source.recentActivity(
            matching: OperatorRequest(watchlist: [WatchTarget(chain: "ethereum", address: address)]),
            limit: 50
        )

        #expect(matched.count == 1)
        #expect(matched.first?.title == "Transfer")
        #expect(matched.first?.address?.caseInsensitiveCompare(address) == .orderedSame)
    }

    /// The *narrowing* half must fold the address the same way the composer does.
    ///
    /// Fails against the pre-fix source, which keyed this filter on a bare `.lowercased()`: an
    /// unprefixed or padded watch target — the spellings a user types, and what
    /// `MissionControlHomeModel.addOperatorWatchTarget` accepts — matched nothing here, so the feed
    /// arrived empty and the composer's own `addressKey` fix had nothing left to act on. This side
    /// runs first, which is why fixing only the composer left the defect fully reachable.
    @Test
    func watchlistNarrowingFoldsWhitespaceAndThePrefixLikeTheComposer() async {
        let canonical = "0xd8dA6BF26964aF9D7eEd9e03E53415D37aA96045"
        let store = SeededReceiptStore(records: [
            record(summary: "Transfer", address: canonical, chain: "eth-mainnet", success: true),
            record(summary: "Unrelated", address: "0x0000000000000000000000000000000000000001", chain: "eth-mainnet", success: true)
        ])
        let source = ReceiptBackedOperatorDataSource(receiptStore: store)

        let matched = await source.recentActivity(
            matching: OperatorRequest(watchlist: [
                WatchTarget(chain: "ethereum", address: "  d8dA6BF26964aF9D7eEd9e03E53415D37aA96045 ")
            ]),
            limit: 50
        )

        #expect(matched.map(\.title) == ["Transfer"])
    }

    @Test
    func watchlistRequiresBothChainAndAddressToMatch() async {
        let address = "0xd8dA6BF26964aF9D7eEd9e03E53415D37aA96045"
        let store = SeededReceiptStore(records: [
            record(summary: "Ethereum transfer", address: address, chain: "ethereum", success: true),
            record(summary: "Base transfer", address: address, chain: "base", success: true)
        ])
        let source = ReceiptBackedOperatorDataSource(receiptStore: store)

        let matched = await source.recentActivity(
            matching: OperatorRequest(watchlist: [WatchTarget(chain: "ethereum", address: address)]),
            limit: 50
        )

        #expect(matched.map(\.title) == ["Ethereum transfer"])
    }

    @Test
    func identityFilteringUsesStructuredIdentityInsteadOfFreeText() async {
        let identity = "did:example:active"
        let store = SeededReceiptStore(records: [
            record(summary: "Owned", address: nil, chain: nil, identityID: identity, success: true),
            record(summary: "Mentions did:example:active", address: nil, chain: nil, success: true)
        ])
        let source = ReceiptBackedOperatorDataSource(receiptStore: store)

        let matched = await source.recentActivity(
            matching: OperatorRequest(identityID: identity),
            limit: 50
        )

        #expect(matched.map(\.title) == ["Owned"])
    }

    @Test
    func filtersByQueryTerms() async {
        let store = SeededReceiptStore(records: [
            record(summary: "Gas spike detected", address: nil, chain: nil, success: false),
            record(summary: "Playlist organized", address: nil, chain: nil, success: true)
        ])
        let source = ReceiptBackedOperatorDataSource(receiptStore: store)

        let matched = await source.recentActivity(matching: OperatorRequest(query: "gas"), limit: 50)

        #expect(matched.count == 1)
        #expect(matched.first?.title == "Gas spike detected")
    }

    private func record(summary: String, values: [String: ReceiptJSONValue]) -> ReceiptRecord {
        ReceiptRecord(
            id: UUID(), sequenceID: 1, createdAt: .now, actor: .system,
            actorDetail: nil, authorityDetail: nil, mode: .observe,
            trigger: "tool.executed", scope: "runtime", summary: summary, provenance: "local",
            isSuccess: true, correlationID: nil, details: ReceiptPayload(values: values)
        )
    }

    /// An `approveSpending` receipt carries three well-formed addresses under keys that none of the
    /// name-based lookups match, so the address-shaped fallback has several candidates. It used to
    /// iterate the payload dictionary, and Swift seeds `Dictionary` hashing per process — so the
    /// resolved address differed between launches, and `OperatorArtifactComposer` matches watch
    /// targets by address alone. Repeating the mapping many times over freshly-built dictionaries
    /// would surface any residual order dependence.
    @Test
    func addressExtractionIsDeterministicWhenAPayloadCarriesSeveralAddresses() async {
        let token = "0x1111111111111111111111111111111111111111"
        let spender = "0x2222222222222222222222222222222222222222"
        let owner = "0x3333333333333333333333333333333333333333"

        var resolved: Set<String> = []
        for _ in 0..<64 {
            let store = SeededReceiptStore(records: [
                record(summary: "Approval", values: [
                    "token": .string(token),
                    "spender": .string(spender),
                    "owner": .string(owner),
                    "amount": .string("1000"),
                    "transactionHash": .string("0x" + String(repeating: "a", count: 64))
                ])
            ])
            let source = ReceiptBackedOperatorDataSource(receiptStore: store)
            let activity = await source.recentActivity(matching: OperatorRequest(), limit: 10)
            resolved.insert(activity.first?.address ?? "<none>")
        }

        // One answer across every run, and specifically the account the approval is *about* rather
        // than the token contract or the delegate it granted.
        #expect(resolved == [owner])
    }

    /// A key naming the subject outright wins over an address-shaped value found by fallback, so the
    /// priority list is doing the work rather than the scan order happening to agree with it.
    @Test
    func anExplicitlyNamedAddressKeyOutranksTheAddressShapedFallback() async {
        let named = "0x4444444444444444444444444444444444444444"
        let store = SeededReceiptStore(records: [
            record(summary: "Transfer", values: [
                "aaaFirstAlphabetically": .string("0x5555555555555555555555555555555555555555"),
                "address": .string(named)
            ])
        ])
        let source = ReceiptBackedOperatorDataSource(receiptStore: store)

        let activity = await source.recentActivity(matching: OperatorRequest(), limit: 10)

        #expect(activity.first?.address == named)
    }
}
