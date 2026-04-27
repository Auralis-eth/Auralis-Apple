import Foundation
import OSLog

struct Secrets {
    private static let logger = Logger(subsystem: "Auralis", category: "Secrets")
    private static let missingProviderLogState = MissingProviderLogState()

    struct ConfigurationStatus: Equatable, Identifiable {
        let provider: APIKeyProvider
        let isConfigured: Bool

        var id: APIKeyProvider { provider }
        var sourceDescription: String {
            isConfigured ? "Info.plist" : "Missing"
        }
    }

    enum APIKeyProvider: String, CaseIterable {
        case alchemy = "Alchemy"

        var infoPlistKeyName: String {
            "AURALIS_\(rawValue.uppercased())_API_KEY"
        }
    }

    enum SecretsError: LocalizedError {
        case providerKeyNotFound(APIKeyProvider)

        var errorDescription: String? {
            switch self {
            case .providerKeyNotFound(let provider):
                return "API key for \(provider.rawValue) is missing from Info.plist."
            }
        }
    }

    static func apiKey(_ provider: APIKeyProvider, bundle: Bundle = .main) throws -> String {
        guard let infoDictionary = bundle.infoDictionary,
              let value = sanitizedKeyValue(infoDictionary[provider.infoPlistKeyName] as? String) else {
            logMissingProviderIfNeeded(provider)
            throw SecretsError.providerKeyNotFound(provider)
        }

        return value
    }

    static func apiKeyOrNil(_ provider: APIKeyProvider, bundle: Bundle = .main) -> String? {
        try? apiKey(provider, bundle: bundle)
    }

    static func configurationStatuses(bundle: Bundle = .main) -> [ConfigurationStatus] {
        APIKeyProvider.allCases.map { provider in
            ConfigurationStatus(
                provider: provider,
                isConfigured: apiKeyOrNil(provider, bundle: bundle) != nil
            )
        }
    }

    static func validateRequiredProviders(
        _ providers: [APIKeyProvider],
        bundle: Bundle = .main
    ) throws {
        for provider in providers {
            _ = try apiKey(provider, bundle: bundle)
        }
    }

    static func preloadKeys(
        requiredProviders: [APIKeyProvider] = [],
        bundle: Bundle = .main
    ) throws {
        try validateRequiredProviders(requiredProviders, bundle: bundle)
    }

    static func resetCache() { }

    static func cacheInfo() -> (isLoaded: Bool, bundlePath: String?, providerCount: Int) {
        let configuredCount = configurationStatuses().filter(\.isConfigured).count
        return (configuredCount > 0, Bundle.main.bundleURL.path, configuredCount)
    }
}

private extension Secrets {
    static func logMissingProviderIfNeeded(_ provider: APIKeyProvider) {
        guard missingProviderLogState.shouldLog(provider) else {
            return
        }

        logger.error("Missing or invalid \(provider.rawValue, privacy: .public) key in Info.plist")
    }

    static func sanitizedKeyValue(_ rawValue: String?) -> String? {
        guard let trimmed = rawValue?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty,
              !looksLikePlaceholder(trimmed) else {
            return nil
        }

        return trimmed
    }

    static func looksLikePlaceholder(_ value: String) -> Bool {
        let uppercase = value.uppercased()
        return uppercase.contains("YOUR_")
            || uppercase.contains("REPLACE_ME")
            || uppercase.contains("PLACEHOLDER")
            || uppercase.hasPrefix("$(")
            || uppercase.hasPrefix("<#")
    }
}

private final class MissingProviderLogState: @unchecked Sendable {
    private let lock = NSLock()
    private var loggedProviders = Set<Secrets.APIKeyProvider>()

    func shouldLog(_ provider: Secrets.APIKeyProvider) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return loggedProviders.insert(provider).inserted
    }
}
