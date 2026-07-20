import AuralisPrimaryModels
import AuralisPrimaryPersistence
import Foundation
import ReceiptStorage
import SwiftData
import TokenStorage

#if canImport(CoreSpotlight)
@preconcurrency import CoreSpotlight
import UniformTypeIdentifiers
#endif

struct SearchSpotlightIndexConfiguration {
    static let indexName = "AuralisGlobalSearch"

    static let searchableDomains = [
        SearchIndexedDocument.Domain.account.rawValue,
        SearchIndexedDocument.Domain.nft.rawValue,
        SearchIndexedDocument.Domain.collection.rawValue,
        SearchIndexedDocument.Domain.erc20.rawValue,
        SearchIndexedDocument.Domain.receipt.rawValue,
    ]
}

struct SearchScope: Equatable, Sendable {
    let accountAddress: String?
    let chain: Chain

    var normalizedAccountAddress: String? {
        NFT.normalizedScopeComponent(accountAddress)
    }
}

final class SearchSpotlightScopeRegistry: @unchecked Sendable {
    private let lock = NSLock()
    private var storedScope: SearchScope?

    var currentScope: SearchScope? {
        lock.withLock { storedScope }
    }

    func update(_ scope: SearchScope) {
        lock.withLock {
            storedScope = scope
        }
    }
}

enum SearchSpotlightMetadataToken {
    static func token(_ key: String, _ value: String?) -> String? {
        guard let cleanedValue = cleaned(value) else {
            return nil
        }

        return "auralis:\(canonicalKey(key))=\(cleanedValue)"
    }

    static func value(for key: String, in keywords: [String]) -> String? {
        let tokenPrefix = "auralis:\(canonicalKey(key))="
        guard let token = keywords.first(where: { $0.lowercased().hasPrefix(tokenPrefix) }) else {
            return nil
        }

        return String(token.dropFirst(tokenPrefix.count))
    }

    private static func canonicalKey(_ key: String) -> String {
        key.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private static func cleaned(_ value: String?) -> String? {
        let trimmed = value?
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }
}

struct SearchSpotlightDocumentMetadata: Equatable, Sendable {
    let domainLabel: String
    let chainName: String?
    let accountAddress: String?
    let contractAddress: String?
    let tokenID: String?
    let tokenStandard: String?
    let collectionName: String?
    let artistName: String?
    let mediaKind: String?
    let receiptTrigger: String?
    let receiptStatus: String?
    let receiptScope: String?
    let receiptActor: String?
    let balanceDisplay: String?
    let isPlayable: Bool?
    let collectionItemCount: Int?
    let hydrationContext: String?

    static let empty = SearchSpotlightDocumentMetadata(
        domainLabel: "Auralis item",
        chainName: nil,
        accountAddress: nil,
        contractAddress: nil,
        tokenID: nil,
        tokenStandard: nil,
        collectionName: nil,
        artistName: nil,
        mediaKind: nil,
        receiptTrigger: nil,
        receiptStatus: nil,
        receiptScope: nil,
        receiptActor: nil,
        balanceDisplay: nil,
        isPlayable: nil,
        collectionItemCount: nil,
        hydrationContext: nil
    )

    var keywordValues: [String] {
        let humanKeywords = [
            domainLabel,
            chainName,
            accountAddress,
            contractAddress,
            tokenID,
            tokenStandard,
            collectionName,
            artistName,
            mediaKind,
            receiptTrigger,
            receiptStatus,
            receiptScope,
            receiptActor,
            balanceDisplay,
            isPlayable.map { $0 ? "playable" : "not playable" },
            collectionItemCount.map { "collection count \($0)" },
        ].compactMap(cleanedText)

        let structuredKeywords = [
            SearchSpotlightMetadataToken.token("domainLabel", domainLabel),
            SearchSpotlightMetadataToken.token("chain", chainName),
            SearchSpotlightMetadataToken.token("accountAddress", accountAddress),
            SearchSpotlightMetadataToken.token("contractAddress", contractAddress),
            SearchSpotlightMetadataToken.token("tokenID", tokenID),
            SearchSpotlightMetadataToken.token("tokenStandard", tokenStandard),
            SearchSpotlightMetadataToken.token("collectionName", collectionName),
            SearchSpotlightMetadataToken.token("artistName", artistName),
            SearchSpotlightMetadataToken.token("mediaKind", mediaKind),
            SearchSpotlightMetadataToken.token("receiptTrigger", receiptTrigger),
            SearchSpotlightMetadataToken.token("receiptStatus", receiptStatus),
            SearchSpotlightMetadataToken.token("receiptScope", receiptScope),
            SearchSpotlightMetadataToken.token("receiptActor", receiptActor),
            SearchSpotlightMetadataToken.token("balanceDisplay", balanceDisplay),
            isPlayable.flatMap { SearchSpotlightMetadataToken.token("isPlayable", $0 ? "true" : "false") },
            collectionItemCount.flatMap { SearchSpotlightMetadataToken.token("collectionItemCount", "\($0)") },
        ].compactMap { $0 }

        return humanKeywords + structuredKeywords
    }

