import AuralisCrypto
import AuralisAppShell
import AuralisOperators
import OSLog
import AuralisReceipts
import SwiftData
import SwiftUI

@main
struct AuralisApp: App {
    private let logger = Logger(subsystem: "Auralis", category: "App")
    private let primaryStoreCopy = PrimaryStoreCopy.standard
    private let primaryStoreInitializationErrorMessage: String?
    private let usesInMemoryPrimaryStore: Bool
    private let uiTestFixture: UITestFixture
    /// Built here and installed directly, rather than letting
    /// `.modelContainer(for:inMemory:isUndoEnabled:)` create one.
    ///
    /// That convenience modifier takes no `cloudKitDatabase` argument, so the container it builds
    /// always uses `ModelConfiguration`'s `.automatic` default — which, now that the app carries an
    /// iCloud entitlement for the receipt witness, means SwiftData tries to mirror this schema to
    /// CloudKit and every store fails to load. See ``PrimaryStoreSchema/configuration(isStoredInMemoryOnly:)``
    /// for the full argument. Installing the container is the only way to pass the opt-out.
    ///
    /// `nil` only if even the in-memory fallback could not be built, which the scene handles by
    /// falling back to the convenience modifier — worse than nothing to fix, but better than a
    /// launch with no `modelContext` in the environment at all.
    private let primaryModelContainer: ModelContainer?
    #if canImport(UIKit)
    @UIApplicationDelegateAdaptor(AuralisAppDelegate.self) private var appDelegate
    #endif
    @Environment(\.scenePhase) private var scenePhase
    @State private var primaryStoreRecoveryAlertPresented = false

    init() {
        AppLaunchConfiguration().configure()

        let missingProviders = Secrets.configurationStatuses()
            .filter { !$0.isConfigured }

        if !missingProviders.isEmpty {
            let providerNames = missingProviders.map(\.provider.rawValue).joined(separator: ", ")
            logger.error("Launching with missing provider configuration: \(providerNames, privacy: .public)")
        }

        let uiTestFixture = UITestFixture(arguments: ProcessInfo.processInfo.arguments)
        // Resolved before the container is built, so a UI-test launch asks for in-memory storage on
        // the first attempt instead of opening the real store and discarding it.
        let bootstrap = Self.makePrimaryModelContainer(
            logger: logger,
            inMemory: uiTestFixture.usesInMemoryPrimaryStore
        )
        primaryStoreInitializationErrorMessage = bootstrap.errorMessage
        usesInMemoryPrimaryStore = bootstrap.usesInMemoryContainer
        primaryModelContainer = bootstrap.container
        self.uiTestFixture = uiTestFixture
    }

    var body: some Scene {
        primaryStoreScene
    }
}

