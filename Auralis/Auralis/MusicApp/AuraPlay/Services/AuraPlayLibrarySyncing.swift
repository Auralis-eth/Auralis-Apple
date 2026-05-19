import ReceiptsCore
import AuralisPrimaryModels
import AuralisPrimaryPersistence
import Foundation
import MusicFeature
import SwiftData

@MainActor
struct LiveAuraPlayLibrarySyncService: AuraPlayLibrarySyncing {
    private let sourceSnapshotStore: AuraPlaySourceNFTSnapshotStore
    private let accountSyncStateService: AuraPlayAccountSyncStateService
    private let mediaItemService: AuraPlayMediaItemService
    private let requestBuilder: AuraPlayLibrarySyncRequestBuilder
    private let musicReceiptLogger: MusicReceiptEventLogger
    private let logger: any AuraPlayLogging

    init(
        sourceModelContext: ModelContext,
        auraPlayModelContainer: ModelContainer,
        musicReceiptLogger: MusicReceiptEventLogger,
        logger: any AuraPlayLogging,
        requestBuilder: AuraPlayLibrarySyncRequestBuilder = .init()
    ) {
        self.sourceSnapshotStore = AuraPlaySourceNFTSnapshotStore(modelContainer: sourceModelContext.container)
        self.accountSyncStateService = AuraPlayAccountSyncStateService(modelContainer: sourceModelContext.container)
        self.mediaItemService = AuraPlayMediaItemService(modelContainer: auraPlayModelContainer)
        self.requestBuilder = requestBuilder
        self.musicReceiptLogger = musicReceiptLogger
        self.logger = logger
    }

