//
//  Moralis.swift
//  KickingHorse
//
//  Created by Daniel Bell on 8/24/24.
//

import Foundation
import Foundation

struct Moralis {
    enum MoralisError: Error {
        case invalidResponse
        case invalidData
    }
    let apiKey = Secrets.apiKey(.moralis)

    // Parameters
    // fromDate The start date from which to get the transactions (format in seconds or datestring accepted by momentjs)
    // toDate Get the transactions up to this date (format in seconds or datestring accepted by momentjs)
    // cursor   The cursor returned in the previous response (used for getting the next page).

    //=====================================
    // include_internal_transactions   boolean If the result should contain the internal transactions.
    //include_internal_transactions: Include internal transactions in your results when set to true. By default, native_transfers always include internal transactions.

    // include_input_data  boolean Set the input data from the result
    //include_input_data: Includes the raw transaction input data when set to true. This also decodes the transaction to populate the method_label.

    // nft_metadata    boolean If the result should contain the nft metadata.
    //nft_metadata: Include NFT metadata in your results when set to true.

    // order   string  The order of the result, in ascending (ASC) or descending (DESC)
    //order: Sort the results in ascending (ASC) or descending (DESC) order.

    // limit   number  The desired page size of the result.
    //limit: Adjust the page size of your results to your preference.
    func transctions(for user: String, chain: String = "eth", fromBlock: Int? = nil, toBlock: Int? = nil, fromDate: String? = nil, toDate: String? = nil, cursor: String? = nil) async -> WalletHistoryResponse? {

        guard user.isHex || user.isHexIgnorePrefix else {
            return nil
        }

        var queryItems = [ URLQueryItem(name: "chain", value: chain) ]
        queryItems.append(URLQueryItem(name: "order", value: "DESC"))
        if let fromBlock {
            queryItems.append(URLQueryItem(name: "from_block", value: "\(fromBlock)"))
        } else if let fromDate {
            queryItems.append(
                URLQueryItem(
                    name: "from_date",
                    value: fromDate.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)
                ))
        }

        if let toBlock {
            queryItems.append(URLQueryItem(name: "to_block", value: "\(toBlock)"))
        } else if let toDate {
            queryItems.append(
                URLQueryItem(
                    name: "to_date",
                    value: toDate.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)
                ))
        }

        if let cursor {
            queryItems.append(URLQueryItem(name: "cursor", value: cursor))
        }

        var components = URLComponents()
        components.scheme = "https"
        components.host = "deep-index.moralis.io"
        components.path = "/api/v2.2/wallets/" + user + "/history"
        components.queryItems = queryItems

        return try? await getValueFrom(components.url)
    }


    //TODO: Test
    //TODO: Create UI
    //https://docs.moralis.com/web3-data-api/evm/reference/wallet-api/get-nfts-by-wallet?address=0xff3879b8a363aed92a6eaba8f61f1a96a9ec3c1e&chain=eth&format=decimal&token_addresses=[]&media_items=false
    func getNFTs(for address: String, chain: String = "eth", format: String? = "decimal", limit: Int? = nil, excludeSpam: Bool? = nil, tokenAddresses: [String]? = nil, cursor: String? = nil, normalizeMetadata: Bool? = nil, mediaItems: Bool? = nil) async throws -> WalletNFTResponse? {

            guard address.isHex || address.isHexIgnorePrefix else {
                return nil
            }

            var queryItems = [ URLQueryItem(name: "chain", value: chain) ]
            if let format {
                queryItems.append(URLQueryItem(name: "format", value: format))
            }
            if let limit {
                queryItems.append(URLQueryItem(name: "limit", value: "\(limit)"))
            }
            if let excludeSpam {
                queryItems.append(URLQueryItem(name: "exclude_spam", value: excludeSpam ? "true" : "false"))
            }
            if let tokenAddresses {
                queryItems.append(URLQueryItem(name: "token_addresses", value: tokenAddresses.joined(separator: ",")))
            }
            if let cursor {
                queryItems.append(URLQueryItem(name: "cursor", value: cursor))
            }
            if let normalizeMetadata {
                queryItems.append(URLQueryItem(name: "normalizeMetadata", value: normalizeMetadata ? "true" : "false"))
            }
            if let mediaItems {
                queryItems.append(URLQueryItem(name: "media_items", value: mediaItems ? "true" : "false"))
            }

            var components = URLComponents()
            components.scheme = "https"
            components.host = "deep-index.moralis.io"
            components.path = "/api/v2.2/" + address + "/nft"
            components.queryItems = queryItems

            return try await getValueFrom(components.url)
        }

    func getValueFrom<T: Codable>(_ refUrl: URL? ) async throws -> T? {
        guard let url = refUrl else { return nil }
        guard let apiKey else { return nil }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.addValue(apiKey, forHTTPHeaderField: "X-API-Key")
        request.addValue("application/json", forHTTPHeaderField: "accept")

        do {
            let (data, _) = try await URLSession.shared.data(for: request)
            return try JSONDecoder().decode(T.self, from: data)
        } catch is DecodingError {
            throw MoralisError.invalidData
        } catch {
            print(error)
            throw MoralisError.invalidResponse
        }
    }
}
