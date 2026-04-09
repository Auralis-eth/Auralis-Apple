import Foundation

enum SearchQueryKind: String, Equatable, Sendable {
    case empty
    case walletAddress
    case contractAddress
    case ambiguousAddress
    case invalidAddress
    case ensName
    case invalidENSLike
    case tokenSymbol
    case nftName
    case collectionName
    case text

    var title: String {
        switch self {
        case .empty:
            return "Start Typing"
        case .walletAddress:
            return "Wallet Address"
        case .contractAddress:
            return "Contract Address"
        case .ambiguousAddress:
            return "Address"
        case .invalidAddress:
            return "Invalid Address"
        case .ensName:
            return "ENS Name"
        case .invalidENSLike:
            return "Invalid ENS-Like Input"
        case .tokenSymbol:
            return "Token Symbol"
        case .nftName:
            return "NFT Name"
        case .collectionName:
            return "Collection"
        case .text:
            return "Text Query"
        }
    }

    var feedbackMessage: String {
        switch self {
        case .empty:
            return "Enter an ENS name, wallet address, contract address, token symbol, NFT name, or collection."
        case .walletAddress:
            return "Valid wallet address detected from local account data."
        case .contractAddress:
            return "Valid contract address detected from the active chain's local NFT data."
        case .ambiguousAddress:
            return "Valid address format detected, but local data cannot yet prove whether it is a wallet or contract."
        case .invalidAddress:
            return "This looks like an address, but it is not a valid Ethereum address."
        case .ensName:
            return "Valid ENS-style input detected. Resolution stays local-only in this slice."
        case .invalidENSLike:
            return "This looks domain-like, but it is not a valid `.eth` name."
        case .tokenSymbol:
            return "Short symbol-style input matched local token metadata."
        case .nftName:
            return "This query matches NFT item names in the active scope."
        case .collectionName:
            return "This query matches collection names in the active scope."
        case .text:
            return "Treating this as a general local text query."
        }
    }

    var isInvalidInput: Bool {
        switch self {
        case .invalidAddress, .invalidENSLike:
            return true
        default:
            return false
        }
    }
}

struct SearchQueryClassification: Equatable, Sendable {
    let rawQuery: String
    let normalizedQuery: String
    let kind: SearchQueryKind
    let localMatches: [SearchLocalMatch]

