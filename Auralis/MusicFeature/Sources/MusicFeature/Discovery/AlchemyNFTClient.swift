import AuralisPrimaryModels
import Foundation

public actor AlchemyNFTClient: EVMNFTDiscovering {
    private let apiKey: String
    private let urlSession: URLSession
    private let endpointBaseURLs: [Chain: URL]
    private let pageSize: Int
    private let retryCount: Int
    private let retryDelayNanoseconds: UInt64

    public init(
        apiKey: String,
        urlSession: URLSession = .shared,
        endpointBaseURLs: [Chain: URL]? = nil,
        pageSize: Int = 100,
        retryCount: Int = 3,
        retryDelayNanoseconds: UInt64 = 1_000_000_000
    ) {
        self.apiKey = apiKey
        self.urlSession = urlSession
        self.endpointBaseURLs = endpointBaseURLs ?? Self.liveEndpointBaseURLs(apiKey: apiKey)
        self.pageSize = pageSize
        self.retryCount = max(retryCount, 1)
        self.retryDelayNanoseconds = retryDelayNanoseconds
    }

    public func fetchAll(owner: String, chain: Chain) async throws -> [NFTTokenDTO] {
        let trimmedOwner = owner.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedOwner.isEmpty else {
            throw AuraPlayError.library("Alchemy NFT discovery requires a wallet address.")
        }
        guard endpointBaseURLs[chain] != nil else {
            throw AuraPlayError.library("Alchemy NFT discovery does not support \(chain.rawValue).")
        }

        var pageKey: String?
        var allTokens: [NFTTokenDTO] = []

        repeat {
            let response = try await fetchPage(owner: trimmedOwner, chain: chain, pageKey: pageKey)
            allTokens.append(contentsOf: response.ownedNfts.map { map(nft: $0, owner: trimmedOwner, chain: chain) })
            pageKey = response.pageKey
        } while pageKey?.isEmpty == false

        return deduplicated(allTokens)
    }
}

private extension AlchemyNFTClient {
    static func liveEndpointBaseURLs(apiKey: String) -> [Chain: URL] {
        [
            .ethMainnet: URL(string: "https://eth-mainnet.g.alchemy.com/nft/v3/\(apiKey)")!,
            .polygonMainnet: URL(string: "https://polygon-mainnet.g.alchemy.com/nft/v3/\(apiKey)")!,
            .baseMainnet: URL(string: "https://base-mainnet.g.alchemy.com/nft/v3/\(apiKey)")!,
            .optMainnet: URL(string: "https://opt-mainnet.g.alchemy.com/nft/v3/\(apiKey)")!,
            .arbMainnet: URL(string: "https://arb-mainnet.g.alchemy.com/nft/v3/\(apiKey)")!
        ]
    }

    func fetchPage(owner: String, chain: Chain, pageKey: String?) async throws -> AlchemyNFTResponseEnvelope {
        var lastError: Error?

        for attempt in 1...retryCount {
            do {
                return try await fetchPageOnce(owner: owner, chain: chain, pageKey: pageKey)
            } catch {
                lastError = error
                if shouldRetry(error), attempt < retryCount {
                    try await Task.sleep(nanoseconds: retryDelayNanoseconds * UInt64(attempt))
                    continue
                }
                throw mappedFinalError(error)
            }
        }

        throw lastError.map(mappedFinalError) ?? AuraPlayError.library("Alchemy NFT discovery failed.")
    }

    func fetchPageOnce(owner: String, chain: Chain, pageKey: String?) async throws -> AlchemyNFTResponseEnvelope {
        guard let baseURL = endpointBaseURLs[chain],
              var components = URLComponents(url: baseURL.appending(path: "getNFTsForOwner"), resolvingAgainstBaseURL: false) else {
            throw AuraPlayError.library("Alchemy NFT endpoint URL is invalid.")
        }

        var queryItems = [
            URLQueryItem(name: "owner", value: owner),
            URLQueryItem(name: "withMetadata", value: "true"),
            URLQueryItem(name: "pageSize", value: String(pageSize))
        ]
        if let pageKey, !pageKey.isEmpty {
            queryItems.append(URLQueryItem(name: "pageKey", value: pageKey))
        }
        components.queryItems = queryItems

        guard let url = components.url else {
            throw AuraPlayError.library("Alchemy NFT endpoint URL could not be constructed.")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 30
        request.addValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await urlSession.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw AuraPlayError.library("Alchemy NFT discovery returned a non-HTTP response.")
        }

        switch httpResponse.statusCode {
        case 200...299:
            return try JSONDecoder().decode(AlchemyNFTResponseEnvelope.self, from: data)
        case 429:
            throw AlchemyNFTClientError.rateLimited
        case 500...599:
            throw AlchemyNFTClientError.serverError(statusCode: httpResponse.statusCode)
        default:
            throw AuraPlayError.library("Alchemy NFT discovery failed with HTTP \(httpResponse.statusCode).")
        }
    }

