import SwiftData

@MainActor
protocol LogoutCleaning {
    func clearLocalDataForLogout(plan: HomeLogoutPlan) throws
}

@MainActor
struct LogoutCleanupService: LogoutCleaning {
    private let modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    func clearLocalDataForLogout(plan: HomeLogoutPlan) throws {
        do {
            try modelContext.performRollbackSafeMutation {
                try modelContext.deleteAllShellSupportData()

                if plan.shouldDeleteNFTs {
                    try modelContext.deleteAllNFTData()
                }

                // Watch-only logout clears local app state but intentionally preserves
                // saved accounts so people can hop back into previously scoped wallets.
                if plan.shouldDeleteAccounts {
                    try modelContext.delete(model: EOAccount.self)
                }

                if plan.shouldDeleteTags {
                    try modelContext.delete(model: Tag.self)
                }
            }
        } catch {
            throw LocalDataResetError.rollbackCompleted(
                phase: .transactionalStore,
                underlying: error
            )
        }
    }
}
