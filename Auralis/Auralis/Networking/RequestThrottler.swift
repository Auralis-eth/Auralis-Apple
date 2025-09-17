//
//  RequestThrottler.swift
//  Auralis
//
//  Created by Daniel Bell on 8/6/25.
//

import Foundation
/// High-performance request throttler with precise timing and error handling
///
/// This actor ensures thread-safe throttling with consistent state management.
/// On task cancellation or errors, the internal state remains unchanged to prevent corruption.
/// All delays are calculated reactively after successful completion.
actor RequestThrottler {
    
    // MARK: - Configuration
    private let minimumInterval: TimeInterval
    private static let nanosecondsPerSecond: UInt64 = 1_000_000_000
    
    // MARK: - State
    /// Last successful request completion time
    /// Only updated after successful throttling completion to maintain consistency
    private var lastRequestTime: Date = .distantPast
    
    // MARK: - Initialization
    
    /// Creates a request throttler with validated minimum interval
    /// - Parameter minimumInterval: Minimum time between requests (must be > 0)
    /// - Precondition: minimumInterval must be greater than 0
    init(minimumInterval: TimeInterval = 0.1) {
        precondition(minimumInterval > 0, "minimumInterval must be greater than 0")
        self.minimumInterval = minimumInterval
    }
    
    // MARK: - Core Throttling
    
    /// Enforces minimum interval between requests with precise timing
    ///
    /// State consistency guarantees:
    /// - On successful completion: lastRequestTime updated to actual completion time
    /// - On cancellation/error: lastRequestTime remains unchanged, preserving consistent state
    /// - All timing calculations use single timestamp to prevent drift
    ///
    /// - Throws: TaskCancellationError if cancelled, other Task.sleep errors
    func throttle() async throws {
        // THROT-26: Single timestamp capture to eliminate timing drift
        let now = Date()
        let timeElapsed = now.timeIntervalSince(lastRequestTime)
        
        // THROT-34: Compute delay once and reuse to eliminate redundancy
        let delayNeeded = max(0, minimumInterval - timeElapsed)
        
        // THROT-29: Skip overhead when no delay needed
        if delayNeeded > 0 {
            // THROT-37: Inline nanosecond conversion to eliminate function call overhead
            // THROT-35: Simplified conversion without overkill overflow protection for realistic delays
            let nanoseconds = UInt64(delayNeeded * Double(Self.nanosecondsPerSecond))
            
            // THROT-32: Consistent error handling with proper propagation
            try await Task.sleep(nanoseconds: nanoseconds)
        }
        
        // THROT-33 & THROT-38: Reactive state update ONLY after successful completion
        // This prevents state corruption on cancellation/errors and maintains consistency
        lastRequestTime = Date()
    }
    
    // MARK: - Observability
    
    /// Returns time remaining until next request can be made immediately
    /// - Returns: TimeInterval in seconds, 0 if request can be made now
    /// - Note: Creates new Date() on each call for accuracy. For high-frequency polling,
    ///   consider caching or using reactive patterns with state change publishers.
    func timeUntilNextRequest() -> TimeInterval {
        let timeElapsed = Date().timeIntervalSince(lastRequestTime)
        return max(0, minimumInterval - timeElapsed)
    }
    
    /// Checks if a request can be made without delay
    /// - Returns: true if no throttling delay is needed
    func canMakeImmediateRequest() -> Bool {
        return timeUntilNextRequest() <= 0
    }
    
    /// Gets current throttling configuration
    /// - Returns: Current minimum interval setting
    func getCurrentInterval() -> TimeInterval {
        return minimumInterval
    }
}

// MARK: - Execution Helpers

extension RequestThrottler {
    
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
