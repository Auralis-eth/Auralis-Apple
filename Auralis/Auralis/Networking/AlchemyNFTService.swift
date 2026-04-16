//
//  AlchemyNFTService.swift
//  Auralis
//
//  Created by Daniel Bell on 3/29/25.
//

import Foundation
import OSLog

final class AlchemyNFTService: NFTInventoryProviding {
    private let logger = Logger(subsystem: "Auralis", category: "AlchemyNFTService")
    private let baseURL: URL
    private let network: String
    private var ownerFetchMode: OwnerFetchMode = .primary

    // MARK: - Initialization

    init(
        chain: Chain,
        configurationResolver: any ProviderConfigurationResolving = LiveProviderConfigurationResolver()
    ) throws {
        let configuration = try configurationResolver.configuration(for: chain)
        guard let baseURL = configuration.alchemyNFTBaseURL else {
            logger.error("Missing Alchemy NFT base URL for chain=\(chain.rawValue, privacy: .public)")
            throw ProviderAbstractionError.missingAPIKey(.alchemy)
        }

        self.network = chain.rawValue
        self.baseURL = baseURL
        logger.notice("Initialized Alchemy NFT service chain=\(chain.rawValue, privacy: .public) host=\(baseURL.host ?? "unknown", privacy: .public)")
    }

    // MARK: - Types

    enum SpamConfidenceLevel: String, CaseIterable {
        case veryHigh = "VERY_HIGH"
        case high = "HIGH"
        case medium = "MEDIUM"
        case low = "LOW"
        case veryLow = "VERY_LOW"
        case unknown = "UNKNOWN"
    }

    enum NFTFilter: String, CaseIterable {
        case spam = "SPAM"
        case airdrops = "AIRDROPS"
    }

    enum OrderBy: String {
        case transferTime = "transferTime"
    }

    private enum OwnerFetchMode {
        case primary
        case degraded
    }

    // Common error envelope shapes
    private struct ErrorEnvelope1: Decodable {
        struct Inner: Decodable {
            let code: String?
            let message: String?
            let details: String?
        }
        let error: Inner
    }
    
    private struct ErrorEnvelope2: Decodable {
        let code: String?
        let message: String?
        let detail: String?
        let error: String?
    }

    enum APIError: Error, LocalizedError {
        // Input validation
        case emptyOwner
        case invalidOwnerFormat
        case invalidContractAddress(String)
        case invalidPageSize
        case tooManyContractAddresses(max: Int)
        case mutuallyExclusiveFilters
        case orderingNotSupportedOnNetwork(String)
        case invalidTokenUriTimeout
        case invalidRequestTimeout

        // HTTP/Server side
        case badRequest(message: String?)
        case unauthorized(message: String?)
        case forbidden(message: String?)
        case notFound(message: String?)
        case requestTimeout(message: String?)
        case rateLimited(retryAfter: TimeInterval?, message: String?)
        case serverError(status: Int, message: String?)
        case httpError(status: Int, message: String?)
        case badURL
        case badServerResponse

        var errorDescription: String? {
            switch self {
            case .emptyOwner:
                return "Owner must not be empty."
            case .invalidOwnerFormat:
                return "Owner must be a valid Ethereum address (0x + 40 hex chars) or a valid ENS name (e.g., vitalik.eth)."
            case .invalidContractAddress(let addr):
                return "Invalid contract address: \(addr). Must be 0x + 40 hex chars."
            case .invalidPageSize:
                return "pageSize must be between 1 and 100."
            case .tooManyContractAddresses(let max):
                return "A maximum of \(max) contract addresses is allowed."
            case .mutuallyExclusiveFilters:
                return "excludeFilters and includeFilters are mutually exclusive. Provide only one."
            case .orderingNotSupportedOnNetwork(let net):
                return "orderBy is only supported on eth-mainnet and polygon-mainnet. Current network: \(net)."
            case .invalidTokenUriTimeout:
                return "tokenUriTimeoutInMs must be between 1 and 60000."
            case .invalidRequestTimeout:
                return "requestTimeoutSeconds must be between 1 and 120 seconds."
            case .badRequest(let msg):
                return "Bad request: \(msg ?? "No message")."
            case .unauthorized(let msg):
                return "Unauthorized: \(msg ?? "No message")."
            case .forbidden(let msg):
                return "Forbidden: \(msg ?? "No message")."
            case .notFound(let msg):
                return "Not found: \(msg ?? "No message")."
            case .requestTimeout(let msg):
                return "Request timeout: \(msg ?? "No message")."
            case .rateLimited(let retry, let msg):
                if let retry { return "Rate limited. Retry after \(retry) seconds. \(msg ?? "")" }
                return "Rate limited. \(msg ?? "")"
            case .serverError(let status, let msg):
                return "Server error \(status): \(msg ?? "No message")."
            case .httpError(let status, let msg):
                return "HTTP error \(status): \(msg ?? "No message")."
            case .badURL:
                return "Failed to construct URL."
            case .badServerResponse:
                return "Invalid server response."
            }
        }
    }

