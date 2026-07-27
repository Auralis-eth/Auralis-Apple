import Foundation

public enum WalletRequestMethod: String, Hashable, Codable, Sendable {
    case ethSendTransaction = "eth_sendTransaction"
    case ethPersonalSign = "personal_sign"
    case ethSignTypedData = "eth_signTypedData"
    case ethSignTypedDataV4 = "eth_signTypedData_v4"
    case solanaSignMessage = "solana_signMessage"
    case solanaSignTransaction = "solana_signTransaction"
    case solanaSignAllTransactions = "solana_signAllTransactions"
}

public struct WalletSessionNamespace: Hashable, Codable, Sendable {
    public let name: String
    public let accounts: [WalletAccount]
    public let methods: [String]
    public let events: [String]

    public init(name: String, accounts: [WalletAccount], methods: [String], events: [String]) {
        self.name = name
        self.accounts = accounts
        self.methods = methods
        self.events = events
    }
}

public struct WalletNamespaceProposal: Hashable, Codable, Sendable {
    public let chains: [WalletBlockchain]
    public let methods: [String]
    public let events: [String]

    public init(chains: [WalletBlockchain], methods: [String], events: [String]) {
        self.chains = chains
        self.methods = methods
        self.events = events
    }
}

public struct WalletNamespaceProposalSet: Hashable, Codable, Sendable {
    public let proposals: [String: WalletNamespaceProposal]

    public init(proposals: [String: WalletNamespaceProposal]) {
        self.proposals = proposals
    }

    public static let defaultV1 = WalletNamespaceProposalSet(
        proposals: [
            "eip155": WalletNamespaceProposal(
                chains: WalletChain.evmChains.map { WalletBlockchain(namespace: $0.namespace, reference: $0.chainReference) },
                methods: WalletConnectionNamespaces.evmMethods,
                events: WalletConnectionNamespaces.evmEvents
            ),
            "solana": WalletNamespaceProposal(
                chains: [WalletBlockchain(namespace: WalletChain.solana.namespace, reference: WalletChain.solana.chainReference)],
                methods: WalletConnectionNamespaces.solanaMethods,
                events: WalletConnectionNamespaces.solanaEvents
            ),
        ]
    )
}

public enum WalletConnectionNamespaces {
    public static let evmMethods: [String] = [
        WalletRequestMethod.ethPersonalSign.rawValue,
        WalletRequestMethod.ethSendTransaction.rawValue,
        WalletRequestMethod.ethSignTypedData.rawValue,
        WalletRequestMethod.ethSignTypedDataV4.rawValue,
    ]

    public static let evmEvents: [String] = [
        "accountsChanged",
        "chainChanged",
    ]

    public static let solanaMethods: [String] = [
        WalletRequestMethod.solanaSignMessage.rawValue,
        WalletRequestMethod.solanaSignTransaction.rawValue,
        WalletRequestMethod.solanaSignAllTransactions.rawValue,
    ]

    public static let solanaEvents: [String] = []
}

public struct WalletTransactionRequest: Hashable, Codable, Sendable {
    public let from: String
    public let to: String?
    public let value: String
    public let data: String
    public let nonce: Int?
    public let gas: String?
    public let gasPrice: String?
    public let maxFeePerGas: String?
    public let maxPriorityFeePerGas: String?
    public let gasLimit: String?
    public let chainId: String

    public init(
        from: String,
        to: String? = nil,
        value: String,
        data: String,
        nonce: Int? = nil,
        gas: String? = nil,
        gasPrice: String? = nil,
        maxFeePerGas: String? = nil,
        maxPriorityFeePerGas: String? = nil,
        gasLimit: String? = nil,
        chainId: String
    ) {
        self.from = from
        self.to = to
        self.value = value
        self.data = data
        self.nonce = nonce
        self.gas = gas
        self.gasPrice = gasPrice
        self.maxFeePerGas = maxFeePerGas
        self.maxPriorityFeePerGas = maxPriorityFeePerGas
        self.gasLimit = gasLimit
        self.chainId = chainId
    }
}

public struct WalletAddEthereumChainRequest: Hashable, Codable, Sendable {
    public struct NativeCurrency: Hashable, Codable, Sendable {
        public let name: String
        public let symbol: String
        public let decimals: Int

        public init(name: String, symbol: String, decimals: Int) {
            self.name = name
            self.symbol = symbol
            self.decimals = decimals
        }
    }

    public let chainId: String
    public let blockExplorerUrls: [String]?
    public let chainName: String?
    public let iconUrls: [String]?
    public let nativeCurrency: NativeCurrency?
    public let rpcUrls: [String]

    public init(
        chainId: String,
        blockExplorerUrls: [String]? = nil,
        chainName: String? = nil,
        iconUrls: [String]? = nil,
        nativeCurrency: NativeCurrency? = nil,
        rpcUrls: [String]
    ) {
        self.chainId = chainId
        self.blockExplorerUrls = blockExplorerUrls
        self.chainName = chainName
        self.iconUrls = iconUrls
        self.nativeCurrency = nativeCurrency
        self.rpcUrls = rpcUrls
    }
}

public struct WalletWatchAssetRequest: Hashable, Codable, Sendable {
    public let type: String
    public let address: String
    public let symbol: String?
    public let decimals: Int?
    public let image: String?

    public init(type: String = "ERC20", address: String, symbol: String? = nil, decimals: Int? = nil, image: String? = nil) {
        self.type = type
        self.address = address
        self.symbol = symbol
        self.decimals = decimals
        self.image = image
    }
}

public enum WalletRPCRequest: Hashable, Codable, Sendable {
    case requestAccounts
    case personalSign(address: String, message: String)
    case signTransaction(WalletTransactionRequest)
    case sendTransaction(WalletTransactionRequest)
    case switchEthereumChain(chainId: String)
    case addEthereumChain(WalletAddEthereumChainRequest)
    case watchAsset(WalletWatchAssetRequest)

    public var methodName: String {
        switch self {
        case .requestAccounts:
            "eth_requestAccounts"
        case .personalSign:
            "personal_sign"
        case .signTransaction:
            "eth_signTransaction"
        case .sendTransaction:
            "eth_sendTransaction"
        case .switchEthereumChain:
            "wallet_switchEthereumChain"
        case .addEthereumChain:
            "wallet_addEthereumChain"
        case .watchAsset:
            "wallet_watchAsset"
        }
    }
}
