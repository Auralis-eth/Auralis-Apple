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
}
