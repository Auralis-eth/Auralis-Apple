import AuralisPrimaryModels
import Foundation

public enum AuraPlaySearchMatchSource: String, Equatable, Sendable {
    case local
    case semantic
    case localAndSemantic
}

public struct AuraPlaySearchDiagnostics: Equatable, Sendable {
    public let localCount: Int
    public let semanticCount: Int
    public let overlapCount: Int

    public init(localCount: Int = 0, semanticCount: Int = 0, overlapCount: Int = 0) {
        self.localCount = localCount
        self.semanticCount = semanticCount
        self.overlapCount = overlapCount
    }
}

public struct AuraPlaySearchResult: Identifiable, Equatable, Sendable {
    public let item: MediaItemQueryItem
    public let source: AuraPlaySearchMatchSource
    public let semanticScore: Float?
    public let rank: Int

    public var id: String { item.sourceNFTID }

    public init(
        item: MediaItemQueryItem,
        source: AuraPlaySearchMatchSource,
        semanticScore: Float?,
        rank: Int
    ) {
        self.item = item
        self.source = source
        self.semanticScore = semanticScore
        self.rank = rank
    }
}

public struct AuraPlaySearchSuggestion: Identifiable, Equatable, Sendable {
    public enum Kind: String, Equatable, Sendable {
        case title
        case creator
        case collection
    }

    public let value: String
    public let kind: Kind

    public var id: String {
        "\(kind.rawValue):\(value.lowercased())"
    }

    public init(value: String, kind: Kind) {
        self.value = value
        self.kind = kind
    }
}

public enum AuraPlaySearchCoordinator {
    public static let suggestedQueries = [
        "lo-fi beats",
        "spoken word",
        "dark ambient",
        "high energy",
        "video tracks"
    ]

    public static func suggestions(
        for query: String,
        in items: [MediaItemQueryItem],
        limit: Int = 6
    ) -> [AuraPlaySearchSuggestion] {
        let normalizedQuery = normalized(query)
        guard !normalizedQuery.isEmpty else { return [] }

        var suggestions: [AuraPlaySearchSuggestion] = []
        var seen: Set<String> = []
        for item in items {
            appendSuggestion(
                item.title,
                kind: .title,
                query: normalizedQuery,
                suggestions: &suggestions,
                seen: &seen,
                limit: limit
            )
            appendSuggestion(
                item.artistName,
                kind: .creator,
                query: normalizedQuery,
                suggestions: &suggestions,
                seen: &seen,
                limit: limit
            )
            appendSuggestion(
                item.collectionName,
                kind: .collection,
                query: normalizedQuery,
                suggestions: &suggestions,
                seen: &seen,
                limit: limit
            )
            if suggestions.count >= limit { break }
        }

        return suggestions
    }

    public static func localMatches(
        query: String,
        in items: [MediaItemQueryItem]
    ) -> [MediaItemQueryItem] {
        let normalizedQuery = normalized(query)
        guard !normalizedQuery.isEmpty else { return [] }

        return items.filter { item in
            searchableText(for: item).contains(normalizedQuery)
        }
    }

    public static func merge(
        localItems: [MediaItemQueryItem],
        semanticResults: [AuraPlaySemanticSearchResult],
        resolvedSemanticItems: [MediaItemQueryItem]
    ) -> (results: [AuraPlaySearchResult], diagnostics: AuraPlaySearchDiagnostics) {
        let semanticScores = Dictionary(
            uniqueKeysWithValues: semanticResults.map { ($0.id, $0.score) }
        )
        let semanticIDs = Set(semanticResults.map(\.id))
        let localIDs = Set(localItems.map(\.sourceNFTID))
        let resolvedByID = Dictionary(
            resolvedSemanticItems.map { ($0.sourceNFTID, $0) },
            uniquingKeysWith: { current, _ in current }
        )

        var orderedItems: [MediaItemQueryItem] = []
        var seen: Set<String> = []
        for item in localItems {
            orderedItems.append(item)
            seen.insert(item.sourceNFTID)
        }

        for semantic in semanticResults where !seen.contains(semantic.id) {
            if let item = resolvedByID[semantic.id] {
                orderedItems.append(item)
                seen.insert(item.sourceNFTID)
            }
        }

        let results = orderedItems.enumerated().map { index, item in
            let isLocal = localIDs.contains(item.sourceNFTID)
            let isSemantic = semanticIDs.contains(item.sourceNFTID)
            let source: AuraPlaySearchMatchSource
            switch (isLocal, isSemantic) {
            case (true, true): source = .localAndSemantic
            case (false, true): source = .semantic
            default: source = .local
            }
            return AuraPlaySearchResult(
                item: item,
                source: source,
                semanticScore: semanticScores[item.sourceNFTID],
                rank: index
            )
        }

        return (
            results,
            AuraPlaySearchDiagnostics(
                localCount: localItems.count,
                semanticCount: semanticResults.count,
                overlapCount: localIDs.intersection(semanticIDs).count
            )
        )
    }

