import AuralisPrimaryModels
import AuralisPrimaryPersistence
import OSLog
import SwiftData
import SwiftUI
import NFTDomain
import NFTPersistence
import NFTPresentation
import NFTProviderAdapters
import ProviderKit

@main
struct AuralisApp: App {
    private let logger = Logger(subsystem: "Auralis", category: "App")
    private let primaryStoreCopy = PrimaryStoreCopy.standard
    private let primaryStoreInitializationErrorMessage: String?
    private let usesInMemoryPrimaryStore: Bool
    private let uiTestFixture: UITestFixture
    @State private var primaryStoreRecoveryAlertPresented = false

    init() {
        let missingProviders = Secrets.configurationStatuses()
            .filter { !$0.isConfigured }

        if !missingProviders.isEmpty {
            let providerNames = missingProviders.map(\.provider.rawValue).joined(separator: ", ")
            logger.error("Launching with missing provider configuration: \(providerNames, privacy: .public)")
        }

        let bootstrap = Self.makePrimaryModelContainer(logger: logger)
        let uiTestFixture = UITestFixture(arguments: ProcessInfo.processInfo.arguments)
        primaryStoreInitializationErrorMessage = bootstrap.errorMessage
        usesInMemoryPrimaryStore = bootstrap.usesInMemoryContainer || uiTestFixture.usesInMemoryPrimaryStore
        self.uiTestFixture = uiTestFixture
    }

    var body: some Scene {
        primaryStoreScene(inMemory: usesInMemoryPrimaryStore)
    }
}

private extension AuralisApp {
    @SceneBuilder
    func primaryStoreScene(inMemory: Bool) -> some Scene {
        WindowGroup {
            UITestSeededRoot(
                fixture: uiTestFixture,
                primaryStoreInitializationErrorMessage: primaryStoreInitializationErrorMessage
            )
            .task {
                primaryStoreRecoveryAlertPresented = primaryStoreInitializationErrorMessage != nil
            }
            .alert(primaryStoreCopy.unavailableAlertTitle, isPresented: $primaryStoreRecoveryAlertPresented) {
                Button("Continue") { }
            } message: {
                Text(
                    primaryStoreInitializationErrorMessage ??
                        primaryStoreCopy.unavailableFallbackMessage
                )
            }
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

private enum UITestFixture: Equatable {
    case none
    case cleanGateway
    case authenticatedAccount

    init(arguments: [String]) {
        if arguments.contains("-ui-testing-authenticated") {
            self = .authenticatedAccount
        } else if arguments.contains("-reset-onboarding") {
            self = .cleanGateway
        } else {
            self = .none
        }
    }

    var usesInMemoryPrimaryStore: Bool {
        self != .none
    }

    var seededAccount: EOAccount? {
        guard self == .authenticatedAccount else {
            return nil
        }

        return EOAccount(
            address: "0x1234567890abcdef1234567890abcdef12345678",
            name: "Accessibility Test Wallet",
            source: .guestPass,
            lastSelectedAt: .now
        )
    }

    var tabBarVisibility: AppTabBarVisibility {
        switch self {
        case .none:
            return .live
        case .cleanGateway, .authenticatedAccount:
            return .release
        }
    }
}

private struct UITestSeededRoot: View {
    @Environment(\.modelContext) private var modelContext
    @State private var isReady = false

    let fixture: UITestFixture
    let primaryStoreInitializationErrorMessage: String?

    var body: some View {
        Group {
            if isReady {
                MainAuraView(
                    dependencies: .live,
                    tabBarVisibility: fixture.tabBarVisibility,
                    primaryStoreInitializationErrorMessage: primaryStoreInitializationErrorMessage
                )
            } else {
                ProgressView()
                    .accessibilityLabel(String(localized: "Preparing test data"))
            }
        }
        .task {
            seedFixtureIfNeeded()
            isReady = true
        }
    }

    private func seedFixtureIfNeeded() {
        guard let account = fixture.seededAccount else {
            return
        }

        do {
            let address = account.address
            let descriptor = FetchDescriptor<EOAccount>(
                predicate: #Predicate<EOAccount> { existingAccount in
                    existingAccount.address == address
                }
            )

            if try modelContext.fetch(descriptor).isEmpty {
                modelContext.insert(account)
            }

            try modelContext.save()
        } catch {
            assertionFailure("Failed to seed UI test account: \(error.localizedDescription)")
        }
    }
}
