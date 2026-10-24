import CapabilitiesCore
import Foundation
@testable import RuntimeCore
import Testing

/// Pins the *tolerant* half of attribution decoding (P0.5-602, W4).
///
/// `ActorRef` was added to types that were already being persisted, and every store reads those rows
/// back through `compactMap`. A required attribution column therefore does not degrade to "row with a
/// missing actor" — it deletes the row. For the worklog that silently shortens history; for a lease it
/// silently withdraws authority. Both are worse than an imprecise actor.
///
/// These use JSON literals rather than round-trips on purpose: a round-trip encodes and decodes with
/// the same symbols, so it passes no matter how the field is declared. Only a fixture that genuinely
/// lacks the key proves the fallback exists.
@Suite("Attribution tolerant decoding")
struct AttributionTolerantDecodingTests {
    @Test("a worklog entry with no actor decodes as system rather than being dropped")
    func worklogEntryWithoutActorDecodes() throws {
        let json = Data("""
        {
          "id": "1B3B2E4E-0000-4000-8000-00000000AAAA",
          "event": { "blocked": { "reason": "no lease" } },
          "timestamp": 0
        }
        """.utf8)

        let step = try JSONDecoder().decode(WorkflowStepLog.self, from: json)

        #expect(step.actor == .system)
        #expect(step.authority == nil)
        #expect(step.event == .blocked(reason: "no lease"))
    }

    @Test("a lease with no grantedTo decodes as system rather than being dropped")
    func leaseWithoutGrantedToDecodes() throws {
        let lease = try decodeLegacyLease()

        #expect(lease.grantedTo == .system)
        #expect(lease.capability == .runPlugin)
        #expect(lease.reason == "legacy grant")
        #expect(lease.scope == .execution)
    }

    /// The fallback must not become a skeleton key. `.system` is the conservative reading of "we no
    /// longer know who this was granted to" — it keeps the row inspectable without silently extending
    /// the grant to a named agent that was never on it.
    @Test("the system fallback does not widen a legacy lease to a named actor")
    func systemFallbackDoesNotWidenAuthority() throws {
        let lease = try decodeLegacyLease()
        let now = Date(timeIntervalSinceReferenceDate: 500)

        #expect(lease.isActive(at: now))
        #expect(lease.grants(capability: .runPlugin, to: .system, correlationID: nil, at: now))
        #expect(!lease.grants(
            capability: .runPlugin,
            to: ActorRef(kind: .operatorAgent, identifier: "music.organizer"),
            correlationID: nil,
            at: now
        ))
    }

    /// The authority column has the same shape of risk as the actor column, from the other direction:
    /// `AuthorityRef.Source` is a raw-value enum, so a fourth source written by a newer build throws
    /// on decode and takes the whole row with it. An unreadable authority must cost the field, not the
    /// history.
    ///
    /// These rewrite encoded JSON rather than using a literal because the value under test is one this
    /// build has no symbol for — there is no `Source` case to encode, so it can only be injected.
    @Test("a worklog entry with an unreadable authority source keeps the entry")
    func worklogEntryWithUnknownAuthoritySourceSurvives() throws {
        let step = WorkflowStepLog(
            correlationID: "run-1",
            toolID: "wallet.send",
            event: .executed(artifactID: UUID(), durationSeconds: 2),
            actor: ActorRef(kind: .scheduledRoutine, identifier: "cron.morning"),
            authority: .humanApproval(capability: .runPlugin, reason: "approved once")
        )

        let decoded = try JSONDecoder().decode(
            WorkflowStepLog.self,
            from: try rewritingAuthoritySource(of: step, to: "delegatedMandate")
        )

        #expect(decoded.authority == nil)
        #expect(decoded.actor.identifier == "cron.morning")
        #expect(decoded.correlationID == "run-1")
        #expect(decoded.event == step.event)
    }

    @Test("a session with an unreadable authority source keeps the session")
    func sessionWithUnknownAuthoritySourceSurvives() throws {
        var session = AgentSession(
            correlationID: "run-2",
            goal: "Summarize the week",
            actor: ActorRef(kind: .operatorAgent, identifier: "music.organizer")
        )
        session.note(authority: .humanApproval(capability: .runPlugin, reason: "approved once"))
        session.note(receiptID: UUID())

        let decoded = try JSONDecoder().decode(
            AgentSession.self,
            from: try rewritingAuthoritySource(of: session, to: "delegatedMandate")
        )

        #expect(decoded.authority == nil)
        #expect(decoded.actor.identifier == "music.organizer")
        #expect(decoded.goal == "Summarize the week")
        #expect(decoded.receiptIDs.count == 1)
    }

    /// Encodes `value`, replaces its `authority.source` with `source`, and returns the result — a row
    /// as a build that knows a further authority source would have written it.
    private func rewritingAuthoritySource(of value: some Encodable, to source: String) throws -> Data {
        let encoded = try JSONEncoder().encode(value)
        let raw = try JSONSerialization.jsonObject(with: encoded)
        var object = try #require(raw as? [String: Any])
        var authority = try #require(object["authority"] as? [String: Any])
        authority["source"] = source
        object["authority"] = authority
        return try JSONSerialization.data(withJSONObject: object)
    }

    /// A lease persisted before `ActorRef` existed: every column present except `grantedTo`.
    private func decodeLegacyLease() throws -> CapabilityLease {
        let json = Data("""
        {
          "id": "1B3B2E4E-0000-4000-8000-00000000BBBB",
          "capability": "run_plugin",
          "reason": "legacy grant",
          "scope": "execution",
          "grantedAt": 0,
          "expiresAt": 1000
        }
        """.utf8)
        return try JSONDecoder().decode(CapabilityLease.self, from: json)
    }
}
