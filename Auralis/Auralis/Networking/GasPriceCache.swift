//
//  GasPriceCache.swift
//  Auralis
//
//  Created by Daniel Bell on 8/27/25.
//

import Foundation

/// Result type for cache operations providing clear differentiation between states
enum CacheResult<T: Sendable>: Sendable {
    case hit(T)
    case miss
    case expired(T) // Contains expired value for potential fallback use
}

/// Streamlined actor-based cache optimized for gas price estimates
actor GasPriceCache {
    static let shared = GasPriceCache()

    // MARK: - Configuration

    struct Configuration {
        let ttl: TimeInterval
        let maxSize: Int
        let cleanupInterval: TimeInterval

        init(ttl: TimeInterval = 15.0, maxSize: Int = 100, cleanupInterval: TimeInterval = 30.0) {
            self.ttl = ttl
            self.maxSize = maxSize
            self.cleanupInterval = cleanupInterval
        }
    }

    // MARK: - Private Properties

    private struct CacheEntry {
        let value: GasPriceEstimate
        let timestamp: CFAbsoluteTime
        var lastAccessTime: CFAbsoluteTime // True LRU tracking

        init(value: GasPriceEstimate, timestamp: CFAbsoluteTime) {
            self.value = value
            self.timestamp = timestamp
            self.lastAccessTime = timestamp
        }
    }

    private var store: [Int: CacheEntry] = [:]
    private let config: Configuration
    private var cleanupTask: Task<Void, Never>? // Fixed: Never instead of Error

    // Cache performance tracking
    private var accessCount: Int = 0
    private var hitCount: Int = 0

    // MARK: - Initialization

    init(configuration: Configuration = Configuration()) {
        self.config = configuration
        Task { await self.startBackgroundCleanup() }
    }

    deinit {
        cleanupTask?.cancel()
    }

    // MARK: - Public Interface

    /// Retrieves gas price from cache with detailed result information
    func getGasPrice(for chainId: Int) async -> CacheResult<GasPriceEstimate> {
        let currentTime = CFAbsoluteTimeGetCurrent()
        accessCount += 1

        guard var entry = store[chainId] else {
            return .miss
        }

        // Update last access time for true LRU
        entry.lastAccessTime = currentTime
        store[chainId] = entry

        // Check if expired
        if currentTime - entry.timestamp >= config.ttl {
            return .expired(entry.value)
        }

        hitCount += 1
        return .hit(entry.value)
    }

    /// Sets gas price in cache with automatic size management
    func setGasPrice(_ estimate: GasPriceEstimate, for chainId: Int) async {
        let currentTime = CFAbsoluteTimeGetCurrent()

        store[chainId] = CacheEntry(
            value: estimate,
            timestamp: currentTime
        )

        // Efficient size enforcement - only evict one entry if needed
        if store.count > config.maxSize {
            await removeOldestEntry()
        }
    }

    /// Convenience method that returns only valid (non-expired) gas prices
    func getValidGasPrice(for chainId: Int) async -> GasPriceEstimate? {
        let result = await getGasPrice(for: chainId)
        if case .hit(let estimate) = result {
            return estimate
        }
        return nil
    }

    /// Removes specific chain from cache
    func removeGasPrice(for chainId: Int) {
        store.removeValue(forKey: chainId)
    }

    /// Clears all cache entries
    func clearCache() {
        store.removeAll()
        accessCount = 0
        hitCount = 0
    }

    /// Returns current cache statistics (synchronous for efficiency)
    func getCacheStats() -> CacheStats {
        let currentTime = CFAbsoluteTimeGetCurrent()
        let expired = store.values.filter { currentTime - $0.timestamp >= config.ttl }.count

        return CacheStats(
            totalEntries: store.count,
            expiredEntries: expired,
            validEntries: store.count - expired,
            maxSize: config.maxSize,
            ttl: config.ttl,
            accessCount: accessCount,
            hitCount: hitCount
        )
    }

    // MARK: - Private Methods

    /// Efficient O(n) removal of single LRU entry
    private func removeOldestEntry() async {
        guard !store.isEmpty else { return }

        var lruKey: Int?
        var oldestAccessTime = CFAbsoluteTimeGetCurrent()

        for (chainId, entry) in store where entry.lastAccessTime < oldestAccessTime {
            oldestAccessTime = entry.lastAccessTime
            lruKey = chainId
        }

        if let keyToRemove = lruKey {
            store.removeValue(forKey: keyToRemove)
        }
    }

    /// Efficient removal of multiple oldest entries for batch operations
    private func removeOldestEntries(count: Int) async {
        guard count > 0, count < store.count else { return }

        // Sort all entries by access time and remove the oldest ones
        let sortedEntries = store.sorted { $0.value.lastAccessTime < $1.value.lastAccessTime }
        let keysToRemove = sortedEntries.prefix(count).map { $0.key }

        for key in keysToRemove {
            store.removeValue(forKey: key)
        }
    }

    /// Efficient expired entry cleanup using single-pass filtering
    private func cleanupExpired() {
        let currentTime = CFAbsoluteTimeGetCurrent()

        // Single-pass filtering instead of double iteration
        store = store.filter { _, entry in
            currentTime - entry.timestamp < config.ttl
        }
    }

    /// Start background cleanup with proper actor isolation
    private func startBackgroundCleanup() {
        // Cancel existing task to prevent leaks
        cleanupTask?.cancel()

        // Fixed: Proper actor isolation without MainActor switching
        cleanupTask = Task {
            while !Task.isCancelled {
                do {
                    try await Task.sleep(for: .seconds(config.cleanupInterval))
                    // Direct call within actor context - no nested tasks
                    cleanupExpired()
                } catch {
                    // Task was cancelled, exit gracefully
                    break
                }
            }
        }
    }
}

