import Foundation

public struct AuraPlaySmartPlaylistMetadata: Codable, Equatable, Sendable {
    public let prompt: String
    public let resultIDs: [String]
    public let minimumScore: Float
    public let modelVersion: String?
    public let createdAt: Date

    public init(
        prompt: String,
        resultIDs: [String],
        minimumScore: Float,
        modelVersion: String?,
        createdAt: Date
    ) {
        self.prompt = prompt
        self.resultIDs = resultIDs
        self.minimumScore = minimumScore
        self.modelVersion = modelVersion
        self.createdAt = createdAt
    }
}

public struct AuraPlayGeneratedPlaylistPreview: Equatable, Sendable {
    public enum GenerationMode: Equatable, Sendable {
        case initial
        case regenerated
        case smallPoolFallback
    }

    public let prompt: String
    public let items: [MediaItemQueryItem]
    public let semanticResults: [AuraPlaySemanticSearchResult]
    public let mode: GenerationMode
    public let note: String?

    public init(
        prompt: String,
        items: [MediaItemQueryItem],
        semanticResults: [AuraPlaySemanticSearchResult],
        mode: GenerationMode,
        note: String? = nil
    ) {
        self.prompt = prompt
        self.items = items
        self.semanticResults = semanticResults
        self.mode = mode
        self.note = note
    }

    public var canSave: Bool {
        items.count >= 5
    }
}

public protocol AuraPlayPlaylistGenerating: Sendable {
    func preview(
        prompt: String,
        scope: AuraPlayLibraryScope,
        excludingPreviousIDs previousIDs: Set<String>
    ) async throws -> AuraPlayGeneratedPlaylistPreview
}

public struct AuraPlayPlaylistGenerator: AuraPlayPlaylistGenerating {
    public let semanticSearch: any AuraPlaySemanticSearching
    public let mediaQueryService: any AuraPlayMediaItemQuerying
    public let candidateLimit: Int
    public let previewLimit: Int
    public let minimumScore: Float

    public init(
        semanticSearch: any AuraPlaySemanticSearching,
        mediaQueryService: any AuraPlayMediaItemQuerying,
        candidateLimit: Int = 60,
        previewLimit: Int = 25,
        minimumScore: Float = AuraPlayIntelligenceSettings.defaultSemanticMinimumScore
    ) {
        self.semanticSearch = semanticSearch
        self.mediaQueryService = mediaQueryService
        self.candidateLimit = max(1, candidateLimit)
        self.previewLimit = max(1, previewLimit)
        self.minimumScore = minimumScore
    }

    public func preview(
        prompt: String,
        scope: AuraPlayLibraryScope,
        excludingPreviousIDs previousIDs: Set<String> = []
    ) async throws -> AuraPlayGeneratedPlaylistPreview {
        let cleanedPrompt = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanedPrompt.isEmpty else {
            return AuraPlayGeneratedPlaylistPreview(
                prompt: cleanedPrompt,
                items: [],
                semanticResults: [],
                mode: .initial,
                note: "Describe the playlist you want."
            )
        }

        let candidates = try await semanticSearch.search(
            query: cleanedPrompt,
            in: scope,
            limit: candidateLimit,
            minimumScore: minimumScore
        )
        let selection = selectedIDs(from: candidates, prompt: cleanedPrompt, excludingPreviousIDs: previousIDs)
        let orderedIDs = selection.ids
        let resolvedItems = try await mediaQueryService.fetchItems(scope: scope, ids: orderedIDs)
        let resolvedByID = Dictionary(
            resolvedItems.map { ($0.sourceNFTID, $0) },
            uniquingKeysWith: { current, _ in current }
        )
        let orderedItems = orderedIDs.compactMap { resolvedByID[$0] }
        // Report the mode that matches the selection branch actually taken so the
        // note and UI stay honest about whether the seeded reshuffle fallback ran.
        let mode: AuraPlayGeneratedPlaylistPreview.GenerationMode
        let note: String?
        if selection.usedFallback {
            mode = .smallPoolFallback
            note = "Only a few strong matches are available for this prompt."
        } else {
            mode = previousIDs.isEmpty ? .initial : .regenerated
            note = nil
        }

        return AuraPlayGeneratedPlaylistPreview(
            prompt: cleanedPrompt,
            items: orderedItems,
            semanticResults: candidates.filter { orderedIDs.contains($0.id) },
            mode: mode,
            note: orderedItems.count < 5 ? "Try a broader prompt to find enough matching tracks." : note
        )
    }

