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
    private let sourceSnapshotStore: AuraPlaySourceNFTSnapshotStore
    private let walletService: AuraPlayWalletService
    private let tokenService: AuraPlayNFTTokenService
    private let mediaItemService: AuraPlayMediaItemService
    private let requestBuilder: AuraPlayLibrarySyncRequestBuilder
    private let logger: any AuraPlayLogging

    init(
        sourceModelContext: ModelContext,
        modelContainer: ModelContainer,
        logger: any AuraPlayLogging,
        requestBuilder: AuraPlayLibrarySyncRequestBuilder = .init()
    ) {
        self.sourceSnapshotStore = AuraPlaySourceNFTSnapshotStore(modelContainer: sourceModelContext.container)
        self.walletService = AuraPlayWalletService(modelContainer: modelContainer)
        self.tokenService = AuraPlayNFTTokenService(modelContainer: modelContainer)
        self.mediaItemService = AuraPlayMediaItemService(modelContainer: modelContainer)
        self.requestBuilder = requestBuilder
        self.logger = logger
    }

    func syncLibrary(in scope: AuraPlayLibraryScope, accountName: String?) async throws {
        guard let normalizedAccountAddress = NFT.normalizedScopeComponent(scope.accountAddress) else {
            return
        }

        let syncedAt = Date()
        let sourceSnapshots = try await sourceSnapshotStore.fetchEligibleNFTSnapshots(
            accountAddress: normalizedAccountAddress,
            chain: scope.chain
        )
        let walletID = try await walletService.upsert(
            AuraPlayWalletUpsertRequest(
                address: normalizedAccountAddress,
                chain: scope.chain,
                displayName: accountName,
                syncedAt: syncedAt
            )
        )
        let requestBundle = await requestBuilder.makeRequestBundle(
            from: sourceSnapshots,
            walletID: walletID
        )

        try await tokenService.replaceAll(
            walletID: walletID,
            requests: requestBundle.tokenRequests,
            syncedAt: syncedAt
        )
        try await mediaItemService.replaceAll(
            walletID: walletID,
            requests: requestBundle.mediaItemRequests,
            syncedAt: syncedAt
        )

        logger.log(
            AuraPlayLogEvent(
                category: .library,
                level: .info,
                message: "AuraPlay synced \(requestBundle.mediaItemRequests.count) persisted media items for \(walletID)"
            )
        )
    }
}

@ModelActor
private actor AuraPlaySourceNFTSnapshotStore {
    func fetchEligibleNFTSnapshots(accountAddress: String, chain: Chain) throws -> [LiveAuraPlayLibrarySyncService.SourceNFTSnapshot] {
        let chainRawValue = chain.rawValue
        var descriptor = FetchDescriptor<NFT>(
            predicate: #Predicate<NFT> { nft in
                nft.accountAddressRawValue == accountAddress &&
                nft.networkRawValue == chainRawValue &&
                nft.audioUrl != nil &&
                nft.audioUrl != ""
            },
            sortBy: [SortDescriptor(\NFT.id)]
        )
        descriptor.relationshipKeyPathsForPrefetching = [
            \NFT.contract,
            \NFT.image,
            \NFT.collection,
        ]

        return try modelContext.fetch(descriptor).map(LiveAuraPlayLibrarySyncService.SourceNFTSnapshot.init)
    }
}

extension LiveAuraPlayLibrarySyncService {
    typealias SourceNFTSnapshot = AuraPlayLibrarySyncRequestBuilder.SourceNFTSnapshot
}

struct AuraPlayLibrarySyncRequestBuilder: Sendable {
    struct RequestBundle: Sendable {
        let tokenRequests: [AuraPlayNFTTokenUpsertRequest]
        let mediaItemRequests: [AuraPlayMediaItemUpsertRequest]
    }

    struct SourceNFTSnapshot: Sendable {
        let id: String
        let tokenID: String
        let tokenType: String?
        let accountAddressRawValue: String
        let chain: Chain
        let contractAddressRawValue: String?
        let name: String?
        let artistName: String?
        let collectionName: String?
        let collectionDisplayName: String?
        let thumbnailURLString: String?
        let originalImageURLString: String?
        let playbackURLString: String?
        let contentType: String?
        let sourceUpdatedAtRawValue: String?

        init(
            id: String,
            tokenID: String,
            tokenType: String?,
            accountAddressRawValue: String,
            chain: Chain,
            contractAddressRawValue: String?,
            name: String?,
            artistName: String?,
            collectionName: String?,
            collectionDisplayName: String?,
            thumbnailURLString: String?,
            originalImageURLString: String?,
            playbackURLString: String?,
            contentType: String?,
            sourceUpdatedAtRawValue: String?
        ) {
            self.id = id
            self.tokenID = tokenID
            self.tokenType = tokenType
            self.accountAddressRawValue = accountAddressRawValue
            self.chain = chain
            self.contractAddressRawValue = contractAddressRawValue
            self.name = name
            self.artistName = artistName
            self.collectionName = collectionName
            self.collectionDisplayName = collectionDisplayName
            self.thumbnailURLString = thumbnailURLString
            self.originalImageURLString = originalImageURLString
            self.playbackURLString = playbackURLString
            self.contentType = contentType
            self.sourceUpdatedAtRawValue = sourceUpdatedAtRawValue
        }

