import AuralisPrimaryModels
import AuralisPrimaryPersistence
import AuralisShellCore
import OSLog
import SwiftData
import SwiftUI
import NFTDomain
import NFTLibraryFeature
import NFTPersistence
import NFTPresentation
import NFTProviderAdapters
import ProviderKit
import ReceiptStorage

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
                dependencies: uiTestFixture.shellBootstrapDependencies,
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
    case authenticatedAccount(tabBarVisibility: AppTabBarVisibility, presentsSeededNFTDetail: Bool = false)

    init(arguments: [String]) {
        if arguments.contains("-ui-testing-authenticated") {
            if arguments.contains("-ui-testing-search-tabs") {
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
