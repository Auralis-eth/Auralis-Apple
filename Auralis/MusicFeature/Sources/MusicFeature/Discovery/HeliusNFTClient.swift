import Foundation
import OSLog

public actor HeliusNFTClient: SolanaNFTDiscovering {
    public typealias WarningLogger = @Sendable (String) -> Void

    private let apiKey: String
    private let urlSession: URLSession
    private let endpointBaseURL: URL
    private let pageLimit: Int
    private let retryCount: Int
    private let retryDelayNanoseconds: UInt64
    private let warningLogger: WarningLogger

    private static let nanosecondsPerSecond: UInt64 = 1_000_000_000

    public init(
        apiKey: String,
        urlSession: URLSession = .shared,
        endpointBaseURL: URL = URL(string: "https://mainnet.helius-rpc.com/")!,
        pageLimit: Int = 1000,
        retryCount: Int = 3,
        retryDelayNanoseconds: UInt64 = 1_000_000_000,
        warningLogger: @escaping WarningLogger = HeliusNFTClient.logWarning
    ) {
        self.apiKey = apiKey
        self.urlSession = urlSession
        self.endpointBaseURL = endpointBaseURL
        self.pageLimit = min(max(pageLimit, 1), 1000)
        self.retryCount = max(retryCount, 1)
        self.retryDelayNanoseconds = retryDelayNanoseconds
        self.warningLogger = warningLogger
    }

    public func fetchAll(owner: String) async throws -> [NFTTokenDTO] {
        let trimmedOwner = owner.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedOwner.isEmpty else {
            throw AuraPlayError.library("Helius NFT discovery requires a wallet address.")
        }

        var page = 1
        var allTokens: [NFTTokenDTO] = []

        while true {
            let result = try await fetchPage(owner: trimmedOwner, page: page).unwrappedResult
            let mappedTokens = result.items.compactMap { asset -> NFTTokenDTO? in
                guard asset.ownership.owner == trimmedOwner else {
                    warningLogger("Skipping Helius asset \(asset.id) because response owner \(asset.ownership.owner) does not match requested owner \(trimmedOwner).")
                    return nil
                }
                return map(asset: asset, owner: trimmedOwner)
            }
            allTokens.append(contentsOf: mappedTokens)

            if result.items.count < pageLimit {
                break
            }
            page += 1
        }

        return deduplicated(allTokens)
    }
}

public extension HeliusNFTClient {
    nonisolated static func logWarning(_ message: String) {
        Logger(subsystem: "Auralis", category: "music.discovery.helius").warning("\(message, privacy: .public)")
    }
}

private extension HeliusNFTClient {
    func fetchPage(owner: String, page: Int) async throws -> HeliusDASResponse {
        var lastError: Error?

        for attempt in 1...retryCount {
            do {
                return try await fetchPageOnce(owner: owner, page: page)
            } catch {
                lastError = error
                if shouldRetry(error), attempt < retryCount {
                    try await Task.sleep(nanoseconds: retryDelay(after: error, attempt: attempt))
                    continue
                }
                throw mappedFinalError(error)
            }
        }

        throw lastError.map(mappedFinalError) ?? AuraPlayError.library("Helius NFT discovery failed.")
    }

    func fetchPageOnce(owner: String, page: Int) async throws -> HeliusDASResponse {
        let endpointURL = try endpointURL()
        var request = URLRequest(url: endpointURL)
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.addValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = try makeRequestBody(owner: owner, page: page)

        let (data, response) = try await urlSession.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw AuraPlayError.library("Helius NFT discovery returned a non-HTTP response.")
        }

