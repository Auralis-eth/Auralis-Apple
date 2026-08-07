import Foundation

public enum WalletJSONValue: Hashable, Codable, Sendable {
    case string(String)
    case bool(Bool)
    case int(Int)
    case double(Double)
    case array([WalletJSONValue])
    case object([String: WalletJSONValue])
    case null

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Int.self) {
            self = .int(value)
        } else if let value = try? container.decode(Double.self) {
            self = .double(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([WalletJSONValue].self) {
            self = .array(value)
        } else if let value = try? container.decode([String: WalletJSONValue].self) {
            self = .object(value)
        } else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unsupported wallet JSON value.")
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let value):
            try container.encode(value)
        case .bool(let value):
            try container.encode(value)
        case .int(let value):
            try container.encode(value)
        case .double(let value):
            try container.encode(value)
        case .array(let value):
            try container.encode(value)
        case .object(let value):
            try container.encode(value)
        case .null:
            try container.encodeNil()
        }
    }

    public var stringValue: String? {
        if case .string(let value) = self { return value }
        return nil
    }

    public var objectValue: [String: WalletJSONValue]? {
        if case .object(let value) = self { return value }
        return nil
    }

    public var arrayValue: [WalletJSONValue]? {
        if case .array(let value) = self { return value }
        return nil
    }

    public var jsonObject: Any? {
        switch self {
        case .string(let value):
            return value
        case .bool(let value):
            return value
        case .int(let value):
            return value
        case .double(let value):
            return value
        case .array(let values):
            return values.map(\.jsonObject)
        case .object(let values):
            return values.mapValues { $0.jsonObject }
        case .null:
            return nil
        }
    }
}

public extension WalletJSONValue {
    static func strings(_ values: [String]) -> [WalletJSONValue] {
        values.map(WalletJSONValue.string)
    }
}

public struct WalletRequest: Identifiable, Hashable, Codable, Sendable {
    public let id: WalletSignRequestID
    public let chain: WalletBlockchain
    public let method: WalletRequestMethod
    public let params: [WalletJSONValue]
    public let expiryDate: Date

    public init(
        id: WalletSignRequestID,
        chain: WalletBlockchain,
        method: WalletRequestMethod,
        params: [WalletJSONValue],
        expiryDate: Date = Date().addingTimeInterval(300)
    ) {
        self.id = id
        self.chain = chain
        self.method = method
        self.params = params
        self.expiryDate = expiryDate
    }

    public init(
        id: WalletSignRequestID,
        chain: WalletBlockchain,
        method: WalletRequestMethod,
        params: [String],
        expiryDate: Date = Date().addingTimeInterval(300)
    ) {
        self.init(
            id: id,
            chain: chain,
            method: method,
            params: WalletJSONValue.strings(params),
            expiryDate: expiryDate
        )
    }

