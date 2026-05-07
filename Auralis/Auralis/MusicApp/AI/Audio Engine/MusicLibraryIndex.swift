import AuralisPrimaryModels
import Foundation
import SwiftData

struct MusicLibraryIndexRebuildResult: Equatable, Sendable {
    let scannedCount: Int
    let writtenCount: Int
    let removedCount: Int
}

@MainActor
protocol MusicLibraryIndexing {
    func itemCount(accountAddress: String?, chain: Chain) throws -> Int
    func needsRebuild(accountAddress: String?, chain: Chain) async throws -> Bool
    func rebuildIndex(
        accountAddress: String?,
        chain: Chain,
        correlationID: String?,
        receiptEventLogger: ReceiptEventLogger?
    ) async throws -> MusicLibraryIndexRebuildResult
}

@ModelActor
private actor MusicLibraryIndexPersistenceStore {
    func needsRebuild(accountAddress: String?, chain: Chain) throws -> Bool {
        let sourceNFTs = try fetchEligibleNFTs(accountAddress: accountAddress, chain: chain)
        let existingItems = try fetchScopedItems(accountAddress: accountAddress, chain: chain)

        if sourceNFTs.count != existingItems.count {
            return true
        }

        let existingBySourceID = Dictionary(uniqueKeysWithValues: existingItems.map { ($0.sourceNFTID, $0) })

        for nft in sourceNFTs {
            let descriptor = makeDescriptor(from: nft)
            guard let existingItem = existingBySourceID[nft.id] else {
                return true
            }

            if !matches(existingItem: existingItem, descriptor: descriptor) {
                return true
            }
        }

        return false
    }

    func rebuildIndex(
        accountAddress: String?,
        chain: Chain,
        correlationID: String?,
        receiptEventLogger: ReceiptEventLogger?
    ) async throws -> MusicLibraryIndexRebuildResult {
        let scopedAccountAddress = NFT.normalizedScopeComponent(accountAddress) ?? ""
        if let receiptEventLogger {
            _ = try? await receiptEventLogger.recordMusicLibraryIndexStarted(
                accountAddress: scopedAccountAddress,
                chain: chain,
                correlationID: correlationID
            )
        }

        do {
            let sourceNFTs = try fetchEligibleNFTs(accountAddress: accountAddress, chain: chain)
            let existingItems = try fetchScopedItems(accountAddress: accountAddress, chain: chain)
            let existingBySourceID = Dictionary(uniqueKeysWithValues: existingItems.map { ($0.sourceNFTID, $0) })
            let indexedAt = Date()

            var retainedSourceIDs = Set<String>()
            var writtenCount = 0

            for nft in sourceNFTs.sorted(by: { $0.id < $1.id }) {
                let descriptor = makeDescriptor(from: nft)
                retainedSourceIDs.insert(descriptor.sourceNFTID)

                if let existingItem = existingBySourceID[descriptor.sourceNFTID] {
                    if !matches(existingItem: existingItem, descriptor: descriptor) {
                        existingItem.apply(descriptor, indexedAt: indexedAt)
                        writtenCount += 1
                    }
                } else {
                    modelContext.insert(
                        MusicLibraryItem(
                            id: descriptor.id,
                            sourceNFTID: descriptor.sourceNFTID,
                            accountAddressRawValue: descriptor.accountAddressRawValue,
                            networkRawValue: descriptor.networkRawValue,
                            title: descriptor.title,
                            artistName: descriptor.artistName,
                            collectionName: descriptor.collectionName,
                            normalizedTitleKey: descriptor.normalizedTitleKey,
                            normalizedArtistKey: descriptor.normalizedArtistKey,
                            normalizedCollectionKey: descriptor.normalizedCollectionKey,
                            artworkURLString: descriptor.artworkURLString,
                            contentType: descriptor.contentType,
                            playbackURLString: descriptor.playbackURLString,
                            availability: descriptor.availability,
                            availabilityReason: descriptor.availabilityReason,
                            sourceUpdatedAtRawValue: descriptor.sourceUpdatedAtRawValue,
                            indexedAt: indexedAt
                        )
                    )
                    writtenCount += 1
                }
            }

            let staleItems = existingItems.filter { !retainedSourceIDs.contains($0.sourceNFTID) }
            for staleItem in staleItems {
                modelContext.delete(staleItem)
            }

            if writtenCount > 0 || !staleItems.isEmpty {
                try modelContext.save()
            }

            let result = MusicLibraryIndexRebuildResult(
                scannedCount: sourceNFTs.count,
                writtenCount: writtenCount,
                removedCount: staleItems.count
            )

            if let receiptEventLogger {
                _ = try? await receiptEventLogger.recordMusicLibraryIndexCompleted(
                    accountAddress: scopedAccountAddress,
                    chain: chain,
                    correlationID: correlationID,
                    scannedCount: result.scannedCount,
                    writtenCount: result.writtenCount,
                    removedCount: result.removedCount
                )
            }

            return result
        } catch {
            modelContext.rollback()
            if let receiptEventLogger {
                _ = try? await receiptEventLogger.recordMusicLibraryIndexFailed(
                    accountAddress: scopedAccountAddress,
                    chain: chain,
                    correlationID: correlationID,
                    error: error
                )
            }
            throw error
        }
    }
}

