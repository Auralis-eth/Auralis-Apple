public struct ContextRequestScope: Equatable, Sendable {
    public let accountAddress: String
    public let chainID: String
    public let modeID: String

    public init(accountAddress: String, chainID: String, modeID: String) {
        self.accountAddress = accountAddress
        self.chainID = chainID
        self.modeID = modeID
    }
}

public struct ContextRefreshResolution: Equatable, Sendable {
    public let snapshot: ContextSnapshot
    public let shouldCommit: Bool
    public let reusedInFlightRefresh: Bool

    public init(
        snapshot: ContextSnapshot,
        shouldCommit: Bool,
        reusedInFlightRefresh: Bool
    ) {
        self.snapshot = snapshot
        self.shouldCommit = shouldCommit
        self.reusedInFlightRefresh = reusedInFlightRefresh
    }
}

@MainActor
public final class ContextRefreshCoordinator {
    private var inFlightTask: Task<ContextSnapshot, Never>?
    private var inFlightScope: ContextRequestScope?
    private var refreshGeneration = 0

    public init() {}

    public func resolve(
        scope: ContextRequestScope,
        operation: @escaping @MainActor () async -> ContextSnapshot
    ) async -> ContextRefreshResolution {
        if let inFlightTask, inFlightScope == scope {
            return ContextRefreshResolution(
                snapshot: await inFlightTask.value,
                shouldCommit: false,
                reusedInFlightRefresh: true
            )
        }

        inFlightTask?.cancel()
        refreshGeneration += 1
        let generation = refreshGeneration
        let task = Task { @MainActor in
            await operation()
        }

        inFlightTask = task
        inFlightScope = scope

        let snapshot = await task.value
        let shouldCommit = generation == refreshGeneration
        if shouldCommit {
            inFlightTask = nil
            inFlightScope = nil
        }

        return ContextRefreshResolution(
            snapshot: snapshot,
            shouldCommit: shouldCommit,
            reusedInFlightRefresh: false
        )
    }
}
