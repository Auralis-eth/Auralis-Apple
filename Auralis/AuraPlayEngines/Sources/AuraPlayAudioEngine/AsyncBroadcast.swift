import Foundation

final class AsyncBroadcast<Element: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var continuations: [UUID: AsyncStream<Element>.Continuation] = [:]
    private var isFinished = false

    func stream(bufferingPolicy: AsyncStream<Element>.Continuation.BufferingPolicy = .unbounded) -> AsyncStream<Element> {
        AsyncStream(Element.self, bufferingPolicy: bufferingPolicy) { continuation in
            let id = UUID()
            lock.withLock {
                if isFinished {
                    continuation.finish()
                } else {
                    continuations[id] = continuation
                }
            }
            continuation.onTermination = { [weak self] _ in
                self?.removeContinuation(id: id)
            }
        }
    }

    func yield(_ value: Element) {
        let currentContinuations = lock.withLock {
            Array(continuations.values)
        }
        for continuation in currentContinuations {
            continuation.yield(value)
        }
    }

    func finish() {
        let currentContinuations = lock.withLock {
            isFinished = true
            let values = Array(continuations.values)
            continuations.removeAll()
            return values
        }
        for continuation in currentContinuations {
            continuation.finish()
        }
    }

    private func removeContinuation(id: UUID) {
        _ = lock.withLock {
            continuations.removeValue(forKey: id)
        }
    }
}

private extension NSLock {
    func withLock<Result>(_ operation: () throws -> Result) rethrows -> Result {
        lock()
        defer { unlock() }
        return try operation()
    }
}
