import Foundation
@testable import AuralisRuntime
import Testing

@Suite("PerformanceStore")
struct PerformanceStoreTests {
    @Test
    func computesHealthMetrics() async {
        let store = PerformanceStore()
        await store.record(PerformanceEvent(playbookID: "pb", outcome: .success, durationSeconds: 1))
        await store.record(PerformanceEvent(playbookID: "pb", outcome: .failed, durationSeconds: 3, requiredIntervention: true))
        let approvalRunID = UUID()
        await store.record(PerformanceEvent(playbookID: "pb", outcome: .needsApproval, durationSeconds: 2, runID: approvalRunID))
        await store.record(PerformanceEvent(playbookID: "pb", outcome: .blocked, durationSeconds: 0, blockCategory: .policy))
        await store.recordApprovalDecision(runID: approvalRunID, decision: .approved)

        let health = await store.health(forPlaybook: "pb")
        #expect(health.totalRuns == 4)
        #expect(health.failureCount == 1)
        #expect(abs(health.successRate - 0.25) < 0.0001)
        #expect(health.approvalRate == 1)
        #expect(health.resolvedApprovalCount == 1)
        #expect(abs(health.blockRate - 0.25) < 0.0001)
        #expect(abs(health.policyBlockRate - 0.25) < 0.0001)
        #expect(abs(health.interventionRate - 0.25) < 0.0001)
        #expect(abs(health.averageLatencySeconds - 1.5) < 0.0001)
    }

    @Test
    func approvalRateUsesOnlyResolvedHumanDecisions() async {
        let store = PerformanceStore()
        let approvedID = UUID()
        let rejectedID = UUID()
        await store.record(PerformanceEvent(playbookID: "pb", outcome: .needsApproval, durationSeconds: 1, runID: approvedID))
        await store.record(PerformanceEvent(playbookID: "pb", outcome: .needsApproval, durationSeconds: 1, runID: rejectedID))
        await store.record(PerformanceEvent(playbookID: "pb", outcome: .needsApproval, durationSeconds: 1, runID: UUID()))

        await store.recordApprovalDecision(runID: approvedID, decision: .approved)
        await store.recordApprovalDecision(runID: rejectedID, decision: .rejected)

        let health = await store.health(forPlaybook: "pb")
        #expect(health.resolvedApprovalCount == 2)
        #expect(health.approvalRate == 0.5)
    }

    @Test
    func policyBlockRateExcludesOtherBlockCategories() {
        let events = [
            PerformanceEvent(playbookID: "pb", outcome: .blocked, durationSeconds: 0, blockCategory: .policy),
            PerformanceEvent(playbookID: "pb", outcome: .blocked, durationSeconds: 0, blockCategory: .authority),
            PerformanceEvent(playbookID: "pb", outcome: .blocked, durationSeconds: 0, blockCategory: .context),
            PerformanceEvent(playbookID: "pb", outcome: .success, durationSeconds: 1)
        ]

        let health = PlaybookHealth(playbookID: "pb", events: events)
        #expect(health.blockRate == 0.75)
        #expect(health.policyBlockRate == 0.25)
    }

    @Test
    func emptyPlaybookHasZeroedHealth() async {
        let store = PerformanceStore()
        let health = await store.health(forPlaybook: "unknown")
        #expect(health.totalRuns == 0)
        #expect(health.successRate == 0)
        #expect(health.classification == .insufficientData)
    }

    @Test
    func classifiesStableAndFlakyPlaybooksDeterministically() {
        let stableEvents = (0..<5).map { _ in
            PerformanceEvent(playbookID: "stable", outcome: .success, durationSeconds: 1)
        }
        let flakyEvents = [
            PerformanceEvent(playbookID: "flaky", outcome: .failed, durationSeconds: 1, failureReason: "timeout"),
            PerformanceEvent(playbookID: "flaky", outcome: .failed, durationSeconds: 1, failureReason: "timeout"),
            PerformanceEvent(playbookID: "flaky", outcome: .success, durationSeconds: 1),
            PerformanceEvent(playbookID: "flaky", outcome: .success, durationSeconds: 1),
            PerformanceEvent(playbookID: "flaky", outcome: .success, durationSeconds: 1)
        ]

        #expect(PlaybookHealth(playbookID: "stable", events: stableEvents).classification == .stable)
        #expect(PlaybookHealth(playbookID: "flaky", events: flakyEvents).classification == .flaky)
    }

