import AuralisFoundation
import Foundation
@testable import AuralisRuntime
import Testing

@Suite("Playbook")
struct PlaybookTests {
    private func playbook(_ id: String, capabilities: [CapabilityID], state: PlaybookInstallState = .available) -> Playbook {
        Playbook(
            id: id,
            name: id,
            summary: "does \(id)",
            trigger: .schedule(intervalSeconds: 3600),
            authority: PlaybookAuthority(capabilities: capabilities, allowedOutputs: [.brief]),
            completionCondition: "artifact produced",
            contextContract: .noContext(identifier: "test.\(id)")
        )
    }

    @Test
    func triggerClassification() {
        #expect(PlaybookTrigger.manual.classification == "manual")
        #expect(PlaybookTrigger.schedule(intervalSeconds: 60).classification == "time-based")
        #expect(PlaybookTrigger.event(.artifactStale).classification == "event-based")
        #expect(PlaybookTrigger.maintenance(intervalSeconds: 60).classification == "maintenance")
    }

    @Test
    func authorityDetectsCrypto() {
        #expect(playbook("crypto", capabilities: [.signMessage]).authority.touchesCrypto)
        #expect(playbook("music", capabilities: [.playlistManagement]).authority.touchesCrypto == false)
    }

    @Test
    func roundTripsThroughJSON() throws {
        let pb = Playbook(
            id: "research",
            name: "Research",
            summary: "does research",
            trigger: .maintenance(intervalSeconds: 3600),
            authority: PlaybookAuthority(
                capabilities: [.runPlugin],
                allowedOutputs: [.brief],
                approvalThreshold: 1,
                requiredApprovals: ["operator review"]
            ),
            completionCondition: "artifact produced",
            supportedFlows: [.read, .prepare],
            source: .user,
            contextContract: .noContext(identifier: "test.research")
        )
        let data = try JSONEncoder().encode(pb)
        let decoded = try JSONDecoder().decode(Playbook.self, from: data)
        #expect(decoded == pb)
        #expect(decoded.supportsV0ReadPrepareOnly)
    }

    @Test
    func legacyJSONDefaultsToSystemReadPrepare() throws {
        let legacy = """
        {
          "id": "legacy",
          "name": "Legacy",
          "summary": "old payload",
          "trigger": { "manual": {} },
          "authority": {
            "capabilities": ["run_plugin"],
            "allowedOutputs": ["brief"],
            "approvalThreshold": 0
          },
          "completionCondition": "done",
          "installState": "available"
        }
        """

        let decoded = try JSONDecoder().decode(Playbook.self, from: Data(legacy.utf8))

        #expect(decoded.source == .system)
        #expect(decoded.supportedFlows == [.read, .prepare])
        #expect(decoded.authority.requiredApprovals.isEmpty)
        #expect(decoded.supportsV0ReadPrepareOnly)
    }

    @Test
    func roundTripsOutcomeSpec() throws {
        let spec = OutcomeSpec(
            summary: "A brief lands unattended",
            criteria: [.producedArtifact, .completedWithin(seconds: 30), .judgeDidNotEscalate],
            proseCriteria: ["The brief is worth reading."]
        )
        let pb = Playbook(
            id: "research", name: "Research", summary: "does research",
            trigger: .manual,
            authority: PlaybookAuthority(capabilities: [.runPlugin], allowedOutputs: [.brief]),
            completionCondition: "artifact produced",
            contextContract: .noContext(identifier: "test.research"),
            outcome: spec
        )

        let decoded = try JSONDecoder().decode(Playbook.self, from: JSONEncoder().encode(pb))

        // Equality alone would pass if `outcome` were dropped on both sides, so assert the payload.
        #expect(decoded.outcome == spec)
        #expect(decoded.outcome?.criteria == [.producedArtifact, .completedWithin(seconds: 30), .judgeDidNotEscalate])
        #expect(decoded.outcome?.proseCriteria == ["The brief is worth reading."])
        #expect(decoded == pb)
    }

