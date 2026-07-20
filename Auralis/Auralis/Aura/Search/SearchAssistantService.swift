import AuralisPrimaryModels
import Foundation
import SwiftData

#if canImport(CoreSpotlight)
@preconcurrency import CoreSpotlight
#endif

#if canImport(FoundationModels)
import FoundationModels
#endif

struct SearchAssistantSnapshot: Equatable, Sendable {
    let answer: String?
    let sections: [SearchAssistantResultSection]
    let isStreaming: Bool
}

struct SearchAssistantRequest: Equatable, Sendable {
    let query: String
    let scope: SearchScope
    let kind: SearchQueryKind
}

struct SearchAssistantToolPlan: Equatable, Sendable {
    let usesSimilarityMatch: Bool
    let usesDateMatch: Bool
    let usesMediaCapabilityStage: Bool
    let usesReceiptRollupStage: Bool
}

struct SearchAssistantResultSection: Identifiable, Equatable, Sendable {
    let id: String
    let label: String
    let queryTokenDescription: String
    let stageTokenDescription: String?
    let payload: SearchAssistantPayload
    let isStreaming: Bool
}

enum SearchAssistantPayload: Equatable, Sendable {
    struct ScoredMatch: Identifiable, Equatable, Sendable {
        let match: SearchLocalMatch
        let score: Double

        var id: String {
            match.id
        }
    }

    struct GroupedMatches: Identifiable, Equatable, Sendable {
        let id: String
        let label: String
        let matches: [SearchLocalMatch]
    }

    struct Table: Equatable, Sendable {
        let columns: [String]
        let rows: [[String]]
    }

    struct Statistic: Equatable, Sendable {
        let name: String
        let value: String
        let header: String?
    }

    case matches([SearchLocalMatch])
    case scoredMatches([ScoredMatch])
    case groupedMatches([GroupedMatches])
    case count(Int, header: String?)
    case table(Table)
    case statistic(Statistic)
    case text(String, header: String?)

    var isEmpty: Bool {
        switch self {
        case .matches(let matches):
            return matches.isEmpty
        case .scoredMatches(let matches):
            return matches.isEmpty
        case .groupedMatches(let groups):
            return groups.allSatisfy { $0.matches.isEmpty }
        case .count:
            return false
        case .table(let table):
            return table.rows.isEmpty
        case .statistic:
            return false
        case .text(let text, _):
            return text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }
}

enum SearchAssistantAvailability: Equatable, Sendable {
    case available
    case deviceNotEligible
    case appleIntelligenceNotEnabled
    case modelNotReady
    case unavailable(String)

    var title: String {
        switch self {
        case .available:
            return "Assistant Ready"
        case .deviceNotEligible:
            return "Assistant Unavailable"
        case .appleIntelligenceNotEnabled:
            return "Apple Intelligence Disabled"
        case .modelNotReady:
            return "Assistant Preparing"
        case .unavailable:
            return "Assistant Unavailable"
        }
    }

    var message: String {
        switch self {
        case .available:
            return "Auralis can answer natural-language searches using local Spotlight results."
        case .deviceNotEligible:
            return "This device does not support on-device language model search. Exact search still works."
        case .appleIntelligenceNotEnabled:
            return "Enable Apple Intelligence to use assistant-backed search. Exact search still works."
        case .modelNotReady:
            return "The on-device model is not ready yet. Try again after the model finishes preparing."
        case .unavailable(let message):
            return message
        }
    }
}

enum SearchAssistantState: Equatable, Sendable {
    case idle
    case loading
    case streaming(SearchAssistantSnapshot)
    case unavailable(SearchAssistantAvailability)
    case failed(String)
}

protocol SearchAssistantProviding: Sendable {
    var availability: SearchAssistantAvailability { get }
    func streamAnswer(for request: SearchAssistantRequest) -> AsyncStream<SearchAssistantState>
}

struct UnavailableSearchAssistantService: SearchAssistantProviding {
    let availability: SearchAssistantAvailability

    init(availability: SearchAssistantAvailability = .unavailable("Assistant-backed search is not available in this build.")) {
        self.availability = availability
    }

