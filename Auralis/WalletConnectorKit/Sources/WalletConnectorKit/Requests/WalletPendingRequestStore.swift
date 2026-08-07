import Foundation

/// Correlates outbound wallet requests with the responses the relay delivers.
///
/// Waiters and responses are keyed by the on-the-wire JSON-RPC id. Responses can
/// arrive before the waiter registers (the publish call and the inbound response
/// race), so early outcomes are buffered and handed to the next matching waiter.
///
/// This is the core equivalent of the Reown adapter's `ReownPendingRequestStore`.
public actor WalletPendingRequestStore {
    private enum Outcome {
        case success(WalletResponse)
        case failure(Error)
    }

    private var continuations: [WalletSignRequestID: CheckedContinuation<WalletResponse, Error>] = [:]
    private var expiryTasks: [WalletSignRequestID: Task<Void, Never>] = [:]
    private var bufferedOutcomes: [WalletSignRequestID: Outcome] = [:]
    private var bufferedOrder: [WalletSignRequestID] = []
    private let maxBufferedOutcomes = 128

    public init() {}

    /// Waits for the response correlated with `id` (the on-the-wire JSON-RPC id).
    public func wait(id: WalletSignRequestID, expiryDate: Date) async throws -> WalletResponse {
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                if let outcome = takeBufferedOutcome(id) {
                    resume(continuation, with: outcome)
                    return
                }
                continuations[id] = continuation
                expiryTasks[id]?.cancel()
                expiryTasks[id] = Task { [id, expiryDate] in
                    let delay = max(0, expiryDate.timeIntervalSinceNow)
                    try? await Task.sleep(for: .seconds(delay))
                    self.expire(id)
                }
            }
        } onCancel: {
            Task { await self.reject(id, error: WalletConnectionError.cancelled) }
        }
    }

    public func resolve(_ response: WalletResponse) {
        deliver(id: response.id, outcome: .success(response))
    }

    public func fail(_ requestID: WalletSignRequestID, error: Error) {
        deliver(id: requestID, outcome: .failure(error))
    }

    /// Rejects an outstanding waiter without buffering — for cancellation and
    /// other cases where a late waiter must not inherit a stale error.
    public func reject(_ requestID: WalletSignRequestID, error: Error) {
        expiryTasks.removeValue(forKey: requestID)?.cancel()
        continuations.removeValue(forKey: requestID)?.resume(throwing: error)
    }

    public func expire(_ requestID: WalletSignRequestID) {
        reject(requestID, error: WalletConnectionError.requestTimedOut(requestID))
    }

    private func deliver(id: WalletSignRequestID, outcome: Outcome) {
        expiryTasks.removeValue(forKey: id)?.cancel()
        if let continuation = continuations.removeValue(forKey: id) {
            resume(continuation, with: outcome)
        } else {
            bufferOutcome(id, outcome)
        }
    }

    private func resume(_ continuation: CheckedContinuation<WalletResponse, Error>, with outcome: Outcome) {
        switch outcome {
        case .success(let response):
            continuation.resume(returning: response)
        case .failure(let error):
            continuation.resume(throwing: error)
        }
    }

    private func bufferOutcome(_ id: WalletSignRequestID, _ outcome: Outcome) {
        if bufferedOutcomes[id] == nil {
            bufferedOrder.append(id)
        }
        bufferedOutcomes[id] = outcome
        while bufferedOrder.count > maxBufferedOutcomes {
            let evicted = bufferedOrder.removeFirst()
            bufferedOutcomes.removeValue(forKey: evicted)
        }
    }

    private func takeBufferedOutcome(_ id: WalletSignRequestID) -> Outcome? {
        guard let outcome = bufferedOutcomes.removeValue(forKey: id) else { return nil }
        bufferedOrder.removeAll { $0 == id }
        return outcome
    }
}
