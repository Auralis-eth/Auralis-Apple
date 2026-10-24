import Foundation

public actor ChaseTimeSeekCoordinator {
    public typealias SeekOperation = @Sendable (_ targetSeconds: Double, _ tolerance: VideoSeekTolerance) async -> Bool

    private var isSeekInProgress = false
    private var chaseTarget: SeekTarget?

    public init() {}

    public func requestSeek(
        to targetSeconds: Double,
        tolerance: VideoSeekTolerance,
        perform: @escaping SeekOperation
    ) async {
        chaseTarget = SeekTarget(seconds: targetSeconds, tolerance: tolerance)

        guard !isSeekInProgress else { return }
        isSeekInProgress = true

        while let target = chaseTarget {
            chaseTarget = nil
            _ = await perform(target.seconds, target.tolerance)
        }

        isSeekInProgress = false
    }

    private struct SeekTarget {
        let seconds: Double
        let tolerance: VideoSeekTolerance
    }
}