    public static func filtered(
        _ results: [AuraPlaySearchResult],
        filter: MediaItemFilter
    ) -> [AuraPlaySearchResult] {
        results.filter { result in
            includes(result.item, filter: filter)
        }
    }

    public static func queueWindow(
        startingAt itemID: String,
        in results: [AuraPlaySearchResult],
        query: String,
        windowSize: Int = 100
    ) -> (item: AuraPlayPlaybackItemPresentation, window: AuraPlayQueueWindow)? {
        let items = results.map(\.item)
        guard let tappedIndex = items.firstIndex(where: { $0.sourceNFTID == itemID }),
              items[tappedIndex].isPlayable else {
            return nil
        }

        let playable = items[tappedIndex...].filter(\.isPlayable).prefix(windowSize)
        let window = AuraPlayQueueWindow(
            items: playable.map(\.playbackPresentation),
            startIndex: 0,
            origin: .search(query: query),
            queryContext: nil,
            windowSize: windowSize,
            nextOffset: nil
        )
        return (items[tappedIndex].playbackPresentation, window)
    }

    public static func includes(_ item: MediaItemQueryItem, filter: MediaItemFilter) -> Bool {
        if !filter.selectedChains.isEmpty, !filter.selectedChains.contains(item.chain) {
            return false
        }
        if !filter.includeNonPlayable, !item.isPlayable {
            return false
        }
        if filter.unplayedOnly, item.lastPlayedAt != nil {
            return false
        }
        switch filter.mediaType {
        case .all:
            return true
        case .audio:
            return item.hasAudio
        case .video:
            return item.hasVideo
        }
    }

    private static func appendSuggestion(
        _ value: String?,
        kind: AuraPlaySearchSuggestion.Kind,
        query: String,
        suggestions: inout [AuraPlaySearchSuggestion],
        seen: inout Set<String>,
        limit: Int
    ) {
        guard suggestions.count < limit,
              let cleaned = cleaned(value),
              cleaned.lowercased().contains(query) else {
            return
        }

        let key = "\(kind.rawValue):\(cleaned.lowercased())"
        guard seen.insert(key).inserted else { return }
        suggestions.append(AuraPlaySearchSuggestion(value: cleaned, kind: kind))
    }

    private static func searchableText(for item: MediaItemQueryItem) -> String {
        [
            item.title,
            item.artistName,
            item.collectionName,
            item.chain.routingDisplayName,
            item.contractAddress,
            item.tokenID
        ]
        .compactMap(cleaned)
        .joined(separator: " ")
        .lowercased()
    }

    private static func normalized(_ query: String) -> String {
        query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private static func cleaned(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }
}

@MainActor
public struct AuraPlayRecentSearchStore {
    private let defaults: UserDefaults
    private let keyPrefix: String
    private let limit: Int

    public init(
        defaults: UserDefaults = .standard,
        keyPrefix: String = "auraplay.search.recents",
        limit: Int = 10
    ) {
        self.defaults = defaults
        self.keyPrefix = keyPrefix
        self.limit = max(1, limit)
    }

    public func queries(scope: AuraPlayLibraryScope) -> [String] {
        defaults.stringArray(forKey: key(for: scope)) ?? []
    }

    public func record(_ query: String, scope: AuraPlayLibraryScope) {
        let cleaned = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return }

        var existing = queries(scope: scope).filter {
            $0.caseInsensitiveCompare(cleaned) != .orderedSame
        }
        existing.insert(cleaned, at: 0)
        defaults.set(Array(existing.prefix(limit)), forKey: key(for: scope))
    }

    public func clear(scope: AuraPlayLibraryScope) {
        defaults.removeObject(forKey: key(for: scope))
    }

    private func key(for scope: AuraPlayLibraryScope) -> String {
        let account = scope.accountAddress?.lowercased() ?? "none"
        return "\(keyPrefix).\(account).\(scope.chain.rawValue)"
    }
}