    public var stringParams: [String] {
        params.compactMap(\.stringValue)
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

public enum WalletSolanaTransactionEncoding: String, CaseIterable, Hashable, Codable, Sendable {
    case base58
    case base64
}

public struct WalletSolanaTransactionSetPayload: Hashable, Codable, Sendable {
    public let encoding: WalletSolanaTransactionEncoding
    public let transactions: [String]

    public init(encoding: WalletSolanaTransactionEncoding, transactions: [String]) {
        self.encoding = encoding
        self.transactions = transactions
    }

    var jsonValue: WalletJSONValue {
        .object([
            "encoding": .string(encoding.rawValue),
            "transactions": .array(transactions.map(WalletJSONValue.string)),
        ])
    }
}

public enum WalletRequestValidation {
    public static func validate(_ request: WalletRequest) throws {
        switch request.method {
        case .ethPersonalSign, .ethSignTypedData, .ethSignTypedDataV4, .ethSendTransaction, .walletSwitchEthereumChain, .walletAddEthereumChain, .walletWatchAsset:
            guard request.chain.namespace == "eip155" else {
                throw WalletConnectionError.unsupportedChain(request.chain.knownChain ?? .ethereum)
            }
        case .solanaSignMessage, .solanaSignTransaction, .solanaSignAllTransactions, .solanaSignAndSendTransaction:
            guard request.chain.namespace == "solana" else {
                throw WalletConnectionError.unsupportedChain(request.chain.knownChain ?? .solana)
            }
        }

        guard request.params.count == request.method.requiredParameterCount else {
            throw WalletConnectionError.invalidResponse
        }

        switch request.method {
        case .walletSwitchEthereumChain:
            guard let object = request.params.first?.objectValue,
                  let chainId = object["chainId"]?.stringValue,
                  Self.isValidEVMQuantity(chainId) else {
                throw WalletConnectionError.invalidChain(request.params.first?.objectValue?["chainId"]?.stringValue ?? "")
            }
        case .ethSendTransaction:
            try validateTransactionParam(request.params[0])
        case .walletAddEthereumChain:
            try validateAddEthereumChainParam(request.params[0])
        case .walletWatchAsset:
            try validateWatchAssetParam(request.params[0])
        case .solanaSignTransaction, .solanaSignAndSendTransaction:
            guard isValidSolanaSerializedTransactionParam(request.params[0]) else {
                throw WalletConnectionError.invalidResponse
            }
        case .solanaSignAllTransactions:
            try validateSolanaTransactionSetParam(request.params[0])
        case .ethPersonalSign, .ethSignTypedData, .ethSignTypedDataV4, .solanaSignMessage:
            break
        }
    }

    private static func validateTransactionParam(_ value: WalletJSONValue) throws {
        guard let transaction = WalletTransactionRequest(jsonValue: value) else {
            throw WalletConnectionError.invalidResponse
        }
        guard isValidEVMQuantity(transaction.chainId) else {
            throw WalletConnectionError.invalidChain(transaction.chainId)
        }
        guard isValidEVMQuantity(transaction.value) else {
            throw WalletConnectionError.invalidResponse
        }
        for quantity in [transaction.gas, transaction.gasPrice, transaction.maxFeePerGas, transaction.maxPriorityFeePerGas, transaction.gasLimit] {
            if let quantity, !isValidEVMQuantity(quantity) {
                throw WalletConnectionError.invalidResponse
            }
        }
    }

    private static func validateAddEthereumChainParam(_ value: WalletJSONValue) throws {
        guard let request = WalletAddEthereumChainRequest(jsonValue: value),
              isValidEVMQuantity(request.chainId),
              !request.rpcUrls.isEmpty else {
            throw WalletConnectionError.invalidResponse
        }
    }

    private static func validateWatchAssetParam(_ value: WalletJSONValue) throws {
        guard let object = value.objectValue,
              object["type"]?.stringValue?.isEmpty == false,
              let options = object["options"]?.objectValue,
              options["address"]?.stringValue?.isEmpty == false else {
            throw WalletConnectionError.invalidResponse
        }
    }

    private static func validateSolanaTransactionSetParam(_ value: WalletJSONValue) throws {
        guard let payload = WalletSolanaTransactionSetPayload(jsonValue: value),
              !payload.transactions.isEmpty,
              payload.transactions.allSatisfy({ !$0.isEmpty }) else {
            throw WalletConnectionError.invalidResponse
        }
    }

    private static func isValidEVMQuantity(_ value: String) -> Bool {
        guard value.hasPrefix("0x"), value.count > 2 else { return false }
        let digits = value.dropFirst(2)
        guard digits.allSatisfy(\.isHexDigit) else { return false }
        return digits.count == 1 || digits.first != "0"
    }

    private static func isValidSolanaSerializedTransactionParam(_ value: WalletJSONValue) -> Bool {
        guard let object = value.objectValue,
              let transaction = object["transaction"]?.stringValue,
              !transaction.isEmpty,
              let encodingValue = object["encoding"]?.stringValue,
              WalletSolanaTransactionEncoding(rawValue: encodingValue) != nil else {
            return false
        }
        return true
    }
}

public extension WalletRequestMethod {
    var requiredParameterCount: Int {
        switch self {
        case .ethPersonalSign, .ethSignTypedData, .ethSignTypedDataV4, .solanaSignMessage:
            return 2
        case .ethSendTransaction, .walletSwitchEthereumChain, .walletAddEthereumChain, .walletWatchAsset, .solanaSignTransaction, .solanaSignAndSendTransaction:
            return 1
        case .solanaSignAllTransactions:
            return 1
        }
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
            params: [.string(message), .string(address)],
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
            params: [.string(message), .string(address)],
            expiryDate: expiryDate
        )
    }

    public static func signTypedDataV4(
        id: WalletSignRequestID,
        address: String,
        typedDataJSON: String,
        chain: WalletChain = .ethereum,
        expiryDate: Date = Date().addingTimeInterval(300)
    ) -> WalletRequest {
        WalletRequest(
            id: id,
            chain: WalletBlockchain(namespace: chain.namespace, reference: chain.chainReference),
            method: .ethSignTypedDataV4,
            params: [.string(address), .string(typedDataJSON)],
            expiryDate: expiryDate
        )
    }

    public static func sendTransaction(
        id: WalletSignRequestID,
        transaction: WalletTransactionRequest,
        chain: WalletChain = .ethereum,
        expiryDate: Date = Date().addingTimeInterval(300)
    ) -> WalletRequest {
        WalletRequest(
            id: id,
            chain: WalletBlockchain(namespace: chain.namespace, reference: chain.chainReference),
            method: .ethSendTransaction,
            params: [transaction.jsonValue],
            expiryDate: expiryDate
        )
    }

    public static func switchEthereumChain(
        id: WalletSignRequestID,
        chainId: String,
        chain: WalletChain = .ethereum,
        expiryDate: Date = Date().addingTimeInterval(300)
    ) -> WalletRequest {
        WalletRequest(
            id: id,
            chain: WalletBlockchain(namespace: chain.namespace, reference: chain.chainReference),
            method: .walletSwitchEthereumChain,
            params: [.object(["chainId": .string(chainId)])],
            expiryDate: expiryDate
        )
    }

    public static func addEthereumChain(
        id: WalletSignRequestID,
        request: WalletAddEthereumChainRequest,
        chain: WalletChain = .ethereum,
        expiryDate: Date = Date().addingTimeInterval(300)
    ) -> WalletRequest {
        WalletRequest(
            id: id,
            chain: WalletBlockchain(namespace: chain.namespace, reference: chain.chainReference),
            method: .walletAddEthereumChain,
            params: [request.jsonValue],
            expiryDate: expiryDate
        )
    }

    public static func watchAsset(
        id: WalletSignRequestID,
        request: WalletWatchAssetRequest,
        chain: WalletChain = .ethereum,
        expiryDate: Date = Date().addingTimeInterval(300)
    ) -> WalletRequest {
        WalletRequest(
            id: id,
            chain: WalletBlockchain(namespace: chain.namespace, reference: chain.chainReference),
            method: .walletWatchAsset,
            params: [request.jsonValue],
            expiryDate: expiryDate
        )
    }

    public static func solanaSignTransaction(
        id: WalletSignRequestID,
        serializedTransaction: String,
        encoding: WalletSolanaTransactionEncoding = .base64,
        expiryDate: Date = Date().addingTimeInterval(300)
    ) -> WalletRequest {
        solanaTransactionRequest(
            id: id,
            method: .solanaSignTransaction,
            serializedTransaction: serializedTransaction,
            encoding: encoding,
            expiryDate: expiryDate
        )
    }

    public static func solanaSignAndSendTransaction(
        id: WalletSignRequestID,
        serializedTransaction: String,
        encoding: WalletSolanaTransactionEncoding = .base64,
        expiryDate: Date = Date().addingTimeInterval(300)
    ) -> WalletRequest {
        solanaTransactionRequest(
            id: id,
            method: .solanaSignAndSendTransaction,
            serializedTransaction: serializedTransaction,
            encoding: encoding,
            expiryDate: expiryDate
        )
    }

    public static func solanaSignAllTransactions(
        id: WalletSignRequestID,
        serializedTransactions: [String],
        encoding: WalletSolanaTransactionEncoding = .base64,
        expiryDate: Date = Date().addingTimeInterval(300)
    ) throws -> WalletRequest {
        guard !serializedTransactions.isEmpty else {
            throw WalletConnectionError.invalidResponse
        }
        return WalletRequest(
            id: id,
            chain: WalletBlockchain(namespace: WalletChain.solana.namespace, reference: WalletChain.solana.chainReference),
            method: .solanaSignAllTransactions,
            params: [WalletSolanaTransactionSetPayload(encoding: encoding, transactions: serializedTransactions).jsonValue],
            expiryDate: expiryDate
        )
    }

    private static func solanaTransactionRequest(
        id: WalletSignRequestID,
        method: WalletRequestMethod,
        serializedTransaction: String,
        encoding: WalletSolanaTransactionEncoding,
        expiryDate: Date
    ) -> WalletRequest {
        WalletRequest(
            id: id,
            chain: WalletBlockchain(namespace: WalletChain.solana.namespace, reference: WalletChain.solana.chainReference),
            method: method,
            params: [.object(["encoding": .string(encoding.rawValue), "transaction": .string(serializedTransaction)])],
            expiryDate: expiryDate
        )
    }
}

private extension WalletTransactionRequest {
    var jsonValue: WalletJSONValue {
        var value: [String: WalletJSONValue] = [
            "from": .string(from),
            "value": .string(self.value),
            "data": .string(data),
            "chainId": .string(chainId),
        ]
        value["to"] = to.map(WalletJSONValue.string)
        value["nonce"] = nonce.map(WalletJSONValue.int)
        value["gas"] = gas.map(WalletJSONValue.string)
        value["gasPrice"] = gasPrice.map(WalletJSONValue.string)
        value["maxFeePerGas"] = maxFeePerGas.map(WalletJSONValue.string)
        value["maxPriorityFeePerGas"] = maxPriorityFeePerGas.map(WalletJSONValue.string)
        value["gasLimit"] = gasLimit.map(WalletJSONValue.string)
        return .object(value)
    }

