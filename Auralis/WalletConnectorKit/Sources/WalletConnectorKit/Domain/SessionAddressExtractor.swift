import Foundation

public struct WalletSessionAddress: Hashable, Codable, Sendable {
    public let account: ParsedWalletAccount
    public let chain: WalletChain
    public let sessionID: WalletSessionID
    public let topic: WalletPairingTopic
    public let providerID: String
    public let providerName: String

    public init(
        account: ParsedWalletAccount,
        chain: WalletChain,
        sessionID: WalletSessionID,
        topic: WalletPairingTopic,
        providerID: String,
        providerName: String
    ) {
        self.account = account
        self.chain = chain
        self.sessionID = sessionID
        self.topic = topic
        self.providerID = providerID
        self.providerName = providerName
    }
}

public enum WalletSessionAddressExtractor {
    public static func extract(from session: WalletConnectorSession) -> [WalletSessionAddress] {
        var seen: Set<String> = []
        var extracted: [WalletSessionAddress] = []

        for walletAccount in session.accounts {
            guard
                let parsed = walletAccount.parsed,
                let chain = parsed.blockchain.knownChain
            else {
                continue
            }

            let addressKey = chain.namespace == "eip155" ? parsed.address.lowercased() : parsed.address
            let key = "\(parsed.blockchain.caip2):\(addressKey)"
            guard seen.insert(key).inserted else {
                continue
            }

            extracted.append(
                WalletSessionAddress(
                    account: parsed,
                    chain: chain,
                    sessionID: session.id,
                    topic: session.topic,
                    providerID: session.providerID,
                    providerName: session.providerName
                )
            )
        }

        return extracted
    }
}
