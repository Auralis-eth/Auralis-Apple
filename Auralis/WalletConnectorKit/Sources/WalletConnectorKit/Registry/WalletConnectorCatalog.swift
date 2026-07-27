import Foundation

public enum WalletConnectorCatalog {
    public static let rabby = ThirdPartyWalletProvider(
        id: "rabby",
        displayName: "Rabby",
        supportedChains: WalletChain.evmChains,
        connectionMethods: [
            .deepLink(scheme: "rabby"),
        ]
    )

    public static let metamask = ThirdPartyWalletProvider(
        id: "metamask",
        displayName: "MetaMask",
        supportedChains: WalletChain.evmChains,
        connectionMethods: [
            .universalLink("https://metamask.app.link"),
            .deepLink(scheme: "metamask"),
            .mobileSDK(identifier: "metamask-mobile-sdk"),
        ]
    )

    public static let rainbow = ThirdPartyWalletProvider(
        id: "rainbow",
        displayName: "Rainbow",
        supportedChains: WalletChain.evmChains,
        connectionMethods: [
            .universalLink("https://rnbwapp.com"),
            .deepLink(scheme: "rainbow"),
        ]
    )

    public static let coinbaseWallet = ThirdPartyWalletProvider(
        id: "coinbase-wallet",
        displayName: "Coinbase Wallet",
        supportedChains: WalletChain.evmChains,
        connectionMethods: [
            .universalLink("https://go.cb-w.com"),
            .deepLink(scheme: "cbwallet"),
            .mobileSDK(identifier: "coinbase-wallet-sdk"),
        ]
    )

    public static let phantom = ThirdPartyWalletProvider(
        id: "phantom",
        displayName: "Phantom",
        supportedChains: [.solana] + WalletChain.evmChains,
        connectionMethods: [
            .universalLink("https://phantom.app/ul"),
            .deepLink(scheme: "phantom"),
        ]
    )

    public static let backpack = ThirdPartyWalletProvider(
        id: "backpack",
        displayName: "Backpack",
        supportedChains: [.solana] + WalletChain.evmChains,
        connectionMethods: [
            .deepLink(scheme: "backpack"),
        ]
    )

    public static let solflare = ThirdPartyWalletProvider(
        id: "solflare",
        displayName: "Solflare",
        supportedChains: [.solana],
        connectionMethods: [
            .deepLink(scheme: "solflare"),
        ]
    )

    public static let privy = ThirdPartyWalletProvider(
        id: "privy",
        displayName: "Privy",
        supportedChains: WalletChain.evmChains,
        connectionMethods: [
            .mobileSDK(identifier: "privy-adapter"),
        ]
    )

    public static let dynamic = ThirdPartyWalletProvider(
        id: "dynamic",
        displayName: "Dynamic",
        supportedChains: WalletChain.evmChains,
        connectionMethods: [
            .mobileSDK(identifier: "dynamic-adapter"),
        ]
    )

    public static let genericWallet = ThirdPartyWalletProvider(
        id: "generic-wallet",
        displayName: "Generic Wallet",
        supportedChains: [.solana] + WalletChain.evmChains,
        connectionMethods: [
            .browserExtension(identifier: "walletconnect-uri"),
        ]
    )

    public static let defaultProviders: [ThirdPartyWalletProvider] = [
        rabby,
        metamask,
        rainbow,
        coinbaseWallet,
        phantom,
        backpack,
        solflare,
        privy,
        dynamic,
        genericWallet,
    ]
}