    var modelContextLines: [String] {
        [
            "Type: \(domainLabel)",
            chainName.map { "Chain: \($0)" },
            accountAddress.map { "Wallet: \($0)" },
            contractAddress.map { "Contract: \($0)" },
            tokenID.map { "Token ID: \($0)" },
            tokenStandard.map { "Token standard: \($0)" },
            collectionName.map { "Collection: \($0)" },
            artistName.map { "Artist: \($0)" },
            mediaKind.map { "Media: \($0)" },
            receiptTrigger.map { "Trigger: \($0)" },
            receiptStatus.map { "Status: \($0)" },
            receiptScope.map { "Scope: \($0)" },
            receiptActor.map { "Actor: \($0)" },
            balanceDisplay.map { "Balance: \($0)" },
            isPlayable.map { "Playable: \($0 ? "yes" : "no")" },
            collectionItemCount.map { "Collection item count: \($0)" },
            hydrationContext,
        ].compactMap(cleanedText)
    }

    private func cleanedText(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }
}

extension SearchSpotlightDocumentMetadata {
    func replacing(
        domainLabel: String? = nil,
        chainName: String? = nil,
        accountAddress: String? = nil,
        contractAddress: String? = nil,
        tokenID: String? = nil,
        tokenStandard: String? = nil,
        collectionName: String? = nil,
        artistName: String? = nil,
        mediaKind: String? = nil,
        receiptTrigger: String? = nil,
        receiptStatus: String? = nil,
        receiptScope: String? = nil,
        receiptActor: String? = nil,
        balanceDisplay: String? = nil,
        isPlayable: Bool? = nil,
        collectionItemCount: Int? = nil,
        hydrationContext: String? = nil
    ) -> SearchSpotlightDocumentMetadata {
        SearchSpotlightDocumentMetadata(
            domainLabel: domainLabel ?? self.domainLabel,
            chainName: chainName ?? self.chainName,
            accountAddress: accountAddress ?? self.accountAddress,
            contractAddress: contractAddress ?? self.contractAddress,
            tokenID: tokenID ?? self.tokenID,
            tokenStandard: tokenStandard ?? self.tokenStandard,
            collectionName: collectionName ?? self.collectionName,
            artistName: artistName ?? self.artistName,
            mediaKind: mediaKind ?? self.mediaKind,
            receiptTrigger: receiptTrigger ?? self.receiptTrigger,
            receiptStatus: receiptStatus ?? self.receiptStatus,
            receiptScope: receiptScope ?? self.receiptScope,
            receiptActor: receiptActor ?? self.receiptActor,
            balanceDisplay: balanceDisplay ?? self.balanceDisplay,
            isPlayable: isPlayable ?? self.isPlayable,
            collectionItemCount: collectionItemCount ?? self.collectionItemCount,
            hydrationContext: hydrationContext ?? self.hydrationContext
        )
    }
}

struct SearchIndexedDocument: Identifiable, Equatable, Sendable {
    enum Domain: String, Equatable, Sendable, CaseIterable {
        case account = "account"
        case nft = "nft"
        case collection = "collection"
        case erc20 = "erc20"
        case receipt = "receipt"
        case auraPlayMedia = "com.auraplay.media"
    }

    let id: String
    let domain: Domain
    let title: String
    let subtitle: String
    let contentDescription: String
    let keywords: [String]
    let createdAt: Date?
    let modifiedAt: Date?
    let destination: SearchDestination
    let metadata: SearchSpotlightDocumentMetadata

    var searchableIdentifier: String {
        "auralis.search.\(domain.rawValue):\(id)"
    }