    func syncLibrary(in scope: AuraPlayLibraryScope, accountName: String?) async throws {
        guard let normalizedAccountAddress = NFT.normalizedScopeComponent(scope.accountAddress) else {
            return
        }

        let syncedAt = Date()
        let correlationID = UUID().uuidString
        let receiptContext = MusicReceiptContext(
            triggerCause: .systemSync,
            actor: .system,
            accountAddress: normalizedAccountAddress,
            chain: scope.chain,
            correlationID: correlationID,
            surface: "music.library.sync"
        )
        let sourceSnapshots = try await sourceSnapshotStore.fetchEligibleNFTSnapshots(
            accountAddress: normalizedAccountAddress,
            chain: scope.chain
        )
        try await accountSyncStateService.markSynced(
            AuraPlayAccountSyncUpdateRequest(
                address: normalizedAccountAddress,
                chain: scope.chain,
                displayName: accountName,
                syncedAt: syncedAt
            )
        )
        let requestBundle = await requestBuilder.makeRequestBundle(
            from: sourceSnapshots
        )
        let affectedMediaIDs = requestBundle.mediaItemRequests.map(\.sourceNFTID).sorted()

        try await mediaItemService.replaceAll(
            accountAddress: normalizedAccountAddress,
            chain: scope.chain,
            requests: requestBundle.mediaItemRequests,
            syncedAt: syncedAt
        )

        if !affectedMediaIDs.isEmpty {
            _ = try? await musicReceiptLogger.recordMediaClassified(
                affectedMediaIDs: affectedMediaIDs,
                beforeSummary: nil,
                afterSummary: .classification(
                    totalCount: requestBundle.mediaItemRequests.count,
                    playableCount: requestBundle.mediaItemRequests.filter(\.isPlayable).count,
                    metadataOnlyCount: requestBundle.mediaItemRequests.filter { !$0.isPlayable }.count,
                    artworkCount: requestBundle.mediaItemRequests.filter(\.hasArtwork).count
                ),
                context: receiptContext
            )
        }

        let metadataOverrideDelta = metadataOverrideDelta(
            sourceSnapshots: sourceSnapshots,
            mediaItemRequests: requestBundle.mediaItemRequests
        )
        if !metadataOverrideDelta.affectedMediaIDs.isEmpty {
            _ = try? await musicReceiptLogger.recordMetadataOverrideApplied(
                affectedMediaIDs: metadataOverrideDelta.affectedMediaIDs,
                beforeSummary: metadataOverrideDelta.beforeSummary,
                afterSummary: metadataOverrideDelta.afterSummary,
                reason: "AuraPlay normalized sparse source metadata while projecting account-scoped media into the local music library.",
                context: receiptContext
            )
        }

        _ = try? await musicReceiptLogger.recordExportCreated(
            exportName: "aura_play_account_projection",
            format: "swiftdata_projection",
            affectedMediaIDs: affectedMediaIDs,
            itemCount: requestBundle.mediaItemRequests.count,
            context: receiptContext
        )
        _ = try? await musicReceiptLogger.recordBackgroundMusicTaskRun(
            taskName: "library_sync",
            affectedMediaIDs: affectedMediaIDs,
            beforeSummary: .task(
                name: "library_sync",
                inputCount: sourceSnapshots.count,
                outputCount: 0
            ),
            afterSummary: .task(
                name: "library_sync",
                inputCount: sourceSnapshots.count,
                outputCount: requestBundle.mediaItemRequests.count
            ),
            context: receiptContext
        )

        logger.log(
            AuraPlayLogEvent(
                category: .library,
                level: .info,
                message: "AuraPlay synced \(requestBundle.mediaItemRequests.count) persisted media items for \(normalizedAccountAddress):\(scope.chain.rawValue)"
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

private extension LiveAuraPlayLibrarySyncService {
    struct MetadataOverrideDelta {
        let affectedMediaIDs: [String]
        let beforeSummary: MusicReceiptStateSummary
        let afterSummary: MusicReceiptStateSummary
    }

    func metadataOverrideDelta(
        sourceSnapshots: [SourceNFTSnapshot],
        mediaItemRequests: [AuraPlayMediaItemUpsertRequest]
    ) -> MetadataOverrideDelta {
        let snapshotsByID = Dictionary(uniqueKeysWithValues: sourceSnapshots.map { ($0.id, $0) })
        var affectedMediaIDs: [String] = []
        var titleOverrideCount = 0
        var artistOverrideCount = 0
        var collectionOverrideCount = 0

        for request in mediaItemRequests {
            guard let sourceSnapshot = snapshotsByID[request.sourceNFTID] else {
                continue
            }

            let sourceTitle = normalizedSourceText(sourceSnapshot.name)
            let sourceArtist = normalizedSourceText(sourceSnapshot.artistName)
            let sourceCollection = normalizedSourceText(sourceSnapshot.collectionName)
            let projectedCollection = normalizedSourceText(sourceSnapshot.collectionName ?? sourceSnapshot.collectionDisplayName)

            var didOverride = false

            if sourceTitle == nil && request.title == "Unknown Track" {
                titleOverrideCount += 1
                didOverride = true
            }

            if request.artistName != sourceArtist {
                artistOverrideCount += 1
                didOverride = true
            }

            if request.collectionName != projectedCollection || projectedCollection != sourceCollection {
                collectionOverrideCount += 1
                didOverride = true
            }

            if didOverride {
                affectedMediaIDs.append(request.sourceNFTID)
            }
        }

        let sortedAffectedMediaIDs = Array(Set(affectedMediaIDs)).sorted()
        let overrideCount = titleOverrideCount + artistOverrideCount + collectionOverrideCount

        return MetadataOverrideDelta(
            affectedMediaIDs: sortedAffectedMediaIDs,
            beforeSummary: MusicReceiptStateSummary(
                values: [
                    "titleOverrideCount": .number(0),
                    "artistOverrideCount": .number(0),
                    "collectionOverrideCount": .number(0),
                    "overrideCount": .number(0),
                    "affectedItemCount": .number(Double(sortedAffectedMediaIDs.count))
                ]
            ),
            afterSummary: MusicReceiptStateSummary(
                values: [
                    "titleOverrideCount": .number(Double(titleOverrideCount)),
                    "artistOverrideCount": .number(Double(artistOverrideCount)),
                    "collectionOverrideCount": .number(Double(collectionOverrideCount)),
                    "overrideCount": .number(Double(overrideCount)),
                    "affectedItemCount": .number(Double(sortedAffectedMediaIDs.count))
                ]
            )
        )
    }

    func normalizedSourceText(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }
}

struct AuraPlayLibrarySyncRequestBuilder: Sendable {
    struct RequestBundle: Sendable {
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
        from snapshots: [SourceNFTSnapshot]
    ) async -> RequestBundle {
        await Task.detached(priority: .userInitiated) {
            let dedupedSnapshots = Dictionary(snapshots.map { ($0.id, $0) }) { _, latest in
                latest
            }
                .values
                .sorted { $0.id < $1.id }

            let mediaItemRequests = dedupedSnapshots.map(makeMediaItemRequest(from:))

            return RequestBundle(
                mediaItemRequests: mediaItemRequests
            )
        }.value
    }

    private func makeMediaItemRequest(
        from snapshot: SourceNFTSnapshot
    ) -> AuraPlayMediaItemUpsertRequest {
        let title = cleanedText(snapshot.name) ?? "Unknown Track"
        let artistName = cleanedText(snapshot.artistName)
        let collectionName = cleanedText(snapshot.collectionName ?? snapshot.collectionDisplayName)
        let playbackURLString = cleanedText(snapshot.playbackURLString)
        let artworkURLString = artworkURLString(from: snapshot)
        let contractAddress = NFT.normalizedScopeComponent(snapshot.contractAddressRawValue)

        return AuraPlayMediaItemUpsertRequest(
            sourceNFTID: snapshot.id,
            accountAddressRawValue: snapshot.accountAddressRawValue,
            chain: snapshot.chain,
            contractAddressRawValue: contractAddress,
            tokenID: snapshot.tokenID,
            tokenType: snapshot.tokenType,
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
