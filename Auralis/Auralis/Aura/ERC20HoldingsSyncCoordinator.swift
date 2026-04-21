import Foundation

@MainActor
final class ERC20HoldingsSyncCoordinator {
    struct Request: Equatable, Sendable {
        let accountAddress: String
        let chain: Chain
    }

    enum Result: Equatable {
        case applied(TokenHoldingsProviderWarning?)
        case fetchFailed
        case persistFailed
        case dropped
        case cancelled
    }

    private var activeSyncID: UUID?

    func sync(
        request: Request,
        fetch: @escaping (Request) async throws -> TokenHoldingsFetchResult,
        persist: @escaping @MainActor (Request, [ProviderTokenHolding]) throws -> Void
    ) async -> Result {
        let syncID = UUID()
        activeSyncID = syncID

        do {
            let fetchResult = try await fetch(request)
            try Task.checkCancellation()
            guard activeSyncID == syncID else {
                return .dropped
            }

            do {
                try persist(request, fetchResult.holdings)
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
            return .applied(fetchResult.warning)
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
