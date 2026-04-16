import Foundation

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
        let id: String
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

        let nameEntries = scopedNFTs.compactMap { nft -> NameEntry? in
            guard let name = Self.cleanedText(nft.name) else {
                return nil
            }

            return NameEntry(
                nftID: nft.id,
                normalizedName: name.lowercased(),
                displayName: name,
                collectionDisplayName: Self.cleanedText(nft.collectionName ?? nft.collection?.name)
            )
        }

        var seenCollectionIDs = Set<String>()
        let collectionEntries = scopedNFTs.compactMap { nft -> CollectionEntry? in
            guard let name = Self.cleanedText(nft.collectionName ?? nft.collection?.name) else {
                return nil
            }

            let normalizedContractAddress = NFT.normalizedScopeComponent(nft.contract.address)
            let entryID = [
                currentChain.rawValue,
                normalizedContractAddress ?? "name:\(name.lowercased())",
                name.lowercased()
            ].joined(separator: ":")

            guard seenCollectionIDs.insert(entryID).inserted else {
                return nil
            }

            return CollectionEntry(
                id: entryID,
                normalizedName: name.lowercased(),
                displayName: name,
                chain: currentChain,
                contractAddress: normalizedContractAddress
            )
        }

        return SearchLocalIndex(
            accounts: uniqueAccounts.values.sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending },
            ensEntries: ensEntries.values.sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending },
            contracts: contractEntries.values.sorted { $0.label.localizedCaseInsensitiveCompare($1.label) == .orderedAscending },
            tokenSymbols: symbolEntries.values.sorted { $0.symbol < $1.symbol },
            nftNames: nameEntries.sorted { lhs, rhs in
                lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName) == .orderedAscending
            },
            collections: collectionEntries.sorted { lhs, rhs in
                lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName) == .orderedAscending
            }
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
