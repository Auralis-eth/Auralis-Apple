import MissionControlFeature
import PolicyCore
import ReceiptStorage
import RuntimeKit
import SwiftData
import SwiftUI

/// App-side host for the Mission Control tab. Builds a stable `RuntimeHost` + model once from the
/// shell's `ModelContext`-backed receipt store, so the operator console has a durable event bus and
/// pause state for the lifetime of the tab.
struct MissionControlTabContainer: View {
    @State private var model: MissionControlHomeModel
    @State private var didSeedUITestFixtures = false

    private let seedsUITestFixtures: Bool
    private let routedArtifactID: UUID?

    @MainActor
    init(
        modelContext: ModelContext,
        modeState: ModeState,
        activeIdentityID: String,
        routedArtifactID: UUID? = nil
    ) {
        let receiptStore = ReceiptStores.live(modelContext: modelContext)
        self.routedArtifactID = routedArtifactID
        #if DEBUG
        seedsUITestFixtures = ProcessInfo.processInfo.arguments.contains("-ui-testing-mission-control-fixtures")
        let host = if seedsUITestFixtures {
            RuntimeHost(
                receiptStore: receiptStore,
                identity: RuntimeIdentityHooks(
                    activeIdentityProvider: { activeIdentityID },
                    cryptoModeProvider: { modeState.mode },
                    cryptoModeSetter: { modeState.setMode($0) }
                )
            )
        } else {
            RuntimeAssembly.sharedHost(
                modelContext: modelContext,
                activeIdentityProvider: { activeIdentityID },
                cryptoModeProvider: { modeState.mode },
                cryptoModeSetter: { modeState.setMode($0) }
            )
        }
        #else
        seedsUITestFixtures = false
        let host = RuntimeAssembly.sharedHost(
            modelContext: modelContext,
            activeIdentityProvider: { activeIdentityID },
            cryptoModeProvider: { modeState.mode },
            cryptoModeSetter: { modeState.setMode($0) }
        )
        #endif
        // Live on-chain simulation for the Proposal Diff Viewer (P1-AGENT-103). Skipped when seeding
        // UI-test fixtures so those runs stay hermetic and never touch the network.
        let proposalSimulator: (any ProposalSimulating)? = seedsUITestFixtures ? nil : AlchemyProposalSimulator()
        _model = State(initialValue: MissionControlHomeModel(
            host: host,
            receiptStore: receiptStore,
            proposalSimulator: proposalSimulator,
            activeIdentityID: activeIdentityID,
            operatorWatchlistStore: UserDefaultsOperatorWatchlistStore()
        ))
    }

    var body: some View {
        MissionControlRootView(model: model, routedArtifactID: routedArtifactID)
            .task {
                await seedUITestFixturesIfNeeded()
            }
    }

    @MainActor
    private func seedUITestFixturesIfNeeded() async {
        #if DEBUG
        guard seedsUITestFixtures, !didSeedUITestFixtures else { return }
        didSeedUITestFixtures = true

        do {
            try await model.seedUITestFixtures()
        } catch {
            assertionFailure("Failed to seed Mission Control UI fixtures: \(error.localizedDescription)")
        }
        #endif
    }
}
