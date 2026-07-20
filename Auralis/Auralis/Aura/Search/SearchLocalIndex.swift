import AuralisPrimaryModels
import AuralisPrimaryPersistence
import Foundation
import TokenStorage

struct SearchLocalIndex: Equatable, Sendable {
    struct AccountSnapshot: Sendable {
        let address: String
        let name: String?
    }

    struct NFTSnapshot: Sendable {
        let id: String
        let name: String?
        let collectionName: String?
        let collectionDisplayName: String?
        let contractAddress: String?
        let accountAddressRawValue: String?
        let networkRawValue: String?
    }

    struct HoldingSnapshot: Sendable {
        let accountAddressRawValue: String
        let chainRawValue: String
        let balanceKind: TokenHoldingKind
        let contractAddress: String?
        let symbol: String?
        let displayName: String
    }

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

    var suggestionCandidates: [SearchSuggestion] {
        let accountSuggestions = accounts.map {
            SearchSuggestion(
                completion: $0.displayName,
                detail: $0.address.displayAddress,
                kind: .account
            )
        }

        let ensSuggestions = ensEntries.map {
            SearchSuggestion(
                completion: $0.displayName,
                detail: $0.address.displayAddress,
                kind: .ens
            )
        }

        let tokenSuggestions = tokenSymbols.map {
            SearchSuggestion(
                completion: $0.symbol,
                detail: $0.label,
                kind: .tokenSymbol
            )
        }

        let nftSuggestions = nftNames.map {
            SearchSuggestion(
                completion: $0.displayName,
                detail: $0.collectionDisplayName ?? "Active scope item",
                kind: .nftName
            )
        }

        let collectionSuggestions = collections.map {
            SearchSuggestion(
                completion: $0.displayName,
                detail: $0.chain.routingDisplayName,
                kind: .collectionName
            )
        }

        return accountSuggestions +
            ensSuggestions +
            tokenSuggestions +
            nftSuggestions +
            collectionSuggestions
    }

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
        make(
            nftSnapshots: nfts.map {
                NFTSnapshot(
                    id: $0.id,
                    name: $0.name,
                    collectionName: $0.collectionName,
                    collectionDisplayName: $0.collection?.name,
                    contractAddress: $0.contract.address,
                    accountAddressRawValue: $0.accountAddressRawValue,
                    networkRawValue: $0.networkRawValue
                )
            },
            holdingSnapshots: holdings.map {
                HoldingSnapshot(
                    accountAddressRawValue: $0.accountAddressRawValue,
                    chainRawValue: $0.chainRawValue,
                    balanceKind: $0.balanceKind,
                    contractAddress: $0.contractAddress,
                    symbol: $0.symbol,
                    displayName: $0.displayName
                )
            },
            accountSnapshots: accounts.map {
                AccountSnapshot(
                    address: $0.address,
                    name: $0.name
                )
            },
            currentAccountAddress: currentAccountAddress,
            currentChain: currentChain
        )
    }

    static func make(
        nftSnapshots: [NFTSnapshot],
        holdingSnapshots: [HoldingSnapshot],
        accountSnapshots: [AccountSnapshot],
        currentAccountAddress: String?,
        currentChain: Chain
    ) -> SearchLocalIndex {
        let normalizedAccountAddress = NFT.normalizedScopeComponent(currentAccountAddress) ?? ""
        let scopedNFTs = nftSnapshots.filter {
            $0.accountAddressRawValue == normalizedAccountAddress &&
            $0.networkRawValue == currentChain.rawValue
        }
        let scopedHoldings = holdingSnapshots.filter {
            $0.accountAddressRawValue == normalizedAccountAddress &&
            $0.chainRawValue == currentChain.rawValue &&
            $0.balanceKind == .erc20 &&
            ($0.contractAddress?.isEmpty == false)
        }

        let uniqueAccounts = Dictionary(
            accountSnapshots.map {
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
            accountSnapshots.compactMap { account -> (String, ENSEntry)? in
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
                guard let address = nft.contractAddress.flatMap(NFT.normalizedScopeComponent) else {
                    return nil
                }

                let label = nft.collectionName ?? nft.collectionDisplayName ?? nft.name ?? address.displayAddress
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
                        chain: Chain(rawValue: holding.chainRawValue) ?? currentChain
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
                collectionDisplayName: Self.cleanedText(nft.collectionName ?? nft.collectionDisplayName)
            )
        }

        var seenCollectionIDs = Set<String>()
        let collectionEntries = scopedNFTs.compactMap { nft -> CollectionEntry? in
            guard let name = Self.cleanedText(nft.collectionName ?? nft.collectionDisplayName) else {
                return nil
            }

            let normalizedContractAddress = NFT.normalizedScopeComponent(nft.contractAddress)
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
        let matchesByAddress = Dictionary(grouping: accounts, by: \.address)
        return (matchesByAddress[address] ?? []).map(accountMatch)
    }

    func ensMatches(name: String) -> [SearchLocalMatch] {
        let matchesByName = Dictionary(grouping: ensEntries, by: \.ensName)
        return (matchesByName[name] ?? []).map(ensMatch)
    }

    func contractMatches(address: String) -> [SearchLocalMatch] {
        let matchesByAddress = Dictionary(grouping: contracts, by: \.address)
        return (matchesByAddress[address] ?? []).map(contractMatch)
    }

    func tokenSymbolMatches(symbol: String) -> [SearchLocalMatch] {
        let matchesBySymbol = Dictionary(grouping: tokenSymbols, by: \.symbol)
        return (matchesBySymbol[symbol] ?? []).map(tokenSymbolMatch)
    }

    func exactNFTNameMatches(query: String) -> [SearchLocalMatch] {
        let matchesByName = Dictionary(grouping: nftNames, by: \.normalizedName)
        return (matchesByName[query] ?? []).map(nftNameMatch)
    }

    func partialNFTNameMatches(query: String) -> [SearchLocalMatch] {
        nftNames
            .filter { $0.normalizedName.contains(query) }
            .prefix(6)
            .map(nftNameMatch)
    }

    func exactCollectionMatches(query: String) -> [SearchLocalMatch] {
        let matchesByName = Dictionary(grouping: collections, by: \.normalizedName)
        return (matchesByName[query] ?? []).map(collectionMatch)
    }

    func partialCollectionMatches(query: String) -> [SearchLocalMatch] {
        collections
            .filter { $0.normalizedName.contains(query) }
            .prefix(6)
            .map(collectionMatch)
    }

    func allMatches(filter: SearchFilterState, limit: Int = 24) -> [SearchLocalMatch] {
        var seen = Set<String>()
        let orderedMatches = accounts.map(accountMatch) +
            ensEntries.map(ensMatch) +
            tokenSymbols.map(tokenSymbolMatch) +
            nftNames.map(nftNameMatch) +
            collections.map(collectionMatch) +
            contracts.map(contractMatch)

        return orderedMatches
            .filter { filter.includes(match: $0) }
            .filter { seen.insert($0.id).inserted }
            .prefix(limit)
            .map { $0 }
    }

    private func accountMatch(_ entry: AccountEntry) -> SearchLocalMatch {
        SearchLocalMatch(
            kind: .account,
            title: entry.displayName,
            subtitle: entry.address.displayAddress,
            destination: .profile(address: entry.address)
        )
    }

    private func ensMatch(_ entry: ENSEntry) -> SearchLocalMatch {
        SearchLocalMatch(
            kind: .ens,
            title: entry.displayName,
            subtitle: entry.address.displayAddress,
            destination: .profile(address: entry.address)
        )
    }

    private func contractMatch(_ entry: ContractEntry) -> SearchLocalMatch {
        SearchLocalMatch(
            kind: .contract,
            title: entry.label,
            subtitle: "\(entry.chain.routingDisplayName) • \(entry.address.displayAddress)",
            destination: .nftCollection(
                contractAddress: entry.address,
                title: entry.label,
                chain: entry.chain
            )
        )
    }

    private func tokenSymbolMatch(_ entry: SymbolEntry) -> SearchLocalMatch {
        SearchLocalMatch(
            kind: .tokenSymbol,
            title: entry.symbol,
            subtitle: entry.label,
            destination: .token(
                contractAddress: entry.contractAddress,
                chain: entry.chain,
                symbol: entry.symbol
            )
        )
    }

    private func nftNameMatch(_ entry: NameEntry) -> SearchLocalMatch {
        SearchLocalMatch(
            kind: .nftName,
            title: entry.displayName,
            subtitle: entry.collectionDisplayName ?? "Active scope item",
            destination: .nftItem(id: entry.nftID)
        )
    }

    private func collectionMatch(_ entry: CollectionEntry) -> SearchLocalMatch {
        SearchLocalMatch(
            kind: .collectionName,
            title: entry.displayName,
            subtitle: entry.chain.routingDisplayName,
            destination: .nftCollection(
                contractAddress: entry.contractAddress,
                title: entry.displayName,
                chain: entry.chain
            )
        )
    }

    private static func cleanedText(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }
}
