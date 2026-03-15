import Foundation

struct MainAuraRestoreResult {
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
        MainAuraRestoreResult(
            currentChain: Chain(rawValue: currentChainId) ?? .ethMainnet,
            currentAccount: resolveAccount(for: currentAddress, accounts: accounts),
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
        MainAuraAddressChangeResult(
            currentAccount: resolveAccount(for: newAddress, accounts: accounts),
            shouldResetRoutes: true,
            shouldProcessPendingDeepLink: true
        )
    }

    private func resolveAccount(for address: String, accounts: [EOAccount]) -> EOAccount? {
        guard !address.isEmpty else {
            return nil
        }

        if let existingAccount = accounts.first(where: { $0.address == address }) {
            return existingAccount
        }

        return EOAccount(address: address)
    }
}
