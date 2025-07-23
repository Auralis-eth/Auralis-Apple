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
            // Check HTTP status
            if let httpResponse = response as? HTTPURLResponse {
                print("Status code: \(httpResponse.statusCode)")
                if httpResponse.statusCode == 429 {
                    // Rate limited - implement exponential backoff
                    throw URLError(.resourceUnavailable)
                } else {
                    print("Status code: \(httpResponse.statusCode)")
                    print("Headers: \(httpResponse.allHeaderFields)")
                }
            }
            throw URLError(.badServerResponse)
        }

        let decoder = JSONDecoder()
        return try decoder.decode(AlchemyNFTResponse.self, from: data)
    }
}

