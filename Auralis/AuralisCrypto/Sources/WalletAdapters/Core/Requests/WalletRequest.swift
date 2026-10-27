import Foundation

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
    private static let minimumRequestExpiryInterval: TimeInterval = 300
    private static let maximumRequestExpiryInterval: TimeInterval = 604_800
    private static let expiryClockTolerance: TimeInterval = 1

    public static func validate(_ request: WalletRequest) throws {
        try validateExpiry(request)

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

    private static func validateExpiry(_ request: WalletRequest) throws {
        let interval = request.expiryDate.timeIntervalSinceNow
        guard interval >= minimumRequestExpiryInterval - expiryClockTolerance,
              interval <= maximumRequestExpiryInterval else {
            throw WalletConnectionError.requestTimedOut(request.id)
        }
    }

    private static func validateTransactionParam(_ value: WalletJSONValue) throws {
        guard let transaction = WalletTransactionRequest(jsonValue: value) else {
            throw WalletConnectionError.invalidResponse
        }
        guard isValidEVMQuantity(transaction.chainId) else {
            throw WalletConnectionError.invalidChain(transaction.chainId)
        }
        guard isValidEVMAddress(transaction.from) else {
            throw WalletConnectionError.invalidAccount(transaction.from)
        }
        if let to = transaction.to, !isValidEVMAddress(to) {
            throw WalletConnectionError.invalidAccount(to)
        }
        guard isValidEVMQuantity(transaction.value), isValidHexData(transaction.data) else {
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
              let address = options["address"]?.stringValue,
              !address.isEmpty else {
            throw WalletConnectionError.invalidResponse
        }
        guard isValidEVMAddress(address) else {
            throw WalletConnectionError.invalidAccount(address)
        }
    }

    private static func validateSolanaTransactionSetParam(_ value: WalletJSONValue) throws {
        guard let payload = WalletSolanaTransactionSetPayload(jsonValue: value),
              payload.encoding == .base64,
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

    /// A 20-byte EVM address: `0x` followed by exactly 40 hex characters.
    private static func isValidEVMAddress(_ value: String) -> Bool {
        guard value.hasPrefix("0x") else { return false }
        let digits = value.dropFirst(2)
        return digits.count == 40 && digits.allSatisfy(\.isHexDigit)
    }

    /// `0x`-prefixed even-length hex (calldata). `0x` alone is valid (empty data).
    private static func isValidHexData(_ value: String) -> Bool {
        guard value.hasPrefix("0x") else { return false }
        let digits = value.dropFirst(2)
        return digits.count.isMultiple(of: 2) && digits.allSatisfy(\.isHexDigit)
    }

    private static func isValidSolanaSerializedTransactionParam(_ value: WalletJSONValue) -> Bool {
        guard let object = value.objectValue,
              let transaction = object["transaction"]?.stringValue,
              !transaction.isEmpty,
              let encodingValue = object["encoding"]?.stringValue,
              WalletSolanaTransactionEncoding(rawValue: encodingValue) == .base64 else {
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
    /// Builds an EIP-191 `personal_sign` request.
    ///
    /// - Important: `message` is placed on the wire **verbatim**. Per EIP-191 the
    ///   `personal_sign` data parameter is expected to be a `0x`-prefixed hex
    ///   string; pass already-hex data here. To sign human-readable text and let
    ///   the wallet display it, use ``personalSignText(id:address:text:chain:expiryDate:)``,
    ///   which hex-encodes the UTF-8 bytes for you.
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

    /// Builds an EIP-191 `personal_sign` request for human-readable `text`,
    /// hex-encoding its UTF-8 bytes to the canonical `0x…` form wallets expect.
    public static func personalSignText(
        id: WalletSignRequestID,
        address: String,
        text: String,
        chain: WalletChain = .ethereum,
        expiryDate: Date = Date().addingTimeInterval(300)
    ) -> WalletRequest {
        let hexMessage = "0x" + Data(text.utf8).map { String(format: "%02x", $0) }.joined()
        return personalSign(id: id, address: address, message: hexMessage, chain: chain, expiryDate: expiryDate)
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
              let chainId = object["chainId"]?.stringValue else {
            return nil
        }
        // Per EIP-1193, `eth_sendTransaction` only requires `from`; `value` and
        // `data` are optional (a plain transfer omits `data`, a contract call
        // may omit `value`). Default them so sparse transactions round-trip
        // instead of being rejected as invalid.
        let value = object["value"]?.stringValue ?? "0x0"
        let data = object["data"]?.stringValue ?? "0x"
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
