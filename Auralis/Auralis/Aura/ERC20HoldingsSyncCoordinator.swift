import AuralisPrimaryModels
import Foundation

@MainActor
final class ERC20HoldingsSyncCoordinator {
    struct Request: Equatable, Sendable {
        let accountAddress: String
        let chain: Chain
    }

    enum Result: Equatable {
        case applied(TokenHoldingsProviderWarning?)
        case fetchFailed(Error)
        case persistFailed
        case dropped
        case cancelled

        static func == (lhs: Result, rhs: Result) -> Bool {
            switch (lhs, rhs) {
            case (.applied(let lhsWarning), .applied(let rhsWarning)):
                return lhsWarning == rhsWarning
            case (.fetchFailed, .fetchFailed), (.persistFailed, .persistFailed), (.dropped, .dropped), (.cancelled, .cancelled):
                return true
            default:
                return false
            }
        }
    }

    private var activeSyncID: UUID?

    func sync(
        request: Request,
        fetch: @escaping (Request) async throws -> TokenHoldingsFetchResult,
        persist: @escaping @MainActor (Request, [ProviderTokenHolding]) async throws -> Void
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
                try await persist(request, fetchResult.holdings)
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
            return .fetchFailed(error)
        }
    }

    private func complete(_ syncID: UUID) {
        if activeSyncID == syncID {
            activeSyncID = nil
        }
    }
}
