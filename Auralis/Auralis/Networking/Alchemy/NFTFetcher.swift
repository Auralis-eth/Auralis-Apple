//
//  NFTFetcher.swift
//  Auralis
//
//  Created by Daniel Bell on 4/9/25.
//

import SwiftUI
import SwiftData
actor RequestThrottler {
    private var lastRequestTime: Date = .distantPast
    private let minimumInterval: TimeInterval = 0.1 // 100ms between requests

    func throttle() async {
        let now = Date()
        let timeElapsed = now.timeIntervalSince(lastRequestTime)

        if timeElapsed < minimumInterval {
            let delay = minimumInterval - timeElapsed
            try? await Task.sleep(nanoseconds: UInt64(delay * 100_000_000))
        }

        lastRequestTime = Date()
    }
}

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
    var currentCursor: String? = nil

    func fetchAllNFTs(for account: String, chain: Chain) async throws -> [NFT]? {
//        return NFTExamples.allExamples
        guard let apiKey = Secrets.apiKey(.alchemy) else {
            fatalError("API key not set")
        }
        guard !loading else { throw FetcherError.loadingAlreadyInProgress }
        guard account.count == 42 else { throw FetcherError.invalidAccount }
        guard account.hasPrefix("0x") else { throw FetcherError.invalidAccount }
        loading = true
        error = nil

        let throttler = RequestThrottler()
        var nftMetaData: [NFT]? = nil
        var seenItems: Int = 0
        let retryCount: Int = 10

        var attempt = 0
        let service = AlchemyNFTService(network: chain.rawValue, apiKey: apiKey)
        repeat {
            await throttler.throttle()
            do {
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
                        currentCursor = nil
                        break
                    }
                }
            } catch {
                attempt += 1
                print("Error fetching NFTs: \(error)")
                if let urlError = error as? URLError {
                    print("URL Error code: \(urlError.code.rawValue)")
                }
                let nsError = error as NSError
                if nsError.domain == NSURLErrorDomain, nsError.code == NSURLErrorCancelled {
                    break
                }
                if nsError.code == -1011 {
                    try await Task.sleep(nanoseconds: UInt64(attempt) * 100_000_000)
                }
                self.error = error
            }
            try await Task.sleep(nanoseconds: 100_000_000)
            if attempt > retryCount {
                break
            }
        } while currentCursor != nil

        return nftMetaData
    }

    func reset() {
        itemsLoaded = 0
        total = nil
        loading = false
        currentCursor = nil
    }
}
