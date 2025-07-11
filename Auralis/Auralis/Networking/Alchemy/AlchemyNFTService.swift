//
//  AlchemyNFTService.swift
//  Auralis
//
//  Created by Daniel Bell on 3/29/25.
//

import Foundation

class AlchemyNFTService {
    private let baseURL: String
    private let apiKey: String
    private let network: String

    init(network: String = "eth-mainnet", apiKey: String = "docs-demo") {
        self.network = network
        self.apiKey = apiKey
        self.baseURL = "https://\(network).g.alchemy.com/nft/v3/\(apiKey)"
    }


//    spamConfidenceLevel
//    string
//    Enum - the confidence level at which to filter spam at.
//
//    Confidence Levels:
//
//    VERY_HIGH
//    HIGH
//    MEDIUM
//    LOW
//    The confidence level set means that any spam that is at that confidence level or higher will be filtered out. For example, if the confidence level is HIGH, contracts that we have HIGH or VERY_HIGH confidence in being spam will be filtered out from the response.
//    Defaults to VERY_HIGH for Ethereum Mainnet and MEDIUM for Matic Mainnet.
//
//    Please note that this filter is only available on paid tiers. Upgrade your account here.
    func getNFTsForOwner(
        owner: String,
        contractAddresses: [String]? = nil,
        withMetadata: Bool = true,
        orderBy: Bool = false,
        excludeFilters: [String]? = nil,
        includeFilters: [String]? = nil,
        spamConfidenceLevel: String? = nil,
        tokenUriTimeoutInMs: Int? = nil,
        pageKey: String? = nil,
        pageSize: Int = 100
    ) async throws -> AlchemyNFTResponse {

        guard let url = URL(string: "\(baseURL)/getNFTsForOwner") else {
            throw URLError(.badURL)
        }

        var components = URLComponents(url: url, resolvingAgainstBaseURL: true)!
        var queryItems = [URLQueryItem(name: "owner", value: owner)]

        // Add optional parameters
        queryItems.append(URLQueryItem(name: "withMetadata", value: withMetadata ? "true" : "false"))
        queryItems.append(URLQueryItem(name: "pageSize", value: String(pageSize)))

        if let contractAddresses = contractAddresses, !contractAddresses.isEmpty {
            for address in contractAddresses {
                queryItems.append(URLQueryItem(name: "contractAddresses[]", value: address))
            }
        }

        if orderBy {
            queryItems.append(URLQueryItem(name: "orderBy", value: "transferTime"))
        }

        if let excludeFilters = excludeFilters, !excludeFilters.isEmpty {
            for filter in excludeFilters {
                queryItems.append(URLQueryItem(name: "excludeFilters[]", value: filter))
            }
        }

        if let includeFilters = includeFilters, !includeFilters.isEmpty {
            for filter in includeFilters {
                queryItems.append(URLQueryItem(name: "includeFilters[]", value: filter))
            }
        }

        if let spamConfidenceLevel = spamConfidenceLevel {
            queryItems.append(URLQueryItem(name: "spamConfidenceLevel", value: spamConfidenceLevel))
        }

        if let tokenUriTimeoutInMs = tokenUriTimeoutInMs {
            queryItems.append(URLQueryItem(name: "tokenUriTimeoutInMs", value: String(tokenUriTimeoutInMs)))
        }

        if let pageKey = pageKey {
            queryItems.append(URLQueryItem(name: "pageKey", value: pageKey))
        }

        components.queryItems = queryItems

        var request = URLRequest(url: components.url!)
        request.httpMethod = "GET"
        request.timeoutInterval = 30
        request.addValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }

        let decoder = JSONDecoder()
        return try decoder.decode(AlchemyNFTResponse.self, from: data)
    }
}



extension AlchemyNFTService {

