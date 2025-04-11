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

    func fetchAllNFTs(for account: String, chain: String) async throws -> [NFT]? {
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

        repeat {
            do {
                let service = AlchemyNFTService(network: chain, apiKey: apiKey)
                let nfts = try await service.getNFTsForOwner(owner: account)

                seenItems += nfts.ownedNfts.count
                itemsLoaded = seenItems
                total = nfts.totalCount

                if nftMetaData == nil {
                    nftMetaData = nfts.ownedNfts
                } else {
                    nftMetaData?.append(contentsOf: nfts.ownedNfts)
                }

                currentCursor = nfts.pageKey
                if let totalItems = total {
                    if seenItems >= totalItems {
                        break
                    }
                }
            } catch {
                print("Error fetching NFTs: \(error)")
                self.error = error
            }
        } while currentCursor != nil

        return nftMetaData
    }

    func reset() {
        itemsLoaded = 0
        total = nil
        loading = false
    }
}
