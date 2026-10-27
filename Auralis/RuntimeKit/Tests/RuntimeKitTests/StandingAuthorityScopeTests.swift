import ArtifactCore
import AuralisPrimaryModels
import AuralisFoundation
import Foundation
import ReceiptsCore
import AuralisRuntime
@testable import RuntimeKit
import Testing

/// In-memory receipt store whose records can be read back, including by correlation id.
private actor LedgerReceiptStore: ReceiptStore {
    private var records: [ReceiptRecord] = []

    func append(_ receipt: ReceiptDraft) async throws -> ReceiptRecord {
        let record = ReceiptRecord(
            id: UUID(), sequenceID: records.count + 1, createdAt: receipt.createdAt,
            actor: receipt.actor, actorDetail: receipt.actorDetail,
            authorityDetail: receipt.authorityDetail, mode: receipt.mode, trigger: receipt.trigger,
            scope: receipt.scope, summary: receipt.summary, provenance: receipt.provenance,
            isSuccess: receipt.isSuccess, correlationID: receipt.correlationID, details: receipt.details
        )
        records.insert(record, at: 0)
        return record
    }
    func latest(limit: Int) async throws -> [ReceiptRecord] { Array(records.prefix(limit)) }
    func receipts(forCorrelationID correlationID: String, limit: Int) async throws -> [ReceiptRecord] {
        Array(records.filter { $0.correlationID == correlationID }.prefix(limit))
    }
    func exportAll() async throws -> Data { Data() }
    func resetAll() async throws { records.removeAll() }
}

@Suite("Standing authority scope")
@MainActor
struct StandingAuthorityScopeTests {
    /// `bootstrap()` must not mint a wallet-capability lease.
    ///
    /// `onchain.watch` ships installed and declares `.draftTransaction`, which `CapabilityDomain`
    /// classifies as wallet — so the launch-time seed was granting a 24-hour standing
    /// transaction-drafting lease to the routine *and to the person*, on every cold start, before
    /// anyone had asked for anything. Standing policy still gated execution on the crypto mode, so
    /// nothing could sign; but the lease layer is what this app offers as least-privilege authority,
    /// and an unrequested wallet grant sitting in Mission Control's active-grants list is not that.
    @Test("bootstrap grants no wallet-category standing authority")
    func bootstrapSeedsNoCryptoAuthority() async {
        let host = RuntimeHost(receiptStore: LedgerReceiptStore())
        await host.bootstrap()

        let leases = await host.activeCapabilityLeases()
        let crypto = leases.filter { CapabilityDomain.isCrypto($0.capability) }
        #expect(crypto.isEmpty, "bootstrap seeded wallet leases: \(crypto.map(\.capability.rawValue))")
        // The seed is still doing its job for everything else — this is a narrowing, not a removal.
        #expect(leases.contains { $0.capability == .runPlugin })
    }

    /// The narrowing must not disable the run it was narrowed away from. `runRoutine` re-grants
    /// standing authority for the run's own actor immediately before running, *including* crypto
    /// capabilities, so `onchain.watch` mints the lease it needs on the spot — scoped to the run that
    /// is actually happening rather than standing from launch.
    @Test("a wallet-capability routine still resolves authority when it actually runs")
    func cryptoRoutineMintsItsLeaseOnDemand() async throws {
        let host = RuntimeHost(receiptStore: LedgerReceiptStore())
        await host.bootstrap()
        #expect(await host.activeCapabilityLeases().contains { $0.capability == .draftTransaction } == false)

        let record = await host.runRoutine(id: "onchain.watch", trigger: .artifactStale)

        // The run resolved a real grant rather than failing closed for want of one.
        let authority = try #require(record.authority)
        #expect(authority.source == .lease)
        #expect(authority.capability == .draftTransaction)
        #expect(await host.activeCapabilityLeases().contains { $0.capability == .draftTransaction })
    }

    /// A denied capability still refuses the run after the narrowing — the restriction, not the
    /// absence of a seeded lease, is what does the refusing.
    @Test("a denial still overrides the on-demand grant")
    func denialStillBeatsTheOnDemandGrant() async {
        let host = RuntimeHost(receiptStore: LedgerReceiptStore())
        await host.bootstrap()
        let routineActor = ActorRef(
            kind: .scheduledRoutine,
            identifier: "onchain.watch",
            displayName: "On-Chain Watch"
        )
        _ = await host.denyCapability(
            .capability(.draftTransaction),
            reason: "Operator refused transaction drafting.",
            appliesTo: routineActor
        )

        let record = await host.runRoutine(id: "onchain.watch", trigger: .artifactStale, actor: routineActor)

        #expect(record.outcome == .blocked)
        #expect(record.authority == nil)
    }
}

