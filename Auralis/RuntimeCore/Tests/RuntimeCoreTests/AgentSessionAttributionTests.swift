import CapabilitiesCore
import Foundation
@testable import RuntimeCore
import Testing

/// `AgentSession` is the "run" concept the governed pipeline opens for every tool call, and it is
/// persisted as a JSON blob read back through `compactMap`. Its attribution therefore has two
/// obligations that nothing else covers: the actor must be required at construction (so no call site
/// can quietly record an anonymous session), and both attribution columns must survive the blob
/// round-trip while still tolerating rows written before they existed. (P0.5-601/602)
@Suite("AgentSession attribution")
struct AgentSessionAttributionTests {
    private func roundTrip(_ session: AgentSession) throws -> AgentSession {
        let data = try JSONEncoder().encode(session)
        return try JSONDecoder().decode(AgentSession.self, from: data)
    }

    @Test("the constructing actor is what the session reports")
    func actorIsRetained() {
        let planner = ActorRef(kind: .workflow, identifier: "planner.daily", displayName: "Daily Planner")
        let session = AgentSession(correlationID: "c1", goal: "organize", actor: planner)

        #expect(session.actor == planner)
        #expect(session.actor.kind == .workflow)
        #expect(session.actor.identifier == "planner.daily")
    }

    @Test("actor survives the persistence round-trip")
    func actorSurvivesRoundTrip() throws {
        let session = AgentSession(
            correlationID: "c1",
            goal: "organize",
            actor: ActorRef(kind: .operatorAgent, identifier: "operator.research")
        )

        let decoded = try roundTrip(session)

        #expect(decoded.actor == session.actor)
        #expect(decoded.actor.kind == .operatorAgent)
        #expect(decoded.actor.identifier == "operator.research")
    }

    @Test("a model actor keeps its inference provenance across the round-trip")
    func modelActorProvenanceSurvivesRoundTrip() throws {
        let session = AgentSession(
            correlationID: "c1",
            goal: "summarize",
            actor: .model(
                identifier: "foundation.on-device",
                inference: InferenceProvenance(locality: .local, provider: "apple", modelClass: "afm")
            )
        )

        let decoded = try roundTrip(session)

        #expect(decoded.actor.kind == .model)
        #expect(decoded.actor.inference?.locality == .local)
        #expect(decoded.actor.inference?.provider == "apple")
        #expect(decoded.actor.inference?.modelClass == "afm")
    }

    @Test("a session persisted before the actor column decodes as system rather than being dropped")
    func legacySessionWithoutActorDecodes() throws {
        // Fixture, not a round-trip: only JSON that genuinely lacks the key proves the fallback.
        let json = Data("""
        {
            "id": "5F7E4C6A-0000-4000-8000-000000000042",
            "correlationID": "legacy-1",
            "goal": "old work",
            "goals": [],
            "startedAt": 715000000,
            "status": "active",
            "capabilities": [],
            "receiptIDs": [],
            "approvalIDs": [],
            "artifactIDs": [],
            "modelsUsed": [],
            "promptTokens": 0,
            "completionTokens": 0,
            "estimatedCost": 0,
            "memoryTouched": [],
            "executionUpdates": []
        }
        """.utf8)

        let decoded = try JSONDecoder().decode(AgentSession.self, from: json)

        #expect(decoded.actor == .system)
        #expect(decoded.authority == nil)
        #expect(decoded.modelHops == 0)
        #expect(decoded.correlationID == "legacy-1")
    }

    // --- authority ---

    @Test("a new session has no authority until one is resolved")
    func newSessionHasNoAuthority() {
        let session = AgentSession(correlationID: "c1", goal: "organize", actor: .human)
        #expect(session.authority == nil)
    }

    @Test("the first resolved grant is recorded and later ones do not overwrite it")
    func firstAuthorityWins() {
        var session = AgentSession(correlationID: "c1", goal: "organize", actor: .human)
        let first = AuthorityRef.humanApproval(capability: .autoOrganization, reason: "you approved")
        let second = AuthorityRef.policyDefault(capability: .runPlugin, reason: "standing policy")

        session.note(authority: first)
        session.note(authority: second)

        #expect(session.authority == first)
        #expect(session.authority?.source == .humanApproval)
        #expect(session.authority?.reason == "you approved")
    }

    @Test("authority survives the persistence round-trip")
    func authoritySurvivesRoundTrip() throws {
        let lease = CapabilityLease(
            capability: .autoOrganization,
            reason: "planner may organize",
            scope: CapabilityLeaseScope.defaultScope(for: .autoOrganization),
            grantedTo: ActorRef(kind: .workflow, identifier: "planner.daily"),
            grantedAt: Date(timeIntervalSince1970: 1_700_000_000),
            expiresAt: Date(timeIntervalSince1970: 1_700_003_600)
        )
        var session = AgentSession(
            correlationID: "c1",
            goal: "organize",
            actor: ActorRef(kind: .workflow, identifier: "planner.daily")
        )
        session.note(authority: AuthorityRef(lease: lease))

        let decoded = try roundTrip(session)

        #expect(decoded.authority?.source == .lease)
        #expect(decoded.authority?.leaseID == lease.id)
        #expect(decoded.authority?.capability == .autoOrganization)
        #expect(decoded.authority?.reason == "planner may organize")
    }
}