private extension AuralisApp {
    var primaryStoreScene: some Scene {
        WindowGroup {
            // The container is installed here, on the root *view*, rather than on the scene.
            //
            // It has to be a view modifier because the choice between the resolved container and
            // the last-resort fallback is a conditional, and `@SceneBuilder` rejects control flow
            // ("Closure containing control flow statement cannot be used with result builder
            // 'SceneBuilder'"). `@ViewBuilder` accepts it, and `View/modelContainer(_:)` seeds the
            // same environment for this subtree that the scene-level modifier would have.
            rootView
            .task {
                primaryStoreRecoveryAlertPresented = primaryStoreInitializationErrorMessage != nil
                RuntimeBackgroundScheduler.scheduleNextRefresh()
            }
            .onChange(of: scenePhase) { _, newValue in
                // The runtime's event-checkpoint cursors are coalesced in memory to keep steady
                // UserDefaults churn off the event path, so backgrounding is the known-good moment
                // to make them durable. Without this the coalescing had no counterpart and a
                // terminated process replayed the tail of whatever burst was in flight.
                guard newValue == .background else { return }
                Task { await RuntimeAssembly.flushEventCheckpoints() }
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
        .backgroundTask(.appRefresh(RuntimeBackgroundScheduler.taskIdentifier)) {
            await RuntimeBackgroundScheduler.runInBackground()
        }
    }

    @ViewBuilder
    var rootView: some View {
        let content = UITestSeededRoot(
            fixture: uiTestFixture,
            dependencies: uiTestFixture.shellBootstrapDependencies,
            primaryStoreInitializationErrorMessage: primaryStoreInitializationErrorMessage
        )
        if let primaryModelContainer {
            content.modelContainer(primaryModelContainer)
        } else {
            // Unreachable unless even an in-memory container could not be built. Kept so the app
            // still installs *a* `modelContext` rather than leaving every `@Query` without one.
            // This path takes the `.automatic` CloudKit default and so will fail the same way, which
            // is why it exists to avoid a worse failure rather than to be relied on.
            content.modelContainer(
                for: PrimaryStoreSchema.models,
                inMemory: true,
                isUndoEnabled: true
            )
        }
    }

    static func makePrimaryModelContainer(logger: Logger, inMemory: Bool) -> (
        container: ModelContainer?,
        usesInMemoryContainer: Bool,
        errorMessage: String?
    ) {
        // Returns the container it opened rather than discarding it. This used to build one purely
        // to see whether it *could*, then let the scene modifier build a second — so the store was
        // opened twice on every launch, and the configuration the probe used was not necessarily
        // the configuration the app then ran on. Now there is one container and one configuration.
        do {
            let container = try ModelContainer(
                for: PrimaryStoreSchema.schema,
                configurations: PrimaryStoreSchema.configuration(isStoredInMemoryOnly: inMemory)
            )
            container.mainContext.undoManager = UndoManager()
            return (container, inMemory, nil)
        } catch {
            logger.error(
                "Primary SwiftData store boot failed; falling back to in-memory storage: \(error.localizedDescription, privacy: .public)"
            )
            // `try?`: this is already the failure path, and a second throw here has no better
            // handling available than the `nil` the scene already accounts for.
            let fallback = try? ModelContainer(
                for: PrimaryStoreSchema.schema,
                configurations: PrimaryStoreSchema.configuration(isStoredInMemoryOnly: true)
            )
            fallback?.mainContext.undoManager = UndoManager()
            return (
                fallback,
                true,
                "Local storage could not be opened on this launch. Changes will not persist after you quit Auralis."
            )
        }
    }
}

private enum UITestFixture: Equatable {
    case none
    case cleanGateway
    case authenticatedAccount(tabBarVisibility: AppTabBarVisibility, presentsSeededNFTDetail: Bool = false)

    init(arguments: [String]) {
        if arguments.contains("-ui-testing-authenticated") {
            if arguments.contains("-ui-testing-mission-control-tabs") {
                self = .authenticatedAccount(
                    tabBarVisibility: AppTabBarVisibility(tabBarTabs: [.home, .missionControl])
                )
            } else if arguments.contains("-ui-testing-search-tabs") {
                self = .authenticatedAccount(
                    tabBarVisibility: AppTabBarVisibility(tabBarTabs: [.home, .search])
                )
            } else if arguments.contains("-ui-testing-receipts-tabs") {
                self = .authenticatedAccount(
                    tabBarVisibility: AppTabBarVisibility(tabBarTabs: [.home, .receipts])
                )
            } else if arguments.contains("-ui-testing-nft-tabs") {
                self = .authenticatedAccount(
                    tabBarVisibility: AppTabBarVisibility(tabBarTabs: [.home, .nftTokens]),
                    presentsSeededNFTDetail: arguments.contains("-ui-testing-seeded-nft-detail")
                )
            } else if arguments.contains("-ui-testing-profile-tabs") {
                // Profile *is* in `.release`, unlike the four tabs above — but `.release` carries six
                // tabs and a compact iPhone shows five plus an overflow, so Profile is declared late
                // enough in `tabContent` to land in it. `selectTab` then tapped "More", failed to find
                // the tab in the overflow list, and fell through to `openTabViaHomeLauncher`, which
                // has no Home route to Profile — the "tab not reachable" half of F-105's harness class.
                // Narrowing the tab bar is how the other four audits already avoid the overflow; this
                // is the same remedy, not a new mechanism.
                self = .authenticatedAccount(
                    tabBarVisibility: AppTabBarVisibility(tabBarTabs: [.home, .profile])
                )
            } else {
                self = .authenticatedAccount(tabBarVisibility: .release)
            }
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
        guard case .authenticatedAccount = self else {
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
        case .cleanGateway:
            return .release
        case .authenticatedAccount(let tabBarVisibility, _):
            return tabBarVisibility
        }
    }

    var presentsSeededNFTDetail: Bool {
        switch self {
        case .authenticatedAccount(_, let presentsSeededNFTDetail):
            return presentsSeededNFTDetail
        case .none, .cleanGateway:
            return false
        }
    }

    @MainActor
    var shellBootstrapDependencies: ShellBootstrapDependencies {
        guard let seededAccount else {
            return .live
        }

        return ShellBootstrapDependencies.live(
            selectionPersistence: UITestShellSelectionPersistence(
                address: seededAccount.address,
                chainID: Chain.ethMainnet.rawValue
            )
        )
    }
}

private struct UITestSeededRoot: View {
    @Environment(\.modelContext) private var modelContext
    @State private var isReady = false

    let fixture: UITestFixture
    let dependencies: ShellBootstrapDependencies
    let primaryStoreInitializationErrorMessage: String?

    var body: some View {
        Group {
            if isReady {
                if fixture.presentsSeededNFTDetail, let account = fixture.seededAccount {
                    NavigationStack {
                        UITestNFTDetailHarnessView(accountAddress: account.address)
                    }
                } else {
                    MainAuraView(
                        dependencies: dependencies,
                        tabBarVisibility: fixture.tabBarVisibility,
                        primaryStoreInitializationErrorMessage: primaryStoreInitializationErrorMessage
                    )
                }
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

            seedSearchHistory(accountAddress: address)
            try seedReceipts(accountAddress: address)
            seedNFT(accountAddress: address)

            try modelContext.save()
        } catch {
            assertionFailure("Failed to seed UI test account: \(error.localizedDescription)")
        }
    }

    private func seedSearchHistory(accountAddress: String) {
        let normalizedAccountAddress = NFT.normalizedScopeComponent(accountAddress)
        insertSearchHistoryRecordIfNeeded(accountAddressRawValue: normalizedAccountAddress)
        insertSearchHistoryRecordIfNeeded(accountAddressRawValue: nil)
        insertSearchHistoryRecordIfNeeded(accountAddressRawValue: "")
    }

    private func insertSearchHistoryRecordIfNeeded(accountAddressRawValue: String?) {
        let normalizedQuery = "vitalik.eth"
        let descriptor = FetchDescriptor<SearchHistoryRecord>(
            predicate: #Predicate<SearchHistoryRecord> { record in
                record.accountAddressRawValue == accountAddressRawValue &&
                record.normalizedQuery == normalizedQuery
            }
        )

        if (try? modelContext.fetch(descriptor))?.isEmpty == false {
            return
        }

        modelContext.insert(
            SearchHistoryRecord(
                accountAddressRawValue: accountAddressRawValue,
                normalizedQuery: normalizedQuery,
                query: "vitalik.eth",
                recordedAt: Date(timeIntervalSince1970: 1_800_000_000)
            )
        )
    }

    private func seedReceipts(accountAddress: String) throws {
        let normalizedAccountAddress = NFT.normalizedScopeComponent(accountAddress)
        let correlationID = "a11y-ui-test-correlation"
        let descriptor = FetchDescriptor<StoredReceipt>(
            predicate: #Predicate<StoredReceipt> { receipt in
                receipt.correlationID == correlationID
            }
        )

        if try !modelContext.fetch(descriptor).isEmpty {
            return
        }

        modelContext.insert(
            try StoredReceipt(
                sequenceID: 1,
                createdAt: Date(timeIntervalSince1970: 1_800_000_100),
                actor: .system,
                mode: .observe,
                trigger: "ui_test.seed",
                scope: "Accessibility fixture",
                summary: "Seeded accessibility audit receipt",
                provenance: "ui-tests",
                isSuccess: true,
                correlationID: correlationID,
                timelineAccountAddress: normalizedAccountAddress,
                timelineChainRawValue: Chain.ethMainnet.rawValue,
                accountSequenceID: 1,
                payloadHash: "a11y-payload-hash",
                previousReceiptHash: "a11y-previous-hash",
                chainHash: "a11y-chain-hash",
                details: ReceiptPayload(values: [
                    "accountAddress": .string(accountAddress),
                    "chain": .string(Chain.ethMainnet.rawValue)
                ])
            )
        )
    }

    private func seedNFT(accountAddress: String) {
        let nftID = "a11y-seeded-nft"
        let descriptor = FetchDescriptor<NFT>(
            predicate: #Predicate<NFT> { nft in
                nft.id == nftID
            }
        )

        if (try? modelContext.fetch(descriptor))?.isEmpty == false {
            return
        }

        modelContext.insert(
            NFT(
                id: nftID,
                contract: NFT.Contract(address: "0x0000000000000000000000000000000000000001"),
                tokenId: "1",
                tokenType: "ERC721",
                name: "Accessibility Seed NFT",
                nftDescription: "Deterministic fixture used by accessibility UI audits.",
                collection: NFT.Collection(
                    name: "Accessibility Fixtures",
                    contractAddress: "0x0000000000000000000000000000000000000001"
                ),
                network: .ethMainnet,
                accountAddress: accountAddress,
                contentType: "audio/mpeg",
                collectionName: "Accessibility Fixtures",
                artistName: "Auralis QA",
                audioUrl: "https://example.com/a11y.mp3"
            )
        )
    }
}

private struct UITestNFTDetailHarnessView: View {
    let accountAddress: String

    var body: some View {
        NFTLibraryDetailView(
            nft: NFT(
                id: "a11y-seeded-nft",
                contract: NFT.Contract(address: "0x0000000000000000000000000000000000000001"),
                tokenId: "1",
                tokenType: "ERC721",
                name: "Accessibility Seed NFT",
                nftDescription: "Deterministic fixture used by accessibility UI audits.",
                collection: NFT.Collection(
                    name: "Accessibility Fixtures",
                    contractAddress: "0x0000000000000000000000000000000000000001"
                ),
                network: .ethMainnet,
                accountAddress: accountAddress,
                contentType: "audio/mpeg",
                collectionName: "Accessibility Fixtures",
                artistName: "Auralis QA",
                audioUrl: "https://example.com/a11y.mp3"
            ),
            dependencies: NFTLibraryDependencies { _ in }
        )
    }
}

@MainActor
private final class UITestShellSelectionPersistence: ShellSelectionPersisting {
    private let address: String
    private let chainID: String

    init(address: String, chainID: String) {
        self.address = address
        self.chainID = chainID
    }

    func loadSelection() async throws -> (address: String, chainID: String) {
        (address, chainID)
    }

    func saveSelection(address: String, chainID: String) async throws {}

    func clearSelection() async throws {}
}