    init?(jsonValue: WalletJSONValue) {
        guard let object = jsonValue.objectValue,
              let from = object["from"]?.stringValue,
              let value = object["value"]?.stringValue,
              let data = object["data"]?.stringValue,
              let chainId = object["chainId"]?.stringValue else {
            return nil
        }
        self.init(
            from: from,
            to: object["to"]?.stringValue,
            value: value,
            data: data,
            nonce: object["nonce"]?.intValue,
            gas: object["gas"]?.stringValue,
            gasPrice: object["gasPrice"]?.stringValue,
            maxFeePerGas: object["maxFeePerGas"]?.stringValue,
            maxPriorityFeePerGas: object["maxPriorityFeePerGas"]?.stringValue,
            gasLimit: object["gasLimit"]?.stringValue,
            chainId: chainId
        )
    }
}

private extension WalletAddEthereumChainRequest {
    var jsonValue: WalletJSONValue {
        var value: [String: WalletJSONValue] = [
            "chainId": .string(chainId),
            "rpcUrls": .array(rpcUrls.map(WalletJSONValue.string)),
        ]
        value["blockExplorerUrls"] = blockExplorerUrls.map { .array($0.map(WalletJSONValue.string)) }
        value["chainName"] = chainName.map(WalletJSONValue.string)
        value["iconUrls"] = iconUrls.map { .array($0.map(WalletJSONValue.string)) }
        if let nativeCurrency {
            value["nativeCurrency"] = .object([
                "name": .string(nativeCurrency.name),
                "symbol": .string(nativeCurrency.symbol),
                "decimals": .int(nativeCurrency.decimals),
            ])
        }
        return .object(value)
    }

