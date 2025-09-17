//
//  infura.swift
//  KickingHorse
//
//  Created by Daniel Bell on 10/9/24.
//

import Foundation

struct Infura {
    // MARK: - Errors
    enum InfuraError: Error {
        case invalidKey
        case networkFailure(underlying: Error)
        case badStatus(Int)
        case rateLimited(remaining: Int?)
        case decodingFailed(underlying: Error)
        case invalidURL
        case backoffOverflow
        case nonHttpResponse
    }

    // Shared URLSession for efficient connection pooling
    private static let infuraSession: URLSession = {
        let cfg = URLSessionConfiguration.default
        cfg.timeoutIntervalForRequest = 10
        cfg.timeoutIntervalForResource = 30
        return URLSession(configuration: cfg)
    }()
    
    private let requestThrottler = RequestThrottler(minimumInterval: 0.1)
    private static let nanosecondsPerSecond: UInt64 = 1_000_000_000

    // Public API -------------------------------------------------------------
    func getGasPrice(chainId: Int = 1) async throws -> GasPriceEstimate {
        let cacheResult = await GasPriceCache.shared.getGasPrice(for: chainId)
        
        switch cacheResult {
        case .hit(let estimate):
            return estimate
            
        case .expired(let estimate):
            do {
                try await requestThrottler.throttle()
                let freshEstimate = try await fetchWithRetry(chainId: chainId, maxAttempts: 3)
                await GasPriceCache.shared.setGasPrice(freshEstimate, for: chainId)
                return freshEstimate
            } catch {
                return estimate
            }
            
        case .miss:
            try await requestThrottler.throttle()
            let estimate = try await fetchWithRetry(chainId: chainId, maxAttempts: 3)
            await GasPriceCache.shared.setGasPrice(estimate, for: chainId)
            return estimate
        }
    }
    
    // Immutable helpers ------------------------------------------------------
    private func buildURL(for chain: Int) throws -> URL {
        guard let key = Secrets.apiKeyOrNil(.infura) else { throw InfuraError.invalidKey }
        guard let url = URL(
            string: "https://gas.api.infura.io/v3/\(key)/networks/\(chain)/suggestedGasFees"
        ) else { throw InfuraError.invalidURL }
        return url
    }
    
    // Retry wrapper with intelligent rate limit handling
    private func fetchWithRetry(chainId: Int, maxAttempts: Int) async throws -> GasPriceEstimate {
        var delayNS: UInt64 = Self.nanosecondsPerSecond
        
        for attempt in 1...maxAttempts {
            do {
                return try await fetchOnce(chainId: chainId)
            } catch {
                guard attempt < maxAttempts,
                      let infErr = error as? InfuraError,
                      shouldRetry(after: infErr) else { throw error }
                
                // Intelligent delay calculation based on rate limit info
                delayNS = calculateRetryDelay(for: infErr, currentDelay: delayNS)
                try await Task.sleep(nanoseconds: delayNS)
            }
        }
        throw InfuraError.backoffOverflow
    }
    
    private func calculateRetryDelay(for error: InfuraError, currentDelay: UInt64) -> UInt64 {
        switch error {
        case .rateLimited(let remaining):
            // Intelligent backoff based on remaining rate limit
            if let remaining = remaining {
                if remaining <= 5 {
                    // Very few requests remaining - longer delay
                    return min(5 * Self.nanosecondsPerSecond, 8 * Self.nanosecondsPerSecond)
                } else if remaining <= 20 {
                    // Low remaining - moderate delay
                    return min(2 * Self.nanosecondsPerSecond, 8 * Self.nanosecondsPerSecond)
                }
            }
            // Default rate limit delay
            return min(Self.nanosecondsPerSecond, 8 * Self.nanosecondsPerSecond)
            
        default:
            // Standard exponential backoff for other retryable errors
            let (next, ovf) = currentDelay.multipliedReportingOverflow(by: 2)
            return ovf ? 8 * Self.nanosecondsPerSecond : min(next, 8 * Self.nanosecondsPerSecond)
        }
    }
    
    private func shouldRetry(after error: InfuraError) -> Bool {
        switch error {
        case .networkFailure:
            return true
        case .badStatus(let c) where (500...599).contains(c):
            return true
        case .rateLimited:
            return true
        default:
            return false
        }
    }
    
    // Single request ---------------------------------------------------------
    private func fetchOnce(chainId: Int) async throws -> GasPriceEstimate {
        let url = try buildURL(for: chainId)
        let req = URLRequest(url: url)
        
        let (data, resp): (Data, URLResponse)
        do {
            (data, resp) = try await Self.infuraSession.data(for: req)
        } catch {
            throw InfuraError.networkFailure(underlying: error)
        }
        
        guard let http = resp as? HTTPURLResponse else {
            throw InfuraError.nonHttpResponse
        }
        
        let status = http.statusCode
        let remaining = http.value(forHTTPHeaderField: "X-RateLimit-Remaining").flatMap(Int.init)
        
        switch status {
        case 200...299:
            break
        case 429, 503:
            throw InfuraError.rateLimited(remaining: remaining)
        default:
            throw InfuraError.badStatus(status)
        }
        
        do {
            return try JSONDecoder().decode(GasPriceEstimate.self, from: data)
        } catch {
            throw InfuraError.decodingFailed(underlying: error)
        }
    }
}
