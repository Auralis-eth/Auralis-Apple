import AuralisPrimaryModels
import Foundation
import OSLog

public final class HeliusDASNFTService: NFTInventoryProviding, Sendable {
    private enum RequestError: Error {
        case badStatus(Int, message: String?, retryAfter: TimeInterval?)
        case invalidResponse
    }

    private let logger = Logger(subsystem: "Auralis", category: "HeliusDASNFTService")
    private let apiKey: String
    private let endpointBaseURL: URL
    private let session: URLSession
    private let pageLimit: Int
    private let maxRetryCount: Int
    private let baseDelayNanoseconds: UInt64
    private let maxDelayNanoseconds: UInt64

    private static let nanosecondsPerSecond: UInt64 = 1_000_000_000

    public init(
        apiKey: String,
        session: URLSession? = nil,
        endpointBaseURL: URL = URL(string: "https://mainnet.helius-rpc.com/")!,
        pageLimit: Int = 1000,
        maxRetryCount: Int = 3,
        baseDelayNanoseconds: UInt64 = 200_000_000,
        maxDelayNanoseconds: UInt64 = 2_000_000_000
    ) {
        self.apiKey = apiKey
        self.session = session ?? .shared
        self.endpointBaseURL = endpointBaseURL
        self.pageLimit = min(max(pageLimit, 1), 1000)
        self.maxRetryCount = max(maxRetryCount, 1)
        self.baseDelayNanoseconds = baseDelayNanoseconds
        self.maxDelayNanoseconds = maxDelayNanoseconds
    }

    public func nftsForOwner(owner: String, pageKey: String?) async throws -> AlchemyNFTResponse {
        let trimmedOwner = owner.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedOwner.isEmpty else {
            throw ProviderAbstractionError.invalidAddress
        }

        let page = max(Int(pageKey ?? "1") ?? 1, 1)
        let result = try await fetchPage(owner: trimmedOwner, page: page).unwrappedResult
        let mappedNFTs = result.items.compactMap { asset -> AlchemyNFTResponse.OwnedNFT? in
            guard asset.ownership.owner == trimmedOwner else {
                logger.warning("Skipping Helius asset with owner mismatch asset=\(asset.id, privacy: .public)")
                return nil
            }
            return map(asset: asset, owner: trimmedOwner)
        }

        let nextPageKey = result.items.count == pageLimit ? String(result.page + 1) : nil

        return AlchemyNFTResponse(
            ownedNfts: mappedNFTs,
            totalCount: result.total,
            pageKey: nextPageKey,
            validAt: nil
        )
    }
}

private extension HeliusDASNFTService {
    func fetchPage(owner: String, page: Int) async throws -> HeliusDASResponse {
        var delay = baseDelayNanoseconds

        for attempt in 1...maxRetryCount {
            do {
                return try await fetchPageOnce(owner: owner, page: page)
            } catch {
                guard attempt < maxRetryCount, shouldRetry(error) else {
                    throw mapRequestError(error)
                }

                try await Task.sleep(nanoseconds: retryDelay(after: error, fallbackDelay: delay))
                let (nextDelay, overflowed) = delay.multipliedReportingOverflow(by: 2)
                delay = overflowed ? maxDelayNanoseconds : min(nextDelay, maxDelayNanoseconds)
            }
        }

        throw ProviderAbstractionError.invalidResponse
    }

    func fetchPageOnce(owner: String, page: Int) async throws -> HeliusDASResponse {
        let request = try makeRequest(owner: owner, page: page)
        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw RequestError.invalidResponse
        }