    @Test
    func classificationRequiresEnoughRuns() {
        let events = (0..<4).map { _ in
            PerformanceEvent(playbookID: "new", outcome: .failed, durationSeconds: 1)
        }
        #expect(PlaybookHealth(playbookID: "new", events: events).classification == .insufficientData)
    }

    @Test
    func allHealthGroupsByPlaybook() async {
        let store = PerformanceStore()
        await store.record(PerformanceEvent(playbookID: "a", outcome: .success, durationSeconds: 1))
        await store.record(PerformanceEvent(playbookID: "b", outcome: .success, durationSeconds: 1))
        let all = await store.allHealth()
        #expect(all.map(\.playbookID) == ["a", "b"])
    }

    @Test
    func recordInterventionMarksTheRunWithoutAddingOne() async {
        let store = PerformanceStore()
        let runID = UUID()
        await store.record(PerformanceEvent(playbookID: "pb", outcome: .success, durationSeconds: 1, runID: runID))
        await store.record(PerformanceEvent(playbookID: "pb", outcome: .success, durationSeconds: 1, runID: UUID()))

        // Before: nobody stepped in.
        #expect(await store.health(forPlaybook: "pb").interventionRate == 0)

        await store.recordIntervention(runID: runID)

        let health = await store.health(forPlaybook: "pb")
        // Intervention is a property of an existing run, so the run count is unchanged (2)…
        #expect(health.totalRuns == 2)
        // …and exactly one of the two runs is now flagged.
        #expect(abs(health.interventionRate - 0.5) < 0.0001)
    }

    @Test
    func recordInterventionIsANoOpForUnknownRun() async {
        let store = PerformanceStore()
        await store.record(PerformanceEvent(playbookID: "pb", outcome: .success, durationSeconds: 1, runID: UUID()))
        await store.recordIntervention(runID: UUID())
        #expect(await store.health(forPlaybook: "pb").interventionRate == 0)
    }

    @Test
    func failurePatternsGroupByReasonMostFrequentFirst() async {
        let base = Date()
        let events = [
            PerformanceEvent(playbookID: "pb", outcome: .failed, durationSeconds: 1, recordedAt: base, triggerSource: "schedule", failureReason: "provider timeout"),
            PerformanceEvent(playbookID: "pb", outcome: .failed, durationSeconds: 1, recordedAt: base.addingTimeInterval(60), triggerSource: "schedule", failureReason: "provider timeout"),
            PerformanceEvent(playbookID: "pb", outcome: .failed, durationSeconds: 1, recordedAt: base.addingTimeInterval(120), triggerSource: "manual", failureReason: "rate limited"),
            PerformanceEvent(playbookID: "pb", outcome: .success, durationSeconds: 1)
        ]
        let health = PlaybookHealth(playbookID: "pb", events: events)

        #expect(health.failureCount == 3)
        #expect(health.failurePatterns.count == 2)
        // Most frequent first, and it's flagged recurring.
        let top = health.failurePatterns[0]
        #expect(top.key == "provider timeout")
        #expect(top.occurrences == 2)
        #expect(top.isRecurring)
        #expect(top.lastSeen == base.addingTimeInterval(60))
        // The one-off is present but not recurring.
        #expect(health.failurePatterns[1].isRecurring == false)
    }

