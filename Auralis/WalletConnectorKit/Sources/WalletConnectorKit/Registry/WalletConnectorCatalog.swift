import Foundation

public enum WalletConnectorCatalog {
    public static let metamask = ThirdPartyWalletProvider(
        id: "metamask",
        displayName: "MetaMask",
        supportedChains: [.ethereum, .polygon, .base, .optimism, .arbitrum],
        connectionMethods: [
            .universalLink("https://metamask.app.link"),
            .deepLink(scheme: "metamask"),
            .mobileSDK(identifier: "metamask-mobile-sdk"),
        ]
    )

    public static let rainbow = ThirdPartyWalletProvider(
        id: "rainbow",
        displayName: "Rainbow",
        supportedChains: [.ethereum, .polygon, .base, .optimism, .arbitrum],
        connectionMethods: [
            .universalLink("https://rnbwapp.com"),
            .deepLink(scheme: "rainbow"),
        ]
    )

    public static let coinbaseWallet = ThirdPartyWalletProvider(
        id: "coinbase-wallet",
        displayName: "Coinbase Wallet",
        supportedChains: [.ethereum, .polygon, .base, .optimism, .arbitrum],
        connectionMethods: [
            .universalLink("https://go.cb-w.com"),
            .deepLink(scheme: "cbwallet"),
            .mobileSDK(identifier: "coinbase-wallet-sdk"),
        ]
    )

    public static let phantom = ThirdPartyWalletProvider(
        id: "phantom",
        displayName: "Phantom",
        supportedChains: [.solana, .ethereum, .polygon, .base],
        connectionMethods: [
            .universalLink("https://phantom.app/ul"),
            .deepLink(scheme: "phantom"),
        ]
    )

    public static let defaultProviders: [ThirdPartyWalletProvider] = [
        metamask,
        rainbow,
        coinbaseWallet,
        phantom,
    ]
}
