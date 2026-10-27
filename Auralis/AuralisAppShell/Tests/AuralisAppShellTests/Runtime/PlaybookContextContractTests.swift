import AuralisReceipts
import AuralisPrimaryModels
import Foundation
import AuralisRuntime
@testable import AuralisAppShell
import Testing

/// Minimal in-memory receipt store: these tests assert on execution records and artifacts, so the
/// receipt leg only has to not fail.
private actor DiscardingReceiptStore: ReceiptStore {
    func append(_ receipt: ReceiptDraft) async throws -> ReceiptRecord {
        ReceiptRecord(
            id: UUID(), sequenceID: 1, createdAt: receipt.createdAt,
            actor: receipt.actor, actorDetail: receipt.actorDetail,
            authorityDetail: receipt.authorityDetail, mode: receipt.mode, trigger: receipt.trigger,
            scope: receipt.scope, summary: receipt.summary, provenance: receipt.provenance,
            isSuccess: receipt.isSuccess, correlationID: receipt.correlationID, details: receipt.details
        )
    }
    func latest(limit: Int) async throws -> [ReceiptRecord] { [] }
    func receipts(forCorrelationID correlationID: String, limit: Int) async throws -> [ReceiptRecord] { [] }
    func exportAll() async throws -> Data { Data() }
    func resetAll() async throws { }
}

/// P0.5-402 — context governance has to refuse playbooks that *over-reach*, not playbooks it merely
/// doesn't recognize. Keying contracts only by known id did the latter: a routine authored in Mission
/// Control had no declaration and so could never run, whatever it asked for.
@Suite("Playbook context contracts")
struct PlaybookContextContractTests {
    private func playbook(
        id: String,
        source: PlaybookSource,
        trigger: PlaybookTrigger = .manual
    ) -> Playbook {
        Playbook(
            id: id,
            name: "Playbook \(id)",
            summary: "Prepares a brief.",
            trigger: trigger,
            authority: PlaybookAuthority(capabilities: [.runPlugin], allowedOutputs: [.brief]),
            completionCondition: "A brief is prepared.",
            source: source,
            contextContract: SystemPlaybookContracts.contract(
                for: id,
                identifier: source == .user ? "user.playbook.\(id)" : "system.playbook.\(id)"
            ),
            installState: .installed
        )
    }

    @Test
    func userAuthoredPlaybookResolvesItsDeclaredContract() throws {
        let contract = try #require(
            SystemPlaybookContracts.registry.contract(for: playbook(id: "user.custom", source: .user))
        )

        #expect(contract.identifier == "user.playbook.user.custom")
    }

    @Test
    func systemDeclarationsAreValidAtRegistration() {
        #expect(SystemPlaybookContracts.registry.registrationErrors.isEmpty)
    }

    /// IDs in this catalogue are hand-written strings, and a duplicate one is silently destructive:
    /// `InMemoryPlaybookStore` — the store `RuntimeHost` falls back to, seeded from exactly this
    /// list — keeps only the last declaration, so a copy-pasted ID drops a shipped playbook from the
    /// library with no error anywhere. Catch it here, where it is a build-time mistake.
    @Test
    func systemPlaybookIDsAreUnique() {
        let ids = SystemPlaybooks.all.map(\.id)
        #expect(Set(ids).count == ids.count, "Duplicate system playbook IDs: \(ids.sorted())")
    }

    @Test
    func builtInPlaybookKeepsItsDeclaredContract() throws {
        let systemPlaybook = try #require(SystemPlaybooks.all.first)

        let contract = try #require(SystemPlaybookContracts.registry.contract(for: systemPlaybook))

        #expect(contract.identifier == "system.playbook.\(systemPlaybook.id)")
    }

    /// The derived contract is not a relaxation: it declares only definition identity and still
    /// rejects anything the provider didn't declare, so a user playbook sees the same projection a
    /// built-in one does.
    @Test
    func derivedContractStillRejectsUndeclaredContext() throws {
        let contract = try #require(
            SystemPlaybookContracts.registry.contract(for: playbook(id: "user.custom", source: .user))
        )
        #expect(contract.additionalFieldBehavior == .reject)
        #expect(contract.requirements.map(\.key) == [
            "playbook", "playbook.name", "playbook.source", "playbook.trigger", "playbook.flows"
        ])

        let overReaching = ContextBundle(fields: [
            ContextField(
                key: "playbook",
                stringValue: "user.custom",
                dataClass: .publicIdentifier,
                source: .playbookDefinition,
                lastRefreshed: .now
            ),
            ContextField(
                key: "playbook.name",
                stringValue: "Playbook user.custom",
                dataClass: .publicIdentifier,
                source: .playbookDefinition,
                lastRefreshed: .now
            ),
            ContextField(key: "playbook.source", stringValue: "user", dataClass: .derived, source: .playbookDefinition, lastRefreshed: .now),
            ContextField(key: "playbook.trigger", stringValue: "manual", dataClass: .derived, source: .playbookDefinition, lastRefreshed: .now),
            ContextField(key: "playbook.flows", stringValue: "prepare,read", dataClass: .derived, source: .playbookDefinition, lastRefreshed: .now),
            ContextField(
                key: "wallet.seedPhrase",
                stringValue: "hidden",
                dataClass: .sensitive,
                source: .localCache,
                lastRefreshed: .now
            )
        ])

        let validation = contract.validate(overReaching)

        #expect(validation.isSatisfied == false)
        #expect(validation.violations.contains("bundle contains undeclared field “wallet.seedPhrase”"))
        #expect(validation.approvedBundle.fields.map(\.key) == [
            "playbook", "playbook.name", "playbook.source", "playbook.trigger", "playbook.flows"
        ])
    }

    /// The registry stays closed unless a derivation is supplied — the engine's fail-closed default
    /// for an undeclared playbook is unchanged.
    @Test
    func registryWithoutDerivationStaysClosed() {
        let closed = ContextContractRegistry(contracts: [:])

        #expect(closed.contract(for: playbook(id: "user.custom", source: .user)) == nil)
    }

    @Test
    func explicitDeclarationWinsOverDerivation() {
        let declared = ContextBundleContract(identifier: "explicit", requirements: [])
        let registry = ContextContractRegistry(
            contracts: ["user.custom": declared],
            derived: { _ in ContextBundleContract(identifier: "derived", requirements: []) }
        )

        #expect(registry.contract(for: playbook(id: "user.custom", source: .user))?.identifier == "explicit")
        #expect(registry.contract(for: playbook(id: "user.other", source: .user))?.identifier == "derived")
    }

    /// End to end: a user-authored routine now actually runs and produces its artifact, instead of
    /// being recorded as blocked for want of a declaration.
    @Test
    @MainActor
    func userAuthoredRoutineRunsThroughTheHost() async throws {
        let playbookStore = InMemoryPlaybookStore(seed: [playbook(id: "user.custom", source: .user)])
        let artifactStore = InMemoryArtifactStore()
        let host = RuntimeHost(
            receiptStore: DiscardingReceiptStore(),
            stores: RuntimeHostStores(
                artifactStore: artifactStore,
                playbookStore: playbookStore
            )
        )

        let record = await host.runRoutine(id: "user.custom")

        #expect(record.outcome == .success)
        let artifactID = try #require(record.artifactID)
        #expect(await artifactStore.get(id: artifactID)?.creatorPlaybookID == "user.custom")
    }
}
