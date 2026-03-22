import Foundation
import SwiftData

protocol ShellContextSourceBuilding {
    func makeContextSource(
        accountProvider: @escaping () -> EOAccount?,
        addressProvider: @escaping () -> String,
        chainProvider: @escaping () -> Chain,
        modeProvider: @escaping () -> AppMode,
        loadingProvider: @escaping () -> Bool,
        refreshedAtProvider: @escaping () -> Date?,
        freshnessTTLProvider: @escaping () -> TimeInterval?,
        trackedNFTCountProvider: @escaping () -> Int?,
        prefersDemoDataProvider: @escaping () -> Bool?
    ) -> any ContextSource
}

struct LiveShellContextSourceBuilder: ShellContextSourceBuilding {
    func makeContextSource(
        accountProvider: @escaping () -> EOAccount?,
        addressProvider: @escaping () -> String,
        chainProvider: @escaping () -> Chain,
        modeProvider: @escaping () -> AppMode,
        loadingProvider: @escaping () -> Bool,
        refreshedAtProvider: @escaping () -> Date?,
        freshnessTTLProvider: @escaping () -> TimeInterval?,
        trackedNFTCountProvider: @escaping () -> Int?,
        prefersDemoDataProvider: @escaping () -> Bool?
    ) -> any ContextSource {
        LiveContextSource(
            accountProvider: accountProvider,
            addressProvider: addressProvider,
            chainProvider: chainProvider,
            modeProvider: modeProvider,
            loadingProvider: loadingProvider,
            refreshedAtProvider: refreshedAtProvider,
            freshnessTTLProvider: freshnessTTLProvider,
            trackedNFTCountProvider: trackedNFTCountProvider,
            prefersDemoDataProvider: prefersDemoDataProvider
        )
    }
}

@MainActor
protocol ObservePolicyActionHandling {
    func attempt(_ action: ObserveBlockedAction) -> PolicyGateResult
}

@MainActor
struct ObservePolicyActionService: ObservePolicyActionHandling {
    private let modeState: ModeState
    private let receiptStore: any ReceiptStore

    init(
        modeState: ModeState,
        receiptStore: any ReceiptStore
    ) {
        self.modeState = modeState
        self.receiptStore = receiptStore
    }

    func attempt(_ action: ObserveBlockedAction) -> PolicyGateResult {
        ExecutePolicyGate.attempt(
            action,
            modeState: modeState,
            receiptStore: receiptStore
        )
    }
}

@MainActor
struct ShellServiceHub {
    let modeStateFactory: @MainActor () -> ModeState
    let nftServiceFactory: @MainActor () -> NFTService
    let contextSourceBuilder: any ShellContextSourceBuilding
    let receiptStoreFactory: @MainActor (ModelContext) -> any ReceiptStore
    let policyActionHandlerFactory: @MainActor (ModelContext, ModeState) -> any ObservePolicyActionHandling

    static let live = ShellServiceHub(
        modeStateFactory: { ModeState() },
        nftServiceFactory: { NFTService() },
        contextSourceBuilder: LiveShellContextSourceBuilder(),
        receiptStoreFactory: { modelContext in
            ReceiptStores.live(modelContext: modelContext)
        },
        policyActionHandlerFactory: { modelContext, modeState in
            ObservePolicyActionService(
                modeState: modeState,
                receiptStore: ReceiptStores.live(modelContext: modelContext)
            )
        }
    )
}