@Suite("Capability authority audit trail")
@MainActor
struct CapabilityAuthorityAuditTests {
    /// A grant is receipted, not only its revocation and expiry.
    ///
    /// `RuntimeReceiptObserver` handled `.capabilityRevoked` and `.capabilityLeaseExpired` and fell
    /// through everything else, so the ledger recorded every *withdrawal* of authority and no
    /// issuance of it: a lease granted and later expired appeared as an expiry with no origin, and a
    /// lease still live appeared nowhere at all.
    @Test("granting a capability lease writes a durable receipt")
    func grantIsReceipted() async throws {
        let store = LedgerReceiptStore()
        let host = RuntimeHost(receiptStore: store)
        await host.bootstrap()

        let lease = await host.grantCapabilityLease(
            capability: .draftTransaction,
            grantedTo: .human,
            reason: "Reviewing a prepared action.",
            correlationID: "corr-grant"
        )

        // Narrowed to *this* grant: bootstrap's own seed grants are receipted too, so matching on the
        // kind alone would assert against whichever seed receipt happened to land first.
        let receipt = try await eventually(in: store) {
            $0.trigger == "runtime.capability.granted"
                && $0.details.values["capability"] == .string(CapabilityID.draftTransaction.rawValue)
        }
        #expect(receipt.details.values["capability"] == .string(lease.capability.rawValue))
        #expect(receipt.details.values["grantedTo"] == .string(Self.name(of: .human)))
        #expect(receipt.details.values["reason"] == .string("Reviewing a prepared action."))
        // The wallet flag is what makes a crypto grant findable in the ledger without re-deriving
        // the capability taxonomy at read time.
        #expect(receipt.details.values["isCrypto"] == .bool(true))
    }

    /// Applying a restriction is the strongest governance act available — `grantingLease` honours it
    /// ahead of any grant — and it wrote nothing to the ledger at all. Both paths published only a
    /// free-text `executionUpdate`, which the receipt observer cannot classify.
    @Test("denying and then lifting a capability restriction are both receipted")
    func restrictionDecisionsAreReceipted() async throws {
        let store = LedgerReceiptStore()
        let host = RuntimeHost(receiptStore: store)
        await host.bootstrap()

        let restriction = await host.denyCapability(
            .capability(.approveSpending),
            reason: "No token approvals for now.",
            appliesTo: .human,
            correlationID: "corr-restriction"
        )

        let denial = try await eventually(in: store) { $0.trigger == "runtime.capability.denied" }
        #expect(denial.correlationID == "corr-restriction")
        #expect(denial.details.values["reason"] == .string("No token approvals for now."))
        #expect(denial.details.values["restrictionID"] == .string(restriction.id.uuidString))
        #expect(denial.details.values["appliesTo"] == .string(Self.name(of: .human)))
        // A person made this call, and the receipt has to say so rather than blaming the runtime.
        #expect(denial.actorDetail?.kind == ActorKind.human.rawValue)
        #expect(denial.authorityDetail?.source == "humanApproval")

        await host.revokeCapabilityRestriction(id: restriction.id)

        let lifted = try await eventually(in: store) { $0.trigger == "runtime.capability.restrictionRevoked" }
        #expect(lifted.details.values["restrictionID"] == .string(restriction.id.uuidString))
        #expect(lifted.authorityDetail?.source == "humanApproval")
    }

    /// How the runtime names an actor in these receipts. Derived rather than spelled out, so the
    /// assertions track the identifier/display-title fallback instead of pinning today's string.
    private static func name(of actor: ActorRef) -> String {
        actor.identifier ?? actor.kind.displayTitle
    }

    /// The grant receipt is written by the event observer, which consumes the bus asynchronously, so
    /// the assertion has to wait for it rather than read once and race it.
    private func eventually(
        in store: LedgerReceiptStore,
        matching predicate: @escaping (ReceiptRecord) -> Bool
    ) async throws -> ReceiptRecord {
        for _ in 0..<200 {
            if let match = ((try? await store.latest(limit: 200)) ?? []).first(where: predicate) {
                return match
            }
            try? await Task.sleep(for: .milliseconds(10))
        }
        throw NoMatchingReceipt()
    }

    private struct NoMatchingReceipt: Error { }
}
