import OSLog
import SwiftData
import SwiftUI

@main
struct AuralisApp: App {
    private let logger = Logger(subsystem: "Auralis", category: "App")
    private let primaryStoreInitializationErrorMessage: String?
    private let usesInMemoryPrimaryStore: Bool

    init() {
        let missingProviders = Secrets.configurationStatuses()
            .filter { !$0.isConfigured }

        if !missingProviders.isEmpty {
            let providerNames = missingProviders.map(\.provider.rawValue).joined(separator: ", ")
            logger.error("Launching with missing provider configuration: \(providerNames, privacy: .public)")
        }

        let bootstrap = Self.makePrimaryModelContainer(logger: logger)
        primaryStoreInitializationErrorMessage = bootstrap.errorMessage
        usesInMemoryPrimaryStore = bootstrap.usesInMemoryContainer
    }

    var body: some Scene {
        primaryStoreScene(inMemory: usesInMemoryPrimaryStore)
    }
}

private extension AuralisApp {
    @SceneBuilder
    func primaryStoreScene(inMemory: Bool) -> some Scene {
        WindowGroup {
            MainAuraView(
                services: .live,
                primaryStoreInitializationErrorMessage: primaryStoreInitializationErrorMessage
            )
        }
        .modelContainer(
            for: PrimaryStoreSchema.models,
            inMemory: inMemory,
            isUndoEnabled: true
        )
    }

    static func makePrimaryModelContainer(logger: Logger) -> (
        usesInMemoryContainer: Bool,
        errorMessage: String?
    ) {
        do {
            _ = try ModelContainer(for: PrimaryStoreSchema.schema)
            return (false, nil)
        } catch {
            logger.error(
                "Primary SwiftData store boot failed; falling back to in-memory storage: \(error.localizedDescription, privacy: .public)"
            )
            return (
                true,
                "Local storage could not be opened on this launch. Changes will not persist after you quit Auralis."
            )
        }
    }
}