    init(
        id: String,
        domain: Domain,
        title: String,
        subtitle: String,
        contentDescription: String,
        keywords: [String],
        createdAt: Date?,
        modifiedAt: Date?,
        destination: SearchDestination,
        metadata: SearchSpotlightDocumentMetadata = .empty
    ) {
        self.id = id
        self.domain = domain
        self.title = title
        self.subtitle = subtitle
        self.contentDescription = contentDescription
        self.keywords = keywords
        self.createdAt = createdAt
        self.modifiedAt = modifiedAt
        self.destination = destination
        self.metadata = metadata
    }
}

protocol SearchSpotlightIndexing: Sendable {
    func index(_ documents: [SearchIndexedDocument]) async throws
    func delete(ids: [String]) async throws
    func reconcile(scope: SearchScope) async throws
}

@MainActor
struct SearchSpotlightDocumentBuilder {
    private let modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    func documents(scope: SearchScope) throws -> [SearchIndexedDocument] {
        var documents: [SearchIndexedDocument] = []
        documents.append(contentsOf: try accountDocuments())
        documents.append(contentsOf: try scopedNFTDocuments(scope: scope))
        documents.append(contentsOf: try scopedTokenDocuments(scope: scope))
        documents.append(contentsOf: try receiptDocuments())
        return documents
    }

    func document(forSearchableIdentifier searchableIdentifier: String) throws -> SearchIndexedDocument? {
        guard let parsed = SearchIndexedDocument.parseSearchableIdentifier(searchableIdentifier) else {
            return nil
        }

        switch parsed.domain {
        case .account:
            return try accountDocument(id: parsed.id)
        case .nft:
            return try nftDocument(id: parsed.id)
        case .collection:
            return try collectionDocument(id: parsed.id)
        case .erc20:
            return try tokenDocument(id: parsed.id)
        case .receipt:
            return try receiptDocument(id: parsed.id)
        case .auraPlayMedia:
            return nil
        }
    }

    private func accountDocuments() throws -> [SearchIndexedDocument] {
        try modelContext.fetch(FetchDescriptor<EOAccount>()).map { account in
            let address = NFT.normalizedScopeComponent(account.address) ?? account.address.lowercased()
            let title = cleanedText(account.name) ?? address.displayAddress
            return SearchIndexedDocument(
                id: address,
                domain: .account,
                title: title,
                subtitle: address.displayAddress,
                contentDescription: [
                    "Wallet account",
                    "Address: \(address)",
                    cleanedText(account.name).map { "Name: \($0)" },
                ].compactMap { $0 }.joined(separator: ". "),
                keywords: [title, address, "wallet", "account"],
                createdAt: account.addedAt,
                modifiedAt: account.lastSelectedAt,
                destination: .profile(address: address),
                metadata: SearchSpotlightDocumentMetadata.empty.replacing(
                    domainLabel: "Wallet account",
                    accountAddress: address,
                    hydrationContext: "Account name: \(title)"
                )
            )
        }
    }

    private func scopedNFTDocuments(scope: SearchScope) throws -> [SearchIndexedDocument] {
        let normalizedAccountAddress = scope.normalizedAccountAddress ?? ""
        let chainRawValue = scope.chain.rawValue
        var descriptor = FetchDescriptor<NFT>(
            predicate: #Predicate<NFT> { nft in
                nft.accountAddressRawValue == normalizedAccountAddress && nft.networkRawValue == chainRawValue
            },
            sortBy: [SortDescriptor(\NFT.id)]
        )
        descriptor.relationshipKeyPathsForPrefetching = [\NFT.contract, \NFT.collection]
        let nfts = try modelContext.fetch(descriptor)
        let nftDocuments = nfts.map { nftDocument(nft: $0) }
        let collectionDocuments = collectionDocuments(from: nfts, chain: scope.chain)
        return nftDocuments + collectionDocuments
    }

    private func scopedTokenDocuments(scope: SearchScope) throws -> [SearchIndexedDocument] {
        let normalizedAccountAddress = scope.normalizedAccountAddress ?? ""
        let chainRawValue = scope.chain.rawValue
        let holdings = try modelContext.fetch(
            FetchDescriptor<TokenHolding>(
                predicate: #Predicate<TokenHolding> { holding in
                    holding.accountAddressRawValue == normalizedAccountAddress
                        && holding.chainRawValue == chainRawValue
                },
                sortBy: [SortDescriptor(\TokenHolding.displayName)]
            )
        )
        .filter { $0.balanceKind == .erc20 }


