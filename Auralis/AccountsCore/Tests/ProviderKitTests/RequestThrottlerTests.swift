import Foundation
@testable import ProviderKit
import Testing

/// `RequestThrottler` is what stands between a burst of parallel provider calls and a 429. An
/// `actor` only serializes *between* suspension points, so an implementation that stored the last
/// request time and had each caller derive its delay from it was thread-safe but did not throttle:
/// every caller arriving during one caller's sleep read the same timestamp and woke at the same
/// instant. Audit finding F-20.
@Suite("Request throttler")
struct RequestThrottlerTests {
    @Test("concurrent callers are spaced, not released together")
    func concurrentCallersAreSpaced() async throws {
        let interval: TimeInterval = 0.05
        let throttler = RequestThrottler(minimumInterval: interval)
        let callers = 5

        let start = Date()
        let finishes = await withTaskGroup(of: Date.self, returning: [Date].self) { group in
            for _ in 0..<callers {
                group.addTask {
                    try? await throttler.throttle()
                    return Date()
                }
            }
            return await group.reduce(into: []) { $0.append($1) }
        }

        let elapsed = Date().timeIntervalSince(start)
        // 5 callers at 0.05s spacing occupy slots at 0.00 … 0.20s. Pre-fix they all released at
        // ~0.00s, so this lower bound is the assertion that actually fails on the old code.
        let expectedSpan = interval * Double(callers - 1)
        #expect(
            elapsed >= expectedSpan * 0.8,
            "all \(callers) callers completed in \(elapsed)s; expected at least ~\(expectedSpan)s of spacing"
        )

        let sorted = finishes.sorted()
        let gaps = zip(sorted, sorted.dropFirst()).map { $1.timeIntervalSince($0) }
        #expect(
            gaps.allSatisfy { $0 >= interval * 0.5 },
            "consecutive callers were released \(gaps)s apart; expected >= ~\(interval)s"
        )
    }

    @Test("a single caller on an idle throttler is not delayed")
    func firstCallerIsImmediate() async throws {
        let throttler = RequestThrottler(minimumInterval: 0.5)
        let start = Date()
        try await throttler.throttle()
        #expect(Date().timeIntervalSince(start) < 0.1)
    }

    @Test("sequential callers are still spaced by the interval")
    func sequentialCallersAreSpaced() async throws {
        let throttler = RequestThrottler(minimumInterval: 0.05)
        try await throttler.throttle()
        let start = Date()
        try await throttler.throttle()
        #expect(Date().timeIntervalSince(start) >= 0.04)
    }

    @Test("timeUntilNextRequest reflects reserved slots")
    func timeUntilNextRequestReflectsReservations() async throws {
        let throttler = RequestThrottler(minimumInterval: 0.2)
        try await throttler.throttle()
        let remaining = await throttler.timeUntilNextRequest()
        #expect(remaining > 0)
        #expect(await throttler.canMakeImmediateRequest() == false)
    }

    @Test("execute runs the operation and returns its value")
    func executeReturnsOperationResult() async throws {
        let throttler = RequestThrottler(minimumInterval: 0.01)
        let value = try await throttler.execute { 42 }
        #expect(value == 42)
    }
}