    @Test
    func failurePatternsFallBackToTriggerWhenNoReason() async {
        let events = [
            PerformanceEvent(playbookID: "pb", outcome: .failed, durationSeconds: 1, triggerSource: "artifactStale"),
            PerformanceEvent(playbookID: "pb", outcome: .failed, durationSeconds: 1, triggerSource: "artifactStale")
        ]
        let patterns = PlaybookHealth(playbookID: "pb", events: events).failurePatterns
        #expect(patterns.count == 1)
        #expect(patterns[0].key == "artifactStale trigger")
        #expect(patterns[0].occurrences == 2)
    }

    /// The contract `RuntimePerformanceObserver` relies on to survive a replay: it reuses the runtime
    /// event envelope's ID as the event ID and checkpoints only *after* recording, so a crash in
    /// between replays that event. Re-recording it must update the run, not add a second one.
    @Test("re-recording an event ID replaces the run instead of double-counting it")
    func recordingIsIdempotentByEventID() async {
        let store = PerformanceStore()
        let id = UUID()
        let base = Date(timeIntervalSince1970: 1_700_000_000)
        await store.record(
            PerformanceEvent(id: id, playbookID: "planner", outcome: .success, durationSeconds: 1, recordedAt: base)
        )
        await store.record(
            PerformanceEvent(
                playbookID: "planner",
                outcome: .success,
                durationSeconds: 1,
                recordedAt: base.addingTimeInterval(1)
            )
        )

        // The replay: same ID, and this time the run is known to have failed.
        await store.record(
            PerformanceEvent(
                id: id,
                playbookID: "planner",
                outcome: .failed,
                durationSeconds: 2,
                recordedAt: base,
                failureReason: "no candidate cleared"
            )
        )

        let health = await store.health(forPlaybook: "planner")
        #expect(health.totalRuns == 2)
        #expect(health.failureCount == 1)
        let events = await store.events(forPlaybook: "planner")
        #expect(events.count == 2)
        #expect(events.first?.id == id)
        #expect(events.first?.failureReason == "no candidate cleared")
    }

    /// A run that made several governed tool calls has several events; intervention is a property of
    /// the run, so all of them carry it. Marking only the first understated `interventionRate` by
    /// however many calls the run made, and disagreed with the durable `SwiftDataPerformanceStore`,
    /// which has always marked every matching row.
    @Test("intervention marks every event belonging to the run")
    func interventionMarksEveryEventOfTheRun() async {
        let store = PerformanceStore()
        let runID = UUID()
        for _ in 0..<3 {
            await store.record(PerformanceEvent(
                playbookID: "pb",
                outcome: .success,
                durationSeconds: 1,
                runID: runID
            ))
        }
        await store.record(PerformanceEvent(playbookID: "pb", outcome: .success, durationSeconds: 1, runID: UUID()))

        await store.recordIntervention(runID: runID)

        let events = await store.events(forPlaybook: "pb")
        #expect(events.filter(\.requiredIntervention).count == 3)
        #expect(await store.health(forPlaybook: "pb").interventionRate == 0.75)
    }

    /// The other half of the replay contract: a replayed event is rebuilt from the runtime envelope,
    /// so it never carries what a *person* later did to that run. Overwriting wholesale erased it.
    @Test("a replay preserves the intervention flag and approval decision already recorded")
    func replayDoesNotEraseHumanAnnotations() async {
        let store = PerformanceStore()
        let id = UUID()
        let runID = UUID()
        let event = PerformanceEvent(
            id: id,
            playbookID: "planner",
            outcome: .needsApproval,
            durationSeconds: 1,
            runID: runID
        )
        await store.record(event)
        await store.recordIntervention(runID: runID)
        await store.recordApprovalDecision(runID: runID, decision: .approved)

        // The replay: same envelope, reconstructed, so unannotated.
        await store.record(event)

        let replayed = await store.events(forPlaybook: "planner")
        #expect(replayed.count == 1)
        #expect(replayed.first?.requiredIntervention == true)
        #expect(replayed.first?.approvalDecision == .approved)
        let health = await store.health(forPlaybook: "planner")
        #expect(health.interventionRate == 1)
        #expect(health.resolvedApprovalCount == 1)
    }