    func getNFTMetadataBatch(
        tokens: [TokenRequest],
        tokenUriTimeoutInMs: Int? = nil,
        refreshCache: Bool? = false
    ) async throws -> [NFTMetadataResponse] {

        guard let url = URL(string: "\(baseURL)/getNFTMetadataBatch") else {
            throw URLError(.badURL)
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let requestBody = NFTMetadataRequest(
            tokens: tokens,
            tokenUriTimeoutInMs: tokenUriTimeoutInMs,
            refreshCache: refreshCache
        )

        request.httpBody = try JSONEncoder().encode(requestBody)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }

        let decoder = JSONDecoder()
        return try decoder.decode([NFTMetadataResponse].self, from: data)
    }
}




struct NFTMetadataRequest: Codable {
    let tokens: [TokenRequest]
    let tokenUriTimeoutInMs: Int?
    let refreshCache: Bool?
}

struct TokenRequest: Codable {
    let contractAddress: String
    let tokenId: String
}
//===========================================
// MARK: Response

struct NFTMetadataResponse: Codable {
    let contract: Contract?
    let tokenId: String?
    let tokenType: String?
    let name: String?
    let description: String?
    let image: ImageInfo?
    let raw: RawMetadata?
    let collection: Collection?
    let tokenUri: String?
    let timeLastUpdated: String?
    let acquiredAt: AcquiredAt?
}

// Contract information
struct Contract: Codable {
    let address: String?
    let name: String?
    let symbol: String?
    let totalSupply: String?
    let tokenType: String?
    let contractDeployer: String?
    let deployedBlockNumber: Double?
    let openseaMetadata: OpenseaMetadata?
    let isSpam: String?
    let spamClassifications: [String]?
}

// OpenSea metadata
struct OpenseaMetadata: Codable {
    let floorPrice: Double?
    let collectionName: String?
    let safelistRequestStatus: String?
    let imageUrl: String?
    let description: String?
    let externalUrl: String?
    let twitterUsername: String?
    let discordUrl: String?
    let lastIngestedAt: String?
}

// Raw metadata
struct RawMetadata: Codable {
    let tokenUri: String?
    let metadata: [String: JSONValue]?
    let error: String?
}

enum JSONValue: Codable {
    case string(String)
    case int(Int)
    case double(Double)
    case bool(Bool)
    case object([String: JSONValue])
    case array([JSONValue])
    case null

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let str = try? container.decode(String.self) {
            self = .string(str)
        } else if let int = try? container.decode(Int.self) {
            self = .int(int)
        } else if let dbl = try? container.decode(Double.self) {
            self = .double(dbl)
        } else if let bool = try? container.decode(Bool.self) {
            self = .bool(bool)
        } else if let obj = try? container.decode([String: JSONValue].self) {
            self = .object(obj)
        } else if let arr = try? container.decode([JSONValue].self) {
            self = .array(arr)
        } else {
            throw DecodingError.typeMismatch(
                JSONValue.self,
                DecodingError.Context(codingPath: decoder.codingPath,
                                      debugDescription: "Unsupported JSON type")
            )
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .null:
            try container.encodeNil()
        case .string(let value):
            try container.encode(value)
        case .int(let value):
            try container.encode(value)
        case .double(let value):
            try container.encode(value)
        case .bool(let value):
            try container.encode(value)
        case .object(let dict):
            try container.encode(dict)
        case .array(let array):
            try container.encode(array)
        }
    }
}

// NFT attributes
struct NFTAttribute: Codable {
    let value: String?
    let traitType: String?

    private enum CodingKeys: String, CodingKey {
        case value
        case traitType = "trait_type"
    }
}

// Image information
struct ImageInfo: Codable {
    let cachedUrl: String?
    let thumbnailUrl: String?
    let pngUrl: String?
    let contentType: String?
    let size: Int?
    let originalUrl: String?
}

// Collection information
struct Collection: Codable {
    let name: String?
    let slug: String?
    let externalUrl: String?
    let bannerImageUrl: String?
}

// Acquired at information
struct AcquiredAt: Codable {
    let blockTimestamp: String?
    let blockNumber: String?
}