        let decoder = JSONDecoder()
        switch httpResponse.statusCode {
        case 200...299:
            let envelope = try decoder.decode(HeliusDASResponse.self, from: data)
            if let error = envelope.error {
                throw mapRPCError(error)
            }
            guard envelope.result != nil else {
                throw AuraPlayError.library("Helius NFT discovery returned an empty response.")
            }
            return envelope
        case 401, 403:
            throw HeliusNFTClientError.unauthorized
        case 404:
            return HeliusDASResponse.empty(page: page)
        case 429:
            throw HeliusNFTClientError.rateLimited(retryAfter: parseRetryAfter(from: httpResponse))
        case 500...599:
            throw HeliusNFTClientError.serverError(statusCode: httpResponse.statusCode)
        default:
            throw AuraPlayError.library("Helius NFT discovery failed with HTTP \(httpResponse.statusCode).")
        }
    }

    func endpointURL() throws -> URL {
        guard var components = URLComponents(url: endpointBaseURL, resolvingAgainstBaseURL: false) else {
            throw AuraPlayError.library("Helius endpoint URL is invalid.")
        }
        components.queryItems = [URLQueryItem(name: "api-key", value: apiKey)]
        guard let url = components.url else {
            throw AuraPlayError.library("Helius endpoint URL could not be constructed.")
        }
        return url
    }

    func makeRequestBody(owner: String, page: Int) throws -> Data {
        let requestObject: [String: Any] = [
            "jsonrpc": "2.0",
            "id": UUID().uuidString,
            "method": "getAssetsByOwner",
            "params": [
                "ownerAddress": owner,
                "page": page,
                "limit": pageLimit,
                "sortBy": [
                    "sortBy": "created",
                    "sortDirection": "desc"
                ],
                "options": [
                    "showUnverifiedCollections": true,
                    "showCollectionMetadata": true,
                    "showFungible": false,
                    "showNativeBalance": false,
                    "showZeroBalance": false
                ]
            ]
        ]

        return try JSONSerialization.data(withJSONObject: requestObject)
    }

    func shouldRetry(_ error: Error) -> Bool {
        if case .rateLimited = error as? HeliusNFTClientError {
            return true
        }

        if case .serverError = error as? HeliusNFTClientError {
            return true
        }

        let urlError = error as? URLError
        return urlError?.code == .timedOut ||
        urlError?.code == .networkConnectionLost ||
        urlError?.code == .notConnectedToInternet
    }

    func mappedFinalError(_ error: Error) -> Error {
        if case HeliusNFTClientError.rateLimited = error {
            return AuraPlayError.network(.rateLimited)
        }
        if case HeliusNFTClientError.unauthorized = error {
            return AuraPlayError.library("Helius NFT discovery is not authorized for this API key.")
        }
        return error
    }

    func retryDelay(after error: Error, attempt: Int) -> UInt64 {
        if case .rateLimited(let retryAfter?) = error as? HeliusNFTClientError {
            let retryDelay = UInt64(max(0, retryAfter) * Double(Self.nanosecondsPerSecond))
            return retryDelay
        }

        return retryDelayNanoseconds * UInt64(attempt)
    }

    func map(asset: HeliusAsset, owner: String) -> NFTTokenDTO {
        let contractAddress = asset.grouping?.first {
            $0.groupKey == "collection"
        }?.groupValue
        let metadataRaw = asset.encodedRawJSON()

        return NFTTokenDTO(
            chain: .solanaMainnet,
            walletAddress: owner,
            contractAddress: contractAddress,
            tokenId: asset.id,
            tokenStandard: asset.interface,
            collectionName: nil,
            name: asset.content.metadata.name,
            description: asset.content.metadata.description,
            imageURL: asset.content.links?.image,
            metadataURL: asset.content.jsonURI,
            metadataRaw: metadataRaw,
            providerUpdatedAt: nil,
            isActive: true,
            provider: .helius
        )
    }

    func deduplicated(_ tokens: [NFTTokenDTO]) -> [NFTTokenDTO] {
        var seenIDs = Set<String>()
        var deduplicatedTokens: [NFTTokenDTO] = []

        for token in tokens where seenIDs.insert(token.compositeID).inserted {
            deduplicatedTokens.append(token)
        }
        return deduplicatedTokens
    }
}

private enum HeliusNFTClientError: Error, Equatable {
    case rateLimited(retryAfter: TimeInterval?)
    case unauthorized
    case serverError(statusCode: Int)
}

private struct HeliusDASResponse: Decodable {
    let result: HeliusResult?
    let error: HeliusRPCError?

    static func empty(page: Int) -> HeliusDASResponse {
        HeliusDASResponse(
            result: HeliusResult(items: [], total: 0, page: page),
            error: nil
        )
    }
}

private extension HeliusDASResponse {
    var unwrappedResult: HeliusResult {
        get throws {
            guard let result else {
                throw AuraPlayError.library("Helius NFT discovery returned an empty response.")
            }
            return result
        }
    }
}

private struct HeliusRPCError: Decodable {
    let code: Int
    let message: String
}