    /// An incoming decision must still win, or a replay would pin the first answer forever.
    @Test("a re-record carrying its own decision overrides the stored one")
    func reRecordedDecisionWins() async {
        let store = PerformanceStore()
        let id = UUID()
        let runID = UUID()
        await store.record(PerformanceEvent(id: id, playbookID: "pb", outcome: .needsApproval, durationSeconds: 1, runID: runID))
        await store.recordApprovalDecision(runID: runID, decision: .rejected)
        await store.record(PerformanceEvent(
            id: id,
            playbookID: "pb",
            outcome: .needsApproval,
            durationSeconds: 1,
            runID: runID,
            approvalDecision: .approved
        ))

        #expect(await store.events(forPlaybook: "pb").first?.approvalDecision == .approved)
    }

    /// `RuntimeHost` falls back to this store when no durable one is injected, and the tool-call sink
    /// records one event per governed call, so the history has to be bounded rather than grow for the
    /// life of the process. Every event here shares a timestamp, which is the case a date-only cutoff
    /// cannot separate — ties must still be droppable.
    @Test("history is capped, evicting the oldest runs first")
    func historyIsBoundedAndEvictsOldestFirst() async {
        let store = PerformanceStore()
        let base = Date(timeIntervalSince1970: 1_700_000_000)
        // Oldest, and distinguishable: it should be the first thing evicted.
        let oldestID = UUID()
        await store.record(PerformanceEvent(
            id: oldestID,
            playbookID: "pb",
            outcome: .success,
            durationSeconds: 1,
            recordedAt: base
        ))
        let newest = base.addingTimeInterval(60)
        for _ in 0..<4_200 {
            await store.record(PerformanceEvent(playbookID: "pb", outcome: .success, durationSeconds: 1, recordedAt: newest))
        }

        let events = await store.events(forPlaybook: "pb")
        #expect(events.count <= 4_096)
        #expect(events.contains { $0.id == oldestID } == false)
        // The survivors are the newest ones, and the cap did not corrupt the aggregate.
        #expect(await store.health(forPlaybook: "pb").totalRuns == events.count)
    }

    /// Idempotency must keep working across a trim: the ID index is rebuilt when events are evicted,
    /// and a stale index would either replace the wrong run or double-count this one.
    @Test("re-recording still replaces after the history has been trimmed")
    func idempotencySurvivesTrimming() async {
        let store = PerformanceStore()
        let base = Date(timeIntervalSince1970: 1_700_000_000)
        let survivorID = UUID()
        for offset in 0..<4_200 {
            await store.record(PerformanceEvent(
                playbookID: "pb",
                outcome: .success,
                durationSeconds: 1,
                recordedAt: base.addingTimeInterval(Double(offset))
            ))
        }
        // Newest, so it survives the next trim.
        await store.record(PerformanceEvent(
            id: survivorID,
            playbookID: "pb",
            outcome: .success,
            durationSeconds: 1,
            recordedAt: base.addingTimeInterval(9_999)
        ))
        let countAfterFirstRecord = await store.events(forPlaybook: "pb").count

        await store.record(PerformanceEvent(
            id: survivorID,
            playbookID: "pb",
            outcome: .failed,
            durationSeconds: 1,
            recordedAt: base.addingTimeInterval(9_999)
        ))

        let events = await store.events(forPlaybook: "pb")
        #expect(events.count == countAfterFirstRecord)
        #expect(events.filter { $0.id == survivorID }.count == 1)
        #expect(events.last?.outcome == .failed)
    }

