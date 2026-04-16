import SwiftUI

@MainActor
final class ERC20HoldingsSyncCoordinator: ObservableObject {
    struct Request: Equatable, Sendable {
        let accountAddress: String
        let chain: Chain
    }

    enum Result: Equatable {
        case applied
        case fetchFailed
        case persistFailed
        case dropped
        case cancelled
    }

    private var activeSyncID: UUID?

    func sync(
        request: Request,
        fetch: @escaping (Request) async throws -> [ProviderTokenHolding],
        persist: @escaping @MainActor (Request, [ProviderTokenHolding]) throws -> Void
    ) async -> Result {
        let syncID = UUID()
        activeSyncID = syncID

        do {
            let holdings = try await fetch(request)
            try Task.checkCancellation()
            guard activeSyncID == syncID else {
                return .dropped
            }

            do {
                try persist(request, holdings)
            } catch {
                guard activeSyncID == syncID else {
                    return .dropped
                }
                complete(syncID)
                return .persistFailed
            }

            try Task.checkCancellation()
            guard activeSyncID == syncID else {
                return .dropped
            }

            complete(syncID)
            return .applied
        } catch is CancellationError {
            if activeSyncID == syncID {
                complete(syncID)
                return .cancelled
            }
            return .dropped
        } catch {
            guard activeSyncID == syncID else {
                return .dropped
            }
            complete(syncID)
            return .fetchFailed
        }
    }

    private func complete(_ syncID: UUID) {
        if activeSyncID == syncID {
            activeSyncID = nil
        }
    }
}
