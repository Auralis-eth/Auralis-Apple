import AuralisRuntime
import Foundation
import AuralisReceipts
import RuntimeKit
import Testing

@testable import MissionControlFeature

@Suite("Mission Control report cards")
@MainActor
struct MissionControlReportCardTests {

    private func playbook(_ id: String, criteria: [SuccessCriterion]) -> Playbook {
        Playbook(
            id: id,
            name: id,
            summary: "s",
            trigger: .manual,
            authority: PlaybookAuthority(capabilities: [.runPlugin], allowedOutputs: [.brief]),
            completionCondition: "done",
            contextContract: .noContext(identifier: "test.\(id)"),
            outcome: criteria.isEmpty ? nil : OutcomeSpec(summary: "s", criteria: criteria),
            installState: .installed
        )
    }

    private func model(playbooks: [Playbook]) -> MissionControlHomeModel {
        let store = ReportCardReceiptStore()
        let host = RuntimeHost(
            receiptStore: store,
            stores: RuntimeHostStores(
                playbookStore: InMemoryPlaybookStore(seed: playbooks)
            )
        )
        return MissionControlHomeModel(host: host, receiptStore: store)
    }

    /// End to end through the real host: running two operators produces one card each, with grades
    /// attributed to the right operator.
    @Test func gradesAreGroupedOntoTheOperatorThatEarnedThem() async {
        let subject = model(playbooks: [
            playbook("p1", criteria: [.traceFullyLegible]),
            playbook("p2", criteria: [.traceFullyLegible])
        ])
        await subject.host.bootstrap()

        await subject.host.runRoutine(id: "p1")
        await subject.host.runRoutine(id: "p1")
        await subject.host.runRoutine(id: "p2")

        await subject.loadReportCards()

        #expect(subject.reportCards.map(\.playbookID) == ["p1", "p2"])
        #expect(subject.reportCards[0].gradedRunCount == 2)
        #expect(subject.reportCards[1].gradedRunCount == 1)
    }

    /// An operator with run history but no declared criteria still gets a card — showing it as
    /// ungraded, not as failing. A union rather than an intersection.
    @Test func anUngradedOperatorStillGetsACard() async {
        let subject = model(playbooks: [playbook("p1", criteria: [])])
        await subject.host.bootstrap()

        await subject.host.runRoutine(id: "p1")
        await subject.loadReportCards()

        let card = try? #require(subject.reportCards.first)
        #expect(card?.playbookID == "p1")
        #expect(card?.gradedRunCount == 0)
        #expect(card?.passRate == nil)
        #expect((card?.health.totalRuns ?? 0) > 0)
    }

    @Test func noHistoryYieldsNoCards() async {
        let subject = model(playbooks: [playbook("p1", criteria: [.traceFullyLegible])])
        await subject.host.bootstrap()

        await subject.loadReportCards()

        #expect(subject.reportCards.isEmpty)
    }

    /// Cards are sorted so the section order is stable between loads.
    @Test func cardsAreSortedByPlaybookID() async {
        let subject = model(playbooks: [
            playbook("zeta", criteria: [.traceFullyLegible]),
            playbook("alpha", criteria: [.traceFullyLegible])
        ])
        await subject.host.bootstrap()

        await subject.host.runRoutine(id: "zeta")
        await subject.host.runRoutine(id: "alpha")
        await subject.loadReportCards()

        #expect(subject.reportCards.map(\.playbookID) == ["alpha", "zeta"])
    }

    /// Reloading must not accumulate: a card's graded-run count reflects stored grades, not how many
    /// times the view appeared.
    @Test func reloadingDoesNotDoubleCountGrades() async {
        let subject = model(playbooks: [playbook("p1", criteria: [.traceFullyLegible])])
        await subject.host.bootstrap()
        await subject.host.runRoutine(id: "p1")

        await subject.loadReportCards()
        await subject.loadReportCards()

        #expect(subject.reportCards.count == 1)
        #expect(subject.reportCards[0].gradedRunCount == 1)
    }
}

private actor ReportCardReceiptStore: ReceiptStore {
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