    /// `resetAll()` is a privacy requirement, not a convenience: run history names what the person's
    /// operators did and when.
    @Test
    func resetAllErasesEveryRecordedRun() async {
        let store = PerformanceStore()
        await store.record(PerformanceEvent(playbookID: "a", outcome: .success, durationSeconds: 1))
        await store.record(PerformanceEvent(playbookID: "b", outcome: .failed, durationSeconds: 1))

        await store.resetAll()

        #expect(await store.events(forPlaybook: "a").isEmpty)
        #expect(await store.allHealth().isEmpty)
        #expect(await store.health(forPlaybook: "a").classification == .insufficientData)

        // The store is still usable — reset must not leave a stale ID index behind.
        let id = UUID()
        await store.record(PerformanceEvent(id: id, playbookID: "a", outcome: .success, durationSeconds: 1))
        await store.record(PerformanceEvent(id: id, playbookID: "a", outcome: .success, durationSeconds: 1))
        #expect(await store.events(forPlaybook: "a").count == 1)
    }

    @Test
    func recordApprovalDecisionIsANoOpForUnknownRun() async {
        let store = PerformanceStore()
        await store.record(PerformanceEvent(playbookID: "pb", outcome: .needsApproval, durationSeconds: 1, runID: UUID()))

        await store.recordApprovalDecision(runID: UUID(), decision: .approved)

        let health = await store.health(forPlaybook: "pb")
        #expect(health.resolvedApprovalCount == 0)
        #expect(health.approvalRate == 0)
        #expect(health.totalRuns == 1)
    }

    @Test
    func eventsAreReturnedOldestFirstRegardlessOfRecordingOrder() async {
        let store = PerformanceStore()
        let base = Date(timeIntervalSince1970: 1_700_000_000)
        await store.record(PerformanceEvent(playbookID: "pb", outcome: .success, durationSeconds: 1, recordedAt: base.addingTimeInterval(120)))
        await store.record(PerformanceEvent(playbookID: "pb", outcome: .success, durationSeconds: 1, recordedAt: base))
        await store.record(PerformanceEvent(playbookID: "pb", outcome: .success, durationSeconds: 1, recordedAt: base.addingTimeInterval(60)))

        let recordedAt = await store.events(forPlaybook: "pb").map(\.recordedAt)
        #expect(recordedAt == [base, base.addingTimeInterval(60), base.addingTimeInterval(120)])
    }

    @Test
    func classifiesNeedsAttentionBetweenTheFailureFloors() async {
        // 1 failure in 10 runs: past the 10% floor, short of 25%, and no reason so nothing recurs.
        var events = [PerformanceEvent(playbookID: "pb", outcome: .failed, durationSeconds: 1, triggerSource: "schedule")]
        events += (0..<9).map { _ in PerformanceEvent(playbookID: "pb", outcome: .success, durationSeconds: 1) }

        #expect(PlaybookHealth(playbookID: "pb", events: events).classification == .needsAttention)
    }

    /// Intervention alone reaches `.needsAttention` even with nothing failing.
    @Test
    func interventionRateAloneReachesNeedsAttention() async {
        var events = (0..<9).map { _ in PerformanceEvent(playbookID: "pb", outcome: .success, durationSeconds: 1) }
        events.append(PerformanceEvent(playbookID: "pb", outcome: .success, durationSeconds: 1, requiredIntervention: true))

        #expect(PlaybookHealth(playbookID: "pb", events: events).classification == .needsAttention)
    }

    /// A recurring signature used to be the dominant term, so two identical failures condemned a
    /// playbook as `.flaky` at any volume — and, because patterns never age out, permanently.
    @Test("a recurring failure below the failure floor is not flaky")
    func rareRecurringFailureIsNotFlaky() async {
        var events = (0..<2).map { _ in
            PerformanceEvent(playbookID: "pb", outcome: .failed, durationSeconds: 1, failureReason: "provider timeout")
        }
        events += (0..<998).map { _ in PerformanceEvent(playbookID: "pb", outcome: .success, durationSeconds: 1) }

        let health = PlaybookHealth(playbookID: "pb", events: events)
        // The pattern is still reported — it just no longer decides the classification.
        #expect(health.failurePatterns.first?.isRecurring == true)
        #expect(health.classification == .stable)
    }