    /// A playbook persisted before contracts existed must still declare the operating context the
    /// routine operator actually supplies, or every legacy routine fails its bundle check.
    @Test
    func legacyContextContractDeclaresThePlaybookDefinitionFields() throws {
        let legacy = """
        {
          "id": "legacy",
          "name": "Legacy",
          "summary": "old payload",
          "trigger": { "manual": {} },
          "authority": { "capabilities": ["run_plugin"], "allowedOutputs": ["brief"] },
          "completionCondition": "done"
        }
        """

        let contract = try JSONDecoder().decode(Playbook.self, from: Data(legacy.utf8)).contextContract

        #expect(contract.identifier == "legacy.playbook.legacy")
        #expect(
            Set(contract.requirements.map(\.key)) == [
                "playbook", "playbook.name", "playbook.source", "playbook.trigger", "playbook.flows"
            ]
        )
        #expect(contract.requirements.allSatisfy { $0.authoritativeSource == .playbookDefinition })
        #expect(contract.missingFieldBehavior == .fail)
    }

    @Test
    func unschedulableIntervalsFallBackToAnHourlyCadence() throws {
        let fallback = PlaybookTrigger.fallbackIntervalSeconds

        #expect(PlaybookTrigger.schedule(intervalSeconds: 0).normalized == .schedule(intervalSeconds: fallback))
        #expect(PlaybookTrigger.schedule(intervalSeconds: -60).normalized == .schedule(intervalSeconds: fallback))
        #expect(PlaybookTrigger.maintenance(intervalSeconds: .nan).normalized == .maintenance(intervalSeconds: fallback))
        #expect(PlaybookTrigger.maintenance(intervalSeconds: .infinity).normalized == .maintenance(intervalSeconds: fallback))
        // A declared cadence, however short, is left exactly as authored.
        #expect(PlaybookTrigger.schedule(intervalSeconds: 10).normalized == .schedule(intervalSeconds: 10))
        #expect(PlaybookTrigger.manual.normalized == .manual)
        #expect(PlaybookTrigger.event(.artifactStale).normalized == .event(.artifactStale))

        // The guard has to hold on both paths into the model, not just the authoring one.
        #expect(playbookWithInterval(0).trigger == .schedule(intervalSeconds: fallback))
        let persisted = """
        { "id": "p", "name": "p", "summary": "s",
          "trigger": { "schedule": { "intervalSeconds": 0 } },
          "authority": { "capabilities": [], "allowedOutputs": [] },
          "completionCondition": "done" }
        """
        let decoded = try JSONDecoder().decode(Playbook.self, from: Data(persisted.utf8))
        #expect(decoded.trigger == .schedule(intervalSeconds: fallback))
    }

    private func playbookWithInterval(_ seconds: Double) -> Playbook {
        Playbook(
            id: "p", name: "p", summary: "s",
            trigger: .schedule(intervalSeconds: seconds),
            authority: PlaybookAuthority(capabilities: [], allowedOutputs: []),
            completionCondition: "done",
            contextContract: .noContext(identifier: "test.interval")
        )
    }

    @Test
    func executeFlowIsOutsideV0Policy() {
        let pb = Playbook(
            id: "execute", name: "Execute", summary: "x",
            trigger: .manual,
            authority: PlaybookAuthority(capabilities: [.runPlugin], allowedOutputs: [.brief]),
            completionCondition: "done",
            supportedFlows: [.read, .execute],
            contextContract: .noContext(identifier: "test.execute")
        )
        #expect(pb.supportsV0ReadPrepareOnly == false)
    }
}

@Suite("InMemoryPlaybookStore")
struct InMemoryPlaybookStoreTests {
    private func playbook(_ id: String, state: PlaybookInstallState) -> Playbook {
        Playbook(
            id: id, name: id, summary: "s",
            trigger: .manual,
            authority: PlaybookAuthority(capabilities: [.autoOrganization], allowedOutputs: [.report]),
            completionCondition: "done",
            contextContract: .noContext(identifier: "test.\(id)"),
            installState: state
        )
    }

    @Test
    func filtersByStateAndUpdates() async throws {
        let store = InMemoryPlaybookStore(seed: [
            playbook("a", state: .installed),
            playbook("b", state: .available)
        ])
        #expect(await store.playbooks(inState: .installed).map(\.id) == ["a"])

        try await store.setInstallState(id: "b", to: .installed)
        #expect(await store.playbooks(inState: .installed).map(\.id) == ["a", "b"])

        try await store.setInstallState(id: "a", to: .paused)
        #expect(await store.playbook(id: "a")?.installState == .paused)
    }

    /// A repeated ID is a seeding mistake, not a reason to take down the process: this store is the
    /// `RuntimeHost` fallback, so trapping here meant a launch crash.
    @Test
    func duplicateSeedIDsKeepTheLastDeclarationInsteadOfTrapping() async {
        let store = InMemoryPlaybookStore(seed: [
            playbook("dup", state: .available),
            playbook("dup", state: .installed),
            playbook("other", state: .available)
        ])

        #expect(await store.all().map(\.id) == ["dup", "other"])
        #expect(await store.playbook(id: "dup")?.installState == .installed)
    }

    /// Install/pause is a user-facing control, so a miss has to be reportable rather than look like
    /// a successful flip.
    @Test
    func setInstallStateThrowsForAnUnknownID() async throws {
        let store = InMemoryPlaybookStore(seed: [playbook("a", state: .available)])

        await #expect(throws: PlaybookStoreError.notFound(id: "ghost")) {
            try await store.setInstallState(id: "ghost", to: .installed)
        }
        #expect(await store.all().map(\.id) == ["a"])
        #expect(await store.playbook(id: "a")?.installState == .available)
    }
}
