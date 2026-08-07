import Foundation

public enum WalletSessionGrantValidator {
    public static func validate(_ request: WalletRequest, in session: WalletConnectorSession) throws {
        let matchingNamespaces = session.namespaces.filter { namespace in
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
        if let signerAddress = signerAddress(in: request) {
            guard session.accounts.contains(where: { account in
                guard let parsed = account.parsed, chainMatches(parsed.blockchain, request.chain) else { return false }
                return addressesMatch(parsed.address, signerAddress, namespace: request.chain.namespace)
            }) else {
                throw WalletConnectionError.invalidAccount(signerAddress)
            }
        }
    }

    private static func signerAddress(in request: WalletRequest) -> String? {
        switch request.method {
        case .ethPersonalSign, .solanaSignMessage:
            return request.params.dropFirst().first?.stringValue
        case .ethSignTypedData, .ethSignTypedDataV4:
            return request.params.first?.stringValue
        case .ethSendTransaction:
            return request.params.first?.objectValue?["from"]?.stringValue
        case .walletSwitchEthereumChain, .walletAddEthereumChain, .walletWatchAsset, .solanaSignTransaction, .solanaSignAllTransactions, .solanaSignAndSendTransaction:
            return nil
        }
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