    // MARK: - Public API

    func nftsForOwner(
        owner: String,
        pageKey: String?
    ) async throws -> AlchemyNFTResponse {
        if ownerFetchMode == .degraded {
            return try await degradedNFTsForOwner(owner: owner, pageKey: pageKey)
        }

        do {
            return try await getNFTsForOwner(owner: owner, pageKey: pageKey)
        } catch let error as APIError {
            guard case .serverError = error else {
                throw error
            }

            ownerFetchMode = .degraded
            logger.notice("Primary owner fetch failed; retrying degraded request")
            return try await degradedNFTsForOwner(owner: owner, pageKey: pageKey)
        }
    }

    func getNFTsForOwner(
        owner: String,
        contractAddresses: [String]? = nil,
        withMetadata: Bool = true,
        orderBy: OrderBy? = nil,
        excludeFilters: [NFTFilter]? = nil,
        includeFilters: [NFTFilter]? = nil,
        spamConfidenceLevel: SpamConfidenceLevel? = nil,
        tokenUriTimeoutInMs: Int? = nil,
        pageKey: String? = nil,
        pageSize: Int = 100,
        requestTimeoutSeconds: TimeInterval = 30
    ) async throws -> AlchemyNFTResponse {
        // Sanitize inputs
        let trimmedOwner = owner.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedOwner.isEmpty else { throw APIError.emptyOwner }

        // Owner must be ETH address or ENS
        guard Self.isValidEthereumAddress(trimmedOwner) || Self.isValidENSName(trimmedOwner) else {
            throw APIError.invalidOwnerFormat
        }

        // Page size 1-100
        guard (1...100).contains(pageSize) else { throw APIError.invalidPageSize }

        // Contract address validation and limit
        var normalizedAddresses: [String]? = nil
        if let addresses = contractAddresses {
            if addresses.count > 45 {
                throw APIError.tooManyContractAddresses(max: 45)
            }
            let trimmed = addresses.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            for addr in trimmed where !addr.isEmpty {
                guard Self.isValidEthereumAddress(addr) else {
                    throw APIError.invalidContractAddress(addr)
                }
            }
            normalizedAddresses = trimmed.filter { !$0.isEmpty }
        }

        // Mutually exclusive filters
        let hasExclude = (excludeFilters?.isEmpty == false)
        let hasInclude = (includeFilters?.isEmpty == false)
        if hasExclude && hasInclude {
            throw APIError.mutuallyExclusiveFilters
        }

        // orderBy network check
        if orderBy != nil {
            let supportedForOrderBy: Set<String> = ["eth-mainnet", "polygon-mainnet"]
            if !supportedForOrderBy.contains(network) {
                throw APIError.orderingNotSupportedOnNetwork(network)
            }
        }

        // tokenUriTimeoutInMs 1-60000
        if let tokenUriTimeoutInMs {
            guard (1...60000).contains(tokenUriTimeoutInMs) else {
                throw APIError.invalidTokenUriTimeout
            }
        }

        // Request timeout 1-120 s
        guard requestTimeoutSeconds >= 1, requestTimeoutSeconds <= 120 else {
            throw APIError.invalidRequestTimeout
        }

        // URL and components
        let url = baseURL.appending(path: "getNFTsForOwner")
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: true) else {
            throw APIError.badURL
        }

        // Build query via helper (sanitized inputs)
        let queryItems = try buildQueryItems(
            owner: trimmedOwner,
            contractAddresses: normalizedAddresses,
            withMetadata: withMetadata,
            orderBy: orderBy,
            excludeFilters: excludeFilters,
            includeFilters: includeFilters,
            spamConfidenceLevel: spamConfidenceLevel,
            tokenUriTimeoutInMs: tokenUriTimeoutInMs,
            pageKey: pageKey?.trimmingCharacters(in: .whitespacesAndNewlines),
            pageSize: pageSize
        )

        components.queryItems = queryItems
        guard let finalURL = components.url else { throw APIError.badURL }