@MainActor
final class SwiftDataMusicLibraryIndexer: MusicLibraryIndexing {
    private let modelContext: ModelContext
    private let persistenceStore: MusicLibraryIndexPersistenceStore

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
        self.persistenceStore = MusicLibraryIndexPersistenceStore(modelContainer: modelContext.container)
    }

    func itemCount(accountAddress: String?, chain: Chain) throws -> Int {
        let normalizedAccountAddress = NFT.normalizedScopeComponent(accountAddress) ?? ""
        let chainRawValue = chain.rawValue
        let descriptor = FetchDescriptor<MusicLibraryItem>(
            predicate: #Predicate<MusicLibraryItem> {
                $0.accountAddressRawValue == normalizedAccountAddress &&
                $0.networkRawValue == chainRawValue
            }
        )
        return try modelContext.fetchCount(descriptor)
    }

    func needsRebuild(accountAddress: String?, chain: Chain) async throws -> Bool {
        try await persistenceStore.needsRebuild(
            accountAddress: accountAddress,
            chain: chain
        )
    }

    func rebuildIndex(
        accountAddress: String?,
        chain: Chain,
        correlationID: String?,
        receiptEventLogger: ReceiptEventLogger?
    ) async throws -> MusicLibraryIndexRebuildResult {
        try await persistenceStore.rebuildIndex(
            accountAddress: accountAddress,
            chain: chain,
            correlationID: correlationID,
            receiptEventLogger: receiptEventLogger
        )
    }
}

private extension MusicLibraryIndexPersistenceStore {
    func fetchEligibleNFTs(accountAddress: String?, chain: Chain) throws -> [NFT] {
        let normalizedAccountAddress = NFT.normalizedScopeComponent(accountAddress) ?? ""
        let chainRawValue = chain.rawValue

        var descriptor = FetchDescriptor<NFT>(
            predicate: #Predicate<NFT> {
                $0.accountAddressRawValue == normalizedAccountAddress &&
                $0.networkRawValue == chainRawValue &&
                $0.audioUrl != nil &&
                $0.audioUrl != ""
            },
            sortBy: [SortDescriptor(\NFT.id)]
        )
        descriptor.relationshipKeyPathsForPrefetching = [
            \NFT.contract,
            \NFT.image,
            \NFT.collection,
        ]

        let eligibleNFTs = try modelContext.fetch(descriptor)
        let dedupedByID = Dictionary(uniqueKeysWithValues: eligibleNFTs.map { ($0.id, $0) })
        return dedupedByID.values.sorted { $0.id < $1.id }
    }

    func fetchScopedItems(accountAddress: String?, chain: Chain) throws -> [MusicLibraryItem] {
        try modelContext.fetch(scopedItemsDescriptor(accountAddress: accountAddress, chain: chain))
    }

    func scopedItemsDescriptor(accountAddress: String?, chain: Chain) -> FetchDescriptor<MusicLibraryItem> {
        let normalizedAccountAddress = NFT.normalizedScopeComponent(accountAddress) ?? ""
        let chainRawValue = chain.rawValue

        return FetchDescriptor<MusicLibraryItem>(
            predicate: #Predicate<MusicLibraryItem> {
                $0.accountAddressRawValue == normalizedAccountAddress &&
                $0.networkRawValue == chainRawValue
            }
        )
    }

    func makeDescriptor(from nft: NFT) -> MusicLibraryItemDescriptor {
        let title = cleanedText(nft.name) ?? "Unknown Track"
        let artistName = cleanedText(nft.artistName)
        let collectionName = cleanedText(nft.collectionName ?? nft.collection?.name)
        let playbackURLString = nft.musicURL?.absoluteString
        let availability: MusicLibraryAvailability = playbackURLString == nil ? .unavailable : .ready
        let artworkCandidates: [String?] = [nft.image?.thumbnailUrl, nft.image?.originalUrl]
        let artworkURLString = artworkCandidates
            .compactMap { rawValue -> String? in
                guard let rawValue else {
                    return nil
                }

                return URL.sanitizedRemoteMediaURL(from: rawValue)?.absoluteString
            }
            .first

        return MusicLibraryItemDescriptor(
            id: nft.id,
            sourceNFTID: nft.id,
            accountAddressRawValue: nft.accountAddressRawValue,
            networkRawValue: nft.networkRawValue,
            title: title,
            artistName: artistName,
            collectionName: collectionName,
            normalizedTitleKey: normalizedKey(title),
            normalizedArtistKey: normalizedKey(artistName),
            normalizedCollectionKey: normalizedKey(collectionName),
            artworkURLString: artworkURLString,
            contentType: cleanedText(nft.contentType),
            playbackURLString: playbackURLString,
            availability: availability,
            availabilityReason: availability == .ready ? nil : "audio_url_unavailable",
            sourceUpdatedAtRawValue: cleanedText(nft.timeLastUpdated)
        )
    }

    func matches(existingItem: MusicLibraryItem, descriptor: MusicLibraryItemDescriptor) -> Bool {
        existingItem.id == descriptor.id &&
        existingItem.sourceNFTID == descriptor.sourceNFTID &&
        existingItem.accountAddressRawValue == descriptor.accountAddressRawValue &&
        existingItem.networkRawValue == descriptor.networkRawValue &&
        existingItem.title == descriptor.title &&
        existingItem.artistName == descriptor.artistName &&
        existingItem.collectionName == descriptor.collectionName &&
        existingItem.normalizedTitleKey == descriptor.normalizedTitleKey &&
        existingItem.normalizedArtistKey == descriptor.normalizedArtistKey &&
        existingItem.normalizedCollectionKey == descriptor.normalizedCollectionKey &&
        existingItem.artworkURLString == descriptor.artworkURLString &&
        existingItem.contentType == descriptor.contentType &&
        existingItem.playbackURLString == descriptor.playbackURLString &&
        existingItem.availability == descriptor.availability &&
        existingItem.availabilityReason == descriptor.availabilityReason &&
        existingItem.sourceUpdatedAtRawValue == descriptor.sourceUpdatedAtRawValue
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