    func streamAnswer(for request: SearchAssistantRequest) -> AsyncStream<SearchAssistantState> {
        AsyncStream { continuation in
            continuation.yield(.unavailable(availability))
            continuation.finish()
        }
    }
}

extension SearchAssistantRequest {
    var toolPlan: SearchAssistantToolPlan {
        let normalizedQuery = query.lowercased()
        let isMediaQuery = normalizedQuery.contains("music")
            || normalizedQuery.contains("audio")
            || normalizedQuery.contains("playable")
            || normalizedQuery.contains("video")
            || normalizedQuery.contains("media")
        let isReceiptQuery = normalizedQuery.contains("receipt")
            || normalizedQuery.contains("activity")
            || normalizedQuery.contains("failed")
            || normalizedQuery.contains("status")
            || normalizedQuery.contains("trigger")
            || normalizedQuery.contains("wallet")

        switch kind {
        case .tokenSymbol, .nftName, .collectionName:
            return SearchAssistantToolPlan(
                usesSimilarityMatch: true,
                usesDateMatch: false,
                usesMediaCapabilityStage: isMediaQuery,
                usesReceiptRollupStage: false
            )
        case .text:
            return SearchAssistantToolPlan(
                usesSimilarityMatch: true,
                usesDateMatch: isReceiptQuery,
                usesMediaCapabilityStage: isMediaQuery,
                usesReceiptRollupStage: isReceiptQuery
            )
        case .empty,
             .walletAddress,
             .contractAddress,
             .ambiguousAddress,
             .invalidAddress,
             .ensName,
             .invalidENSLike:
            return SearchAssistantToolPlan(
                usesSimilarityMatch: false,
                usesDateMatch: false,
                usesMediaCapabilityStage: false,
                usesReceiptRollupStage: false
            )
        }
    }
}

#if canImport(FoundationModels) && canImport(CoreSpotlight)
@available(iOS 27.0, *)
@Generable
struct AuralisMediaCapabilityStage: CustomStage {
    static var name: String { "auralis_media_capability" }
    static var description: String {
        "Scores NFTs and AuraPlay media by audio, video, playable state, artist, collection, and media kind."
    }
    static var inputTypes: [SearchPipelineDataType] { [.items] }
    static var outputTypes: [SearchPipelineDataType] { [.scoredItems] }

    @Guide(description: "Optional media kind to prefer, such as audio, video, playable, music, or visual.")
    var preferredMediaKind: String?

    @Guide(description: "Minimum score from 0.0 to 1.0 to include in output.")
    var threshold: Double?

    // Scoring weights for the media-capability stage. Kept as named constants so the
    // heuristic is auditable instead of a set of inline magic numbers.
    static let audioWeight = 0.35
    static let videoWeight = 0.25
    static let playableWeight = 0.25
    static let attributionWeight = 0.15
    static let preferenceWeight = 0.35
    static let defaultThreshold = 0.15

    func execute(items: [CSSearchableItem]) async throws -> SearchPipelineData {
        let normalizedPreference = Self.canonicalMediaKind(from: preferredMediaKind)
        let minimumScore = threshold ?? Self.defaultThreshold
        let scoredItems = items.compactMap { item -> ScoredSearchableItem? in
            let keywords = item.attributeSet.keywords ?? []
            let mediaKind = SearchSpotlightMetadataToken.value(for: "mediaKind", in: keywords)?.lowercased()
            let isPlayable = SearchSpotlightMetadataToken.value(for: "isPlayable", in: keywords) == "true"
            let hasArtist = SearchSpotlightMetadataToken.value(for: "artistName", in: keywords) != nil
            let hasCollection = SearchSpotlightMetadataToken.value(for: "collectionName", in: keywords) != nil

            var score = 0.0
            switch mediaKind {
            case "audio":
                score += Self.audioWeight
            case "video":
                score += Self.videoWeight
            default:
                break
            }
            if isPlayable {
                score += Self.playableWeight
            }
            if hasArtist || hasCollection {
                score += Self.attributionWeight
            }
            if let normalizedPreference {
                let matchesPreference = normalizedPreference == "playable"
                    ? isPlayable
                    : mediaKind == normalizedPreference
                if matchesPreference {
                    score += Self.preferenceWeight
                }
            }

            guard score >= minimumScore else {
                return nil
            }

            return ScoredSearchableItem(item: item, score: min(score, 1.0))
        }
        .sorted { $0.score > $1.score }

        return .scoredItems(scoredItems)
    }

    // Maps free-form user media-kind phrasing onto the canonical values written by the
    // Spotlight indexer (audio / video / visual) plus the special "playable" preference.
    static func canonicalMediaKind(from preference: String?) -> String? {
        guard let normalized = preference?
            .lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines),
            !normalized.isEmpty
        else {
            return nil
        }

