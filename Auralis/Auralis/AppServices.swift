import AuralisShellCore
import NFTDomain
import NFTPersistence
import NFTPresentation
import NFTProviderAdapters
import SwiftData

@MainActor
struct ShellBootstrapDependencies {
    let modeStateFactory: @MainActor () -> ModeState
    let nftServiceFactory: @MainActor () -> NFTService
    let makeMusicRuntime: @MainActor () -> MusicRuntime
    let configureMusicReceiptLogger: @MainActor (AuraPlayPlaybackRuntime?, ModelContext) -> Void
    let makeShellStore: @MainActor (ModelContext, NFTService, AppRouter) -> ShellStore
    let makeGatewayDependencies: @MainActor (ModelContext) -> GatewayDependencies
    let makeMainTabDependencies: @MainActor (ModelContext) -> MainTabDependencies

    static let live = live()

    static func live(
        selectionPersistence: (any ShellSelectionPersisting)? = nil
    ) -> ShellBootstrapDependencies {
        let environment = AppEnvironment.live
        return ShellBootstrapDependencies(
            modeStateFactory: environment.modeStateFactory,
            nftServiceFactory: environment.music.makeNFTService,
            makeMusicRuntime: environment.music.makeRuntime,
            configureMusicReceiptLogger: environment.music.configureReceiptLogger,
            makeShellStore: { modelContext, nftService, router in
                environment.shell.makeShellStore(
                    modelContext: modelContext,
                    nftService: nftService,
                    router: router,
                    selectionPersistence: selectionPersistence
                )
            },
            makeGatewayDependencies: { modelContext in
                environment.accounts.makeGatewayDependencies(modelContext: modelContext)
            },
            makeMainTabDependencies: { modelContext in
                environment.mainTabs.makeMainTabDependencies(modelContext: modelContext)
            }
        )
    }
}

@MainActor
/// Bundles the long-lived service assemblies needed to assemble the Aura shell.
struct AppEnvironment {
    let modeStateFactory: @MainActor () -> ModeState
    let providers: ProviderAssembly
    let receipts: ReceiptAssembly
    let accounts: AccountAssembly
    let shell: ShellAssembly
    let music: MusicAssembly
    let privacy: PrivacyAssembly
    let tokenHoldings: TokenHoldingsAssembly
    let search: SearchAssembly
    let home: HomeAssembly
    let policy: PolicyAssembly
    let mainTabs: MainTabAssembly

    static let live: AppEnvironment = {
        let providers = ProviderAssembly()
        let receipts = ReceiptAssembly()
        let accounts = AccountAssembly(
            providerAssembly: providers,
            receiptAssembly: receipts
        )
        let shell = ShellAssembly(
            accountAssembly: accounts,
            receiptAssembly: receipts
        )
        let music = MusicAssembly(
            providerAssembly: providers,
            receiptAssembly: receipts
        )
        let privacy = PrivacyAssembly()
        let tokenHoldings = TokenHoldingsAssembly(providerAssembly: providers)
        let search = SearchAssembly()
        let home = HomeAssembly()
        let policy = PolicyAssembly(receiptAssembly: receipts)
        let mainTabs = MainTabAssembly(
            accounts: accounts,
            shell: shell,
            providers: providers,
            receipts: receipts,
            music: music,
            privacy: privacy,
            tokenHoldings: tokenHoldings,
            search: search,
            home: home,
            policy: policy
        )

        return AppEnvironment(
            modeStateFactory: { ModeState() },
            providers: providers,
            receipts: receipts,
            accounts: accounts,
            shell: shell,
            music: music,
            privacy: privacy,
            tokenHoldings: tokenHoldings,
            search: search,
            home: home,
            policy: policy,
            mainTabs: mainTabs
        )
    }()
}