        let decoder = JSONDecoder()
        switch httpResponse.statusCode {
        case 200...299:
            let envelope = try decoder.decode(HeliusDASResponse.self, from: data)
            if let error = envelope.error {
                throw mapRPCError(error)
            }
            guard envelope.result != nil else {
                throw RequestError.invalidResponse
            }
            return envelope
        case 401, 403:
            throw ProviderAbstractionError.unauthorized
        case 404:
            return HeliusDASResponse.empty(page: page)
        case 429:
            throw RequestError.badStatus(
                httpResponse.statusCode,
                message: sanitizedProviderErrorMessage(from: data),
                retryAfter: RetryAfterSupport.parse(from: httpResponse)
            )
        case 500...599:
            throw RequestError.badStatus(
                httpResponse.statusCode,
                message: sanitizedProviderErrorMessage(from: data),
                retryAfter: nil
            )
        default:
            throw RequestError.badStatus(
                httpResponse.statusCode,
                message: sanitizedProviderErrorMessage(from: data),
                retryAfter: nil
            )
        }
    }

    func makeRequest(owner: String, page: Int) throws -> URLRequest {
        guard var components = URLComponents(url: endpointBaseURL, resolvingAgainstBaseURL: false) else {
            throw ProviderAbstractionError.invalidURL
        }
        components.queryItems = [URLQueryItem(name: "api-key", value: apiKey)]
        guard let url = components.url else {
            throw ProviderAbstractionError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.addValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = try makeRequestBody(owner: owner, page: page)
        return request
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
        if let requestError = error as? RequestError {
            switch requestError {
            case .badStatus(let statusCode, _, _):
                return statusCode == 429 || (500...599).contains(statusCode)
            case .invalidResponse:
                return false
            }
        }

        if let providerError = error as? ProviderAbstractionError {
            switch providerError {
            case .rateLimited, .unavailable:
                return true
            default:
                return false
            }
        }

        if let urlError = error as? URLError {
            switch urlError.code {
            case .timedOut, .cannotConnectToHost, .networkConnectionLost, .notConnectedToInternet:
                return true
            default:
                return false
            }
        }

        return false
    }

    func mapRequestError(_ error: Error) -> Error {
        if let requestError = error as? RequestError {
            switch requestError {
            case .badStatus(let statusCode, _, _) where statusCode == 429:
                return ProviderAbstractionError.rateLimited
            case .badStatus(let statusCode, _, _) where (500...599).contains(statusCode):
                return ProviderAbstractionError.unavailable
            case .badStatus(let statusCode, let message, _):
                return ProviderAbstractionError.badStatus(statusCode, message: message)
            case .invalidResponse:
                return ProviderAbstractionError.invalidResponse
            }
        }

        if let urlError = error as? URLError {
            switch urlError.code {
            case .notConnectedToInternet, .networkConnectionLost:
                return ProviderAbstractionError.offline
            case .timedOut, .cannotConnectToHost:
                return ProviderAbstractionError.unavailable
            default:
                return urlError
            }
        }

        return error
    }

    func retryDelay(after error: Error, fallbackDelay: UInt64) -> UInt64 {
        guard case .badStatus(_, _, let retryAfter?) = error as? RequestError else {
            return fallbackDelay
        }

        let retryDelay = UInt64(max(0, retryAfter) * Double(Self.nanosecondsPerSecond))
        return min(retryDelay, maxDelayNanoseconds)
    }

    func sanitizedProviderErrorMessage(from data: Data) -> String? {
        ProviderErrorPayloadSanitizer.sanitizedMessage(from: data) {
            try? JSONDecoder().decode(HeliusDASResponse.self, from: data).error?.message
        }
    }

    func map(asset: HeliusAsset, owner: String) -> AlchemyNFTResponse.OwnedNFT {
        let collectionAddress = asset.grouping?.first { $0.groupKey == "collection" }?.groupValue
        let rawMetadata = asset.encodedRawJSON()
        let metadataURL = asset.content.jsonURI
        let imageURL = asset.content.links?.image

        return AlchemyNFTResponse.OwnedNFT(
            contract: .init(address: collectionAddress, chain: .solanaMainnet),
            tokenId: asset.id,
            tokenType: asset.interface,
            name: asset.content.metadata.name,
            nftDescription: asset.content.metadata.description,
            image: .init(originalURL: imageURL, thumbnailURL: imageURL, secureURL: nil),
            raw: .init(tokenURI: metadataURL, metadata: rawMetadata, error: nil),
            collection: .init(name: collectionAddress, chain: .solanaMainnet, contractAddress: collectionAddress),
            tokenURI: metadataURL
        )
    }
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
                throw ProviderAbstractionError.invalidResponse
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

    func encodedRawJSON() -> [String: JSONValue]? {
        guard let data = try? JSONEncoder().encode(self) else {
            return nil
        }
        return try? JSONDecoder().decode([String: JSONValue].self, from: data)
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

private extension HeliusDASNFTService {
    func mapRPCError(_ error: HeliusRPCError) -> ProviderAbstractionError {
        let normalizedMessage = error.message.lowercased()

        if error.code == 429 || normalizedMessage.contains("rate limit") || normalizedMessage.contains("too many requests") {
            return .rateLimited
        }

        if error.code == -32601 || normalizedMessage.contains("method not found") {
            return .unsupportedMethod
        }

        if error.code == -32001
            || error.code == -32003
            || normalizedMessage.contains("unauthorized")
            || normalizedMessage.contains("forbidden")
            || normalizedMessage.contains("api key") {
            return .unauthorized
        }

        return .providerError(ProviderErrorPayloadSanitizer.sanitizedProviderMessage(error.message))
    }
}