        var request = URLRequest(url: finalURL)
        request.httpMethod = "GET"
        request.timeoutInterval = requestTimeoutSeconds
        request.addValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.badServerResponse
        }

        if !(200...299).contains(httpResponse.statusCode) {
            logger.error(
                "Alchemy response status=\(httpResponse.statusCode, privacy: .public) message=\(self.parseErrorMessage(from: data) ?? "nil", privacy: .public)"
            )
        }

        // Decode or throw typed errors
        switch httpResponse.statusCode {
        case 200:
            let decoder = JSONDecoder()
            return try decoder.decode(AlchemyNFTResponse.self, from: data)
        case 400:
            throw APIError.badRequest(message: parseErrorMessage(from: data))
        case 401:
            throw APIError.unauthorized(message: parseErrorMessage(from: data))
        case 403:
            throw APIError.forbidden(message: parseErrorMessage(from: data))
        case 404:
            throw APIError.notFound(message: parseErrorMessage(from: data))
        case 408:
            throw APIError.requestTimeout(message: parseErrorMessage(from: data))
        case 429:
            let retry = parseRetryAfter(from: httpResponse)
            throw APIError.rateLimited(retryAfter: retry, message: parseErrorMessage(from: data))
        case 500...599:
            throw APIError.serverError(status: httpResponse.statusCode, message: parseErrorMessage(from: data))
        default:
            throw APIError.httpError(status: httpResponse.statusCode, message: parseErrorMessage(from: data))
        }
    }

    // MARK: - Helpers

    private func buildQueryItems(
        owner: String,
        contractAddresses: [String]?,
        withMetadata: Bool,
        orderBy: OrderBy?,
        excludeFilters: [NFTFilter]?,
        includeFilters: [NFTFilter]?,
        spamConfidenceLevel: SpamConfidenceLevel?,
        tokenUriTimeoutInMs: Int?,
        pageKey: String?,
        pageSize: Int
    ) throws -> [URLQueryItem] {
        var items: [URLQueryItem] = [
            URLQueryItem(name: "owner", value: owner),
            URLQueryItem(name: "withMetadata", value: withMetadata ? "true" : "false"),
            URLQueryItem(name: "pageSize", value: String(pageSize))
        ]

        if let addresses = contractAddresses, !addresses.isEmpty {
            items.append(contentsOf: addresses.map { URLQueryItem(name: "contractAddresses[]", value: $0) })
        }

        if let orderBy {
            items.append(URLQueryItem(name: "orderBy", value: orderBy.rawValue))
        }

        if let excludeFilters, !excludeFilters.isEmpty {
            items.append(contentsOf: excludeFilters.map { URLQueryItem(name: "excludeFilters[]", value: $0.rawValue) })
        }

        if let includeFilters, !includeFilters.isEmpty {
            items.append(contentsOf: includeFilters.map { URLQueryItem(name: "includeFilters[]", value: $0.rawValue) })
        }

        if let tokenUriTimeoutInMs {
            items.append(URLQueryItem(name: "tokenUriTimeoutInMs", value: String(tokenUriTimeoutInMs)))
        }

        if let pageKey, !pageKey.isEmpty {
            items.append(URLQueryItem(name: "pageKey", value: pageKey))
        }

        return items
    }

    private func degradedNFTsForOwner(
        owner: String,
        pageKey: String?
    ) async throws -> AlchemyNFTResponse {
        try await getNFTsForOwner(
            owner: owner,
            withMetadata: false,
            tokenUriTimeoutInMs: 1,
            pageKey: pageKey,
            pageSize: 50
        )
    }

    private func parseErrorMessage(from data: Data) -> String? {
        if let env1 = try? JSONDecoder().decode(ErrorEnvelope1.self, from: data) {
            return env1.error.message ?? env1.error.details ?? env1.error.code
        }
        if let env2 = try? JSONDecoder().decode(ErrorEnvelope2.self, from: data) {
            return env2.message ?? env2.detail ?? env2.error ?? env2.code
        }
        return String(data: data, encoding: .utf8)
    }

    private func parseRetryAfter(from response: HTTPURLResponse) -> TimeInterval? {
        guard let header = response.value(forHTTPHeaderField: "Retry-After") else { return nil }
        if let seconds = TimeInterval(header.trimmingCharacters(in: .whitespaces)) {
            return seconds
        }
        return nil
    }

    private static func redactedURLString(_ url: URL) -> String {
        let absoluteString = url.absoluteString
        guard let range = absoluteString.range(of: "/nft/v3/") else {
            return absoluteString
        }

        let suffix = absoluteString[range.upperBound...]
        guard let nextSlash = suffix.firstIndex(of: "/") else {
            return absoluteString
        }

        let redactedStart = range.upperBound
        let redactedEnd = nextSlash
        return absoluteString.replacingCharacters(in: redactedStart..<redactedEnd, with: "<redacted>")
    }

    // MARK: - Validation

    // Safe regex compilation (optional)
    private static let ethAddressRegex: NSRegularExpression? = {
        try? NSRegularExpression(pattern: "^0x[0-9a-fA-F]{40}$")
    }()

    // ENS: labels of [a-z0-9-], 1-63 chars, ends with .eth
    private static let ensNameRegex: NSRegularExpression? = {
        try? NSRegularExpression(
            pattern: "^(?:[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?\\.)+eth$",
            options: [.caseInsensitive]
        )
    }()

    private static func isValidEthereumAddress(_ value: String) -> Bool {
        guard let regex = ethAddressRegex else { return false }
        let range = NSRange(value.startIndex..., in: value)
        return regex.firstMatch(in: value, options: [], range: range) != nil
    }

    private static func isValidENSName(_ value: String) -> Bool {
        guard let regex = ensNameRegex else { return false }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let range = NSRange(trimmed.startIndex..., in: trimmed)
        return regex.firstMatch(in: trimmed, options: [], range: range) != nil
    }
}
