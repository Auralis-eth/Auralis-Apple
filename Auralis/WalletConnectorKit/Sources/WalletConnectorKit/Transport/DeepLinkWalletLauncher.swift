import Foundation

public struct DeepLinkWalletLauncher: Sendable {
    private let opener: any WalletApplicationOpening

    public init(opener: any WalletApplicationOpening) {
        self.opener = opener
    }

    public func launch(
        provider: ThirdPartyWalletProvider,
        pairingURI: WalletConnectURI,
        redirect: WalletConnectionRedirect? = nil
    ) async throws {
        guard let scheme = provider.deepLinkScheme else {
            throw WalletConnectionError.walletNotInstalled(provider.id)
        }
        let link = WalletProviderDeepLink(providerID: provider.id, scheme: scheme)
        guard let url = link.url(pairingURI: pairingURI, redirect: redirect) else {
            throw WalletConnectionError.invalidPairingURI
        }
        guard await opener.canOpenURL(url) else {
            throw WalletConnectionError.walletNotInstalled(provider.id)
        }
        guard await opener.open(url) else {
            throw WalletConnectionError.walletOpenFailed(provider.id)
        }
    }
}