        return holdings.compactMap { holding in
            guard let contractAddress = cleanedText(holding.contractAddress) else {
                return nil
            }
            let symbol = cleanedText(holding.symbol)?.uppercased() ?? holding.displayName
            let chain = Chain(rawValue: holding.chainRawValue) ?? scope.chain
            return SearchIndexedDocument(
                id: [chain.rawValue, contractAddress].joined(separator: ":"),
                domain: .erc20,
                title: symbol,
                subtitle: holding.displayName,
                contentDescription: [
                    "ERC-20 token",
                    "Name: \(holding.displayName)",
                    "Symbol: \(symbol)",
                    "Chain: \(chain.routingDisplayName)",
                    "Contract: \(contractAddress)",
                    "Balance: \(holding.amountDisplay)",
                ].joined(separator: ". "),
                keywords: [symbol, holding.displayName, chain.routingDisplayName, contractAddress, "token", "erc20"],
                createdAt: nil,
                modifiedAt: holding.updatedAt,
                destination: .token(contractAddress: contractAddress, chain: chain, symbol: symbol),
                metadata: SearchSpotlightDocumentMetadata.empty.replacing(
                    domainLabel: "ERC-20 token",
                    chainName: chain.routingDisplayName,
                    accountAddress: normalizedAccountAddress,
                    contractAddress: contractAddress,
                    tokenStandard: "ERC-20",
                    balanceDisplay: holding.amountDisplay
                )
            )
        }
    }

    private func receiptDocuments() throws -> [SearchIndexedDocument] {
        let descriptor = FetchDescriptor<StoredReceipt>(
            sortBy: [
                SortDescriptor(\StoredReceipt.createdAt, order: .reverse),
                SortDescriptor(\StoredReceipt.sequenceID, order: .reverse),
            ]
        )

        return try modelContext.fetch(descriptor).map { storedReceipt in
            receiptDocument(storedReceipt: storedReceipt)
        }
    }

    private func accountDocument(id: String) throws -> SearchIndexedDocument? {
        let normalizedID = NFT.normalizedScopeComponent(id) ?? id.lowercased()
        let descriptor = FetchDescriptor<EOAccount>(
            predicate: #Predicate<EOAccount> { account in account.address == normalizedID }
        )
        return try modelContext.fetch(descriptor).first.map { account in
            let title = cleanedText(account.name) ?? normalizedID.displayAddress
            return SearchIndexedDocument(
                id: normalizedID,
                domain: .account,
                title: title,
                subtitle: normalizedID.displayAddress,
                contentDescription: "Wallet account. Address: \(normalizedID). Name: \(title)",
                keywords: [title, normalizedID, "wallet", "account"],
                createdAt: account.addedAt,
                modifiedAt: account.lastSelectedAt,
                destination: .profile(address: normalizedID),
                metadata: SearchSpotlightDocumentMetadata.empty.replacing(
                    domainLabel: "Wallet account",
                    accountAddress: normalizedID,
                    hydrationContext: "Account name: \(title)"
                )
            )
        }
    }

    private func nftDocument(id: String) throws -> SearchIndexedDocument? {
        let descriptor = FetchDescriptor<NFT>(predicate: #Predicate<NFT> { nft in nft.id == id })
        return try modelContext.fetch(descriptor).first.map(nftDocument(nft:))
    }

    private func collectionDocument(id: String) throws -> SearchIndexedDocument? {
        let descriptor = FetchDescriptor<NFT>()
        let matchingNFTs = try modelContext.fetch(descriptor).filter { nft in
            collectionID(for: nft, chain: nft.network ?? .ethMainnet) == id
        }
        guard let firstNFT = matchingNFTs.first, let chain = firstNFT.network else {
            return nil
        }
        return collectionDocuments(from: matchingNFTs, chain: chain).first
    }

    private func tokenDocument(id: String) throws -> SearchIndexedDocument? {
        let parts = id.split(separator: ":", maxSplits: 1).map(String.init)
        guard parts.count == 2 else { return nil }
        let chainRawValue = parts[0]
        let contractAddress = parts[1]
        let descriptor = FetchDescriptor<TokenHolding>(
            predicate: #Predicate<TokenHolding> { holding in
                holding.chainRawValue == chainRawValue && holding.contractAddress == contractAddress
            }
        )
        guard let holding = try modelContext.fetch(descriptor).first,
              let chain = Chain(rawValue: chainRawValue) else {
            return nil
        }
        let symbol = cleanedText(holding.symbol)?.uppercased() ?? holding.displayName
        return SearchIndexedDocument(
            id: id,
            domain: .erc20,
            title: symbol,
            subtitle: holding.displayName,
            contentDescription: "ERC-20 token. Name: \(holding.displayName). Symbol: \(symbol). Chain: \(chain.routingDisplayName). Contract: \(contractAddress). Balance: \(holding.amountDisplay)",
            keywords: [symbol, holding.displayName, chain.routingDisplayName, contractAddress, "token", "erc20"],
            createdAt: nil,
            modifiedAt: holding.updatedAt,
            destination: .token(contractAddress: contractAddress, chain: chain, symbol: symbol),
            metadata: SearchSpotlightDocumentMetadata.empty.replacing(
                domainLabel: "ERC-20 token",
                chainName: chain.routingDisplayName,
                contractAddress: contractAddress,
                tokenStandard: "ERC-20",
                balanceDisplay: holding.amountDisplay
            )
        )
    }

    private func receiptDocument(id: String) throws -> SearchIndexedDocument? {
        guard let uuid = UUID(uuidString: id) else { return nil }
        let descriptor = FetchDescriptor<StoredReceipt>(
            predicate: #Predicate<StoredReceipt> { receipt in receipt.id == uuid }
        )
        return try modelContext.fetch(descriptor).first.map(receiptDocument(storedReceipt:))
    }

    private func nftDocument(nft: NFT) -> SearchIndexedDocument {
        let chain = nft.network ?? .ethMainnet
        let title = cleanedText(nft.name) ?? "NFT #\(nft.tokenId)"
        let collectionTitle = cleanedText(nft.collectionName ?? nft.collection?.name)
        let contractAddress = cleanedText(nft.contract.address)
        let mediaKind = mediaKind(for: nft)
        return SearchIndexedDocument(
            id: nft.id,
            domain: .nft,
            title: title,
            subtitle: collectionTitle ?? chain.routingDisplayName,
            contentDescription: [
                "NFT: \(title)",
                collectionTitle.map { "Collection: \($0)" },
                "Chain: \(chain.routingDisplayName)",
                contractAddress.map { "Contract: \($0)" },
                "Token ID: \(nft.tokenId)",
                "Media: \(mediaKind)",
                cleanedText(nft.nftDescription),
                cleanedText(nft.artistName).map { "Artist: \($0)" },
                "Owned by active wallet",
            ].compactMap { $0 }.joined(separator: ". "),
            keywords: [
                title,
                collectionTitle,
                contractAddress,
                nft.tokenId,
                chain.routingDisplayName,
                mediaKind,
                nft.tokenType,
                nft.symbols,
                nft.artistName,
                "nft",
            ].compactMap(cleanedText),
            createdAt: nil,
            modifiedAt: nil,
            destination: nft.isMusic() ? .musicItem(id: nft.id) : .nftItem(id: nft.id),
            metadata: SearchSpotlightDocumentMetadata.empty.replacing(
                domainLabel: nft.isMusic() ? "AuraPlay media NFT" : "NFT",
                chainName: chain.routingDisplayName,
                accountAddress: NFT.normalizedScopeComponent(nft.accountAddressRawValue),
                contractAddress: contractAddress,
                tokenID: nft.tokenId,
                tokenStandard: cleanedText(nft.tokenType),
                collectionName: collectionTitle,
                artistName: cleanedText(nft.artistName),
                mediaKind: mediaKind,
                isPlayable: cleanedText(nft.audioUrl) != nil || cleanedText(nft.animationUrl) != nil || cleanedText(nft.secureAnimationUrl) != nil
            )
        )
    }

    private func collectionDocuments(from nfts: [NFT], chain: Chain) -> [SearchIndexedDocument] {
        var seenIDs = Set<String>()
        return nfts.compactMap { nft in
            guard let name = cleanedText(nft.collectionName ?? nft.collection?.name) else {
                return nil
            }
            let id = collectionID(for: nft, chain: chain)
            guard seenIDs.insert(id).inserted else { return nil }
            let contractAddress = NFT.normalizedScopeComponent(nft.contract.address)
            return SearchIndexedDocument(
                id: id,
                domain: .collection,
                title: name,
                subtitle: chain.routingDisplayName,
                contentDescription: [
                    "NFT collection: \(name)",
                    "Chain: \(chain.routingDisplayName)",
                    contractAddress.map { "Contract: \($0)" },
                    "Owned by active wallet",
                ].compactMap { $0 }.joined(separator: ". "),
                keywords: [name, chain.routingDisplayName, contractAddress, "collection", "nft"].compactMap(cleanedText),
                createdAt: nil,
                modifiedAt: nil,
                destination: .nftCollection(contractAddress: contractAddress, title: name, chain: chain),
                metadata: SearchSpotlightDocumentMetadata.empty.replacing(
                    domainLabel: "NFT collection",
                    chainName: chain.routingDisplayName,
                    contractAddress: contractAddress,
                    collectionName: name,
                    collectionItemCount: nfts.filter {
                        collectionID(for: $0, chain: chain) == id
                    }.count
                )
            )
        }
    }

    private func receiptDocument(storedReceipt: StoredReceipt) -> SearchIndexedDocument {
        let record = ReceiptTimelineRecord(storedReceipt: storedReceipt)
        let chainTitle = record.chainTitle
        let accountTitle = record.accountTitle
        let payloadText = record.searchIndex
        return SearchIndexedDocument(
            id: storedReceipt.id.uuidString,
            domain: .receipt,
            title: record.triggerTitle,
            subtitle: record.summary,
            contentDescription: [
                "Receipt event",
                "Summary: \(record.summary)",
                "Trigger: \(record.trigger)",
                "Scope: \(record.scope)",
                "Actor: \(record.actorTitle)",
                "Status: \(record.statusTitle)",
                chainTitle.map { "Chain: \($0)" },
                accountTitle.map { "Account: \($0)" },
                "Payload: \(payloadText)",
            ].compactMap { $0 }.joined(separator: ". "),
            keywords: [
                record.summary,
                record.trigger,
                record.scope,
                record.provenance,
                record.actorTitle,
                record.statusTitle,
                chainTitle,
                accountTitle,
                record.correlationID,
                payloadText,
                "receipt",
                "activity",
            ].compactMap(cleanedText),
            createdAt: storedReceipt.createdAt,
            modifiedAt: storedReceipt.createdAt,
            destination: .receipt(id: storedReceipt.id.uuidString),
            metadata: SearchSpotlightDocumentMetadata.empty.replacing(
                domainLabel: "Receipt event",
                chainName: chainTitle,
                accountAddress: accountTitle,
                receiptTrigger: record.trigger,
                receiptStatus: record.statusTitle,
                receiptScope: record.scope,
                receiptActor: record.actorTitle,
                hydrationContext: "Receipt payload summary: \(payloadText)"
            )
        )
    }

    private func collectionID(for nft: NFT, chain: Chain) -> String {
        let name = cleanedText(nft.collectionName ?? nft.collection?.name) ?? nft.id
        let contractAddress = NFT.normalizedScopeComponent(nft.contract.address)
        return [chain.rawValue, contractAddress ?? "name:\(name.lowercased())", name.lowercased()].joined(separator: ":")
    }

    private func mediaKind(for nft: NFT) -> String {
        if cleanedText(nft.audioUrl) != nil { return "audio" }
        if cleanedText(nft.animationUrl) != nil || cleanedText(nft.secureAnimationUrl) != nil { return "video" }
        if cleanedText(nft.modelUrl) != nil { return "3D model" }
        return cleanedText(nft.contentType) ?? "visual"
    }

    private func cleanedText(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }
}

