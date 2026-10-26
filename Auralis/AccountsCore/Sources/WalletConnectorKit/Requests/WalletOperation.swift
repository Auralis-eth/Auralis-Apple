import Foundation

public enum WalletOperation: Hashable, Codable, Sendable {
    case evm(EVMWalletOperation)
    case solana(SolanaWalletOperation)
    case raw(WalletRequest)

    public func walletRequest(id: WalletSignRequestID, expiryDate: Date = Date().addingTimeInterval(300)) throws -> WalletRequest {
        switch self {
        case .evm(let operation):
            return operation.walletRequest(id: id, expiryDate: expiryDate)
        case .solana(let operation):
            return try operation.walletRequest(id: id, expiryDate: expiryDate)
        case .raw(let request):
            return request
        }
    }
}

public enum EVMWalletOperation: Hashable, Codable, Sendable {
    /// Human-readable EIP-191 `personal_sign` text. The semantic operation hex-encodes
    /// UTF-8 before building the request; use `WalletRequestBuilder.personalSign`
    /// directly when the payload is already `0x`-prefixed hex.
    case personalSign(address: String, message: String, chain: WalletChain = .ethereum)
    case signTypedDataV4(address: String, typedDataJSON: String, chain: WalletChain = .ethereum)
    case sendTransaction(WalletTransactionRequest, chain: WalletChain = .ethereum)
    case switchEthereumChain(chainId: String, chain: WalletChain = .ethereum)
    case addEthereumChain(WalletAddEthereumChainRequest, chain: WalletChain = .ethereum)
    case watchAsset(WalletWatchAssetRequest, chain: WalletChain = .ethereum)

    public func walletRequest(id: WalletSignRequestID, expiryDate: Date = Date().addingTimeInterval(300)) -> WalletRequest {
        switch self {
        case .personalSign(let address, let message, let chain):
            return WalletRequestBuilder.personalSignText(id: id, address: address, text: message, chain: chain, expiryDate: expiryDate)
        case .signTypedDataV4(let address, let typedDataJSON, let chain):
            return WalletRequestBuilder.signTypedDataV4(id: id, address: address, typedDataJSON: typedDataJSON, chain: chain, expiryDate: expiryDate)
        case .sendTransaction(let transaction, let chain):
            return WalletRequestBuilder.sendTransaction(id: id, transaction: transaction, chain: chain, expiryDate: expiryDate)
        case .switchEthereumChain(let chainId, let chain):
            return WalletRequestBuilder.switchEthereumChain(id: id, chainId: chainId, chain: chain, expiryDate: expiryDate)
        case .addEthereumChain(let request, let chain):
            return WalletRequestBuilder.addEthereumChain(id: id, request: request, chain: chain, expiryDate: expiryDate)
        case .watchAsset(let request, let chain):
            return WalletRequestBuilder.watchAsset(id: id, request: request, chain: chain, expiryDate: expiryDate)
        }
    }
}

public struct WalletSolanaSerializedTransaction: Hashable, Codable, Sendable {
    public let value: String
    public let encoding: WalletSolanaTransactionEncoding
    public let recentBlockhash: String?
    public let lastValidBlockHeight: UInt64?
    public let blockhashExpiresAt: Date?

    public init(
        value: String,
        encoding: WalletSolanaTransactionEncoding = .base64,
        recentBlockhash: String? = nil,
        lastValidBlockHeight: UInt64? = nil,
        blockhashExpiresAt: Date? = nil
    ) {
        self.value = value
        self.encoding = encoding
        self.recentBlockhash = recentBlockhash
        self.lastValidBlockHeight = lastValidBlockHeight
        self.blockhashExpiresAt = blockhashExpiresAt
    }

    public func hasExpiredBlockhash(now: Date = Date()) -> Bool {
        guard let blockhashExpiresAt else { return false }
        return blockhashExpiresAt <= now
    }
}

public enum SolanaWalletOperation: Hashable, Codable, Sendable {
    case signMessage(address: String, message: String)
    case signTransaction(WalletSolanaSerializedTransaction)
    case signAllTransactions([WalletSolanaSerializedTransaction])
    case signAndSendTransaction(WalletSolanaSerializedTransaction)

    public func walletRequest(id: WalletSignRequestID, expiryDate: Date = Date().addingTimeInterval(300)) throws -> WalletRequest {
        switch self {
        case .signMessage(let address, let message):
            return WalletRequestBuilder.solanaSignMessage(id: id, address: address, message: message, expiryDate: expiryDate)
        case .signTransaction(let transaction):
            return WalletRequestBuilder.solanaSignTransaction(id: id, serializedTransaction: transaction.value, encoding: transaction.encoding, expiryDate: expiryDate)
        case .signAllTransactions(let transactions):
            guard let encoding = transactions.first?.encoding,
                  transactions.allSatisfy({ $0.encoding == encoding }) else {
                throw WalletConnectionError.invalidResponse
            }
            return try WalletRequestBuilder.solanaSignAllTransactions(
                id: id,
                serializedTransactions: transactions.map(\.value),
                encoding: encoding,
                expiryDate: expiryDate
            )
        case .signAndSendTransaction(let transaction):
            return WalletRequestBuilder.solanaSignAndSendTransaction(id: id, serializedTransaction: transaction.value, encoding: transaction.encoding, expiryDate: expiryDate)
        }
    }
}
