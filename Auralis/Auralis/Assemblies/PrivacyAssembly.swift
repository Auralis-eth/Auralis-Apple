import AccountsCore
import SwiftData

@MainActor
struct PrivacyAssembly {
    func makeLogoutCleanupService(modelContext: ModelContext) -> any LogoutCleaning {
        LogoutCleanupService(modelContext: modelContext)
    }

    func makePrivacyResetService(
        modelContext: ModelContext,
        auraPlayModelContainer: ModelContainer?
    ) -> any PrivacyResetting {
        PrivacyResetServices.live(
            modelContext: modelContext,
            auraPlayModelContainer: auraPlayModelContainer
        )
    }

    func makeAllWalletDisconnectService(
        accountStore: any AccountStoring,
        modelContext: ModelContext,
        auraPlayModelContainer: ModelContainer?,
        activeAddressProvider: @escaping @MainActor () -> String?
    ) -> any AllWalletDisconnecting {
        AllWalletDisconnectService(
            accountStore: accountStore,
            privacyResetService: makePrivacyResetService(
                modelContext: modelContext,
                auraPlayModelContainer: auraPlayModelContainer
            ),
            activeAddressProvider: activeAddressProvider
        )
    }
}
