import Foundation

struct Secrets {
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
        let plistValue = bundle.infoDictionary?[provider.infoPlistKeyName] as? String
        print(
            "[Secrets] resolving \(provider.rawValue) key from \(provider.infoPlistKeyName) " +
            "bundle=\(bundle.bundleURL.lastPathComponent) rawPresent=\(plistValue != nil)"
        )
        guard let infoDictionary = bundle.infoDictionary,
              let value = sanitizedKeyValue(infoDictionary[provider.infoPlistKeyName] as? String) else {
            print("[Secrets] missing or invalid \(provider.rawValue) key in Info.plist")
            throw SecretsError.providerKeyNotFound(provider)
        }

        print("[Secrets] resolved \(provider.rawValue) key length=\(value.count)")
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
