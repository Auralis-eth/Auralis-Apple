import Foundation

/// Lazily extends a bounded playback queue from a captured query context.
/// The fetch is a pure function of the context (scope, sort, filter, offset);
/// it never reads live view state.
public struct AuraPlayMediaQueueWindowProvider: AuraPlayQueueExtending {
    private let queryService: any AuraPlayMediaItemQuerying

    public init(queryService: any AuraPlayMediaItemQuerying) {
        self.queryService = queryService
    }

    public func fetchNextWindow(from context: MediaItemQueryContext) async throws -> AuraPlayQueueWindow {
        let result = try await queryService.fetchWindow(context: context)
        return AuraPlayQueueWindow(
            items: result.items.filter(\.isPlayable).map(\.playbackPresentation),
            startIndex: 0,
            origin: .unknown,
            queryContext: context,
            windowSize: context.limit,
            nextOffset: result.nextOffset
        )
    }
}