        init(nft: NFT) {
            self.id = nft.id
            self.tokenID = nft.tokenId
            self.tokenType = nft.tokenType
            self.accountAddressRawValue = nft.accountAddressRawValue
            self.chain = nft.network ?? .ethMainnet
            self.contractAddressRawValue = nft.contract.address
            self.name = nft.name
            self.artistName = nft.artistName
            self.collectionName = nft.collectionName
            self.collectionDisplayName = nft.collection?.name
            self.thumbnailURLString = nft.image?.thumbnailUrl
            self.originalImageURLString = nft.image?.originalUrl
            self.playbackURLString = nft.musicURL?.absoluteString
            self.contentType = nft.contentType
            self.sourceUpdatedAtRawValue = nft.timeLastUpdated
        }
    }

    func makeRequestBundle(
        from snapshots: [SourceNFTSnapshot],
        walletID: String
    ) async -> RequestBundle {
        await Task.detached(priority: .userInitiated) {
            let dedupedSnapshots = Dictionary(uniqueKeysWithValues: snapshots.map { ($0.id, $0) })
                .values
                .sorted { $0.id < $1.id }

            let tokenRequests = dedupedSnapshots.map { makeTokenRequest(from: $0, walletID: walletID) }
            let mediaItemRequests = dedupedSnapshots.map { makeMediaItemRequest(from: $0, walletID: walletID) }

            return RequestBundle(
                tokenRequests: tokenRequests,
                mediaItemRequests: mediaItemRequests
            )
        }.value
    }

    private func makeTokenRequest(
        from snapshot: SourceNFTSnapshot,
        walletID: String
    ) -> AuraPlayNFTTokenUpsertRequest {
        let contractAddress = NFT.normalizedScopeComponent(snapshot.contractAddressRawValue) ?? "__missing_contract__"

        return AuraPlayNFTTokenUpsertRequest(
            walletID: walletID,
            sourceNFTID: snapshot.id,
            contractAddressRawValue: contractAddress,
            tokenID: snapshot.tokenID,
            tokenType: snapshot.tokenType,
            title: cleanedText(snapshot.name) ?? "Unknown Track",
            artistName: cleanedText(snapshot.artistName),
            collectionName: cleanedText(snapshot.collectionName ?? snapshot.collectionDisplayName),
            artworkURLString: artworkURLString(from: snapshot),
            playbackURLString: cleanedText(snapshot.playbackURLString),
            contentType: cleanedText(snapshot.contentType),
            sourceUpdatedAtRawValue: cleanedText(snapshot.sourceUpdatedAtRawValue)
        )
    }

    private func makeMediaItemRequest(
        from snapshot: SourceNFTSnapshot,
        walletID: String
    ) -> AuraPlayMediaItemUpsertRequest {
        let title = cleanedText(snapshot.name) ?? "Unknown Track"
        let artistName = cleanedText(snapshot.artistName)
        let collectionName = cleanedText(snapshot.collectionName ?? snapshot.collectionDisplayName)
        let playbackURLString = cleanedText(snapshot.playbackURLString)
        let artworkURLString = artworkURLString(from: snapshot)
        let contractAddress = NFT.normalizedScopeComponent(snapshot.contractAddressRawValue) ?? "__missing_contract__"
        let tokenCompositeID = AuraPlayNFTToken.makeCompositeID(
            walletID: walletID,
            contractAddressRawValue: contractAddress,
            tokenID: snapshot.tokenID
        )

        return AuraPlayMediaItemUpsertRequest(
            walletID: walletID,
            tokenCompositeID: tokenCompositeID,
            sourceNFTID: snapshot.id,
            accountAddressRawValue: snapshot.accountAddressRawValue,
            chain: snapshot.chain,
            title: title,
            artistName: artistName,
            collectionName: collectionName,
            normalizedTitleKey: normalizedKey(title),
            normalizedArtistKey: normalizedKey(artistName),
            normalizedCollectionKey: normalizedKey(collectionName),
            artworkURLString: artworkURLString,
            playbackURLString: playbackURLString,
            contentType: cleanedText(snapshot.contentType),
            sourceUpdatedAtRawValue: cleanedText(snapshot.sourceUpdatedAtRawValue),
            hasArtwork: artworkURLString != nil,
            hasAudio: playbackURLString != nil,
            isPlayable: playbackURLString != nil,
            isSearchable: true
        )
    }

    private func artworkURLString(from snapshot: SourceNFTSnapshot) -> String? {
        [snapshot.thumbnailURLString, snapshot.originalImageURLString]
            .compactMap { (rawValue: String?) -> String? in
                guard let rawValue else {
                    return nil
                }
                return URL.sanitizedRemoteMediaURL(from: rawValue)?.absoluteString
            }
            .first
    }

    private func cleanedText(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }

    private func normalizedKey(_ value: String?) -> String {
        cleanedText(value)?
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .lowercased() ?? ""
    }
}
