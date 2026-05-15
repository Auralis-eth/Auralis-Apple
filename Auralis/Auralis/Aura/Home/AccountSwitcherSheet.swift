import AccountsCore
import AccountsFeature
import AuralisPrimaryModels
import AuralisShellCore
import ENS
import SwiftData
import SwiftUI

struct AccountSwitcherHostSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Query(
        sort: [
            SortDescriptor(\EOAccount.lastSelectedAt, order: .reverse),
            SortDescriptor(\EOAccount.addedAt, order: .reverse),
            SortDescriptor(\EOAccount.address)
        ]
    ) private var persistedAccounts: [EOAccount]

    let currentAccount: EOAccount?
    let activeSelection: ActiveShellSelection?
    let accountStoreFactory: @MainActor (ModelContext) -> any AccountStoring
    let onSelectAccount: @MainActor (String) -> Void
    let onRemoveAccount: @MainActor (String) -> Void
    let onCurrentChainChange: @MainActor (Chain) -> Void

    var body: some View {
        AccountSwitcherSheet(
            persistedAccounts: persistedAccounts,
            currentAccount: currentAccount,
            activeSelection: activeSelection.map {
                AccountSwitcherSelection(address: $0.address, chain: $0.chain)
            },
            accountSwitcher: AccountStoreAccountSwitcher(
                store: accountStoreFactory(modelContext)
            ),
            onSelectAccount: onSelectAccount,
            onRemoveAccount: onRemoveAccount,
            onCurrentChainChange: onCurrentChainChange
        )
    }
}

@MainActor
struct AppAccountENSResolver: AccountENSResolving {
    private let resolver: any ENSResolving

    init(resolver: any ENSResolving) {
        self.resolver = resolver
    }

    func resolveAddress(forENS ensName: String, correlationID: String) async throws -> AccountENSResolution {
        do {
            let resolution = try await resolver.resolveAddress(
                forENS: ensName,
                correlationID: correlationID
            )
            return AccountENSResolution(
                address: resolution.address,
                ensName: resolution.ensName,
                isStale: resolution.isStale
            )
        } catch let error as ENSResolutionError {
            switch error {
            case .mappingChanged(let ensName, let cachedAddress, let resolvedAddress):
                throw AccountENSResolutionFailure.mappingChanged(
                    ensName: ensName,
                    cachedAddress: cachedAddress,
                    resolvedAddress: resolvedAddress
                )
            default:
                throw AccountENSResolutionFailure.unavailable(error.localizedDescription)
            }
        } catch {
            throw AccountENSResolutionFailure.unavailable(error.localizedDescription)
        }
    }
}

@MainActor
struct AccountStoreAccountActivator: AccountActivating {
    private let store: any AccountStoring

    init(store: any AccountStoring) {
        self.store = store
    }

    func activateWatchAccount(
        from rawAddress: String,
        name: String?,
        source: EOAccountSource,
        correlationID: String?
    ) async throws -> AccountActivationResult {
        try await store.activateWatchAccount(
            from: rawAddress,
            name: name,
            source: source,
            correlationID: correlationID
        )
    }
}

@MainActor
private struct AccountStoreAccountSwitcher: AccountSwitching {
    private let store: any AccountStoring

    init(store: any AccountStoring) {
        self.store = store
    }

    func persistPreferredChain(
        address rawAddress: String,
        chain: Chain,
        correlationID: String?
    ) async throws -> EOAccount {
        try await store.persistPreferredChain(
            address: rawAddress,
            chain: chain,
            correlationID: correlationID
        )
    }

    func persistCurrentChain(
        address rawAddress: String,
        chain: Chain,
        correlationID: String?
    ) async throws -> EOAccount {
        try await store.persistCurrentChain(
            address: rawAddress,
            chain: chain,
            correlationID: correlationID
        )
    }
}
