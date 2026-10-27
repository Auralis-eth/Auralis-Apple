import Foundation

public enum WalletConnectorCatalog {
    private static let evmExternalCapabilities: WalletConnectorCapabilities = [
        .externalWallet,
        .evm,
        .messageSigning,
        .transactionSigning,
        .chainSwitching,
        .chainAddition,
        .assetWatching,
        .customSchemeReturn,
    ]

    private static let evmUniversalExternalCapabilities: WalletConnectorCapabilities = [
        .externalWallet,
        .evm,
        .messageSigning,
        .transactionSigning,
        .chainSwitching,
        .chainAddition,
        .assetWatching,
        .universalLinkReturn,
        .customSchemeReturn,
    ]

    private static let multichainExternalCapabilities: WalletConnectorCapabilities = [
        .externalWallet,
        .evm,
        .solana,
        .messageSigning,
        .transactionSigning,
        .batchTransactionSigning,
        .signAndSend,
        .chainSwitching,
        .chainAddition,
        .assetWatching,
        .universalLinkReturn,
        .customSchemeReturn,
    ]

    private static let privyEmbeddedProviderCapabilities: WalletConnectorCapabilities = [
        .embeddedWallet,
        .evm,
        .messageSigning,
    ]

    private static let dynamicEmbeddedProviderCapabilities: WalletConnectorCapabilities = [
        .embeddedWallet,
        .evm,
        .messageSigning,
        .transactionSigning,
    ]

    public static let rabby = ThirdPartyWalletProvider(
        id: "rabby",
        displayName: "Rabby",
        supportedChains: WalletChain.evmChains,
        connectionMethods: [
            .deepLink(scheme: "rabby"),
        ],
        capabilities: evmExternalCapabilities
    )

    public static let metamask = ThirdPartyWalletProvider(
        id: "metamask",
        displayName: "MetaMask",
        supportedChains: WalletChain.evmChains,
        connectionMethods: [
            .universalLink("https://metamask.app.link"),
            .deepLink(scheme: "metamask"),
            .mobileSDK(identifier: "metamask-mobile-sdk"),
        ],
        supportStatus: .deprecated("The legacy MetaMask native iOS SDK repository was archived on February 26, 2026; prefer WalletConnect/Reown or MetaMask's current embedded-wallet route."),
        capabilities: evmUniversalExternalCapabilities
    )

    public static let rainbow = ThirdPartyWalletProvider(
        id: "rainbow",
        displayName: "Rainbow",
        supportedChains: WalletChain.evmChains,
        connectionMethods: [
            .universalLink("https://rnbwapp.com"),
            .deepLink(scheme: "rainbow"),
        ],
        capabilities: evmUniversalExternalCapabilities
    )

    public static let coinbaseWallet = ThirdPartyWalletProvider(
        id: "coinbase-wallet",
        displayName: "Coinbase Wallet",
        supportedChains: WalletChain.evmChains,
        connectionMethods: [
            .universalLink("https://go.cb-w.com"),
            .deepLink(scheme: "cbwallet"),
            .mobileSDK(identifier: "coinbase-wallet-sdk"),
        ],
        supportStatus: .limited("Coinbase Mobile Wallet Protocol is direct request/response, not a WalletConnect IRN session."),
        capabilities: [
            .externalWallet,
            .evm,
            .messageSigning,
            .transactionSigning,
            .chainAddition,
            .assetWatching,
            .directRequestResponse,
            .universalLinkReturn,
            .customSchemeReturn,
        ]
    )

    public static let phantom = ThirdPartyWalletProvider(
        id: "phantom",
        displayName: "Phantom",
        supportedChains: [.solana] + WalletChain.evmChains,
        connectionMethods: [
            .universalLink("https://phantom.app/ul"),
            .deepLink(scheme: "phantom"),
        ],
        capabilities: multichainExternalCapabilities
    )

    public static let backpack = ThirdPartyWalletProvider(
        id: "backpack",
        displayName: "Backpack",
        supportedChains: [.solana] + WalletChain.evmChains,
        connectionMethods: [
            .deepLink(scheme: "backpack"),
        ],
        capabilities: multichainExternalCapabilities.subtracting(.universalLinkReturn)
    )

    public static let solflare = ThirdPartyWalletProvider(
        id: "solflare",
        displayName: "Solflare",
        supportedChains: [.solana],
        connectionMethods: [
            .deepLink(scheme: "solflare"),
        ],
        capabilities: [
            .externalWallet,
            .solana,
            .messageSigning,
            .transactionSigning,
            .batchTransactionSigning,
            .signAndSend,
            .customSchemeReturn,
        ]
    )

    public static let privy = ThirdPartyWalletProvider(
        id: "privy",
        displayName: "Privy",
        supportedChains: WalletChain.evmChains,
        connectionMethods: [
            .mobileSDK(identifier: "privy-adapter"),
        ],
        role: .embeddedWalletProvider,
        custodyModel: .providerManaged,
        capabilities: privyEmbeddedProviderCapabilities
    )

    public static let dynamic = ThirdPartyWalletProvider(
        id: "dynamic",
        displayName: "Dynamic",
        supportedChains: WalletChain.evmChains,
        connectionMethods: [
            .mobileSDK(identifier: "dynamic-adapter"),
        ],
        role: .embeddedWalletProvider,
        custodyModel: .providerManaged,
        capabilities: dynamicEmbeddedProviderCapabilities
    )

    public static let genericWallet = ThirdPartyWalletProvider(
        id: "generic-wallet",
        displayName: "Generic Wallet",
        supportedChains: [.solana] + WalletChain.evmChains,
        connectionMethods: [
            .browserExtension(identifier: "walletconnect-uri"),
        ],
        capabilities: [
            .externalWallet,
            .evm,
            .solana,
            .messageSigning,
            .transactionSigning,
            .batchTransactionSigning,
            .signAndSend,
            .chainSwitching,
            .chainAddition,
            .assetWatching,
            .persistentSession,
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