    var trimmedQuery: String {
        rawQuery.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

enum SearchDestination: Equatable, Sendable {
    case profile(address: String)
    case token(contractAddress: String, chain: Chain, symbol: String)
    case nftItem(id: String)
    case nftCollection(contractAddress: String?, title: String, chain: Chain)
}

struct SearchLocalMatch: Identifiable, Equatable, Sendable {
    enum Kind: String, Equatable, Sendable {
        case account
        case ens
        case contract
        case tokenSymbol
        case nftName
        case collectionName

        var title: String {
            switch self {
            case .account:
                return "Account"
            case .ens:
                return "ENS"
            case .contract:
                return "Contract"
            case .tokenSymbol:
                return "Symbol"
            case .nftName:
                return "NFT"
            case .collectionName:
                return "Collection"
            }
        }
    }

    let kind: Kind
    let title: String
    let subtitle: String
    let destination: SearchDestination

    var id: String {
        switch destination {
        case .profile(let address):
            return "\(kind.rawValue):profile:\(address)"
        case .token(let contractAddress, let chain, _):
            return "\(kind.rawValue):token:\(chain.rawValue):\(contractAddress)"
        case .nftItem(let id):
            return "\(kind.rawValue):nft:\(id)"
        case .nftCollection(let contractAddress, let title, let chain):
            return "\(kind.rawValue):collection:\(chain.rawValue):\(contractAddress ?? title)"
        }
    }
}

struct SearchLocalIndex: Equatable, Sendable {
    struct AccountEntry: Equatable, Sendable {
        let address: String
        let displayName: String
    }

    struct ENSEntry: Equatable, Sendable {
        let ensName: String
        let displayName: String
        let address: String
    }

    struct ContractEntry: Equatable, Sendable {
        let address: String
        let label: String
        let chain: Chain
    }

    struct SymbolEntry: Equatable, Sendable {
        let symbol: String
        let label: String
        let contractAddress: String
        let chain: Chain
    }

    struct NameEntry: Equatable, Sendable {
        let nftID: String
        let normalizedName: String
        let displayName: String
        let collectionDisplayName: String?
    }

    struct CollectionEntry: Equatable, Sendable {
        let normalizedName: String
        let displayName: String
        let chain: Chain
        let contractAddress: String?
    }

    let accounts: [AccountEntry]
    let ensEntries: [ENSEntry]
    let contracts: [ContractEntry]
    let tokenSymbols: [SymbolEntry]
    let nftNames: [NameEntry]
    let collections: [CollectionEntry]

    static let empty = SearchLocalIndex(
        accounts: [],
        ensEntries: [],
        contracts: [],
        tokenSymbols: [],
        nftNames: [],
        collections: []
    )

    static func make(
        nfts: [NFT],
        holdings: [TokenHolding],
        accounts: [EOAccount],
        currentAccountAddress: String?,
        currentChain: Chain
    ) -> SearchLocalIndex {
        let normalizedAccountAddress = NFT.normalizedScopeComponent(currentAccountAddress) ?? ""
        let scopedNFTs = nfts.filter {
            $0.matchesScope(accountAddress: currentAccountAddress, chain: currentChain)
        }
        let scopedHoldings = holdings.filter {
            $0.accountAddressRawValue == normalizedAccountAddress &&
            $0.chainRawValue == currentChain.rawValue &&
            $0.balanceKind == .erc20 &&
            ($0.contractAddress?.isEmpty == false)
        }

        let uniqueAccounts = Dictionary(
            accounts.map {
                (
                    NFT.normalizedScopeComponent($0.address) ?? $0.address.lowercased(),
                    AccountEntry(
                        address: NFT.normalizedScopeComponent($0.address) ?? $0.address.lowercased(),
                        displayName: $0.name ?? $0.address.displayAddress
                    )
                )
            },
            uniquingKeysWith: { first, _ in first }
        )

        let ensEntries = Dictionary(
            accounts.compactMap { account -> (String, ENSEntry)? in
                guard let name = account.name?.trimmingCharacters(in: .whitespacesAndNewlines),
                      SearchQueryParser.looksLikeENSName(name) else {
                    return nil
                }

                let normalizedAddress = NFT.normalizedScopeComponent(account.address) ?? account.address.lowercased()
                return (
                    name.lowercased(),
                    ENSEntry(
                        ensName: name.lowercased(),
                        displayName: name,
                        address: normalizedAddress
                    )
                )
            },
            uniquingKeysWith: { first, _ in first }
        )

        let contractEntries = Dictionary(
            scopedNFTs.compactMap { nft -> (String, ContractEntry)? in
                guard let address = nft.contract.address.flatMap(NFT.normalizedScopeComponent) else {
                    return nil
                }

                let label = nft.collectionName ?? nft.collection?.name ?? nft.name ?? address.displayAddress
                return (address, ContractEntry(address: address, label: label, chain: currentChain))
            },
            uniquingKeysWith: { first, _ in first }
        )

        let symbolEntries = Dictionary(
            scopedHoldings.compactMap { holding -> (String, SymbolEntry)? in
                guard let symbol = Self.cleanedText(holding.symbol)?.uppercased(),
                      let contractAddress = holding.contractAddress else {
                    return nil
                }

                return (
                    symbol,
                    SymbolEntry(
                        symbol: symbol,
                        label: holding.displayName,
                        contractAddress: contractAddress,
                        chain: holding.chain
                    )
                )
            },
            uniquingKeysWith: { first, _ in first }
        )

        let nameEntries = Dictionary(
            scopedNFTs.compactMap { nft -> (String, NameEntry)? in
                guard let name = Self.cleanedText(nft.name) else {
                    return nil
                }

                return (
                    name.lowercased(),
                    NameEntry(
                        nftID: nft.id,
                        normalizedName: name.lowercased(),
                        displayName: name,
                        collectionDisplayName: Self.cleanedText(nft.collectionName ?? nft.collection?.name)
                    )
                )
            },
            uniquingKeysWith: { first, _ in first }
        )

        let collectionEntries = Dictionary(
            scopedNFTs.compactMap { nft -> (String, CollectionEntry)? in
                guard let name = Self.cleanedText(nft.collectionName ?? nft.collection?.name) else {
                    return nil
                }

                return (
                    name.lowercased(),
                    CollectionEntry(
                        normalizedName: name.lowercased(),
                        displayName: name,
                        chain: currentChain,
                        contractAddress: NFT.normalizedScopeComponent(nft.contract.address)
                    )
                )
            },
            uniquingKeysWith: { first, _ in first }
        )

        return SearchLocalIndex(
            accounts: uniqueAccounts.values.sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending },
            ensEntries: ensEntries.values.sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending },
            contracts: contractEntries.values.sorted { $0.label.localizedCaseInsensitiveCompare($1.label) == .orderedAscending },
            tokenSymbols: symbolEntries.values.sorted { $0.symbol < $1.symbol },
            nftNames: nameEntries.values.sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending },
            collections: collectionEntries.values.sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
        )
    }

    func accountMatches(address: String) -> [SearchLocalMatch] {
        accounts
            .filter { $0.address == address }
            .map {
                SearchLocalMatch(
                    kind: .account,
                    title: $0.displayName,
                    subtitle: $0.address.displayAddress,
                    destination: .profile(address: $0.address)
                )
            }
    }

    func ensMatches(name: String) -> [SearchLocalMatch] {
        ensEntries
            .filter { $0.ensName == name }
            .map {
                SearchLocalMatch(
                    kind: .ens,
                    title: $0.displayName,
                    subtitle: $0.address.displayAddress,
                    destination: .profile(address: $0.address)
                )
            }
    }

    func contractMatches(address: String) -> [SearchLocalMatch] {
        contracts
            .filter { $0.address == address }
            .map {
                SearchLocalMatch(
                    kind: .contract,
                    title: $0.label,
                    subtitle: "\($0.chain.routingDisplayName) • \($0.address.displayAddress)",
                    destination: .nftCollection(
                        contractAddress: $0.address,
                        title: $0.label,
                        chain: $0.chain
                    )
                )
            }
    }

    func tokenSymbolMatches(symbol: String) -> [SearchLocalMatch] {
        tokenSymbols
            .filter { $0.symbol == symbol }
            .map {
                SearchLocalMatch(
                    kind: .tokenSymbol,
                    title: $0.symbol,
                    subtitle: $0.label,
                    destination: .token(
                        contractAddress: $0.contractAddress,
                        chain: $0.chain,
                        symbol: $0.symbol
                    )
                )
            }
    }

    func exactNFTNameMatches(query: String) -> [SearchLocalMatch] {
        nftNames
            .filter { $0.normalizedName == query }
            .map {
                SearchLocalMatch(
                    kind: .nftName,
                    title: $0.displayName,
                    subtitle: $0.collectionDisplayName ?? "Active scope item",
                    destination: .nftItem(id: $0.nftID)
                )
            }
    }

    func partialNFTNameMatches(query: String) -> [SearchLocalMatch] {
        nftNames
            .filter { $0.normalizedName.contains(query) }
            .prefix(6)
            .map {
                SearchLocalMatch(
                    kind: .nftName,
                    title: $0.displayName,
                    subtitle: $0.collectionDisplayName ?? "Active scope item",
                    destination: .nftItem(id: $0.nftID)
                )
            }
    }

    func exactCollectionMatches(query: String) -> [SearchLocalMatch] {
        collections
            .filter { $0.normalizedName == query }
            .map {
                SearchLocalMatch(
                    kind: .collectionName,
                    title: $0.displayName,
                    subtitle: $0.chain.routingDisplayName,
                    destination: .nftCollection(
                        contractAddress: $0.contractAddress,
                        title: $0.displayName,
                        chain: $0.chain
                    )
                )
            }
    }

    func partialCollectionMatches(query: String) -> [SearchLocalMatch] {
        collections
            .filter { $0.normalizedName.contains(query) }
            .prefix(6)
            .map {
                SearchLocalMatch(
                    kind: .collectionName,
                    title: $0.displayName,
                    subtitle: $0.chain.routingDisplayName,
                    destination: .nftCollection(
                        contractAddress: $0.contractAddress,
                        title: $0.displayName,
                        chain: $0.chain
                    )
                )
            }
    }

    private static func cleanedText(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }
}

