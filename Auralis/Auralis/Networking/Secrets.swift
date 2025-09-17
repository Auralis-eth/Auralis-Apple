//
//  Secrets.swift
//  Auralis
//
//  Created by Daniel Bell on 3/22/25.
//

import Foundation

struct Secrets {
    enum APIKeyProvider: String, CaseIterable {
        case moralis = "Moralis"
        case infura = "Infura"
        case alchemy = "Alchemy"
    }
    
    enum SecretsError: LocalizedError {
        case fileNotFound
        case invalidData
        case parsingFailed
        case missingAPIKeySection
        case providerKeyNotFound(APIKeyProvider)
        
        var errorDescription: String? {
            switch self {
            case .fileNotFound:
                return "Secrets.plist not found in bundle"
            case .invalidData:
                return "Unable to read Secrets.plist data"
            case .parsingFailed:
                return "Failed to parse Secrets.plist as property list"
            case .missingAPIKeySection:
                return "API_KEY section missing from Secrets.plist"
            case .providerKeyNotFound(let provider):
                return "API key for \(provider.rawValue) not found in Secrets.plist"
            }
        }
    }
    
    private struct CacheState {
        let keys: [APIKeyProvider: String]
        let bundleURL: URL
    }
    
    private static var cacheState: CacheState?
    private static let cacheQueue = DispatchQueue(label: "secrets.cache", attributes: .concurrent)
    
    // Create unique bundle identifier that works even when bundleIdentifier is nil
    private static func bundleKey(for bundle: Bundle) -> URL {
        return bundle.bundleURL
    }
    
    // Load keys with proper thread safety and bundle tracking
    private static func loadKeysIfNeeded(from bundle: Bundle) throws -> [APIKeyProvider: String] {
        let bundleURL = bundleKey(for: bundle)
        
        // Use barrier for thread-safe read-check-write
        return try cacheQueue.sync(flags: .barrier) {
            // Check if we have valid cache for this bundle
            if let cached = cacheState, cached.bundleURL == bundleURL {
                return cached.keys
            }
            
            // Load from file
            guard let url = bundle.url(forResource: "Secrets", withExtension: "plist") else {
                throw SecretsError.fileNotFound
            }
            
            let data: Data
            do {
                data = try Data(contentsOf: url)
            } catch {
                throw SecretsError.invalidData
            }
            
            let dict: [String: Any]
            do {
                guard let parsed = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else {
                    throw SecretsError.parsingFailed
                }
                dict = parsed
            } catch {
                throw SecretsError.parsingFailed
            }
            
            guard let apiKeys = dict["API_KEY"] as? [String: String] else {
                throw SecretsError.missingAPIKeySection
            }
            
            // Build cache
            var keys: [APIKeyProvider: String] = [:]
            for provider in APIKeyProvider.allCases {
                if let key = apiKeys[provider.rawValue], !key.isEmpty {
                    keys[provider] = key
                }
            }
            
            // Update cache atomically
            cacheState = CacheState(keys: keys, bundleURL: bundleURL)
            return keys
        }
    }
    
    // Primary API - throws on failure
    static func apiKey(_ provider: APIKeyProvider, bundle: Bundle = .main) throws -> String {
        let keys = try loadKeysIfNeeded(from: bundle)
        
        guard let key = keys[provider] else {
            throw SecretsError.providerKeyNotFound(provider)
        }
        
        return key
    }
    
    // Convenience API - returns nil on failure
    static func apiKeyOrNil(_ provider: APIKeyProvider, bundle: Bundle = .main) -> String? {
        return try? apiKey(provider, bundle: bundle)
    }
    
    // Preload for performance (useful at app startup)
    static func preloadKeys(bundle: Bundle = .main) throws {
        _ = try loadKeysIfNeeded(from: bundle)
    }
    
    // Reset cache (useful for testing)
    static func resetCache() {
        cacheQueue.sync(flags: .barrier) {
            cacheState = nil
        }
    }
    
    // Debug helper
    static func cacheInfo() -> (isLoaded: Bool, bundlePath: String?, providerCount: Int) {
        return cacheQueue.sync {
            guard let state = cacheState else {
                return (false, nil, 0)
            }
            return (true, state.bundleURL.path, state.keys.count)
        }
    }
}
