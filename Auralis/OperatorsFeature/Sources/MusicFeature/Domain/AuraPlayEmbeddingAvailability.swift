import Foundation

public struct AuraPlayEmbeddingAvailability: Equatable, Sendable {
    public let isAvailable: Bool
    public let explanation: String?

    public init(isAvailable: Bool, explanation: String? = nil) {
        self.isAvailable = isAvailable
        self.explanation = explanation
    }

    public static let available = AuraPlayEmbeddingAvailability(isAvailable: true)
    public static let unavailable = AuraPlayEmbeddingAvailability(
        isAvailable: false,
        explanation: "Smart playlist features are not available for the current embedding model."
    )
}

public protocol AuraPlayEmbeddingAvailabilityProviding: Sendable {
    func availability() async -> AuraPlayEmbeddingAvailability
    func refreshAvailability() async -> AuraPlayEmbeddingAvailability
}

public actor AuraPlayEmbeddingAvailabilityProvider: AuraPlayEmbeddingAvailabilityProviding {
    private let embeddingProvider: any TextEmbeddingProviding
    private let probeText: String
    private var cachedAvailability: AuraPlayEmbeddingAvailability?

    public init(
        embeddingProvider: any TextEmbeddingProviding = NaturalLanguageTextEmbeddingProvider(),
        probeText: String = "music"
    ) {
        self.embeddingProvider = embeddingProvider
        self.probeText = probeText
    }

    public func availability() async -> AuraPlayEmbeddingAvailability {
        if let cachedAvailability {
            return cachedAvailability
        }
        return await refreshAvailability()
    }

    public func refreshAvailability() async -> AuraPlayEmbeddingAvailability {
        let result: AuraPlayEmbeddingAvailability = embeddingProvider.vector(for: probeText)?.isEmpty == false
            ? .available
            : .unavailable
        cachedAvailability = result
        return result
    }
}

public struct AlwaysAvailableAuraPlayEmbeddingAvailabilityProvider: AuraPlayEmbeddingAvailabilityProviding {
    public init() {}

    public func availability() async -> AuraPlayEmbeddingAvailability { .available }
    public func refreshAvailability() async -> AuraPlayEmbeddingAvailability { .available }
}

public struct UnavailableAuraPlayEmbeddingAvailabilityProvider: AuraPlayEmbeddingAvailabilityProviding {
    public init() {}

    public func availability() async -> AuraPlayEmbeddingAvailability { .unavailable }
    public func refreshAvailability() async -> AuraPlayEmbeddingAvailability { .unavailable }
}
