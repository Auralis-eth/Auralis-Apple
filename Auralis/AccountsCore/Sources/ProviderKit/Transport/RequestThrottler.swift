//
//  RequestThrottler.swift
//  Auralis
//
//  Created by Daniel Bell on 8/6/25.
//

import Foundation
/// Enforces a minimum interval between requests, including between *concurrent* callers.
///
/// Each caller reserves the next free slot before it suspends, so N callers arriving at once are
/// spaced `minimumInterval` apart rather than all waking together. That reservation is the whole
/// design: an earlier version stored the last request time and had every caller compute its delay
/// from it, but an `actor` only serializes *between* suspension points — so every caller that
/// arrived while one was sleeping read the same timestamp, computed the same delay, and fired
/// simultaneously. It was thread-safe and did not throttle.
public actor RequestThrottler {

    // MARK: - Configuration
    private let minimumInterval: TimeInterval
    private static let nanosecondsPerSecond: UInt64 = 1_000_000_000

    // MARK: - State
    /// The earliest instant the next request may start.
    ///
    /// A reservation rather than a record of the past: it is advanced when a caller claims its slot,
    /// not when a request finishes, which is what keeps concurrent callers from sharing one slot.
    private var nextAllowedTime: Date = .distantPast

    // MARK: - Initialization

    /// Creates a request throttler with validated minimum interval
    /// - Parameter minimumInterval: Minimum time between requests (must be > 0)
    /// - Precondition: minimumInterval must be greater than 0
    public init(minimumInterval: TimeInterval = 0.1) {
        precondition(minimumInterval > 0, "minimumInterval must be greater than 0")
        self.minimumInterval = minimumInterval
    }

    // MARK: - Core Throttling

    /// Waits until this caller's slot is due, spacing it `minimumInterval` after the previously
    /// reserved slot.
    ///
    /// The reservation is taken *before* the suspension, with no `await` between reading
    /// `nextAllowedTime` and advancing it, so it is atomic on this actor and two concurrent callers
    /// cannot claim the same instant. A cancelled caller releases its slot when no later caller has
    /// queued behind it, so cancellation does not leave a permanent idle gap.
    ///
    /// - Throws: `CancellationError` if cancelled while waiting.
    public func throttle() async throws {
        let now = Date()
        let scheduled = max(now, nextAllowedTime)
        nextAllowedTime = scheduled.addingTimeInterval(minimumInterval)

        let delay = scheduled.timeIntervalSince(now)
        guard delay > 0 else { return }

        do {
            try await Task.sleep(nanoseconds: UInt64(delay * Double(Self.nanosecondsPerSecond)))
        } catch {
            if nextAllowedTime == scheduled.addingTimeInterval(minimumInterval) {
                nextAllowedTime = scheduled
            }
            throw error
        }
    }

    // MARK: - Observability

    /// Time until the next *unreserved* slot comes due.
    /// - Returns: seconds to wait, or 0 if a request may start now.
    /// - Note: reflects slots already claimed by in-flight callers, so it can exceed
    ///   `minimumInterval` when several requests are queued.
    public func timeUntilNextRequest() -> TimeInterval {
        max(0, nextAllowedTime.timeIntervalSince(Date()))
    }

    /// Checks if a request can be made without delay
    /// - Returns: true if no throttling delay is needed
    public func canMakeImmediateRequest() -> Bool {
        return timeUntilNextRequest() <= 0
    }

    /// Gets current throttling configuration
    /// - Returns: Current minimum interval setting
    public func getCurrentInterval() -> TimeInterval {
        return minimumInterval
    }
}

// MARK: - Execution Helpers

public extension RequestThrottler {

    /// Executes a request with automatic throttling
    ///
    /// Error handling behavior:
    /// - Throttling errors (cancellation, Task.sleep failures): propagated to caller
    /// - Operation errors: propagated to caller
    /// - On any error: throttler state remains consistent for subsequent calls
    ///
    /// - Parameter operation: Async operation to execute
    /// - Returns: Result of the operation
    /// - Throws: Throttling errors or operation errors
    func execute<T>(_ operation: () async throws -> T) async throws -> T {
        try await throttle()
        return try await operation()
    }
}
