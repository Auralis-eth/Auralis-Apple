import Foundation
import SwiftData

@MainActor
protocol AuraPlayLibrarySyncing {
    func syncLibrary(in scope: AuraPlayLibraryScope, accountName: String?) async throws
}

@MainActor
struct NoOpAuraPlayLibrarySyncService: AuraPlayLibrarySyncing {
    func syncLibrary(in scope: AuraPlayLibraryScope, accountName: String?) async throws {}
}

@MainActor
struct LiveAuraPlayLibrarySyncService: AuraPlayLibrarySyncing {
    private let sourceModelContext: ModelContext
    private let walletService: AuraPlayWalletService
    private let tokenService: AuraPlayNFTTokenService
    private let mediaItemService: AuraPlayMediaItemService
    private let logger: any AuraPlayLogging

    init(
        sourceModelContext: ModelContext,
        modelContainer: ModelContainer,
        logger: any AuraPlayLogging
    ) {
        self.sourceModelContext = sourceModelContext
        self.walletService = AuraPlayWalletService(modelContainer: modelContainer)
        self.tokenService = AuraPlayNFTTokenService(modelContainer: modelContainer)
        self.mediaItemService = AuraPlayMediaItemService(modelContainer: modelContainer)
        self.logger = logger
    }

    func syncLibrary(in scope: AuraPlayLibraryScope, accountName: String?) async throws {
        guard let normalizedAccountAddress = NFT.normalizedScopeComponent(scope.accountAddress) else {
            return
        }

        let syncedAt = Date()
        let walletID = try await walletService.upsert(
            AuraPlayWalletUpsertRequest(
                address: normalizedAccountAddress,
                chain: scope.chain,
                displayName: accountName,
                syncedAt: syncedAt
            )
        )
        let nfts = try fetchEligibleNFTs(accountAddress: normalizedAccountAddress, chain: scope.chain)
        let tokenRequests = nfts.map { makeTokenRequest(from: $0, walletID: walletID) }
        let mediaItemRequests = nfts.map {
            makeMediaItemRequest(
                from: $0,
                walletID: walletID
            )
        }

        try await tokenService.replaceAll(
            walletID: walletID,
            requests: tokenRequests,
            syncedAt: syncedAt
        )
        try await mediaItemService.replaceAll(
            walletID: walletID,
            requests: mediaItemRequests,
            syncedAt: syncedAt
        )

        logger.log(
            AuraPlayLogEvent(
                category: .library,
                level: .info,
                message: "AuraPlay synced \(mediaItemRequests.count) persisted media items for \(walletID)"
            )
        )
    }
}

@MainActor
private extension LiveAuraPlayLibrarySyncService {
    func fetchEligibleNFTs(accountAddress: String, chain: Chain) throws -> [NFT] {
        let chainRawValue = chain.rawValue
        let descriptor = FetchDescriptor<NFT>(
            predicate: #Predicate<NFT> { nft in
                nft.accountAddressRawValue == accountAddress &&
                nft.networkRawValue == chainRawValue &&
                nft.audioUrl != nil &&
                nft.audioUrl != ""
            }
        )

        let nfts = try sourceModelContext.fetch(descriptor)
        let dedupedByID = Dictionary(uniqueKeysWithValues: nfts.map { ($0.id, $0) })
        return dedupedByID.values.sorted { $0.id < $1.id }
    }

    func makeTokenRequest(from nft: NFT, walletID: String) -> AuraPlayNFTTokenUpsertRequest {
        let contractAddress = NFT.normalizedScopeComponent(nft.contract.address) ?? "__missing_contract__"

        return AuraPlayNFTTokenUpsertRequest(
            walletID: walletID,
            sourceNFTID: nft.id,
            contractAddressRawValue: contractAddress,
            tokenID: nft.tokenId,
            tokenType: nft.tokenType,
            title: cleanedText(nft.name) ?? "Unknown Track",
            artistName: cleanedText(nft.artistName),
            collectionName: cleanedText(nft.collectionName ?? nft.collection?.name),
            artworkURLString: artworkURLString(from: nft),
            playbackURLString: nft.musicURL?.absoluteString,
            contentType: cleanedText(nft.contentType),
            sourceUpdatedAtRawValue: cleanedText(nft.timeLastUpdated)
        )
    }

    func makeMediaItemRequest(from nft: NFT, walletID: String) -> AuraPlayMediaItemUpsertRequest {
        let title = cleanedText(nft.name) ?? "Unknown Track"
        let artistName = cleanedText(nft.artistName)
        let collectionName = cleanedText(nft.collectionName ?? nft.collection?.name)
        let playbackURLString = nft.musicURL?.absoluteString
        let artworkURLString = artworkURLString(from: nft)
        let contractAddress = NFT.normalizedScopeComponent(nft.contract.address) ?? "__missing_contract__"
        let tokenCompositeID = AuraPlayNFTToken.makeCompositeID(
            walletID: walletID,
            contractAddressRawValue: contractAddress,
            tokenID: nft.tokenId
        )

        return AuraPlayMediaItemUpsertRequest(
            walletID: walletID,
            tokenCompositeID: tokenCompositeID,
            sourceNFTID: nft.id,
            accountAddressRawValue: nft.accountAddressRawValue,
            chain: nft.network ?? .ethMainnet,
            title: title,
            artistName: artistName,
            collectionName: collectionName,
            normalizedTitleKey: normalizedKey(title),
            normalizedArtistKey: normalizedKey(artistName),
            normalizedCollectionKey: normalizedKey(collectionName),
            artworkURLString: artworkURLString,
            playbackURLString: playbackURLString,
            contentType: cleanedText(nft.contentType),
            sourceUpdatedAtRawValue: cleanedText(nft.timeLastUpdated),
            hasArtwork: artworkURLString != nil,
            hasAudio: playbackURLString != nil,
            isPlayable: playbackURLString != nil,
            isSearchable: true
        )
    }

    func artworkURLString(from nft: NFT) -> String? {
        [nft.image?.thumbnailUrl, nft.image?.originalUrl]
            .compactMap { (rawValue: String?) -> String? in
                guard let rawValue else {
                    return nil
                }
                return URL.sanitizedRemoteMediaURL(from: rawValue)?.absoluteString
            }
            .first
    }

    func cleanedText(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }

    func normalizedKey(_ value: String?) -> String {
        cleanedText(value)?
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .lowercased() ?? ""
    }
}
