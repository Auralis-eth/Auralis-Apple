//
//  NFTFetcher.swift
//  Auralis
//
//  Created by Daniel Bell on 4/9/25.
//

import SwiftUI
import SwiftData

@Observable class NFTFetcher {

    enum FetcherError: Error {
        case loadingAlreadyInProgress
        case invalidResponse
        case invalidAccount
        case unknown
    }

    var total: Int? = nil
    var itemsLoaded: Int? = nil
    var loading: Bool = false
    var error: Error? = nil

    func fetchAllNFTs(for account: String, chain: Chain) async throws -> [NFT]? {
        guard let apiKey = Secrets.apiKey(.alchemy) else {
            fatalError("API key not set")
        }
        guard !loading else { throw FetcherError.loadingAlreadyInProgress }
        guard account.count == 42 else { throw FetcherError.invalidAccount }
        guard account.hasPrefix("0x") else { throw FetcherError.invalidAccount }
        loading = true
        error = nil


        var nftMetaData: [NFT]? = nil
        var currentCursor: String? = nil
        var seenItems: Int = 0

        let service = AlchemyNFTService(network: chain.rawValue, apiKey: apiKey)
        repeat {
            do {
                let nfts = try await service.getNFTsForOwner(owner: account, pageKey: currentCursor)

                seenItems += nfts.ownedNfts.count
                itemsLoaded = seenItems
                total = nfts.totalCount

                if nftMetaData == nil {
                    nftMetaData = nfts.ownedNfts
                } else {
                    nftMetaData?.append(contentsOf: nfts.ownedNfts)
                }

                print("=============================")
                print("seenItems: \(seenItems)")
                print("=============================")
                currentCursor = nfts.pageKey
                if let totalItems = total {
                    if seenItems >= totalItems {
                        break
                    }
                }
            } catch {
                //TODOL 1) replace code with the old code
                //TODOL 1) make NFT raw metadata a dictionary of [String: JSONValue]
                //TODO: 2) finish this
                //TODO: 3) in the NFTService have the metadata parse out whats there
                //
                print("Error fetching NFTs: \(error)")
                let nsError = error as NSError
                if nsError.domain == NSURLErrorDomain, nsError.code == NSURLErrorCancelled {
                    break
                }
                if nsError.code == -1011 {
                    continue
                }
                self.error = error
            }
        } while currentCursor != nil

        return nftMetaData
    }

    func fetchMetadataBatch(for tokens: [TokenRequest], chain: Chain) async throws -> [NFTMetadataResponse] {
        guard let apiKey = Secrets.apiKey(.alchemy) else {
            fatalError("API key not set")
        }

        let service = AlchemyNFTService(network: chain.rawValue, apiKey: apiKey)
        return try await service.getNFTMetadataBatch(tokens: tokens)
    }


    func fetchMetadataBatchLarge(for tokens: [TokenRequest], chain: Chain) async -> [NFTMetadataResponse] {
        guard !tokens.isEmpty else { return [] }

        let batchSize = 100
        var batches: [ArraySlice<TokenRequest>] = []

        for i in stride(from: 0, to: tokens.count, by: batchSize) {
            let endIndex = min(i + batchSize, tokens.count)
            batches.append(tokens[i..<endIndex])
        }

        let results = await withTaskGroup(of: [NFTMetadataResponse].self) { group in
            for batch in batches {
                group.addTask {
                    (try? await self.fetchMetadataBatch(for: Array(batch), chain: chain)) ?? []
                }
            }

            var allMetadata: [NFTMetadataResponse] = []
            for await batchResult in group {
                allMetadata.append(contentsOf: batchResult)
            }
            return allMetadata
        }

        return results
    }

    func reset() {
        itemsLoaded = 0
        total = nil
        loading = false
    }
}