    private func selectedIDs(
        from candidates: [AuraPlaySemanticSearchResult],
        prompt: String,
        excludingPreviousIDs previousIDs: Set<String>
    ) -> (ids: [String], usedFallback: Bool) {
        let playableCandidates = candidates.filter(\.isPlayable)
        let preferred = playableCandidates.filter { !previousIDs.contains($0.id) }
        // A large-enough fresh pool lets us exclude the previous preview and draw a
        // weighted-random sample without replacement. The randomness is seeded from
        // the prompt and previous preview so tests and repeated previews are stable.
        if preferred.count >= min(previewLimit, playableCandidates.count) {
            return (
                Array(
                    Self.weightedSample(
                        preferred,
                        limit: previewLimit,
                        seed: Self.seed(prompt: prompt, previousIDs: previousIDs)
                    )
                    .map(\.id)
                ),
                false
            )
        }

        // Small-pool fallback: not enough unseen candidates to exclude the previous
        // preview. Reshuffle the score-biased order with a seed derived from the
        // previous preview so "Regenerate" still reorders instead of returning an
        // identical list. Initial generation (no previous IDs) stays deterministic.
        let ordered = scoreBiasedOrder(playableCandidates)
        guard !previousIDs.isEmpty else {
            return (Array(ordered.prefix(previewLimit).map(\.id)), false)
        }
        return (
            Array(
                Self.seededReshuffle(ordered, seed: Self.seed(from: previousIDs))
                    .prefix(previewLimit)
                    .map(\.id)
            ),
            true
        )
    }

    /// Efraimidis-Spirakis weighted sampling without replacement. Higher similarity
    /// scores produce larger expected priority keys, but every candidate in the
    /// qualifying pool can surface.
    private static func weightedSample(
        _ candidates: [AuraPlaySemanticSearchResult],
        limit: Int,
        seed: UInt64
    ) -> [AuraPlaySemanticSearchResult] {
        candidates
            .sorted { lhs, rhs in
                let lhsKey = weightedPriorityKey(for: lhs, seed: seed)
                let rhsKey = weightedPriorityKey(for: rhs, seed: seed)
                if lhsKey == rhsKey {
                    return lhs.id < rhs.id
                }
                return lhsKey > rhsKey
            }
            .prefix(limit)
            .map { $0 }
    }

    private static func weightedPriorityKey(
        for candidate: AuraPlaySemanticSearchResult,
        seed: UInt64
    ) -> Double {
        let randomUnit = deterministicUnit(for: candidate.id, seed: seed)
        let weight = max(0.0001, Double(candidate.score))
        return pow(randomUnit, 1.0 / weight)
    }

    private static func deterministicUnit(for id: String, seed: UInt64) -> Double {
        var hash = seed == 0 ? 0xcbf29ce484222325 : seed
        for byte in id.utf8 {
            hash ^= UInt64(byte)
            hash &*= 0x100000001b3
        }
        let bounded = hash % 1_000_000
        return max(0.000001, Double(bounded) / 1_000_000)
    }

    /// Deterministic Fisher-Yates shuffle over a fixed seed so regenerate reorders
    /// reproducibly for a given previous preview.
    private static func seededReshuffle(
        _ candidates: [AuraPlaySemanticSearchResult],
        seed: UInt64
    ) -> [AuraPlaySemanticSearchResult] {
        guard candidates.count > 1 else { return candidates }
        var state = seed == 0 ? 0x9e3779b97f4a7c15 : seed
        func next() -> UInt64 {
            // SplitMix64 step.
            state &+= 0x9e3779b97f4a7c15
            var z = state
            z = (z ^ (z >> 30)) &* 0xbf58476d1ce4e5b9
            z = (z ^ (z >> 27)) &* 0x94d049bb133111eb
            return z ^ (z >> 31)
        }
        var result = candidates
        var index = result.count - 1
        while index > 0 {
            let swapIndex = Int(next() % UInt64(index + 1))
            result.swapAt(index, swapIndex)
            index -= 1
        }
        return result
    }

    private static func seed(prompt: String, previousIDs: Set<String>) -> UInt64 {
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in prompt.utf8 {
            hash ^= UInt64(byte)
            hash &*= 0x100000001b3
        }
        for id in previousIDs.sorted() {
            hash ^= 124
            hash &*= 0x100000001b3
            for byte in id.utf8 {
                hash ^= UInt64(byte)
                hash &*= 0x100000001b3
            }
        }
        return hash
    }

    private static func seed(from ids: Set<String>) -> UInt64 {
        var hash: UInt64 = 0xcbf29ce484222325
        for id in ids.sorted() {
            for byte in id.utf8 {
                hash ^= UInt64(byte)
                hash &*= 0x100000001b3
            }
        }
        return hash
    }

    private func scoreBiasedOrder(_ candidates: [AuraPlaySemanticSearchResult]) -> [AuraPlaySemanticSearchResult] {
        candidates.sorted { lhs, rhs in
            let lhsBucket = Int((lhs.score * 1_000).rounded())
            let rhsBucket = Int((rhs.score * 1_000).rounded())
            if lhsBucket == rhsBucket {
                return lhs.id < rhs.id
            }
            return lhsBucket > rhsBucket
        }
    }
}

public extension AuraPlaySmartPlaylistMetadata {
    static func metadataData(
        prompt: String,
        resultIDs: [String],
        minimumScore: Float,
        modelVersion: String?,
        createdAt: Date
    ) throws -> Data {
        let metadata = AuraPlaySmartPlaylistMetadata(
            prompt: prompt,
            resultIDs: resultIDs,
            minimumScore: minimumScore,
            modelVersion: modelVersion,
            createdAt: createdAt
        )
        return try JSONEncoder().encode(metadata)
    }
}