@MainActor
final class SearchSpotlightIndexer: SearchSpotlightIndexing {
    private let modelContext: ModelContext
    private let client: any SearchSpotlightIndexClient
    private let scopeRegistry: SearchSpotlightScopeRegistry

    init(
        modelContext: ModelContext,
        client: any SearchSpotlightIndexClient = CoreSpotlightSearchIndexClient(),
        scopeRegistry: SearchSpotlightScopeRegistry = SearchSpotlightScopeRegistry()
    ) {
        self.modelContext = modelContext
        self.client = client
        self.scopeRegistry = scopeRegistry
    }

    func index(_ documents: [SearchIndexedDocument]) async throws {
        try await client.index(documents)
    }

    func delete(ids: [String]) async throws {
        try await client.delete(ids: ids)
    }

    func reconcile(scope: SearchScope) async throws {
        scopeRegistry.update(scope)
        let documents = try SearchSpotlightDocumentBuilder(modelContext: modelContext).documents(scope: scope)
        try await client.deleteDomains(SearchSpotlightIndexConfiguration.searchableDomains)
        try await client.index(documents)
    }
}

protocol SearchSpotlightIndexClient: Sendable {
    func index(_ documents: [SearchIndexedDocument]) async throws
    func delete(ids: [String]) async throws
    func deleteDomains(_ domainIdentifiers: [String]) async throws
}

