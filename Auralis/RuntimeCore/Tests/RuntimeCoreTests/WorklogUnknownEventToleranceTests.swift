import AuralisFoundation
import Foundation
@testable import RuntimeCore
import Testing

/// Pins L-09: a worklog entry written by a newer build must survive being read by an older one.
///
/// The stores read through `try?`/`compactMap`, so a throwing event decode does not surface as an
/// error — it silently deletes the entry, taking the actor, authority, correlationID, and timestamp
/// with it. A workflow then reads as though it skipped a step rather than as though one step was
/// unreadable, which is the failure these tests exist to prevent.
@Suite("Worklog unknown-event tolerance")
struct WorklogUnknownEventToleranceTests {
    private let decoder = JSONDecoder()

    private func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }

    /// A step whose `event` object is spelled however the caller wants, with everything else the
    /// same as a real entry.
    private func stepJSON(event: String) -> Data {
        Data("""
        {
          "id": "8A1C2D3E-4F50-4617-9283-A4B5C6D7E8F9",
          "correlationID": "corr-future",
          "toolID": "tool.future",
          "event": \(event),
          "actor": { "kind": "operator", "identifier": "future.operator" },
          "timestamp": 1000
        }
        """.utf8)
    }

    // MARK: - Unfamiliar case names

    @Test("an unrecognized event kind keeps the entry instead of dropping it")
    func unknownCaseNameKeepsTheEntry() throws {
        let step = try decoder.decode(
            WorkflowStepLog.self,
            from: stepJSON(event: #"{ "delegated": { "to": "peer-agent", "hops": 2 } }"#)
        )

        // The point of the fallback: the attribution legs are exactly what make the rest of the
        // trace legible, and they are intact.
        #expect(step.correlationID == "corr-future")
        #expect(step.toolID == "tool.future")
        #expect(step.actor.identifier == "future.operator")
        // `1000` in the fixture is the default `deferredToDate` strategy's reference-date offset.
        #expect(step.timestamp == Date(timeIntervalSinceReferenceDate: 1_000))

        guard case let .unknown(caseName, payload) = step.event else {
            Issue.record("expected an unknown event, got \(step.event)")
            return
        }
        #expect(caseName == "delegated")
        #expect(payload == .object(["to": .string("peer-agent"), "hops": .integer(2)]))
    }

    /// The whole reason the payload is carried verbatim: a downgrade must degrade *rendering*, not
    /// destroy data. If `.unknown` re-encoded as an `unknown` wrapper, the first export taken on the
    /// older build would make the loss permanent.
    @Test("an unrecognized event re-encodes under its original name, byte for byte")
    func unknownEventRoundTripsLosslessly() throws {
        let event = #"{ "delegated": { "hops": 2, "nested": [ 1, true, null, "x" ], "to": "peer" } }"#
        let step = try decoder.decode(WorkflowStepLog.self, from: stepJSON(event: event))

        let reEncoded = try encoder().encode(step)
        let reDecoded = try decoder.decode(WorkflowStepLog.self, from: reEncoded)
        #expect(reDecoded == step)

        // And the bytes themselves still spell the original case name, so a build that *does* know
        // `delegated` reads the real event back out of this export.
        let json = try #require(String(data: reEncoded, encoding: .utf8))
        #expect(json.contains(#""delegated""#))
        #expect(json.contains(#""peer""#))
        #expect(!json.contains("unknown"))
    }

    // MARK: - Newer routine phases

    /// `RoutinePhase` stays a closed enum so its derivations remain exhaustive, which means a newer
    /// phase fails the `routinePhase` decode. That has to degrade to `.unknown` rather than throw —
    /// and the unknown phase's raw name has to survive inside the payload.
    @Test("a routine phase this build does not know keeps the entry and its raw name")
    func unknownRoutinePhaseKeepsTheEntry() throws {
        let step = try decoder.decode(
            WorkflowStepLog.self,
            from: stepJSON(event: #"{ "routinePhase": { "_0": "quarantined", "detail": "held" } }"#)
        )

        guard case let .unknown(caseName, payload) = step.event else {
            Issue.record("expected an unknown event, got \(step.event)")
            return
        }
        #expect(caseName == "routinePhase")
        #expect(payload == .object(["_0": .string("quarantined"), "detail": .string("held")]))
    }

    @Test("a known routine phase still decodes as itself")
    func knownRoutinePhaseIsUnaffected() throws {
        let step = try decoder.decode(
            WorkflowStepLog.self,
            from: stepJSON(event: #"{ "routinePhase": { "_0": "completed", "detail": null } }"#)
        )
        #expect(step.event == .routinePhase(.completed, detail: nil))
    }

    // MARK: - Corrupt payloads

    /// A known case name whose payload this build cannot read lands in the same place. Keeping it is
    /// still the better trade: the bytes are preserved for a later build, and the surrounding trace
    /// keeps its shape.
    @Test("a known event with an unreadable payload keeps the entry")
    func unreadableKnownPayloadKeepsTheEntry() throws {
        let step = try decoder.decode(
            WorkflowStepLog.self,
            from: stepJSON(event: #"{ "blocked": { "reason": 42 } }"#)
        )

        guard case let .unknown(caseName, payload) = step.event else {
            Issue.record("expected an unknown event, got \(step.event)")
            return
        }
        #expect(caseName == "blocked")
        #expect(payload == .object(["reason": .integer(42)]))
    }

    // MARK: - No regression for the known cases

    /// Guards the mirror enum that generates the known cases' wire format. If `KnownWorklogEvent`
    /// ever drifts from `WorkflowWorklogEvent` — a case added to one and not the other — the
    /// symptom would be a real event quietly decoding as `.unknown` on the very build that wrote
    /// it. Every case round-trips here so that drift fails loudly instead.
    @Test("every known event still round-trips as itself, not as unknown", arguments: [
        WorkflowWorklogEvent.considered([
            ConsideredCandidate(
                title: "organize-library",
                capability: .autoOrganization,
                wasSelected: true,
                rationale: "Matched the goal."
            )
        ]),
        .proposed(
            ActionProposal(actor: .system, intent: "play", capability: .audioPlayback, impact: .readOnly)
        ),
        .checksEvaluated([
            DeterministicCheckResult(checkID: "address", passed: false, detail: "bad checksum")
        ]),
        .decided(.block(reason: "policy")),
        .executed(artifactID: UUID(uuidString: "5C6D7E8F-9012-4345-8678-9ABCDEF01234")!, durationSeconds: 1.5),
        .blocked(reason: "policy"),
        .failed(reason: "network"),
        .routinePhase(.artifactRejected, detail: "output type not allowed"),
        .routinePhase(.completed, detail: nil)
    ])
    func knownEventsRoundTripUnchanged(event: WorkflowWorklogEvent) throws {
        let decoded = try decoder.decode(
            WorkflowWorklogEvent.self,
            from: try encoder().encode(event)
        )
        if case let .unknown(caseName, _) = decoded {
            Issue.record("\(event) degraded to unknown(\(caseName)) — the mirror enum has drifted")
            return
        }
        #expect(decoded == event)
    }

    // MARK: - Export contract

    /// ``WorklogExport`` promises two exports of one trace compare equal. An `.unknown` entry must
    /// not break that, or a single downgraded row turns every eval diff into noise.
    @Test("an unknown entry does not destabilize the export")
    func unknownEntryKeepsTheExportStable() async throws {
        let step = try decoder.decode(
            WorkflowStepLog.self,
            from: stepJSON(event: #"{ "delegated": { "b": 2, "a": 1 } }"#)
        )
        let worklog = InMemoryWorklog()
        await worklog.record(step)

        #expect(try await worklog.exportAll() == (try WorklogExport.encode([step])))
    }
}
