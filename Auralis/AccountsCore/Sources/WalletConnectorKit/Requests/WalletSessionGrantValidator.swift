import Foundation

public enum WalletSessionGrantValidator {
    public static func validate(_ request: WalletRequest, in session: WalletConnectorSession) throws {
        try validate(request, accounts: session.accounts, namespaces: session.namespaces)
    }

    public static func validate(_ request: WalletRequest, in session: WalletSession) throws {
        try validate(request, accounts: session.accounts, namespaces: session.namespaces)
    }

    private static func validate(_ request: WalletRequest, accounts: [WalletAccount], namespaces: [WalletSessionNamespace]) throws {
        let matchingNamespaces = namespaces.filter { namespace in
            namespace.name == request.chain.namespace
                && namespace.accounts.contains { account in
                    account.parsed.map { chainMatches($0.blockchain, request.chain) } == true
                }
        }
        guard !matchingNamespaces.isEmpty else {
            throw unsupportedChainError(for: request.chain)
        }
        guard matchingNamespaces.contains(where: { $0.methods.contains(request.method.rawValue) }) else {
            throw WalletConnectionError.unsupportedMethod(request.method.rawValue)
        }
        if request.method == .walletSwitchEthereumChain {
            try validateSwitchEthereumChainTarget(request, accounts: accounts)
        }
        if let signerAddress = signerAddress(in: request) {
            guard accounts.contains(where: { account in
                guard let parsed = account.parsed, chainMatches(parsed.blockchain, request.chain) else { return false }
                return addressesMatch(parsed.address, signerAddress, namespace: request.chain.namespace)
            }) else {
                throw WalletConnectionError.invalidAccount(signerAddress)
            }
        }
    }

    private static func validateSwitchEthereumChainTarget(_ request: WalletRequest, accounts: [WalletAccount]) throws {
        guard let chainId = request.params.first?.objectValue?["chainId"]?.stringValue,
              let reference = evmChainReference(fromQuantity: chainId) else {
            throw WalletConnectionError.invalidChain(request.params.first?.objectValue?["chainId"]?.stringValue ?? "")
        }
        let target = WalletBlockchain(namespace: "eip155", reference: reference)
        guard accounts.contains(where: { account in
            account.parsed.map { chainMatches($0.blockchain, target) } == true
        }) else {
            throw unsupportedChainError(for: target)
        }
    }

    private static func signerAddress(in request: WalletRequest) -> String? {
        switch request.method {
        case .ethPersonalSign, .solanaSignMessage:
            return request.params.dropFirst().first?.stringValue
        case .ethSignTypedData, .ethSignTypedDataV4:
            // The signer position differs by variant: legacy `eth_signTypedData`
            // (v1) is `[typedData, address]` while `eth_signTypedData_v4` is
            // `[address, typedData]`. Hard-coding index 0 silently mis-reads the
            // typed-data blob as the signer for a v1 request and fails closed.
            // Pick whichever param is an EVM-address-shaped string instead — the
            // typed-data payload (a JSON object or JSON string) never matches.
            return request.params.lazy.compactMap(\.stringValue).first(where: isEVMAddress)
        case .ethSendTransaction:
            return request.params.first?.objectValue?["from"]?.stringValue
        case .walletSwitchEthereumChain, .walletAddEthereumChain, .walletWatchAsset, .solanaSignTransaction, .solanaSignAllTransactions, .solanaSignAndSendTransaction:
            return nil
        }
    }

    /// Whether `value` is an EVM-address-shaped string (`0x` + 40 hex digits).
    /// Used to locate the signer among typed-data params regardless of the
    /// variant's parameter ordering (v1 vs v4).
    private static func isEVMAddress(_ value: String) -> Bool {
        guard value.hasPrefix("0x") || value.hasPrefix("0X") else { return false }
        let digits = value.dropFirst(2)
        return digits.count == 40 && digits.allSatisfy(\.isHexDigit)
    }

    private static func evmChainReference(fromQuantity value: String) -> String? {
        let hex = value.lowercased()
        guard hex.hasPrefix("0x"), hex.count > 2 else { return nil }
        let digits = String(hex.dropFirst(2))
        guard digits.allSatisfy({ $0.isHexDigit }),
              let intValue = UInt64(digits, radix: 16) else {
            return nil
        }
        return String(intValue)
    }

    private static func chainMatches(_ granted: WalletBlockchain, _ requested: WalletBlockchain) -> Bool {
        if granted.caip2 == requested.caip2 { return true }
        guard let grantedKnown = granted.knownChain, let requestedKnown = requested.knownChain else { return false }
        return grantedKnown == requestedKnown
    }

    private static func addressesMatch(_ granted: String, _ requested: String, namespace: String) -> Bool {
        if namespace == "eip155" {
            return granted.caseInsensitiveCompare(requested) == .orderedSame
        }
        return granted == requested
    }

    private static func unsupportedChainError(for blockchain: WalletBlockchain) -> WalletConnectionError {
        guard let known = blockchain.knownChain else { return .invalidChain(blockchain.caip2) }
        return .unsupportedChain(known)
    }
}