struct CoreSpotlightSearchIndexClient: SearchSpotlightIndexClient {
    let indexName: String

    init(indexName: String = SearchSpotlightIndexConfiguration.indexName) {
        self.indexName = indexName
    }

    func index(_ documents: [SearchIndexedDocument]) async throws {
        guard !documents.isEmpty else { return }
        #if canImport(CoreSpotlight)
        let items = documents.map(\.searchableItem)
        let index = CSSearchableIndex(name: indexName)
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            index.indexSearchableItems(items) { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        }
        #endif
    }

    func delete(ids: [String]) async throws {
        guard !ids.isEmpty else { return }
        #if canImport(CoreSpotlight)
        let index = CSSearchableIndex(name: indexName)
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            index.deleteSearchableItems(withIdentifiers: ids) { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        }
        #endif
    }

    func deleteDomains(_ domainIdentifiers: [String]) async throws {
        guard !domainIdentifiers.isEmpty else { return }
        #if canImport(CoreSpotlight)
        let index = CSSearchableIndex(name: indexName)
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            index.deleteSearchableItems(withDomainIdentifiers: domainIdentifiers) { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        }
        #endif
    }
}

#if canImport(CoreSpotlight)
private struct SearchSpotlightReindexAcknowledgement: @unchecked Sendable {
    let handler: () -> Void

