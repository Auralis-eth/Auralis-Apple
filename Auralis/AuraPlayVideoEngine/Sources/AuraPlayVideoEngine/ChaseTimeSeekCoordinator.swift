import Foundation

public actor ChaseTimeSeekCoordinator {
    public typealias SeekOperation = @Sendable (_ targetSeconds: Double, _ tolerance: VideoSeekTolerance) async -> Bool

    private var isSeekInProgress = false
    private var chaseTargetSeconds: Double?

    public init() {}

    public func requestSeek(
        to targetSeconds: Double,
        tolerance: VideoSeekTolerance,
        perform: @escaping SeekOperation
    ) async {
        chaseTargetSeconds = targetSeconds

        guard !isSeekInProgress else { return }
        isSeekInProgress = true

        while let target = chaseTargetSeconds {
            chaseTargetSeconds = nil
            _ = await perform(target, tolerance)
        }

        isSeekInProgress = false
    }
}
