import AuralisPrimaryModels
import Foundation
import SwiftData

@ModelActor
public actor AuraPlayMediaItemService {
    public func replaceAll(
        accountAddress: String,
        chain: Chain,
        requests: [AuraPlayMediaItemUpsertRequest],
        syncedAt: Date
    ) throws {
        let existingItems = try fetchScopedItems(accountAddress: accountAddress, chain: chain)
        var existingByID = Dictionary(uniqueKeysWithValues: existingItems.map { ($0.id, $0) })
        var retainedIDs: Set<String> = []

        for request in requests {
            retainedIDs.insert(request.sourceNFTID)

            let item = existingByID[request.sourceNFTID] ?? {
                let newItem = AuraPlayMediaItem(
                    sourceNFTID: request.sourceNFTID,
                    accountAddressRawValue: request.accountAddressRawValue,
                    chain: request.chain,
                    contractAddressRawValue: request.contractAddressRawValue,
                    tokenID: request.tokenID,
                    tokenType: request.tokenType,
                    title: request.title,
                    artistName: request.artistName,
                    creatorIdentifierRawValue: request.creatorIdentifierRawValue ?? Self.creatorIdentifier(from: request),
                    collectionName: request.collectionName,
                    normalizedTitleKey: request.normalizedTitleKey,
                    normalizedArtistKey: request.normalizedArtistKey,
                    normalizedCollectionKey: request.normalizedCollectionKey,
                    artworkURLString: request.artworkURLString,
                    playbackURLString: request.playbackURLString,
                    durationSeconds: request.durationSeconds,
                    contentType: request.contentType,
                    sourceUpdatedAtRawValue: request.sourceUpdatedAtRawValue,
                    hasArtwork: request.hasArtwork,
                    hasAudio: request.hasAudio,
                    hasVideo: request.hasVideo,
                    isPlayable: request.isPlayable,
                    isSearchable: request.isSearchable,
                    createdAt: syncedAt,
                    updatedAt: syncedAt
                )
                modelContext.insert(newItem)
                existingByID[request.sourceNFTID] = newItem
                return newItem
            }()

            item.accountAddressRawValue = request.accountAddressRawValue
            item.chain = request.chain
            item.contractAddressRawValue = request.contractAddressRawValue
            item.tokenID = request.tokenID
            item.tokenType = request.tokenType
            item.title = request.title
            item.artistName = request.artistName
            item.creatorIdentifierRawValue = request.creatorIdentifierRawValue ?? Self.creatorIdentifier(from: request)
            item.collectionName = request.collectionName
            item.normalizedTitleKey = request.normalizedTitleKey
            item.normalizedArtistKey = request.normalizedArtistKey
            item.normalizedCollectionKey = request.normalizedCollectionKey
            item.artworkURLString = request.artworkURLString
            item.playbackURLString = request.playbackURLString
            item.durationSeconds = request.durationSeconds.map { max(0, $0) }
            item.contentType = request.contentType
            item.sourceUpdatedAtRawValue = request.sourceUpdatedAtRawValue
            item.hasArtwork = request.hasArtwork
            item.hasAudio = request.hasAudio
            item.hasVideo = request.hasVideo
            item.isPlayable = request.isPlayable
            item.isSearchable = request.isSearchable
            item.updatedAt = syncedAt
        }

        for item in existingItems where !retainedIDs.contains(item.id) {
            try capturePlaybackTombstoneIfNeeded(for: item, capturedAt: syncedAt)
            modelContext.delete(item)
        }
        try restorePlaybackTombstonesIfPossible(at: syncedAt)

        try modelContext.save()
    }

    public func updatePlaybackCacheState(
        sourceNFTID: String,
        cachedFileStateRawValue: String? = nil,
        approxLoudnessLUFS: Double? = nil,
        updatedAt: Date = .now
    ) throws {
        guard let item = try fetchItem(sourceNFTID: sourceNFTID) else {
            return
        }

        if let cachedFileStateRawValue {
            item.cachedFileStateRawValue = cachedFileStateRawValue
        }
        if let approxLoudnessLUFS {
            item.approxLoudnessLUFS = approxLoudnessLUFS
        }
        item.updatedAt = updatedAt

        try modelContext.save()
    }

    public func fetchPlayable(accountAddress: String? = nil, chain: Chain? = nil) throws -> [AuraPlayMediaItem] {
        let descriptor: FetchDescriptor<AuraPlayMediaItem>
        if let accountAddress, let chain {
            let chainRawValue = chain.rawValue
            descriptor = FetchDescriptor<AuraPlayMediaItem>(
                predicate: #Predicate<AuraPlayMediaItem> { item in
                    item.accountAddressRawValue == accountAddress &&
                    item.chainRawValue == chainRawValue &&
                    item.isPlayable
                },
                sortBy: [SortDescriptor(\.title), SortDescriptor(\.sourceNFTID)]
            )
        } else {
            descriptor = FetchDescriptor<AuraPlayMediaItem>(
                predicate: #Predicate<AuraPlayMediaItem> { item in
                    item.isPlayable
                },
                sortBy: [SortDescriptor(\.title), SortDescriptor(\.sourceNFTID)]
            )
        }
        return try modelContext.fetch(descriptor)
    }

    public func fetchSorted(context: MediaItemQueryContext) throws -> MediaItemQueryResult {
        try fetchWindow(context: context)
    }

    public func fetchWindow(context: MediaItemQueryContext) throws -> MediaItemQueryResult {
        let scopedItems = try fetchScopedItems(context: context)
        let filteredItems = scopedItems.filter { item in
            if !context.filter.selectedChains.isEmpty, !context.filter.selectedChains.contains(item.chain) {
                return false
            }
            if !context.filter.includeNonPlayable, !item.isPlayable { return false }
            if context.filter.unplayedOnly, item.lastPlayedAt != nil {
                return false
            }
            switch context.filter.mediaType {
            case .all:
                return true
            case .audio:
                return item.hasAudio
            case .video:
                return item.hasVideo
            }
        }
        let sortedItems = Self.sort(filteredItems, by: context.sort)
        let start = min(max(0, context.offset), sortedItems.count)
        let end = min(sortedItems.count, start + max(1, context.limit))
        let window = sortedItems[start..<end].map(MediaItemQueryItem.init)
        let nextOffset = end < sortedItems.count ? end : nil

        return MediaItemQueryResult(
            items: window,
            totalCount: sortedItems.count,
            nextOffset: nextOffset
        )
    }

    public func fetchGroupedIndex(scope: AuraPlayLibraryScope) throws -> AuraPlayGroupedLibraryIndex {
        // Single scoped fetch, reduced to distinct groups; callers cache the result
        // and invalidate on sync completion (SwiftData has no GROUP BY).
        let context = MediaItemQueryContext(scope: scope)
        let playableItems = try fetchScopedItems(context: context).filter(\.isPlayable)

        var collectionBuckets: [String: [AuraPlayMediaItem]] = [:]
        var creatorBuckets: [String: [AuraPlayMediaItem]] = [:]
        for item in playableItems {
            collectionBuckets[Self.collectionGroupID(for: item), default: []].append(item)
            creatorBuckets[Self.creatorGroupID(for: item), default: []].append(item)
        }

        let collections = collectionBuckets.map { id, items in
            let first = items[0]
            return LibraryCollectionGroup(
                id: id,
                collectionName: first.collectionName?.isEmpty == false
                    ? first.collectionName ?? "Untitled Collection"
                    : "Untitled Collection",
                contractAddress: first.contractAddressRawValue,
                chain: first.chain,
                itemCount: items.count,
                artworkURLStrings: Array(items.compactMap(\.artworkURLString).prefix(4))
            )
        }
        .sorted { $0.collectionName.localizedCaseInsensitiveCompare($1.collectionName) == .orderedAscending }

        let creators = creatorBuckets.map { id, items in
            let first = items[0]
            return LibraryCreatorGroup(
                id: id,
                displayName: first.artistName?.isEmpty == false
                    ? first.artistName ?? "Unknown Creator"
                    : "Unknown Creator",
                itemCount: items.count,
                artworkURLStrings: Array(items.compactMap(\.artworkURLString).prefix(4))
            )
        }
        .sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }

        return AuraPlayGroupedLibraryIndex(scope: scope, collections: collections, creators: creators)
    }

    public func fetchGroupItems(
        scope: AuraPlayLibraryScope,
        group: LibraryGroupKey,
        sort: MediaItemSort
    ) throws -> [MediaItemQueryItem] {
        let context = MediaItemQueryContext(scope: scope)
        let playableItems = try fetchScopedItems(context: context).filter(\.isPlayable)
        let matching = playableItems.filter { item in
            switch group {
            case .collection(let id):
                Self.collectionGroupID(for: item) == id
            case .creator(let id):
                Self.creatorGroupID(for: item) == id
            }
        }
        return Self.sort(matching, by: sort).map(MediaItemQueryItem.init)
    }

    public func fetchItems(scope: AuraPlayLibraryScope, ids: [String]) throws -> [MediaItemQueryItem] {
        let context = MediaItemQueryContext(scope: scope)
        let scoped = try fetchScopedItems(context: context)
        let requested = Set(ids)
        return scoped
            .filter { requested.contains($0.sourceNFTID) || requested.contains($0.id) }
            .map(MediaItemQueryItem.init)
    }

    public func fetchCreatorProfile(
        creatorIdentifier: String,
        accountAddresses: [String],
        chains: Set<Chain>?,
        sort: MediaItemSort
    ) async throws -> AuraPlayCreatorProfile? {
        let normalizedAccounts = Set(
            accountAddresses.compactMap { NFTTokenDTO.normalizedScopeComponent($0) ?? Self.nonEmpty($0) }
        )
        guard !normalizedAccounts.isEmpty else { return nil }

        let chainRawValues = chains.map { Set($0.map(\.rawValue)) }
        // Bound the fetch to the connected accounts and playable rows in SwiftData
        // instead of loading the whole media table; the creator-identity match is a
        // computed key, so it stays an in-memory filter over this scoped result.
        let descriptor = FetchDescriptor<AuraPlayMediaItem>(
            predicate: #Predicate<AuraPlayMediaItem> { item in
                normalizedAccounts.contains(item.accountAddressRawValue) && item.isPlayable
            }
        )
        let matching = try modelContext.fetch(descriptor).filter { item in
            if let chainRawValues, !chainRawValues.contains(item.chainRawValue) {
                return false
            }
            return Self.creatorGroupID(for: item) == creatorIdentifier
        }

        guard let first = matching.first else { return nil }
        let sorted = Self.sort(matching, by: sort).map(MediaItemQueryItem.init)
        let displayName = Self.nonEmpty(first.artistName) ?? "Unknown Creator"
        return AuraPlayCreatorProfile(id: creatorIdentifier, displayName: displayName, items: sorted)
    }

    static func collectionGroupID(for item: AuraPlayMediaItem) -> String {
        "\(item.chainRawValue)|\(item.contractAddressRawValue ?? item.normalizedCollectionKey)"
    }

    static func creatorGroupID(for item: AuraPlayMediaItem) -> String {
        item.creatorIdentifierRawValue ?? item.normalizedArtistKey
    }

    private func fetchScopedItems(accountAddress: String, chain: Chain) throws -> [AuraPlayMediaItem] {
        let chainRawValue = chain.rawValue
        let descriptor = FetchDescriptor<AuraPlayMediaItem>(
            predicate: #Predicate<AuraPlayMediaItem> { item in
                item.accountAddressRawValue == accountAddress &&
                item.chainRawValue == chainRawValue
            }
        )
        return try modelContext.fetch(descriptor)
    }

    private func fetchItem(sourceNFTID: String) throws -> AuraPlayMediaItem? {
        var descriptor = FetchDescriptor<AuraPlayMediaItem>(
            predicate: #Predicate<AuraPlayMediaItem> { item in
                item.sourceNFTID == sourceNFTID
            }
        )
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first
    }

    private func capturePlaybackTombstoneIfNeeded(for item: AuraPlayMediaItem, capturedAt: Date) throws {
        guard let state = try fetchPlaybackState(mediaID: item.sourceNFTID) else { return }
        let snapshot = AuraPlayPlaybackPositionStateSnapshot(
            mediaID: state.mediaID,
            positionMilliseconds: state.positionMilliseconds,
            durationMilliseconds: state.durationMilliseconds,
            lastPlayedAt: state.lastPlayedAt,
            completedAt: state.completedAt
        )
        guard snapshot.isResumable else { return }

        let tombstone = AuraPlayPlaybackPositionTombstone(
            originalMediaID: item.sourceNFTID,
            accountAddressRawValue: item.accountAddressRawValue,
            chainRawValue: item.chainRawValue,
            contractAddressRawValue: item.contractAddressRawValue,
            tokenID: item.tokenID,
            positionMilliseconds: snapshot.positionMilliseconds,
            durationMilliseconds: snapshot.durationMilliseconds,
            lastPlayedAt: snapshot.lastPlayedAt,
            completedAt: snapshot.completedAt,
            playCount: state.playCount,
            capturedAt: capturedAt
        )
        modelContext.insert(tombstone)

        // The tombstone now owns this position. Delete the source state row so it
        // does not linger as an orphan after the media item is removed; resume is
        // driven exclusively by `restorePlaybackTombstonesIfPossible` when the
        // token returns.
        modelContext.delete(state)
    }

    private func restorePlaybackTombstonesIfPossible(at date: Date) throws {
        let cutoff = AuraPlayPersistentHistoryTombstonePolicy.recencyCutoff(before: date)
        let tombstones = try modelContext.fetch(
            FetchDescriptor<AuraPlayPlaybackPositionTombstone>(
                predicate: #Predicate<AuraPlayPlaybackPositionTombstone> { tombstone in
                    tombstone.consumedAt == nil && tombstone.lastPlayedAt >= cutoff
                },
                sortBy: [SortDescriptor(\.lastPlayedAt, order: .reverse)]
            )
        )

        for tombstone in tombstones {
            // Restore whenever the exact on-chain identity has a playable row again
            // and that row has no live position yet. The returned row may reuse the
            // original `sourceNFTID` (same token) or arrive under a new one; both are
            // valid because the source state was deleted when the tombstone was cut.
            guard let returned = try matchingReturnedMediaItem(for: tombstone) else {
                // The token has not returned yet; leave the tombstone until it
                // either matches on a later sync or ages out of the recency window.
                continue
            }
            guard try fetchPlaybackState(mediaID: returned.sourceNFTID) == nil else {
                // The returned row already has a live position — either restored
                // from a newer tombstone earlier in this pass (tombstones are
                // sorted newest-first) or written by the user. Consume this now
                // redundant same-identity tombstone so it does not linger.
                tombstone.consumedAt = date
                continue
            }
            modelContext.insert(
                AuraPlayPlaybackPositionState(
                    mediaID: returned.sourceNFTID,
                    positionMilliseconds: tombstone.positionMilliseconds,
                    durationMilliseconds: tombstone.durationMilliseconds,
                    lastPlayedAt: tombstone.lastPlayedAt,
                    completedAt: tombstone.completedAt,
                    playCount: tombstone.playCount,
                    updatedAt: date
                )
            )
            returned.lastPlayedAt = tombstone.lastPlayedAt
            returned.updatedAt = date
            tombstone.consumedAt = date
        }
    }

    private func fetchPlaybackState(mediaID: String) throws -> AuraPlayPlaybackPositionState? {
        var descriptor = FetchDescriptor<AuraPlayPlaybackPositionState>(
            predicate: #Predicate<AuraPlayPlaybackPositionState> { state in
                state.mediaID == mediaID
            }
        )
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first
    }

    private func matchingReturnedMediaItem(
        for tombstone: AuraPlayPlaybackPositionTombstone
    ) throws -> AuraPlayMediaItem? {
        let identity = tombstone.persistentHistoryIdentity
        let account = identity.accountAddressRawValue
        let chain = identity.chainRawValue
        let contract = identity.contractAddressRawValue
        let tokenID = identity.tokenID
        var descriptor = FetchDescriptor<AuraPlayMediaItem>(
            predicate: #Predicate<AuraPlayMediaItem> { item in
                item.accountAddressRawValue == account
                    && item.chainRawValue == chain
                    && item.contractAddressRawValue == contract
                    && item.tokenID == tokenID
                    && item.isPlayable
            }
        )
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first
    }
}