    func callAsFunction() {
        handler()
    }
}

final class SearchSpotlightHydrationDelegate: NSObject, CSSearchableIndexDelegate, @unchecked Sendable {
    private let modelContainer: ModelContainer
    private let scopeRegistry: SearchSpotlightScopeRegistry

    init(modelContainer: ModelContainer, scopeRegistry: SearchSpotlightScopeRegistry = SearchSpotlightScopeRegistry()) {
        self.modelContainer = modelContainer
        self.scopeRegistry = scopeRegistry
    }

    func searchableItems(
        forIdentifiers identifiers: [String],
        searchableItemsHandler: @escaping @Sendable ([CSSearchableItem]) -> Void
    ) {
        Task { @MainActor in
            let context = ModelContext(modelContainer)
            let builder = SearchSpotlightDocumentBuilder(modelContext: context)
            let items = identifiers.compactMap { identifier in
                (try? builder.document(forSearchableIdentifier: identifier))?.hydratedSearchableItem
            }
            searchableItemsHandler(items)
        }
    }

    func searchableIndex(
        _ searchableIndex: CSSearchableIndex,
        reindexAllSearchableItemsWithAcknowledgementHandler acknowledgementHandler: @escaping () -> Void
    ) {
        let acknowledgement = SearchSpotlightReindexAcknowledgement(handler: acknowledgementHandler)
        Task { @MainActor in
            guard let scope = scopeRegistry.currentScope else {
                acknowledgement()
                return
            }

            let context = ModelContext(modelContainer)
            let builder = SearchSpotlightDocumentBuilder(modelContext: context)
            let items = ((try? builder.documents(scope: scope)) ?? []).map(\.searchableItem)
            try? await searchableIndex.indexSearchableItems(items)
            acknowledgement()
        }
    }

    func searchableIndex(
        _ searchableIndex: CSSearchableIndex,
        reindexSearchableItemsWithIdentifiers identifiers: [String],
        acknowledgementHandler: @escaping () -> Void
    ) {
        let acknowledgement = SearchSpotlightReindexAcknowledgement(handler: acknowledgementHandler)
        Task { @MainActor in
            let context = ModelContext(modelContainer)
            let builder = SearchSpotlightDocumentBuilder(modelContext: context)
            let items = identifiers.compactMap { identifier in
                (try? builder.document(forSearchableIdentifier: identifier))?.searchableItem
            }
            try? await searchableIndex.indexSearchableItems(items)
            acknowledgement()
        }
    }
}

extension SearchIndexedDocument {
    var searchableItem: CSSearchableItem {
        makeSearchableItem(includeHydrationContext: false)
    }

    var hydratedSearchableItem: CSSearchableItem {
        makeSearchableItem(includeHydrationContext: true)
    }

    private func makeSearchableItem(includeHydrationContext: Bool) -> CSSearchableItem {
        let attributeSet = CSSearchableItemAttributeSet(contentType: contentType)
        attributeSet.title = title
        attributeSet.displayName = title
        attributeSet.contentDescription = searchableDescription(includeHydrationContext: includeHydrationContext)
        attributeSet.textContent = searchableText(includeHydrationContext: includeHydrationContext)
        let documentKeywords = [
            SearchSpotlightMetadataToken.token("documentDomain", domain.rawValue),
        ].compactMap { $0 }
        attributeSet.keywords = Array(Set((keywords + metadata.keywordValues + documentKeywords).filter { !$0.isEmpty })).sorted()
        attributeSet.contentCreationDate = createdAt
        attributeSet.contentModificationDate = modifiedAt ?? createdAt
        attributeSet.metadataModificationDate = modifiedAt ?? createdAt
        attributeSet.timestamp = modifiedAt ?? createdAt
        attributeSet.containerDisplayName = metadata.collectionName ?? metadata.chainName ?? metadata.domainLabel
        attributeSet.containerIdentifier = metadata.contractAddress ?? metadata.accountAddress ?? domain.rawValue
        attributeSet.alternateNames = [
            subtitle,
            metadata.domainLabel,
            metadata.collectionName,
            metadata.artistName,
            metadata.contractAddress,
            metadata.tokenID,
            metadata.tokenStandard,
            metadata.mediaKind,
            metadata.receiptTrigger,
            metadata.receiptStatus,
            metadata.receiptScope,
        ].compactMap { value in
            let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return trimmed.isEmpty ? nil : trimmed
        }
        attributeSet.userOwned = NSNumber(value: true)
        attributeSet.userCurated = NSNumber(value: domain == .receipt)
        attributeSet.userCreated = NSNumber(value: domain == .receipt)
        let item = CSSearchableItem(
            uniqueIdentifier: searchableIdentifier,
            domainIdentifier: domain.rawValue,
            attributeSet: attributeSet
        )
        item.expirationDate = .distantFuture
        return item
    }