struct SearchQueryParser {
    func classify(query: String, index: SearchLocalIndex) -> SearchQueryClassification {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalized = trimmed.lowercased()

        guard !trimmed.isEmpty else {
            return SearchQueryClassification(
                rawQuery: query,
                normalizedQuery: "",
                kind: .empty,
                localMatches: []
            )
        }

        if let normalizedAddress = trimmed.extractedEthereumAddress?.lowercased() {
            let accountMatches = index.accountMatches(address: normalizedAddress)
            let contractMatches = index.contractMatches(address: normalizedAddress)
            let combinedMatches = (accountMatches + contractMatches).prefix(6)

            let kind: SearchQueryKind
            if !accountMatches.isEmpty, contractMatches.isEmpty {
                kind = .walletAddress
            } else if accountMatches.isEmpty, !contractMatches.isEmpty {
                kind = .contractAddress
            } else {
                kind = .ambiguousAddress
            }

            return SearchQueryClassification(
                rawQuery: query,
                normalizedQuery: normalizedAddress,
                kind: kind,
                localMatches: Array(combinedMatches)
            )
        }

        if Self.looksLikeAddressCandidate(trimmed) {
            return SearchQueryClassification(
                rawQuery: query,
                normalizedQuery: normalized,
                kind: .invalidAddress,
                localMatches: []
            )
        }

        if Self.looksLikeENSName(trimmed) {
            return SearchQueryClassification(
                rawQuery: query,
                normalizedQuery: normalized,
                kind: .ensName,
                localMatches: index.ensMatches(name: normalized)
            )
        }

        if Self.looksLikeInvalidENSCandidate(trimmed) {
            return SearchQueryClassification(
                rawQuery: query,
                normalizedQuery: normalized,
                kind: .invalidENSLike,
                localMatches: []
            )
        }

        if let symbolCandidate = Self.normalizedSymbolCandidate(trimmed) {
            let symbolMatches = index.tokenSymbolMatches(symbol: symbolCandidate)
            if !symbolMatches.isEmpty {
                return SearchQueryClassification(
                    rawQuery: query,
                    normalizedQuery: normalized,
                    kind: .tokenSymbol,
                    localMatches: symbolMatches
                )
            }
        }

        let exactNameMatches = index.exactNFTNameMatches(query: normalized)
        if !exactNameMatches.isEmpty {
            return SearchQueryClassification(
                rawQuery: query,
                normalizedQuery: normalized,
                kind: .nftName,
                localMatches: exactNameMatches
            )
        }

        let exactCollectionMatches = index.exactCollectionMatches(query: normalized)
        if !exactCollectionMatches.isEmpty {
            return SearchQueryClassification(
                rawQuery: query,
                normalizedQuery: normalized,
                kind: .collectionName,
                localMatches: exactCollectionMatches
            )
        }

        let partialCollectionMatches = index.partialCollectionMatches(query: normalized)
        if !partialCollectionMatches.isEmpty {
            return SearchQueryClassification(
                rawQuery: query,
                normalizedQuery: normalized,
                kind: .collectionName,
                localMatches: partialCollectionMatches
            )
        }

        let partialNameMatches = index.partialNFTNameMatches(query: normalized)
        if !partialNameMatches.isEmpty {
            return SearchQueryClassification(
                rawQuery: query,
                normalizedQuery: normalized,
                kind: .nftName,
                localMatches: partialNameMatches
            )
        }

        return SearchQueryClassification(
            rawQuery: query,
            normalizedQuery: normalized,
            kind: .text,
            localMatches: []
        )
    }

    private static func looksLikeAddressCandidate(_ query: String) -> Bool {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.hasPrefix("0x")
    }

    private static func looksLikeInvalidENSCandidate(_ query: String) -> Bool {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !trimmed.contains(" "), trimmed.contains(".") else {
            return false
        }

        return !looksLikeENSName(trimmed)
    }

    private static func normalizedSymbolCandidate(_ query: String) -> String? {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.contains(" "),
              trimmed.range(of: #"^[A-Za-z0-9]{2,8}$"#, options: .regularExpression) != nil else {
            return nil
        }

        return trimmed.uppercased()
    }

    fileprivate static func looksLikeENSName(_ candidate: String) -> Bool {
        candidate.trimmingCharacters(in: .whitespacesAndNewlines).range(
            of: #"^[A-Za-z0-9-]+(\.[A-Za-z0-9-]+)*\.eth$"#,
            options: .regularExpression
        ) != nil
    }
}
