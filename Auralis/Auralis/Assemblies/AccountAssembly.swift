import AccountStorage
import AccountsCore
import AccountsFeature
import ENS
import SwiftData

@MainActor
struct AccountAssembly {
    private let providerAssembly: ProviderAssembly
    private let receiptAssembly: ReceiptAssembly
    private let accountStoreFactory: @MainActor (ModelContext, any AccountEventRecorder) -> any AccountStoring
    private let ensResolverFactory: @MainActor (ModelContext) -> any ENSResolving

    init(
        providerAssembly: ProviderAssembly,
        receiptAssembly: ReceiptAssembly,
        accountStoreFactory: (@MainActor (ModelContext, any AccountEventRecorder) -> any AccountStoring)? = nil,
        ensResolverFactory: (@MainActor (ModelContext) -> any ENSResolving)? = nil
    ) {
        self.providerAssembly = providerAssembly
        self.receiptAssembly = receiptAssembly
        self.accountStoreFactory = accountStoreFactory ?? { modelContext, eventRecorder in
            SwiftDataAccountStore(
                modelContext: modelContext,
                eventRecorder: eventRecorder
            )
        }
        self.ensResolverFactory = ensResolverFactory ?? { modelContext in
            ENSResolvers.live(modelContext: modelContext)
        }
    }

    func makeAccountStore(modelContext: ModelContext) -> any AccountStoring {
        accountStoreFactory(
            modelContext,
            receiptAssembly.makeAccountEventRecorder(modelContext: modelContext)
        )
    }

    func makeAccountStore(
        modelContext: ModelContext,
        eventRecorder: any AccountEventRecorder
    ) -> any AccountStoring {
        accountStoreFactory(modelContext, eventRecorder)
    }

    func makeAccountEventRecorder(modelContext: ModelContext) -> any AccountEventRecorder {
        receiptAssembly.makeAccountEventRecorder(modelContext: modelContext)
    }

    func makeENSResolver(modelContext: ModelContext) -> any ENSResolving {
        ensResolverFactory(modelContext)
    }

    func makeGatewayDependencies(modelContext: ModelContext) -> GatewayDependencies {
        GatewayDependencies(
            featureDependencies: AccountsGatewayDependencies(
                ensResolver: AppAccountENSResolver(resolver: makeENSResolver(modelContext: modelContext)),
                accountActivator: AccountStoreAccountActivator(
                    store: makeAccountStore(modelContext: modelContext)
                )
            )
        )
    }

    func makeShellAccountResolver(modelContext: ModelContext) -> SwiftDataShellAccountResolver {
        SwiftDataShellAccountResolver(modelContext: modelContext)
    }

    func makeShellAccountMutator(modelContext: ModelContext) -> SwiftDataShellAccountMutator {
        SwiftDataShellAccountMutator(
            modelContext: modelContext,
            eventRecorder: makeAccountEventRecorder(modelContext: modelContext)
        )
    }
}

@MainActor
struct GatewayDependencies {
    let featureDependencies: AccountsGatewayDependencies
}