    private func searchableDescription(includeHydrationContext: Bool) -> String {
        var lines = [contentDescription]
        if includeHydrationContext {
            lines.append(contentsOf: metadata.modelContextLines)
        }
        return lines.joined(separator: ". ")
    }

    private func searchableText(includeHydrationContext: Bool) -> String {
        let textParts = [
            title,
            subtitle,
            contentDescription,
            keywords.joined(separator: " "),
            metadata.keywordValues.joined(separator: " "),
            SearchSpotlightMetadataToken.token("documentDomain", domain.rawValue),
        ].compactMap { $0 }
        var text = textParts.joined(separator: ". ")
        if includeHydrationContext {
            text += ". " + metadata.modelContextLines.joined(separator: ". ")
        }
        return text
    }

    private var contentType: UTType {
        switch domain {
        case .account:
            return .contact
        case .nft, .collection:
            return .image
        case .erc20:
            return .data
        case .receipt:
            return .text
        case .auraPlayMedia:
            return .audio
        }
    }
}
#endif

extension SearchIndexedDocument {
    static func parseSearchableIdentifier(_ identifier: String) -> (domain: Domain, id: String)? {
        let prefix = "auralis.search."
        guard identifier.hasPrefix(prefix) else { return nil }
        let remainder = identifier.dropFirst(prefix.count)
        guard let separator = remainder.firstIndex(of: ":") else { return nil }
        let rawDomain = String(remainder[..<separator])
        let id = String(remainder[remainder.index(after: separator)...])
        guard let domain = Domain(rawValue: rawDomain), !id.isEmpty else { return nil }
        return (domain, id)
    }
}

#if canImport(CoreSpotlight)
extension SearchLocalMatch {
    init?(searchableItem: CSSearchableItem) {
        let parsed: (domain: SearchIndexedDocument.Domain, id: String)
        if let prefixed = SearchIndexedDocument.parseSearchableIdentifier(searchableItem.uniqueIdentifier) {
            parsed = prefixed
        } else if searchableItem.domainIdentifier == SearchIndexedDocument.Domain.auraPlayMedia.rawValue {
            parsed = (.auraPlayMedia, searchableItem.uniqueIdentifier)
        } else {
            return nil
        }

        let title = searchableItem.attributeSet.title ?? searchableItem.attributeSet.displayName ?? parsed.id
        let subtitle = searchableItem.attributeSet.contentDescription ?? parsed.domain.rawValue

        switch parsed.domain {
        case .account:
            self.init(kind: .account, title: title, subtitle: parsed.id.displayAddress, destination: .profile(address: parsed.id))
        case .nft:
            self.init(kind: .nftName, title: title, subtitle: subtitle, destination: .nftItem(id: parsed.id))
        case .collection:
            let parts = parsed.id.split(separator: ":", maxSplits: 2).map(String.init)
            let chain = parts.first.flatMap(Chain.init(rawValue:)) ?? .ethMainnet
            let contractAddress = parts.count > 1 && !parts[1].hasPrefix("name:") ? parts[1] : nil
            self.init(
                kind: .collectionName,
                title: title,
                subtitle: subtitle,
                destination: .nftCollection(contractAddress: contractAddress, title: title, chain: chain)
            )
        case .erc20:
            let parts = parsed.id.split(separator: ":", maxSplits: 1).map(String.init)
            guard parts.count == 2, let chain = Chain(rawValue: parts[0]) else { return nil }
            self.init(kind: .tokenSymbol, title: title, subtitle: subtitle, destination: .token(contractAddress: parts[1], chain: chain, symbol: title))
        case .receipt:
            self.init(kind: .receipt, title: title, subtitle: subtitle, destination: .receipt(id: parsed.id))
        case .auraPlayMedia:
            self.init(kind: .musicItem, title: title, subtitle: subtitle, destination: .musicItem(id: parsed.id))
        }
    }
}
#endif
