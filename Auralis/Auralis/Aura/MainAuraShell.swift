import Foundation

struct MainAuraRestoreResult {
    let currentAddress: String
    let currentChain: Chain
    let currentAccount: EOAccount?
    let didFinishInitialStateRestore: Bool
    let shouldProcessPendingDeepLink: Bool
}

struct MainAuraAccountChangeResult {
    let currentAddress: String
    let shouldResetRoutes: Bool
    let shouldRefreshNFTs: Bool
    let shouldProcessPendingDeepLink: Bool
}

struct MainAuraAddressChangeResult {
    let currentAddress: String
    let currentAccount: EOAccount?
    let shouldResetRoutes: Bool
    let shouldProcessPendingDeepLink: Bool
}

struct MainAuraShellLogic {
    func restoreInitialState(
        currentAddress: String,
        currentChainId: String,
        accounts: [EOAccount]
    ) -> MainAuraRestoreResult {
        let resolvedSelection = resolveInitialSelection(for: currentAddress, accounts: accounts)

        return MainAuraRestoreResult(
            currentAddress: resolvedSelection.currentAddress,
            currentChain: Chain(rawValue: currentChainId) ?? .ethMainnet,
            currentAccount: resolvedSelection.currentAccount,
            didFinishInitialStateRestore: true,
            shouldProcessPendingDeepLink: true
        )
    }

    func accountDidChange(newAccount: EOAccount?, persistedAddress: String) -> MainAuraAccountChangeResult {
        let nextAddress = newAccount?.address ?? ""
        let shouldRefreshNFTs = newAccount != nil && nextAddress != persistedAddress

        return MainAuraAccountChangeResult(
            currentAddress: nextAddress,
            shouldResetRoutes: shouldRefreshNFTs,
            shouldRefreshNFTs: shouldRefreshNFTs,
            shouldProcessPendingDeepLink: true
        )
    }

    func addressDidChange(newAddress: String, accounts: [EOAccount]) -> MainAuraAddressChangeResult {
        let resolvedAccount = resolvePersistedAccount(for: newAddress, accounts: accounts)

        return MainAuraAddressChangeResult(
            currentAddress: newAddress,
            currentAccount: resolvedAccount,
            shouldResetRoutes: true,
            shouldProcessPendingDeepLink: true
        )
    }

    private func resolveInitialSelection(for address: String, accounts: [EOAccount]) -> (currentAddress: String, currentAccount: EOAccount?) {
        guard !address.isEmpty else {
            return ("", nil)
        }

        if let existingAccount = resolvePersistedAccount(for: address, accounts: accounts) {
            return (existingAccount.address, existingAccount)
        }

        guard let fallbackAccount = fallbackAccount(in: accounts) else {
            return ("", nil)
        }

        return (fallbackAccount.address, fallbackAccount)
    }

    private func resolvePersistedAccount(for address: String, accounts: [EOAccount]) -> EOAccount? {
        guard !address.isEmpty else {
            return nil
        }

        return accounts.first(where: { $0.address == address })
    }

    private func fallbackAccount(in accounts: [EOAccount]) -> EOAccount? {
        accounts.sorted { lhs, rhs in
            if lhs.mostRecentActivityAt != rhs.mostRecentActivityAt {
                return lhs.mostRecentActivityAt > rhs.mostRecentActivityAt
            }

            if lhs.addedAt != rhs.addedAt {
                return lhs.addedAt > rhs.addedAt
            }

            return lhs.address.localizedCompare(rhs.address) == .orderedAscending
        }.first
    }
}