// MARK: - Supporting Types

/// Cache statistics for monitoring and debugging
struct CacheStats {
    let totalEntries: Int
    let expiredEntries: Int
    let validEntries: Int
    let maxSize: Int
    let ttl: TimeInterval
    let accessCount: Int
    let hitCount: Int

    /// True cache hit rate based on actual access patterns
    var hitRate: Double {
        guard accessCount > 0 else { return 0 }
        return Double(hitCount) / Double(accessCount)
    }

    /// Ratio of fresh entries to total entries
    var freshnessRatio: Double {
        guard totalEntries > 0 else { return 0 }
        return Double(validEntries) / Double(totalEntries)
    }

    /// Cache capacity utilization
    var memoryEfficiency: Double {
        guard maxSize > 0 else { return 0 }
        return Double(totalEntries) / Double(maxSize)
    }
}

// MARK: - Batch Operations

extension GasPriceCache {
    /// Batch operation for setting multiple gas prices efficiently
    func setGasPrices(_ estimates: [(chainId: Int, estimate: GasPriceEstimate)]) async {
        let currentTime = CFAbsoluteTimeGetCurrent()

        // Add all entries first
        for (chainId, estimate) in estimates {
            store[chainId] = CacheEntry(value: estimate, timestamp: currentTime)
        }

        // Single efficient cleanup to target size
        let excessCount = store.count - config.maxSize
        if excessCount > 0 {
            await removeOldestEntries(count: excessCount)
        }
    }

    /// Get multiple gas prices in a single operation
    func getGasPrices(for chainIds: [Int]) async -> [Int: CacheResult<GasPriceEstimate>] {
        var results: [Int: CacheResult<GasPriceEstimate>] = [:]

        for chainId in chainIds {
            results[chainId] = await getGasPrice(for: chainId)
        }

        return results
    }

    /// Get only valid gas prices for multiple chains
    func getValidGasPrices(for chainIds: [Int]) async -> [Int: GasPriceEstimate] {
        var results: [Int: GasPriceEstimate] = [:]

        for chainId in chainIds {
            if let estimate = await getValidGasPrice(for: chainId) {
                results[chainId] = estimate
            }
        }

        return results
    }
}
