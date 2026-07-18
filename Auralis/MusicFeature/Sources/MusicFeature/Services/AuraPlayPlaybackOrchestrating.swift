import Foundation

public enum AuraPlayMediaKind: String, Codable, Equatable, Sendable {
    case audio
    case video
}

public struct AuraPlayPlaybackItemPresentation: Identifiable, Codable, Equatable, Sendable {
    public let id: String
    public let title: String
    public let creator: String?
    public let artworkURLString: String?
    public let duration: TimeInterval?
    public let mediaKind: AuraPlayMediaKind
    public let isPiPActive: Bool

    public init(
        id: String,
        title: String,
        creator: String?,
        artworkURLString: String?,
        duration: TimeInterval?,
        mediaKind: AuraPlayMediaKind,
        isPiPActive: Bool = false
    ) {
        self.id = id
        self.title = title
        self.creator = creator
        self.artworkURLString = artworkURLString
        self.duration = duration.map { max(0, $0) }
        self.mediaKind = mediaKind
        self.isPiPActive = isPiPActive
    }
}

public enum AuraPlayOrchestratorState: Equatable, Sendable {
    case idle
    case loading(AuraPlayPlaybackItemPresentation)
    case playing(AuraPlayPlaybackItemPresentation)
    case paused(AuraPlayPlaybackItemPresentation)
    case buffering(AuraPlayPlaybackItemPresentation)
    case failed(AuraPlayPlaybackItemPresentation, message: String)

    public var item: AuraPlayPlaybackItemPresentation? {
        switch self {
        case .idle:
            nil
        case .loading(let item),
             .playing(let item),
             .paused(let item),
             .buffering(let item),
             .failed(let item, _):
            item
        }
    }

    public var isVisibleInMiniPlayer: Bool {
        if case .idle = self {
            return false
        }
        return true
    }
}

public enum AuraPlayQueueOriginPresentation: Codable, Equatable, Sendable {
    case playlist(id: String)
    case collection(contractAddress: String)
    case creator(id: String)
    case search(query: String)
    case single(mediaItemID: String)
    case restored
    case unknown
}

public struct AuraPlayQueueWindow: Equatable, Sendable {
    public let items: [AuraPlayPlaybackItemPresentation]
    public let startIndex: Int
    public let origin: AuraPlayQueueOriginPresentation
    public let queryContext: MediaItemQueryContext?
    public let windowSize: Int
    public let nextOffset: Int?

    public init(
        items: [AuraPlayPlaybackItemPresentation],
        startIndex: Int,
        origin: AuraPlayQueueOriginPresentation,
        queryContext: MediaItemQueryContext?,
        windowSize: Int = 100,
        nextOffset: Int?
    ) {
        self.items = items
        self.startIndex = max(0, startIndex)
        self.origin = origin
        self.queryContext = queryContext
        self.windowSize = max(1, windowSize)
        self.nextOffset = nextOffset
    }
}

@MainActor
public protocol AuraPlayPlaybackOrchestrating: AnyObject {
    var state: AuraPlayOrchestratorState { get }
    var currentTime: TimeInterval { get }

    func togglePlayPause() async
    func pause() async
    func play(
        item: AuraPlayPlaybackItemPresentation,
        queue: AuraPlayQueueWindow?,
        startAt index: Int,
        origin: AuraPlayQueueOriginPresentation
    ) async
    func restoreVideoPresentation()
}

public protocol AuraPlayQueueExtending: Sendable {
    func fetchNextWindow(from context: MediaItemQueryContext) async throws -> AuraPlayQueueWindow
}
