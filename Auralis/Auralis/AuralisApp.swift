import OSLog
import SwiftData
import SwiftUI

@main
struct AuralisApp: App {
    private let logger = Logger(subsystem: "Auralis", category: "App")
    private let appModelContainer: ModelContainer
    private let primaryStoreInitializationErrorMessage: String?

    init() {
        let missingProviders = Secrets.configurationStatuses()
            .filter { !$0.isConfigured }

        if !missingProviders.isEmpty {
            let providerNames = missingProviders.map(\.provider.rawValue).joined(separator: ", ")
            logger.error("Launching with missing provider configuration: \(providerNames, privacy: .public)")
        }

        let bootstrap = Self.makePrimaryModelContainer(logger: logger)
        appModelContainer = bootstrap.container
        appModelContainer.mainContext.undoManager = UndoManager()
        primaryStoreInitializationErrorMessage = bootstrap.errorMessage
    }

    var body: some Scene {
        WindowGroup {
            MainAuraView(
                services: .live,
                primaryStoreInitializationErrorMessage: primaryStoreInitializationErrorMessage
            )
        }
        .modelContainer(appModelContainer)
    }
}

private extension AuralisApp {
    static var primaryStoreModels: [any PersistentModel.Type] {
        [
            EOAccount.self,
            NFT.self,
            Tag.self,
            StoredReceipt.self,
            Playlist.self,
            MusicLibraryItem.self,
            TokenHolding.self,
            SearchHistoryRecord.self,
        ]
    }

    static func makePrimaryModelContainer(logger: Logger) -> (
        container: ModelContainer,
        errorMessage: String?
    ) {
        do {
            return (
                try ModelContainer(
                    for: Schema(primaryStoreModels)
                ),
                nil
            )
        } catch {
            logger.error(
                "Primary SwiftData store boot failed; falling back to in-memory storage: \(error.localizedDescription, privacy: .public)"
            )

            do {
                let fallbackContainer = try ModelContainer(
                    for: Schema(primaryStoreModels),
                    configurations: ModelConfiguration(isStoredInMemoryOnly: true)
                )
                return (
                    fallbackContainer,
                    "Local storage could not be opened on this launch. Changes will not persist after you quit Auralis."
                )
            } catch {
                fatalError("Failed to create fallback in-memory SwiftData model container: \(error.localizedDescription)")
            }
        }
    }
}