        switch normalized {
        case "audio", "music", "song", "songs", "track", "tracks", "sound":
            return "audio"
        case "video", "movie", "movies", "clip", "clips", "film":
            return "video"
        case "visual", "image", "images", "art", "artwork", "picture":
            return "visual"
        case "playable", "play":
            return "playable"
        default:
            return normalized
        }
    }
}

@available(iOS 27.0, *)
extension CustomStage where Self == AuralisMediaCapabilityStage {
    static func auralisMediaCapability(
        preferredMediaKind: String? = nil,
        threshold: Double? = nil
    ) -> Self {
        AuralisMediaCapabilityStage(preferredMediaKind: preferredMediaKind, threshold: threshold)
    }
}

@available(iOS 27.0, *)
@Generable
struct AuralisReceiptRollupStage: CustomStage {
    static var name: String { "auralis_receipt_rollup" }
    static var description: String {
        "Groups and counts Auralis receipt search results by status, trigger, chain, and scope."
    }
    static var inputTypes: [SearchPipelineDataType] { [.items] }
    static var outputTypes: [SearchPipelineDataType] { [.table, .count] }

    @Guide(description: "Optional receipt field to group by: status, trigger, chain, or scope.")
    var groupBy: String?

    func execute(items: [CSSearchableItem]) async throws -> SearchPipelineData {
        let receiptItems = items.filter { item in
            item.domainIdentifier == SearchIndexedDocument.Domain.receipt.rawValue ||
            SearchSpotlightMetadataToken.value(for: "documentDomain", in: item.attributeSet.keywords ?? []) == SearchIndexedDocument.Domain.receipt.rawValue ||
            item.attributeSet.keywords?.contains("receipt") == true
        }

        guard !receiptItems.isEmpty else {
            return .count(0)
        }

        let groupingKey = groupBy?.lowercased() ?? "status"
        let groupedCounts = Dictionary(grouping: receiptItems) { item in
            receiptValue(groupingKey, in: item) ?? "Unspecified"
        }
        .map { key, values in (key: key, count: values.count) }
        .sorted { lhs, rhs in
            if lhs.count == rhs.count {
                return lhs.key.localizedCaseInsensitiveCompare(rhs.key) == .orderedAscending
            }
            return lhs.count > rhs.count
        }

        let columns = [
            SearchResultsTable.Column(name: groupingKey.capitalized, type: .string),
            SearchResultsTable.Column(name: "Count", type: .integer),
        ]
        let rows = groupedCounts.map { group in
            SearchResultsTable.Row(values: [.string(group.key), .integer(group.count)])
        }
        return .table(SearchResultsTable(header: "Receipts by \(groupingKey)", columns: columns, rows: rows))
    }

    // Reads the grouping value straight from the structured Spotlight metadata tokens
    // the indexer emits. Chain is a shared token; the remaining fields are receipt-scoped.
    private func receiptValue(_ key: String, in item: CSSearchableItem) -> String? {
        let tokenKey: String
        switch key {
        case "trigger":
            tokenKey = "receiptTrigger"
        case "chain":
            tokenKey = "chain"
        case "scope":
            tokenKey = "receiptScope"
        default:
            tokenKey = "receiptStatus"
        }

        return SearchSpotlightMetadataToken.value(for: tokenKey, in: item.attributeSet.keywords ?? [])
    }
}

@available(iOS 27.0, *)
extension CustomStage where Self == AuralisReceiptRollupStage {
    static func auralisReceiptRollup(groupBy: String? = nil) -> Self {
        AuralisReceiptRollupStage(groupBy: groupBy)
    }
}

@available(iOS 27.0, *)
final class SearchAssistantService: SearchAssistantProviding, @unchecked Sendable {
    private let hydrationDelegate: SearchSpotlightHydrationDelegate

    init(hydrationDelegate: SearchSpotlightHydrationDelegate) {
        self.hydrationDelegate = hydrationDelegate
    }

    var availability: SearchAssistantAvailability {
        switch SystemLanguageModel.default.availability {
        case .available:
            return .available
        case .unavailable(.deviceNotEligible):
            return .deviceNotEligible
        case .unavailable(.appleIntelligenceNotEnabled):
            return .appleIntelligenceNotEnabled
        case .unavailable(.modelNotReady):
            return .modelNotReady
        case .unavailable(let reason):
            return .unavailable("Assistant-backed search is unavailable: \(String(describing: reason))")
        }
    }