    init?(jsonValue: WalletJSONValue) {
        guard let object = jsonValue.objectValue,
              let chainId = object["chainId"]?.stringValue,
              let rpcUrls = object["rpcUrls"]?.arrayValue?.compactMap(\.stringValue) else {
            return nil
        }
        let nativeCurrency: NativeCurrency?
        if let nativeObject = object["nativeCurrency"]?.objectValue,
           let name = nativeObject["name"]?.stringValue,
           let symbol = nativeObject["symbol"]?.stringValue,
           let decimals = nativeObject["decimals"]?.intValue {
            nativeCurrency = NativeCurrency(name: name, symbol: symbol, decimals: decimals)
        } else {
            nativeCurrency = nil
        }
        self.init(
            chainId: chainId,
            blockExplorerUrls: object["blockExplorerUrls"]?.arrayValue?.compactMap(\.stringValue),
            chainName: object["chainName"]?.stringValue,
            iconUrls: object["iconUrls"]?.arrayValue?.compactMap(\.stringValue),
            nativeCurrency: nativeCurrency,
            rpcUrls: rpcUrls
        )
    }
}

private extension WalletWatchAssetRequest {
    var jsonValue: WalletJSONValue {
        var options: [String: WalletJSONValue] = ["address": .string(address)]
        options["symbol"] = symbol.map(WalletJSONValue.string)
        options["decimals"] = decimals.map(WalletJSONValue.int)
        options["image"] = image.map(WalletJSONValue.string)
        return .object([
            "type": .string(type),
            "options": .object(options),
        ])
    }
}

private extension WalletSolanaTransactionSetPayload {
    init?(jsonValue: WalletJSONValue) {
        guard let object = jsonValue.objectValue,
              let encodingValue = object["encoding"]?.stringValue,
              let encoding = WalletSolanaTransactionEncoding(rawValue: encodingValue),
              let transactions = object["transactions"]?.arrayValue?.compactMap(\.stringValue) else {
            return nil
        }
        self.init(encoding: encoding, transactions: transactions)
    }
}

private extension WalletJSONValue {
    var intValue: Int? {
        if case .int(let value) = self { return value }
        return nil
    }
}
