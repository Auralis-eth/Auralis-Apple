import AuralisFoundation
import Foundation
@testable import AuralisRuntime
import Testing

/// Runtime events are persisted and read back through `compactMap`, so an event shape this build
/// cannot interpret has to degrade to ``WorkflowEvent/unknown(caseName:payload:)`` rather than throw.
/// A throw here does not lose one field — it deletes the whole envelope, taking the timestamp and
/// correlationID that place the event in a trace with it, and stranding any
/// ``RuntimeEventBus/reliableEvents`` checkpoint that pointed at it. Same L-09 posture as
/// ``WorkflowWorklogEvent``.
@Suite("Runtime event tolerance")
struct RuntimeEventToleranceTests {
    private static let lease = CapabilityLease(
        capability: .audioPlayback,
        grantedTo: .human,
        expiresAt: Date(timeIntervalSince1970: 2_000_000)
    )

    private static let knownEvents: [WorkflowEvent] = [
        .sessionStarted(correlationID: "corr", goal: "goal"),
        .sessionEnded(correlationID: "corr", status: .completed),
        .plannerStarted(goal: "goal"),
        .plannerCompleted(selectedCount: 2, rejectedCount: 3),
        .plannerFailed(reason: "no plan"),
        .policyDecision("allowed"),
        .workflowStarted,
        .workflowBlocked(reason: "nope"),
        .receiptCreated(id: UUID()),
        .artifactCreated(id: UUID()),
        .checkFailed(id: "address.format", reason: "malformed"),
        .capabilityRevoked(.signMessage),
        .capabilityLeaseGranted(lease),
        .capabilityLeaseExpired(.audioPlayback),
        .contextRefreshed(key: "balance"),
        .memoryTouched(kind: .memoryRead, key: "notes"),
        .executionUpdate("working")
    ]

    @Test("every known event round-trips as itself, not as unknown", arguments: knownEvents)
    func knownEventsRoundTrip(event: WorkflowEvent) throws {
        let data = try JSONEncoder().encode(event)
        #expect(try JSONDecoder().decode(WorkflowEvent.self, from: data) == event)
    }

    @Test("an approval-required event round-trips with its request intact")
    func approvalRequiredRoundTrips() throws {
        let request = ApprovalRequest(
            proposal: ActionProposal(
                actor: .human,
                intent: "sign",
                capability: .signMessage,
                impact: .highRisk
            ),
            prompt: "Approve?"
        )
        let event = WorkflowEvent.approvalRequired(request)
        let decoded = try JSONDecoder().decode(WorkflowEvent.self, from: JSONEncoder().encode(event))
        #expect(decoded == event)
    }

    @Test("an event case this build does not know keeps the entry and its payload")
    func unknownCaseIsPreserved() throws {
        // The shape a newer build would write for a case that does not exist here.
        let json = Data(#"{"quorumReached":{"quorum":3,"topic":"transfer"}}"#.utf8)

        let decoded = try JSONDecoder().decode(WorkflowEvent.self, from: json)
        guard case let .unknown(caseName, payload) = decoded else {
            Issue.record("expected an unknown event, got \(decoded)")
            return
        }
        #expect(caseName == "quorumReached")
        #expect(payload == .object([
            "quorum": .integer(3),
            "topic": .string("transfer")
        ]))
    }

    @Test("an unknown event re-encodes under its original case name, losslessly")
    func unknownCaseReEncodesVerbatim() throws {
        let json = Data(#"{"quorumReached":{"quorum":3,"topic":"transfer"}}"#.utf8)
        let decoded = try JSONDecoder().decode(WorkflowEvent.self, from: json)

        let reEncoded = try JSONDecoder().decode(
            WorkflowEvent.self,
            from: JSONEncoder().encode(decoded)
        )
        // A newer build reading our export gets the real event back, so a downgrade degrades
        // rendering without destroying data.
        #expect(reEncoded == decoded)
    }

    @Test("a nested enum value this build cannot read keeps the entry")
    func unknownNestedStatusIsPreserved() throws {
        // `AgentSessionStatus` is a raw-value enum, so a newer status throws on decode. That must
        // degrade the event rather than delete the row.
        let json = Data(#"{"sessionEnded":{"correlationID":"corr","status":"awaitingQuorum"}}"#.utf8)

        let decoded = try JSONDecoder().decode(WorkflowEvent.self, from: json)
        guard case let .unknown(caseName, payload) = decoded else {
            Issue.record("expected an unknown event, got \(decoded)")
            return
        }
        #expect(caseName == "sessionEnded")
        // The unreadable status stays legible inside the payload.
        guard case let .object(fields) = payload else {
            Issue.record("expected an object payload, got \(payload)")
            return
        }
        #expect(fields["status"] == .string("awaitingQuorum"))
    }

    @Test("a whole envelope survives an uninterpretable event")
    func envelopeSurvivesUnknownEvent() throws {
        let id = UUID()
        let timestamp = Date(timeIntervalSince1970: 1_700_000_000)
        let json = Data("""
            {"id":"\(id.uuidString)","event":{"quorumReached":{"quorum":3}},\
            "correlationID":"corr","timestamp":\(timestamp.timeIntervalSinceReferenceDate)}
            """.utf8)

        let envelope = try JSONDecoder().decode(WorkflowEventEnvelope.self, from: json)
        // The metadata that makes the event legible in a trace is exactly what a throw used to cost.
        #expect(envelope.id == id)
        #expect(envelope.correlationID == "corr")
        #expect(envelope.timestamp == timestamp)
        guard case .unknown = envelope.event else {
            Issue.record("expected the unreadable event to degrade, got \(envelope.event)")
            return
        }
    }

    @Test("a multi-key event object is still rejected as corrupt")
    func multiKeyObjectIsRejected() {
        // Not a plausible downgrade — a synthesized enum is always a single-key object — so this is
        // corruption, and inventing an `unknown` case name for it would be a guess.
        let json = Data(#"{"workflowStarted":{},"policyDecision":"allowed"}"#.utf8)
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(WorkflowEvent.self, from: json)
        }
    }
}
