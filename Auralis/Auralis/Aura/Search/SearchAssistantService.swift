import AuralisCrypto
import AuralisContext
import Foundation
import AuralisReceipts
import AuralisRuntime
import AuralisAppShell
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
    static var outputType: SearchPipelineDataType { .scoredItems }

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

    // The framework hands stages `[CoreSpotlight.SearchableItem]` (a wrapper with no
    // public initializer); unwrap via `.item` to read the structured attribute set and
    // re-wrap the same value into `ScoredSearchableItem`.
    func execute(items: [SearchableItem]) async throws -> SearchPipelineData {
        let scoredItems = items.compactMap { searchable -> ScoredSearchableItem? in
            score(for: searchable.item).map { ScoredSearchableItem(item: searchable, score: $0) }
        }
        .sorted { $0.score > $1.score }

        return .scoredItems(scoredItems)
    }

    // Pure scoring over a Spotlight item's structured tokens. Returns the clamped score
    // when it clears the threshold, or `nil` when the item should be filtered out.
    // Extracted from `execute` so it stays unit-testable: `SearchableItem` cannot be
    // fabricated in tests (no public init), but `CSSearchableItem` can.
    func score(for item: CSSearchableItem) -> Double? {
        let normalizedPreference = Self.canonicalMediaKind(from: preferredMediaKind)
        let minimumScore = threshold ?? Self.defaultThreshold
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

        return min(score, 1.0)
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
    static var outputType: SearchPipelineDataType { .table }

    @Guide(description: "Optional receipt field to group by: status, trigger, chain, or scope.")
    var groupBy: String?

    func execute(items: [SearchableItem]) async throws -> SearchPipelineData {
        rollup(coreItems: items.map(\.item))
    }

    // Testable core of the stage over plain `CSSearchableItem`s (see `score(for:)` note).
    func rollup(coreItems items: [CSSearchableItem]) -> SearchPipelineData {
        let receiptItems = items.filter { item in
            item.domainIdentifier == SearchIndexedDocument.Domain.receipt.rawValue ||
            SearchSpotlightMetadataToken.value(for: "documentDomain", in: item.attributeSet.keywords ?? []) == SearchIndexedDocument.Domain.receipt.rawValue ||
            item.attributeSet.keywords?.contains("receipt") == true
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
            SearchResultsTable.Column(name: "Count", type: .integer)
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
    private let modelRouter: any ModelRouting
    private let modelInferenceClient: any ModelInferring
    private let receiptStore: (any ReceiptStore)?
    private let allowsRoutedProviderAvailability: Bool
    /// The mode stamped into inference receipts.
    ///
    /// These drafts land in the production ledger, and `mode` is inside the integrity hash, so a
    /// hardcoded value is ledger corruption rather than a cosmetic wrong label. It used to be a
    /// literal `.observe`, which meant every search answered while the user was in Operate recorded
    /// the wrong mode against evidence that is supposed to be the record of what mode they were in.
    /// Defaults to the same persisted key every `ModeState` reads — see ``PersistedCryptoMode``.
    private let modeProvider: @MainActor @Sendable () -> ReceiptMode

    init(
        hydrationDelegate: SearchSpotlightHydrationDelegate,
        modelRouter: any ModelRouting = TaskKindModelRouter.localFirstDefault,
        modelInferenceClient: any ModelInferring = UnsupportedModelInferenceClient(),
        receiptStore: (any ReceiptStore)? = nil,
        allowsRoutedProviderAvailability: Bool = false,
        modeProvider: @escaping @MainActor @Sendable () -> ReceiptMode = { PersistedCryptoMode.currentReceiptMode }
    ) {
        self.hydrationDelegate = hydrationDelegate
        self.modelRouter = modelRouter
        self.modelInferenceClient = modelInferenceClient
        self.receiptStore = receiptStore
        self.allowsRoutedProviderAvailability = allowsRoutedProviderAvailability
        self.modeProvider = modeProvider
    }

    var availability: SearchAssistantAvailability {
        if allowsRoutedProviderAvailability {
            return .available
        }
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

                let route = await modelRouter.route(forTaskKind: ModelTaskKind.searchAssistant) ?? DefaultModelRoutes.localLanguageModel
                // Resolved once, here, rather than inside `appendReceipt`: that function is `static`
                // (it runs from detached stream continuations) and the mode is instance state. Read at
                // the start of the inference so the receipt records the mode the work ran under.
                let receiptMode = await MainActor.run { modeProvider() }

                continuation.yield(.loading)

                if route.locality == .remote {
                    await Self.streamRoutedAnswer(
                        request,
                        route: route,
                        modelInferenceClient: modelInferenceClient,
                        receiptStore: receiptStore,
                        mode: receiptMode,
                        continuation: continuation
                    )
                    return
                }

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
                        .containerIdentifier
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
                    let modelRequest = try Self.authorizedRequest(for: request, at: Date())
                    let session = LanguageModelSession(
                        tools: [tool],
                        instructions: Instructions {
                            for instruction in modelRequest.instructions {
                                instruction
                            }
                        }
                    )
                    let started = Date()
                    let responseStream = session.streamResponse(to: modelRequest.prompt)
                    for try await partialResponse in responseStream {
                        let snapshot = await snapshotAccumulator.update(
                            answer: partialResponse.content,
                            isStreaming: true
                        )
                        continuation.yield(.streaming(snapshot))
                    }
                    let sections = await resultsTask.value
                    let finalAnswer = await snapshotAccumulator.currentAnswer()
                    let telemetry = InferenceTelemetry.estimated(
                        route: route,
                        prompt: (modelRequest.instructions + [modelRequest.prompt]).joined(separator: "\n"),
                        completion: finalAnswer ?? "",
                        durationSeconds: max(0, Date().timeIntervalSince(started))
                    )
                    await Self.appendReceipt(
                        request: request,
                        route: route,
                        telemetry: telemetry,
                        receiptStore: receiptStore,
                        mode: receiptMode,
                        isSuccess: true,
                        failureMessage: nil
                    )
                    continuation.yield(
                        .streaming(
                            SearchAssistantSnapshot(
                                answer: finalAnswer,
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
                    await Self.appendReceipt(
                        request: request,
                        route: route,
                        telemetry: nil,
                        receiptStore: receiptStore,
                        mode: receiptMode,
                        isSuccess: false,
                        failureMessage: error.localizedDescription
                    )
                    continuation.yield(.failed(error.localizedDescription))
                    continuation.finish()
                }
            }

            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }

    private static func streamRoutedAnswer(
        _ request: SearchAssistantRequest,
        route: ModelRoute,
        modelInferenceClient: any ModelInferring,
        receiptStore: (any ReceiptStore)?,
        mode: ReceiptMode,
        continuation: AsyncStream<SearchAssistantState>.Continuation
    ) async {
        do {
            let modelRequest = try authorizedRequest(for: request, at: Date())
            let response = try await modelInferenceClient.respond(to: modelRequest, using: route)
            await appendReceipt(
                request: request,
                route: route,
                telemetry: response.telemetry,
                receiptStore: receiptStore,
                mode: mode,
                isSuccess: true,
                failureMessage: nil
            )
            continuation.yield(
                .streaming(
                    SearchAssistantSnapshot(
                        answer: response.content,
                        sections: [],
                        isStreaming: false
                    )
                )
            )
            continuation.finish()
        } catch {
            await appendReceipt(
                request: request,
                route: route,
                telemetry: nil,
                receiptStore: receiptStore,
                mode: mode,
                isSuccess: false,
                failureMessage: error.localizedDescription
            )
            continuation.yield(.failed(error.localizedDescription))
            continuation.finish()
        }
    }

    private static func authorizedRequest(
        for request: SearchAssistantRequest,
        at now: Date
    ) throws -> ModelInferenceRequest {
        let instructions = [
            "Answer only from Auralis Spotlight search results.",
            "Keep answers concise and mention when no grounded result is available.",
            "Search content includes wallet accounts, NFTs, ERC-20 tokens, receipts, and AuraPlay media."
        ]
        return try ModelInferenceRequest.authorizing(
            taskKind: ModelTaskKind.searchAssistant,
            instructions: instructions,
            bundle: ContextBundle(fields: [
                AuralisRuntime.ContextField(key: "search.query", stringValue: request.query, dataClass: .userProvided, source: .userProvided, lastRefreshed: now),
                AuralisRuntime.ContextField(key: "search.accountAddress", stringValue: request.scope.normalizedAccountAddress ?? "none", dataClass: .publicIdentifier, source: .walletStore, lastRefreshed: now),
                AuralisRuntime.ContextField(key: "search.chain", stringValue: request.scope.chain.routingDisplayName, dataClass: .publicIdentifier, source: .chainProvider, lastRefreshed: now)
            ]),
            contract: ContextBundleContract(
                identifier: "model.search.assistant",
                requirements: [
                    ContextFieldRequirement(key: "search.query", allowedDataClasses: [.userProvided], maxAge: 60, authoritativeSource: .userProvided, missingFieldBehavior: .fail),
                    ContextFieldRequirement(key: "search.accountAddress", allowedDataClasses: [.publicIdentifier], maxAge: 60, authoritativeSource: .walletStore, missingFieldBehavior: .fail),
                    ContextFieldRequirement(key: "search.chain", allowedDataClasses: [.publicIdentifier], maxAge: 60, authoritativeSource: .chainProvider, missingFieldBehavior: .fail)
                ]
            ),
            validationDate: now
        ) { context in
            return """
            Query: \(context.field("search.query")?.stringValue ?? "")
            Active wallet scope: \(context.field("search.accountAddress")?.stringValue ?? "")
            Active chain: \(context.field("search.chain")?.stringValue ?? "")
            """
        }
    }

    /// `mode` is passed in rather than read here: this is `static` (it runs inside detached stream
    /// continuations), and the value belongs to the instance's `modeProvider`. It is resolved by the
    /// caller on the main actor, at the moment the inference happens.
    private static func appendReceipt(
        request: SearchAssistantRequest,
        route: ModelRoute,
        telemetry: InferenceTelemetry?,
        receiptStore: (any ReceiptStore)?,
        mode: ReceiptMode,
        isSuccess: Bool,
        failureMessage: String?
    ) async {
        guard let receiptStore else { return }
        var values: [String: ReceiptJSONValue] = [
            "query": .string(request.query),
            "queryKind": .string(String(describing: request.kind)),
            "taskKind": .string(ModelTaskKind.searchAssistant)
        ]
        let fields = telemetry?.outputFields ?? routeTelemetryFields(route)
        for key in fields.keys.sorted() {
            values[key] = .string(fields[key] ?? "")
        }
        if let failureMessage {
            values["error"] = .string(failureMessage)
        }
        // A model produced this answer, and `route` is right here — record the model actor with its
        // real inference provenance rather than collapsing it to an anonymous `.system` (P0.5-602).
        // This is what lets the receipt say "on-device" vs "sent to provider" for a search answer.
        let assistantActor = ActorRef.model(
            identifier: "search.assistant.\(route.modelClass)",
            route: route
        )
        _ = try? await receiptStore.append(
            ReceiptDraft(
                category: "search",
                kind: "search.assistant.inference",
                // Genuinely un-correlated (P0.5-602): a search answer is one shot of inference for a
                // typed query, with no session, plan, or routine around it. A synthetic id here would
                // only file the receipt under a workflow that never existed.
                correlationID: nil,
                payload: ReceiptPayload(values: values),
                actorDetail: assistantActor.receiptActorDetail,
                authorityDetail: ReceiptAuthorityDetail(source: "policyDefault", reason: "Read-only search inference is allowed by standing policy."),
                mode: mode,
                summary: isSuccess ? "Answered assistant search" : "Assistant search failed",
                provenance: "search",
                isSuccess: isSuccess,
                timelineAccountAddress: request.scope.normalizedAccountAddress,
                timelineChainRawValue: request.scope.chain.rawValue
            )
        )
    }

    private static func routeTelemetryFields(_ route: ModelRoute) -> [String: String] {
        [
            "modelProvider": route.provider,
            "modelClass": route.modelClass,
            "inferenceLocality": route.locality.rawValue,
            "privacyImpact": route.privacyImpact
        ]
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
                .containerDisplayName
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
            payload.identityDescription
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
            self = .matches(Self.matches(from: items.map(\.item)))
        case .scoredItems(let scoredItems):
            self = .scoredMatches(
                scoredItems.compactMap { scoredItem in
                    SearchLocalMatch(searchableItem: scoredItem.item.item).map {
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
                        matches: Self.matches(from: items.map(\.item))
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
