import ArtifactCore
import ArtifactStorage
import EvalCore
import Foundation
import OperatorRuntimeStorage
import OperatorsFeature
import OSLog
import PolicyCore
import ReceiptsCore
import RuntimeCore
import SocialCore
import SwiftData

public extension RuntimeHost {
    /// Builds a host whose playbook / performance / execution-record stores are backed by the on-disk
    /// `OperatorRuntimeStorage` container, so operator runtime state survives relaunch. If the container
    /// cannot be created, the host starts paused and artifact writes fail instead of silently becoming
    /// volatile in-memory records. Seeds the system playbooks on first launch.
    @MainActor
    static func persistent(
        receiptStore: any ReceiptStore,
        modelRouter: any ModelRouting = TaskKindModelRouter.localFirstDefault,
        modelInferenceClient: any ModelInferring = UnsupportedModelInferenceClient(),
        ritualRunNotifier: any RitualRunNotifying = NoOpRitualRunNotifier(),
        // The backings, named rather than constructed inline inside the store arguments they used to
        // be buried in. A `SharedSessionStore` does not expose the persistence it holds, so with the
        // old shape nothing could ask these three whether they had quarantined themselves — which is
        // the state in which they refuse every write, including the privacy reset's. See
        // ``SocialPersistenceQuarantining``.
        // Shared singletons, not fresh instances: see ``SharedCoordinationStores``. A fresh backing
        // per call would key a fresh store per call, and two stores over one `UserDefaults` key
        // overwrite rather than merge.
        sharedSessionPersistence: any SharedSessionPersisting & SocialPersistenceQuarantining
            = SharedCoordinationStores.defaultSharedSessionPersistence,
        ritualStatePersistence: any RitualStatePersisting & SocialPersistenceQuarantining
            = SharedCoordinationStores.defaultRitualStatePersistence,
        socialEventLogPersistence: any SocialEventLogPersisting & SocialPersistenceQuarantining
            = SharedCoordinationStores.defaultSocialEventLogPersistence,
        // `nil` resolves the *process-shared* store for the matching persistence above, which is the
        // shipping path. More than one host exists per process (`RuntimeBackgroundScheduler` opens
        // its own `ModelContainer`, which misses `RuntimeAssembly`'s per-container memo), and these
        // three stores persist by rewriting a whole snapshot — so a per-host instance meant the
        // background refresh's writes were erased by the next foreground write. See F-23.
        // An explicitly injected store is the caller opting out of that backing altogether (tests
        // pass in-memory stores), so no quarantine probe is registered for it — reporting health for
        // a backing the host is not using would be worse than reporting none.
        sharedSessionStore: SharedSessionStore? = nil,
        ritualStore: RitualStore? = nil,
        socialEventLogStore: SocialEventLogStore? = nil,
        operatorDataSource: (any OperatorDataSource)? = nil,
        policyActionExecutor: any ToolExecuting = UnconfiguredPolicyActionExecutor(),
        standardCheckConfiguration: StandardCheckConfiguration = .default,
        // Durable backing for the global kill switch, so a pause survives relaunch and applies to
        // every host in the process (including the one the background refresh builds for itself).
        pauseStateStore: any RuntimePauseStateStoring = UserDefaultsRuntimePauseStateStore(),
        activeIdentityProvider: @escaping @MainActor () -> String? = { nil },
        cryptoModeProvider: @escaping @MainActor @Sendable () -> CryptoMode = { .observe },
        cryptoModeSetter: @escaping @MainActor @Sendable (CryptoMode) -> Void = { _ in },
        makeStorageContainer: () throws -> ModelContainer = OperatorRuntimeStorage.makeContainer
    ) -> RuntimeHost {
        // Resolved before the container is opened, because the coordination stores do not live in it
        // and both paths below forward this one group unchanged.
        var coordinationPersistence: [any SocialPersistenceQuarantining] = []
        let resolvedSharedSessionStore: SharedSessionStore
        if let sharedSessionStore {
            resolvedSharedSessionStore = sharedSessionStore
        } else {
            resolvedSharedSessionStore = SharedCoordinationStores.sharedSessionStore(for: sharedSessionPersistence)
            coordinationPersistence.append(sharedSessionPersistence)
        }
        let resolvedRitualStore: RitualStore
        if let ritualStore {
            resolvedRitualStore = ritualStore
        } else {
            resolvedRitualStore = SharedCoordinationStores.ritualStore(for: ritualStatePersistence)
            coordinationPersistence.append(ritualStatePersistence)
        }
        let resolvedSocialEventLogStore: SocialEventLogStore
        if let socialEventLogStore {
            resolvedSocialEventLogStore = socialEventLogStore
        } else {
            resolvedSocialEventLogStore = SharedCoordinationStores.socialEventLogStore(for: socialEventLogPersistence)
            coordinationPersistence.append(socialEventLogPersistence)
        }
        let coordination = RuntimeCoordinationStores(
            sharedSessionStore: resolvedSharedSessionStore,
            ritualStore: resolvedRitualStore,
            socialEventLogStore: resolvedSocialEventLogStore,
            quarantinablePersistence: coordinationPersistence
        )

        let container: ModelContainer
        do {
            container = try makeStorageContainer()
        } catch {
            let reason = "Operator runtime storage is unavailable. Artifact creation is paused so work products are not lost on relaunch."
            // Everything that does not live in the failed `ModelContainer` is forwarded unchanged.
            // Only the SwiftData-backed stores degrade here. The three coordination stores and the
            // checkpoint store are `UserDefaults`-backed and the operator data source reads the
            // receipt ledger, so none of them depend on this container — dropping them (as this
            // path once did, by simply omitting the arguments) silently swapped healthy durable
            // state for empty in-memory defaults. A person whose container failed to open would
            // find their shared sessions, rituals, and the *pending outbound relay queue* reading
            // as empty, and that queue would never be flushed.
            return RuntimeHost(
                receiptStore: receiptStore,
                stores: RuntimeHostStores(
                    artifactStore: UnavailableArtifactStore(reason: reason),
                    eventCheckpointStore: PersistentRuntimeEventCheckpointStore()
                ),
                // Forwarded as one group, which is the point of grouping them: this path dropped
                // them entirely once, by simply omitting the arguments.
                coordination: coordination,
                models: RuntimeModelStack(
                    modelRouter: modelRouter,
                    modelInferenceClient: modelInferenceClient
                ),
                operators: RuntimeOperatorStack(
                    operatorDataSource: operatorDataSource ?? ReceiptBackedOperatorDataSource(receiptStore: receiptStore),
                    policyActionExecutor: policyActionExecutor,
                    ritualRunNotifier: ritualRunNotifier
                ),
                governance: RuntimeGovernanceOptions(
                    initialPauseReason: reason,
                    standardCheckConfiguration: standardCheckConfiguration,
                    // Supplied on this path too, and it matters most here: the pause store is
                    // `UserDefaults`-backed precisely so the kill switch is still readable when the
                    // SwiftData container is the thing that failed. `rehydratePauseState()` will
                    // leave the storage reason above in place, since it is the more actionable one,
                    // but an operator resume from this state is still written through.
                    pauseStateStore: pauseStateStore
                ),
                identity: RuntimeIdentityHooks(
                    activeIdentityProvider: activeIdentityProvider,
                    cryptoModeProvider: cryptoModeProvider,
                    cryptoModeSetter: cryptoModeSetter
                )
            )
        }
        // Artifacts written before the storage change live in a different table, so they are moved
        // across before any store is built — otherwise they would simply stop appearing. Idempotent
        // and non-throwing: a pass that cannot commit leaves the old rows untouched and retries on
        // the next launch rather than refusing to open the app. See ``LegacyArtifactMigration``.
        // The result is read, not discarded: `didFail` is the one state worth surfacing, because it
        // distinguishes "there was nothing to migrate" from "every pre-upgrade artifact is still
        // invisible". Dropping it left the user looking at an empty artifact list with no explanation.
        let migrationResult = LegacyArtifactMigration.run(in: container)
        if migrationResult.didFail {
            Logger(subsystem: "com.auralis", category: "PersistentRuntimeHost").error(
                "Legacy artifact migration failed; pre-upgrade artifacts remain hidden until a later launch succeeds."
            )
        }

        let playbookStore = SwiftDataPlaybookStore(modelContainer: container)
        let performanceStore = SwiftDataPerformanceStore(modelContainer: container)
        let executionRecordStore = SwiftDataExecutionRecordStore(modelContainer: container)
        // `ArtifactStorage`'s store, which is the hardened one: every write is rolled back if its
        // commit fails, a mutation naming a row that no longer exists throws
        // `ArtifactStoreWriteError.artifactNotFound` instead of returning normally, and a row this
        // build cannot interpret is refused rather than coerced to `.draft`. The near-identical
        // `SwiftDataArtifactStore` that used to be declared in `OperatorRuntimeStorage` did none of
        // those things, and it was the one production built — so Mission Control wrote an
        // `isSuccess: true` receipt for lifecycle decisions that had silently not been recorded.
        let artifactStore = SwiftDataArtifactStore(modelContainer: container)
        let worklogStore = SwiftDataWorklogStore(modelContainer: container)
        let evalResultStore = SwiftDataEvalResultStore(modelContainer: container)
        let improvementRecommendationStore = SwiftDataImprovementRecommendationStore(modelContainer: container)
        let sessionStore = SwiftDataAgentSessionStore(modelContainer: container)
        let eventHistoryStore = SwiftDataRuntimeEventHistoryStore(modelContainer: container)
        let eventCheckpointStore = PersistentRuntimeEventCheckpointStore()
        let capabilityLeaseStore = SwiftDataCapabilityLeaseStore(modelContainer: container)
        return RuntimeHost(
            receiptStore: receiptStore,
            stores: RuntimeHostStores(
                artifactStore: artifactStore,
                playbookStore: playbookStore,
                performanceStore: performanceStore,
                executionRecordStore: executionRecordStore,
                worklogStore: worklogStore,
                evalResultStore: evalResultStore,
                improvementRecommendationStore: improvementRecommendationStore,
                sessionStore: sessionStore,
                eventHistoryStore: eventHistoryStore,
                eventCheckpointStore: eventCheckpointStore,
                capabilityLeaseStore: capabilityLeaseStore
            ),
            coordination: coordination,
            models: RuntimeModelStack(
                modelRouter: modelRouter,
                modelInferenceClient: modelInferenceClient
            ),
            operators: RuntimeOperatorStack(
                operatorDataSource: operatorDataSource ?? ReceiptBackedOperatorDataSource(receiptStore: receiptStore),
                policyActionExecutor: policyActionExecutor,
                ritualRunNotifier: ritualRunNotifier
            ),
            governance: RuntimeGovernanceOptions(
                standardCheckConfiguration: standardCheckConfiguration,
                pauseStateStore: pauseStateStore,
                // Awaited by `bootstrap()` before it seeds routine authority, rather than run as a
                // detached task at construction. As a detached task it raced that seed: `bootstrap()`
                // could read an empty catalog, grant no standing leases, and — because the scheduling
                // engine fails closed — turn every early routine run into a `.blocked` record until
                // something happened to re-seed.
                playbookPreparation: {
                    do {
                        try await playbookStore.seedMissingSystemPlaybooks(SystemPlaybooks.all)
                    } catch {
                        Logger(subsystem: "com.auralis.runtime", category: "playbook-persistence")
                            .error("Failed to seed system playbooks: \(error.localizedDescription, privacy: .public)")
                        throw error
                    }
                }
            ),
            identity: RuntimeIdentityHooks(
                activeIdentityProvider: activeIdentityProvider,
                cryptoModeProvider: cryptoModeProvider,
                cryptoModeSetter: cryptoModeSetter
            )
        )
    }
}