    func streamAnswer(for request: SearchAssistantRequest) -> AsyncStream<SearchAssistantState> {
        AsyncStream<SearchAssistantState> { (continuation: AsyncStream<SearchAssistantState>.Continuation) in
            let task = Task {
                guard availability == .available else {
                    continuation.yield(.unavailable(availability))
                    continuation.finish()
                    return
                }

                continuation.yield(.loading)

                var source = CoreSpotlightSource(
                    searchableIndexDelegate: hydrationDelegate,
                    fetchAttributes: [
                        .title,
                        .displayName,
                        .contentDescription,
                        .textContent,
                        .keywords,
                        .contentCreationDate,
                        .contentModificationDate,
                        .metadataModificationDate,
                        .contentType,
                        .domainIdentifier,
                        .containerDisplayName,
                        .containerIdentifier,
                    ]
                )
                source.maximumResultCount = 20

                let tool = Self.makeTool(source: source, plan: request.toolPlan)
                let snapshotAccumulator = SearchAssistantSnapshotAccumulator()

                let resultsTask = Task { () -> [SearchAssistantResultSection] in
                    for await reply in tool.searchResults {
                        guard !Task.isCancelled else { break }
                        if let section = Self.makeResultSection(from: reply) {
                            let snapshot = await snapshotAccumulator.update(section: section)
                            continuation.yield(.streaming(snapshot))
                        }
                    }
                    return await snapshotAccumulator.currentSections()
                }

                do {
                    let session = LanguageModelSession(
                        tools: [tool],
                        instructions: Instructions {
                            "Answer only from Auralis Spotlight search results."
                            "Keep answers concise and mention when no grounded result is available."
                            "Search content includes wallet accounts, NFTs, ERC-20 tokens, receipts, and AuraPlay media."
                            if let accountAddress = request.scope.normalizedAccountAddress {
                                "The active wallet scope is \(accountAddress)."
                            }
                            "The active chain is \(request.scope.chain.routingDisplayName)."
                        }
                    )
                    let responseStream = session.streamResponse(to: request.query)
                    for try await partialResponse in responseStream {
                        let snapshot = await snapshotAccumulator.update(
                            answer: partialResponse.content,
                            isStreaming: true
                        )
                        continuation.yield(.streaming(snapshot))
                    }
                    let sections = await resultsTask.value
                    continuation.yield(
                        .streaming(
                            SearchAssistantSnapshot(
                                answer: await snapshotAccumulator.currentAnswer(),
                                sections: sections,
                                isStreaming: false
                            )
                        )
                    )
                    continuation.finish()
                } catch is CancellationError {
                    resultsTask.cancel()
                    continuation.finish()
                } catch {
                    resultsTask.cancel()
                    continuation.yield(.failed(error.localizedDescription))
                    continuation.finish()
                }
            }

            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }

    private static func makeTool(
        source: CoreSpotlightSource,
        plan: SearchAssistantToolPlan
    ) -> SpotlightSearchTool {
        let profile = SpotlightSearchTool.GuidanceProfile(
            textMatch: true,
            similarityMatch: plan.usesSimilarityMatch,
            numericMatch: false,
            dates: plan.usesDateMatch,
            people: false,
            contentType: true,
            attributes: [
                .title,
                .displayName,
                .contentDescription,
                .textContent,
                .keywords,
                .contentCreationDate,
                .contentModificationDate,
                .contentType,
                .containerDisplayName,
            ]
        )

        if plan.usesMediaCapabilityStage && plan.usesReceiptRollupStage {
            return SpotlightSearchTool(
                configuration: .init(
                    sources: [.coreSpotlight(source)],
                    guide: .init(level: .dynamic(profile), format: .compact),
                    customStages: [.auralisMediaCapability(), .auralisReceiptRollup()]
                )
            )
        }

        if plan.usesMediaCapabilityStage {
            return SpotlightSearchTool(
                configuration: .init(
                    sources: [.coreSpotlight(source)],
                    guide: .init(level: .dynamic(profile), format: .compact),
                    customStages: [.auralisMediaCapability()]
                )
            )
        }

        if plan.usesReceiptRollupStage {
            return SpotlightSearchTool(
                configuration: .init(
                    sources: [.coreSpotlight(source)],
                    guide: .init(level: .dynamic(profile), format: .compact),
                    customStages: [.auralisReceiptRollup()]
                )
            )
        }

        return SpotlightSearchTool(
            configuration: .init(
                sources: [.coreSpotlight(source)],
                guide: .init(level: .dynamic(profile), format: .compact)
            )
        )
    }

    private static func makeResultSection(
        from reply: SpotlightSearchTool.SearchReply
    ) -> SearchAssistantResultSection? {
        guard let payload = SearchAssistantPayload(replyContent: reply.content), !payload.isEmpty else {
            return nil
        }

        let queryTokenDescription = String(describing: reply.queryToken)
        let stageTokenDescription = String(describing: reply.stageToken)
        let label = reply.label ?? "Spotlight Results"
        let sectionID = [
            queryTokenDescription,
            stageTokenDescription,
            label,
            payload.identityDescription,
        ].joined(separator: ":")

        return SearchAssistantResultSection(
            id: sectionID,
            label: label,
            queryTokenDescription: queryTokenDescription,
            stageTokenDescription: stageTokenDescription,
            payload: payload,
            isStreaming: reply.status == .partial
        )
    }
}

@available(iOS 27.0, *)
private actor SearchAssistantSnapshotAccumulator {
    private var answer: String?
    private var orderedSectionIDs: [String] = []
    private var sectionsByID: [String: SearchAssistantResultSection] = [:]

    func update(answer: String?, isStreaming: Bool) -> SearchAssistantSnapshot {
        self.answer = answer
        return SearchAssistantSnapshot(
            answer: answer,
            sections: currentSections(),
            isStreaming: isStreaming
        )
    }

    func update(section: SearchAssistantResultSection) -> SearchAssistantSnapshot {
        if sectionsByID[section.id] == nil {
            orderedSectionIDs.append(section.id)
        }
        sectionsByID[section.id] = section
        return SearchAssistantSnapshot(
            answer: answer,
            sections: currentSections(),
            isStreaming: section.isStreaming
        )
    }

    func currentAnswer() -> String? {
        answer
    }

    func currentSections() -> [SearchAssistantResultSection] {
        orderedSectionIDs.compactMap { sectionsByID[$0] }
    }
}
#else
typealias SearchAssistantService = UnavailableSearchAssistantService
#endif

#if canImport(FoundationModels) && canImport(CoreSpotlight)
@available(iOS 27.0, *)
extension SearchAssistantPayload {
    init?(replyContent: SpotlightSearchTool.SearchReply.Content) {
        switch replyContent {
        case .items(let items):
            self = .matches(Self.matches(from: items))
        case .scoredItems(let scoredItems):
            self = .scoredMatches(
                scoredItems.compactMap { scoredItem in
                    SearchLocalMatch(searchableItem: scoredItem.item).map {
                        ScoredMatch(match: $0, score: scoredItem.score)
                    }
                }
            )
        case .groupedItems(let groups):
            self = .groupedMatches(
                groups.map { key, items in
                    GroupedMatches(
                        id: String(describing: key),
                        label: String(describing: key),
                        matches: Self.matches(from: items)
                    )
                }
                .sorted { $0.label.localizedCaseInsensitiveCompare($1.label) == .orderedAscending }
            )
        case .count(let count):
            self = .count(count.value, header: count.header)
        case .table(let table):
            self = .table(
                Table(
                    columns: table.columns.map(\.name),
                    rows: table.rows.map { row in
                        row.values.map(Self.cellString(for:))
                    }
                )
            )
        case .statistic(let statistic):
            self = .statistic(
                Statistic(
                    name: statistic.name,
                    value: String(describing: statistic.value),
                    header: statistic.header
                )
            )
        case .text(let text):
            self = .text(text.body, header: text.header)
        @unknown default:
            return nil
        }
    }