    func shouldRetry(_ error: Error) -> Bool {
        switch error {
        case AlchemyNFTClientError.rateLimited:
            return true
        case AlchemyNFTClientError.serverError:
            return true
        default:
            let urlError = error as? URLError
            return urlError?.code == .timedOut ||
            urlError?.code == .networkConnectionLost ||
            urlError?.code == .notConnectedToInternet
        }
    }

    func mappedFinalError(_ error: Error) -> Error {
        if case AlchemyNFTClientError.rateLimited = error {
            return AuraPlayError.network(.rateLimited)
        }
        return error
    }

    func map(nft: AlchemyNFT, owner: String, chain: Chain) -> NFTTokenDTO {
        let metadataRaw = nft.raw.metadata?.encodedJSONString()
        return NFTTokenDTO(
            chain: chain,
            walletAddress: owner,
            contractAddress: nft.contract.address,
            tokenId: nft.tokenId,
            tokenStandard: nft.tokenType,
            collectionName: nft.collection?.name,
            name: nft.name,
            description: nft.description,
            imageURL: nft.image?.cachedURL ?? nft.image?.originalURL,
            metadataURL: nft.raw.tokenURI,
            metadataRaw: metadataRaw,
            providerUpdatedAt: nft.timeLastUpdated,
            isActive: true,
            provider: .alchemy
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

private enum AlchemyNFTClientError: Error, Equatable {
    case rateLimited
    case serverError(statusCode: Int)
}

private struct AlchemyNFTResponseEnvelope: Decodable {
    let ownedNfts: [AlchemyNFT]
    let pageKey: String?
    let totalCount: Int?
}

private struct AlchemyNFT: Decodable {
    let contract: AlchemyContract
    let tokenId: String
    let tokenType: String?
    let name: String?
    let description: String?
    let image: AlchemyImage?
    let raw: AlchemyRaw
    let collection: AlchemyCollection?
    let timeLastUpdated: String?
    let balance: String?
}

private struct AlchemyContract: Decodable {
    let address: String
}

private struct AlchemyImage: Decodable {
    let cachedURL: String?
    let originalURL: String?

    enum CodingKeys: String, CodingKey {
        case cachedURL = "cachedUrl"
        case originalURL = "originalUrl"
    }
}

private struct AlchemyRaw: Decodable {
    let metadata: JSONValue?
    let tokenURI: String?

    enum CodingKeys: String, CodingKey {
        case metadata
        case tokenURI = "tokenUri"
    }
}

private struct AlchemyCollection: Decodable {
    let name: String?
}

private enum JSONValue: Codable, Equatable, Sendable {
    case object([String: JSONValue])
    case array([JSONValue])
    case string(String)
    case number(Double)
    case bool(Bool)
    case null

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let object = try? container.decode([String: JSONValue].self) {
            self = .object(object)
        } else if let array = try? container.decode([JSONValue].self) {
            self = .array(array)
        } else if let bool = try? container.decode(Bool.self) {
            self = .bool(bool)
        } else if let number = try? container.decode(Double.self) {
            self = .number(number)
        } else if let string = try? container.decode(String.self) {
            self = .string(string)
        } else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unsupported JSON value.")
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .object(let value):
            try container.encode(value)
        case .array(let value):
            try container.encode(value)
        case .string(let value):
            try container.encode(value)
        case .number(let value):
            try container.encode(value)
        case .bool(let value):
            try container.encode(value)
        case .null:
            try container.encodeNil()
        }
    }

    func encodedJSONString() -> String? {
        guard let data = try? JSONEncoder().encode(self) else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }
}