private struct HeliusResult: Decodable {
    let items: [HeliusAsset]
    let total: Int?
    let page: Int
}

private struct HeliusAsset: Codable {
    let id: String
    let content: HeliusContent
    let grouping: [HeliusGrouping]?
    let creators: [HeliusCreator]?
    let interface: String
    let ownership: HeliusOwnership

    func encodedRawJSON() -> String? {
        guard let data = try? JSONEncoder().encode(self) else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }
}

private struct HeliusContent: Codable {
    let metadata: HeliusMetadata
    let links: HeliusLinks?
    let jsonURI: String?
    let files: [HeliusFile]?

    enum CodingKeys: String, CodingKey {
        case metadata
        case links
        case jsonURI = "json_uri"
        case files
    }
}

private struct HeliusMetadata: Codable {
    let name: String?
    let description: String?
    let symbol: String?
}

private struct HeliusLinks: Codable {
    let image: String?
    let animationURL: String?
    let audioURL: String?

    enum CodingKeys: String, CodingKey {
        case image
        case animationURL = "animation_url"
        case audioURL = "audio_url"
    }
}

private struct HeliusFile: Codable {
    let uri: String?
    let cdnURI: String?
    let mime: String?

    enum CodingKeys: String, CodingKey {
        case uri
        case cdnURI = "cdn_uri"
        case mime
    }
}

private struct HeliusGrouping: Codable {
    let groupKey: String
    let groupValue: String

    enum CodingKeys: String, CodingKey {
        case groupKey = "group_key"
        case groupValue = "group_value"
    }
}

private struct HeliusCreator: Codable {
    let address: String?
}

private struct HeliusOwnership: Codable {
    let owner: String
}

private extension HeliusNFTClient {
    func mapRPCError(_ error: HeliusRPCError) -> Error {
        let normalizedMessage = error.message.lowercased()

        if error.code == 429 || normalizedMessage.contains("rate limit") || normalizedMessage.contains("too many requests") {
            return HeliusNFTClientError.rateLimited(retryAfter: nil)
        }

        if error.code == -32001
            || error.code == -32003
            || normalizedMessage.contains("unauthorized")
            || normalizedMessage.contains("forbidden")
            || normalizedMessage.contains("api key") {
            return HeliusNFTClientError.unauthorized
        }

        return AuraPlayError.library("Helius NFT discovery failed: \(sanitizedRPCMessage(error.message))")
    }

    func parseRetryAfter(from response: HTTPURLResponse, now: Date = .now) -> TimeInterval? {
        guard let header = response.value(forHTTPHeaderField: "Retry-After") else {
            return nil
        }

        return parseRetryAfter(header, now: now)
    }

    func parseRetryAfter(_ header: String, now: Date = .now) -> TimeInterval? {
        let trimmed = header.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return nil
        }

        if let seconds = TimeInterval(trimmed) {
            return seconds
        }

        guard let retryDate = httpDateParsers.lazy.compactMap({ $0.date(from: trimmed) }).first else {
            return nil
        }

        return max(0, retryDate.timeIntervalSince(now))
    }

    func sanitizedRPCMessage(_ message: String) -> String {
        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return "empty provider error"
        }

        let secretLikePatterns = [
            #"(?i)(authorization|access[_-]?token|refresh[_-]?token|id[_-]?token|bearer|cookie|set-cookie|private[_-]?key|seed|mnemonic|password|secret|api[_-]?key)\s*[:=]"#,
            #"(?i)bearer\s+[A-Za-z0-9._~+/=-]{8,}"#,
            #"(?i)-----BEGIN\s+(EC\s+|RSA\s+|OPENSSH\s+)?PRIVATE\s+KEY-----"#
        ]

        if secretLikePatterns.contains(where: { trimmed.range(of: $0, options: .regularExpression) != nil }) {
            return "provider error payload redacted"
        }

        return String(trimmed.prefix(160))
    }

    var httpDateParsers: [DateFormatter] {
        [
            makeHTTPDateFormatter("EEE',' dd MMM yyyy HH':'mm':'ss zzz"),
            makeHTTPDateFormatter("EEEE',' dd'-'MMM'-'yy HH':'mm':'ss zzz"),
            makeHTTPDateFormatter("EEE MMM d HH':'mm':'ss yyyy")
        ]
    }

    func makeHTTPDateFormatter(_ format: String) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = format
        return formatter
    }
}