    var identityDescription: String {
        switch self {
        case .matches:
            return "items"
        case .scoredMatches:
            return "scored"
        case .groupedMatches:
            return "grouped"
        case .count:
            return "count"
        case .table:
            return "table"
        case .statistic:
            return "statistic"
        case .text:
            return "text"
        }
    }

    // Formats a typed table cell for display, replacing the previous approach of
    // `String(describing:)` (which leaked `.string(...)` enum syntax that the view then
    // had to string-strip). Pattern-matching the typed value keeps formatting correct.
    static func cellString(for value: SearchResultsTable.Value) -> String {
        switch value {
        case .string(let string):
            return string
        case .integer(let integer):
            return String(integer)
        case .double(let double):
            return double.formatted()
        case .date(let date):
            return date.formatted(date: .abbreviated, time: .shortened)
        case .boolean(let boolean):
            return boolean ? "Yes" : "No"
        case .none:
            return ""
        @unknown default:
            return ""
        }
    }

    private static func matches(from items: [CSSearchableItem]) -> [SearchLocalMatch] {
        var seenIDs = Set<String>()
        return items.compactMap { item in
            guard let match = SearchLocalMatch(searchableItem: item), seenIDs.insert(match.id).inserted else {
                return nil
            }
            return match
        }
    }
}
#endif