extension AuraPlayMediaItemService: AuraPlayMediaItemQuerying {}

extension AuraPlayMediaItemService: AuraPlayMediaPersisting {
    public func removeItems(ids: [String], capturedAt: Date) throws {
        guard !ids.isEmpty else { return }
        let removedIDs = Set(ids)
        let items = try modelContext.fetch(
            FetchDescriptor<AuraPlayMediaItem>(
                predicate: #Predicate<AuraPlayMediaItem> { item in
                    removedIDs.contains(item.sourceNFTID)
                }
            )
        )
        guard !items.isEmpty else { return }
        for item in items {
            try capturePlaybackTombstoneIfNeeded(for: item, capturedAt: capturedAt)
            modelContext.delete(item)
        }
        try modelContext.save()
    }

    public func restorePlaybackTombstones(at date: Date) throws {
        try restorePlaybackTombstonesIfPossible(at: date)
        try modelContext.save()
    }

    public func upsertAll(_ items: [MediaItemDTO]) async throws {
        let now = Date()
        // Batch-fetch existing rows for the incoming IDs once instead of a
        // per-item fetch (N+1). Mirrors `replaceAll`'s dictionary lookup.
        let requestedIDs = items.map(\.id)
        let existingItems = try modelContext.fetch(
            FetchDescriptor<AuraPlayMediaItem>(
                predicate: #Predicate<AuraPlayMediaItem> { item in
                    requestedIDs.contains(item.sourceNFTID)
                }
            )
        )
        var existingByID = Dictionary(
            existingItems.map { ($0.sourceNFTID, $0) },
            uniquingKeysWith: { current, _ in current }
        )
        for item in items {
            let request = item.makeAuraPlayMediaItemUpsertRequest()
            if let existing = existingByID[request.sourceNFTID] {
                apply(request, to: existing, updatedAt: now)
            } else {
                let newItem =
                    AuraPlayMediaItem(
                        sourceNFTID: request.sourceNFTID,
                        accountAddressRawValue: request.accountAddressRawValue,
                        chain: request.chain,
                        contractAddressRawValue: request.contractAddressRawValue,
                        tokenID: request.tokenID,
                        tokenType: request.tokenType,
                        title: request.title,
                        artistName: request.artistName,
                        creatorIdentifierRawValue: request.creatorIdentifierRawValue ?? Self.creatorIdentifier(from: request),
                        collectionName: request.collectionName,
                        normalizedTitleKey: request.normalizedTitleKey,
                        normalizedArtistKey: request.normalizedArtistKey,
                        normalizedCollectionKey: request.normalizedCollectionKey,
                        artworkURLString: request.artworkURLString,
                        playbackURLString: request.playbackURLString,
                        durationSeconds: request.durationSeconds,
                        contentType: request.contentType,
                        sourceUpdatedAtRawValue: request.sourceUpdatedAtRawValue,
                        hasArtwork: request.hasArtwork,
                        hasAudio: request.hasAudio,
                        hasVideo: request.hasVideo,
                        isPlayable: request.isPlayable,
                        isSearchable: request.isSearchable,
                        createdAt: now,
                        updatedAt: now
                    )
                modelContext.insert(newItem)
                existingByID[request.sourceNFTID] = newItem
            }
        }
        try modelContext.save()
    }

    private func apply(_ request: AuraPlayMediaItemUpsertRequest, to item: AuraPlayMediaItem, updatedAt: Date) {
        item.accountAddressRawValue = request.accountAddressRawValue
        item.chain = request.chain
        item.contractAddressRawValue = request.contractAddressRawValue
        item.tokenID = request.tokenID
        item.tokenType = request.tokenType
        item.title = request.title
        item.artistName = request.artistName
        item.creatorIdentifierRawValue = request.creatorIdentifierRawValue ?? Self.creatorIdentifier(from: request)
        item.collectionName = request.collectionName
        item.normalizedTitleKey = request.normalizedTitleKey
        item.normalizedArtistKey = request.normalizedArtistKey
        item.normalizedCollectionKey = request.normalizedCollectionKey
        item.artworkURLString = request.artworkURLString
        item.playbackURLString = request.playbackURLString
        item.durationSeconds = request.durationSeconds.map { max(0, $0) }
        item.contentType = request.contentType
        item.sourceUpdatedAtRawValue = request.sourceUpdatedAtRawValue
        item.hasArtwork = request.hasArtwork
        item.hasAudio = request.hasAudio
        item.hasVideo = request.hasVideo
        item.isPlayable = request.isPlayable
        item.isSearchable = request.isSearchable
        item.updatedAt = updatedAt
    }
}

