import Foundation

public struct WalletRequest: Identifiable, Hashable, Codable, Sendable {
    public let id: WalletSignRequestID
    public let chain: WalletBlockchain
    public let method: WalletRequestMethod
    public let params: [String]
    public let expiryDate: Date

    public init(
        id: WalletSignRequestID,
        chain: WalletBlockchain,
        method: WalletRequestMethod,
        params: [String],
        expiryDate: Date = Date().addingTimeInterval(300)
    ) {
        self.id = id
        self.chain = chain
        self.method = method
        self.params = params
        self.expiryDate = expiryDate
    }
}

public struct WalletResponse: Identifiable, Hashable, Codable, Sendable {
    public let id: WalletSignRequestID
    public let result: String

    public init(id: WalletSignRequestID, result: String) {
        self.id = id
        self.result = result
    }
}

public enum WalletRequestBuilder {
    public static func personalSign(
        id: WalletSignRequestID,
        address: String,
        message: String,
        chain: WalletChain = .ethereum,
        expiryDate: Date = Date().addingTimeInterval(300)
    ) -> WalletRequest {
        WalletRequest(
            id: id,
            chain: WalletBlockchain(namespace: chain.namespace, reference: chain.chainReference),
            method: .ethPersonalSign,
            params: [message, address],
            expiryDate: expiryDate
        )
    }

    public static func solanaSignMessage(
        id: WalletSignRequestID,
        address: String,
        message: String,
        expiryDate: Date = Date().addingTimeInterval(300)
    ) -> WalletRequest {
        WalletRequest(
            id: id,
            chain: WalletBlockchain(namespace: WalletChain.solana.namespace, reference: WalletChain.solana.chainReference),
            method: .solanaSignMessage,
            params: [message, address],
            expiryDate: expiryDate
        )
    }
}

