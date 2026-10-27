import AccountsCore
import AccountsFeature
import AccountStorage
import AuralisPrimaryModels
import ENS
import AuralisReceipts
import SwiftData

@MainActor
struct AccountAssembly {
    private let providerAssembly: ProviderAssembly
    private let receiptAssembly: ReceiptAssembly
    private let accountStoreFactory: @MainActor (ModelContext, any AccountEventRecorder) -> any AccountStoring
    private let ensResolverFactory: @MainActor (ModelContext, @escaping @MainActor () -> ReceiptMode) -> any ENSResolving

    init(
        providerAssembly: ProviderAssembly,
        receiptAssembly: ReceiptAssembly,
        accountStoreFactory: (@MainActor (ModelContext, any AccountEventRecorder) -> any AccountStoring)? = nil,
        ensResolverFactory: (@MainActor (ModelContext, @escaping @MainActor () -> ReceiptMode) -> any ENSResolving)? = nil
    ) {
        self.providerAssembly = providerAssembly
        self.receiptAssembly = receiptAssembly
        self.accountStoreFactory = accountStoreFactory ?? { modelContext, eventRecorder in
            SwiftDataAccountStore(
                modelContext: modelContext,
                eventRecorder: eventRecorder,
                scopedPersistenceParticipants: makeAppAccountScopedPersistenceParticipants()
            )
        }
        self.ensResolverFactory = ensResolverFactory ?? { modelContext, modeProvider in
            ENSResolvers.live(
                modelContext: modelContext,
                modeProvider: modeProvider
            )
        }
    }

    func makeAccountStore(
        modelContext: ModelContext,
        modeProvider: @escaping @MainActor () -> ReceiptMode = { PersistedCryptoMode.currentReceiptMode }
    ) -> any AccountStoring {
        accountStoreFactory(
            modelContext,
            receiptAssembly.makeAccountEventRecorder(
                modelContext: modelContext,
                modeProvider: modeProvider
            )
        )
    }

    func makeAccountStore(
        modelContext: ModelContext,
        eventRecorder: any AccountEventRecorder
    ) -> any AccountStoring {
        accountStoreFactory(modelContext, eventRecorder)
    }

    func makeAccountEventRecorder(
        modelContext: ModelContext,
        modeProvider: @escaping @MainActor () -> ReceiptMode = { PersistedCryptoMode.currentReceiptMode }
    ) -> any AccountEventRecorder {
        receiptAssembly.makeAccountEventRecorder(
            modelContext: modelContext,
            modeProvider: modeProvider
        )
    }

    func makeENSResolver(
        modelContext: ModelContext,
        modeProvider: @escaping @MainActor () -> ReceiptMode = { PersistedCryptoMode.currentReceiptMode }
    ) -> any ENSResolving {
        ensResolverFactory(modelContext, modeProvider)
    }

    func makeGatewayDependencies(
        modelContext: ModelContext,
        modeProvider: @escaping @MainActor () -> ReceiptMode = { PersistedCryptoMode.currentReceiptMode }
    ) -> GatewayDependencies {
        GatewayDependencies(
            featureDependencies: AccountsGatewayDependencies(
                ensResolver: AppAccountENSResolver(
                    resolver: makeENSResolver(
                        modelContext: modelContext,
                        modeProvider: modeProvider
                    )
                ),
                accountActivator: AccountStoreAccountActivator(
                    store: makeAccountStore(
                        modelContext: modelContext,
                        modeProvider: modeProvider
                    )
                )
            )
        )
    }

    func makeShellAccountResolver(modelContext: ModelContext) -> SwiftDataShellAccountResolver {
        SwiftDataShellAccountResolver(modelContext: modelContext)
    }

    func makeShellAccountMutator(
        modelContext: ModelContext,
        modeProvider: @escaping @MainActor () -> ReceiptMode = { PersistedCryptoMode.currentReceiptMode }
    ) -> SwiftDataShellAccountMutator {
        SwiftDataShellAccountMutator(
            modelContext: modelContext,
            eventRecorder: makeAccountEventRecorder(
                modelContext: modelContext,
                modeProvider: modeProvider
            )
        )
    }
}

@MainActor
struct GatewayDependencies {
    let featureDependencies: AccountsGatewayDependencies
}