    /// The same signature at a rate that matters is still flaky, below the blunt 25% threshold.
    @Test("a recurring failure at a rate that matters is still flaky")
    func recurringFailureAboveTheFloorIsFlaky() async {
        var events = (0..<2).map { _ in
            PerformanceEvent(playbookID: "pb", outcome: .failed, durationSeconds: 1, failureReason: "provider timeout")
        }
        events += (0..<8).map { _ in PerformanceEvent(playbookID: "pb", outcome: .success, durationSeconds: 1) }

        #expect(PlaybookHealth(playbookID: "pb", events: events).classification == .flaky)
    }

    /// One bad sample would otherwise poison the playbook's whole mean and render as "nan".
    @Test("non-finite and negative durations are clamped at the boundary")
    func durationsAreClamped() async {
        let events = [
            PerformanceEvent(playbookID: "pb", outcome: .success, durationSeconds: .nan),
            PerformanceEvent(playbookID: "pb", outcome: .success, durationSeconds: -5),
            PerformanceEvent(playbookID: "pb", outcome: .success, durationSeconds: .infinity),
            PerformanceEvent(playbookID: "pb", outcome: .success, durationSeconds: 4)
        ]

        #expect(events.allSatisfy { $0.durationSeconds >= 0 && $0.durationSeconds.isFinite })
        #expect(PlaybookHealth(playbookID: "pb", events: events).averageLatencySeconds == 1)
    }

    /// This type *is* the persisted schema — `SwiftDataPerformanceStore` stores a JSON blob per row and
    /// drops any row it cannot decode — so a field a newer build added must degrade, not delete the run.
    @Test("an unknown block category decodes to .other instead of discarding the run")
    func unknownRawValuesDegradeRatherThanFailDecoding() throws {
        let id = UUID()
        let json = """
        {
            "id": "\(id.uuidString)",
            "playbookID": "pb",
            "outcome": "quarantined",
            "durationSeconds": 2,
            "requiredIntervention": true,
            "recordedAt": 1700000000,
            "blockCategory": "quota",
            "approvalDecision": "deferred"
        }
        """

        let decoder = JSONDecoder()
        let event = try decoder.decode(PerformanceEvent.self, from: Data(json.utf8))

        #expect(event.id == id)
        #expect(event.playbookID == "pb")
        #expect(event.durationSeconds == 2)
        #expect(event.requiredIntervention)
        // Unknown category has a bucket; unknown outcome and decision do not, so they take the
        // inert defaults rather than fabricating a failure or a resolved approval.
        #expect(event.blockCategory == .other)
        #expect(event.outcome == .noOp)
        #expect(event.approvalDecision == nil)
    }

    /// The pre-intervention-tracking blobs the optional `runID` already exists for: absent keys must
    /// default, and an absent `blockCategory` must stay `nil` rather than inventing an `.other` block.
    @Test("an event blob missing newer keys still decodes")
    func missingKeysDefaultRatherThanThrowing() throws {
        let json = """
        {
            "id": "\(UUID().uuidString)",
            "playbookID": "pb",
            "outcome": "success",
            "durationSeconds": 1,
            "recordedAt": 1700000000
        }
        """

        let event = try JSONDecoder().decode(PerformanceEvent.self, from: Data(json.utf8))

        #expect(event.outcome == .success)
        #expect(event.requiredIntervention == false)
        #expect(event.runID == nil)
        #expect(event.blockCategory == nil)
        #expect(event.approvalDecision == nil)
    }

    @Test
    func knownEventRoundTripsThroughCoding() throws {
        let event = PerformanceEvent(
            playbookID: "pb",
            outcome: .blocked,
            durationSeconds: 3,
            requiredIntervention: true,
            runID: UUID(),
            triggerSource: "schedule",
            failureReason: "rate limited",
            blockCategory: .authority,
            approvalDecision: .rejected
        )

        let decoded = try JSONDecoder().decode(
            PerformanceEvent.self,
            from: try JSONEncoder().encode(event)
        )
        #expect(decoded == event)
    }
}