public enum RuntimePersistenceError: Error, Equatable, LocalizedError, Sendable {
    case unavailable(String)

    public var errorDescription: String? {
        switch self {
        case let .unavailable(reason):
            return reason
        }
    }
}

private actor UnavailableArtifactStore: ArtifactStore {
    private let reason: String

    init(reason: String) {
        self.reason = reason
    }

    func create(_ draft: ArtifactDraft) throws -> Artifact {
        throw RuntimePersistenceError.unavailable(reason)
    }

    func addVersion(toGroup groupID: UUID, _ draft: ArtifactDraft) throws -> Artifact {
        throw RuntimePersistenceError.unavailable(reason)
    }

    func get(id: UUID) -> Artifact? {
        nil
    }

    func latest(limit: Int) throws -> [Artifact] {
        throw RuntimePersistenceError.unavailable(reason)
    }

    func versions(ofGroup groupID: UUID) throws -> [Artifact] {
        throw RuntimePersistenceError.unavailable(reason)
    }

    func all(ofType type: ArtifactType, limit: Int) throws -> [Artifact] {
        throw RuntimePersistenceError.unavailable(reason)
    }

    func setApprovalState(id: UUID, to state: ArtifactApprovalState) throws {
        throw RuntimePersistenceError.unavailable(reason)
    }

    func linkRelatedReceipt(id receiptID: UUID, toArtifact artifactID: UUID) throws {
        throw RuntimePersistenceError.unavailable(reason)
    }

    func updateLifecycle(
        id: UUID,
        to state: ArtifactApprovalState,
        destination: String?,
        exportFormat: String?
    ) throws {
        throw RuntimePersistenceError.unavailable(reason)
    }

    func exportAll() throws -> Data {
        throw RuntimePersistenceError.unavailable(reason)
    }

    func resetAll() throws {
        throw RuntimePersistenceError.unavailable(reason)
    }
}