private extension AuraPlayMediaItemService {
    func fetchScopedItems(context: MediaItemQueryContext) throws -> [AuraPlayMediaItem] {
        let accountAddress = context.scope.accountAddress ?? ""
        let scopeChainRawValue = context.scope.chain.rawValue
        let selectedChainRawValues = Set(context.filter.selectedChains.map(\.rawValue))

        let descriptor = FetchDescriptor<AuraPlayMediaItem>(
            predicate: #Predicate<AuraPlayMediaItem> { item in
                item.accountAddressRawValue == accountAddress &&
                item.chainRawValue == scopeChainRawValue
            }
        )
        let items = try modelContext.fetch(descriptor)

        guard !selectedChainRawValues.isEmpty else {
            return items
        }

        return items.filter { selectedChainRawValues.contains($0.chainRawValue) }
    }

    static func sort(_ items: [AuraPlayMediaItem], by sort: MediaItemSort) -> [AuraPlayMediaItem] {
        items.sorted { lhs, rhs in
            switch sort {
            case .dateAdded:
                if lhs.createdAt != rhs.createdAt { return lhs.createdAt > rhs.createdAt }
                if lhs.normalizedTitleKey != rhs.normalizedTitleKey { return lhs.normalizedTitleKey < rhs.normalizedTitleKey }
                return lhs.sourceNFTID < rhs.sourceNFTID
            case .titleAZ:
                if lhs.normalizedTitleKey != rhs.normalizedTitleKey { return lhs.normalizedTitleKey < rhs.normalizedTitleKey }
                return lhs.sourceNFTID < rhs.sourceNFTID
            case .creatorAZ:
                if lhs.normalizedArtistKey != rhs.normalizedArtistKey { return lhs.normalizedArtistKey < rhs.normalizedArtistKey }
                if lhs.normalizedTitleKey != rhs.normalizedTitleKey { return lhs.normalizedTitleKey < rhs.normalizedTitleKey }
                return lhs.sourceNFTID < rhs.sourceNFTID
            case .duration:
                let lhsDuration = lhs.durationSeconds ?? .greatestFiniteMagnitude
                let rhsDuration = rhs.durationSeconds ?? .greatestFiniteMagnitude
                if lhsDuration != rhsDuration { return lhsDuration < rhsDuration }
                if lhs.normalizedTitleKey != rhs.normalizedTitleKey { return lhs.normalizedTitleKey < rhs.normalizedTitleKey }
                return lhs.sourceNFTID < rhs.sourceNFTID
            case .lastPlayed:
                let lhsDate = lhs.lastPlayedAt ?? .distantPast
                let rhsDate = rhs.lastPlayedAt ?? .distantPast
                if lhsDate != rhsDate { return lhsDate > rhsDate }
                if lhs.normalizedTitleKey != rhs.normalizedTitleKey { return lhs.normalizedTitleKey < rhs.normalizedTitleKey }
                return lhs.sourceNFTID < rhs.sourceNFTID
            }
        }
    }

    static func creatorIdentifier(from request: AuraPlayMediaItemUpsertRequest) -> String {
        let contract = request.contractAddressRawValue?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let contract, !contract.isEmpty {
            return "\(request.chain.rawValue):\(contract)"
        }

        let artist = request.normalizedArtistKey.trimmingCharacters(in: .whitespacesAndNewlines)
        if !artist.isEmpty {
            return "\(request.chain.rawValue):artist:\(artist)"
        }

        return "\(request.chain.rawValue):unknown:\(request.sourceNFTID)"
    }

    static func nonEmpty(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let trimmed, !trimmed.isEmpty else { return nil }
        return trimmed
    }
}
