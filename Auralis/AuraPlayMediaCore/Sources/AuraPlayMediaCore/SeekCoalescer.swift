import Foundation

public struct SeekTolerance: Equatable, Sendable {
    public let beforeSeconds: TimeInterval
    public let afterSeconds: TimeInterval

    public init(beforeSeconds: TimeInterval = 0, afterSeconds: TimeInterval = 0) {
        self.beforeSeconds = max(0, beforeSeconds)
        self.afterSeconds = max(0, afterSeconds)
    }

    public static let exact = SeekTolerance()
}

public actor SeekCoalescer {
    public typealias SeekOperation = @Sendable (TimeInterval, SeekTolerance) async -> Void

    private var latestRequest: (target: TimeInterval, tolerance: SeekTolerance)?
    private var isSeeking = false

    public init() {}

    public func requestSeek(
        to target: TimeInterval,
        tolerance: SeekTolerance = .exact,
        perform: @escaping SeekOperation
    ) async {
        latestRequest = (max(0, target), tolerance)
        guard !isSeeking else { return }

        isSeeking = true
        defer { isSeeking = false }

        while let request = latestRequest {
            latestRequest = nil
            await perform(request.target, request.tolerance)
        }
    }
}
