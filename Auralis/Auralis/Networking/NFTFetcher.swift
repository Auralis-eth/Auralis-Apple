//
//  NFTFetcher.swift
//  Auralis
//
//  Created by Daniel Bell on 4/9/25.
//

import SwiftUI
import SwiftData
import RegexBuilder

protocol NFTFetching: AnyObject {
    var total: Int? { get set }
    var itemsLoaded: Int? { get set }
    var loading: Bool { get set }
    var error: Error? { get set }
    var currentCursor: String? { get set }

    func fetchAllNFTs(
        for account: String,
        chain: Chain,
        correlationID: String?,
        eventRecorder: any NFTRefreshEventRecording
    ) async throws -> [NFT]

    func reset()
}

@Observable
class NFTFetcher: NFTFetching {

    enum FetcherError: Error, LocalizedError {
        case missingAPIKey
        case loadingAlreadyInProgress
        case invalidAccount(reason: String)
        case rateLimited
        case networkError(Error)
        
        var isRetryable: Bool {
            switch self {
            case .rateLimited, .networkError:
                return true
            case .missingAPIKey, .loadingAlreadyInProgress, .invalidAccount:
                return false
            }
        }
        
        var errorDescription: String? {
            switch self {
            case .missingAPIKey:
                return "API key is missing. Please check your configuration."
            case .loadingAlreadyInProgress:
                return "NFT loading is already in progress. Please wait for the current operation to complete."
            case .invalidAccount(let reason):
                return "Invalid account address: \(reason)"
            case .rateLimited:
                return "Too many requests. Please try again later."
            case .networkError(let error):
                return "Network error occurred: \(error.localizedDescription)"
            }
        }
    }

    var total: Int? = nil
    var itemsLoaded: Int? = nil
    var loading: Bool = false
    var error: Error? = nil
    
    var currentCursor: String? = nil
    
    private let maxRetryCount: Int
    private let baseDelayNanoseconds: UInt64
    private let maxDelayNanoseconds: UInt64
    
    private static let hexAddressRegex = Regex {
        Anchor.startOfSubject
        "0x"
        Repeat(count: 40) { .hexDigit }
        Anchor.endOfSubject
    }
    
    private let throttler = RequestThrottler()
    
    init(maxRetryCount: Int = 10,
         baseDelayNanoseconds: UInt64 = 100_000_000,
         maxDelayNanoseconds: UInt64 = 5_000_000_000) {
        self.maxRetryCount = maxRetryCount
        self.baseDelayNanoseconds = baseDelayNanoseconds
        self.maxDelayNanoseconds = maxDelayNanoseconds
    }
    
    private func validateAccount(_ account: String) throws {
        guard account.hasPrefix("0x") else {
            throw FetcherError.invalidAccount(reason: "Address must start with 0x")
        }
        
        guard account.count >= 40 && account.count <= 42 else {
            throw FetcherError.invalidAccount(reason: "Invalid address length. Expected 40-42 characters, got \(account.count)")
        }
        
        guard account.wholeMatch(of: Self.hexAddressRegex) != nil else {
            throw FetcherError.invalidAccount(reason: "Address contains invalid characters. Only hexadecimal characters (0-9, a-f, A-F) are allowed")
        }
    }
    
    private func backoffDelay(for attempt: Int) -> UInt64 {
        let exponentialDelay = UInt64(pow(2.0, Double(attempt))) * baseDelayNanoseconds
        return min(exponentialDelay, maxDelayNanoseconds)
    }
    
    private func shouldRetry(error: Error, attempt: Int) -> Bool {
        guard attempt < maxRetryCount else { return false }
        
        if let fetcherError = error as? FetcherError {
            return fetcherError.isRetryable
        }
        
        if let urlError = error as? URLError {
            switch urlError.code {
            case .timedOut, .cannotConnectToHost, .networkConnectionLost, .notConnectedToInternet:
                return true
            default:
                return false
            }
        }
        
        let nsError = error as NSError
        if nsError.domain == NSURLErrorDomain, nsError.code == -1011 {
            return true
        }
        
        return false
    }

    func fetchAllNFTs(
        for account: String,
        chain: Chain,
        correlationID: String?,
        eventRecorder: any NFTRefreshEventRecording
    ) async throws -> [NFT] {
//        return NFTExamples.allExamples
        guard let apiKey = Secrets.apiKeyOrNil(.alchemy) else {
            if let correlationID {
                await eventRecorder.recordFetchFailed(
                    accountAddress: account,
                    chain: chain,
                    correlationID: correlationID,
                    error: FetcherError.missingAPIKey
                )
            }
            throw FetcherError.missingAPIKey
        }

        guard !loading else {
            if let correlationID {
                await eventRecorder.recordFetchFailed(
                    accountAddress: account,
                    chain: chain,
                    correlationID: correlationID,
                    error: FetcherError.loadingAlreadyInProgress
                )
            }
            throw FetcherError.loadingAlreadyInProgress
        }

        do {
            try validateAccount(account)
        } catch {
            if let correlationID {
                await eventRecorder.recordFetchFailed(
                    accountAddress: account,
                    chain: chain,
                    correlationID: correlationID,
                    error: error
                )
            }
            throw error
        }

        loading = true
        defer { loading = false }
        error = nil

        var nftMetaData: [NFT] = []
        var seenItems: Int = 0

        var attempt = 0
        let service = AlchemyNFTService(network: chain.rawValue, apiKey: apiKey)
        var cursor: String? = nil
        
        var totalAttempts = 0
        let maxTotalAttempts = maxRetryCount * 3
        
        repeat {
            try await throttler.throttle()
            
            totalAttempts += 1
            if totalAttempts >= maxTotalAttempts {
                print("Reached maximum total attempts (\(maxTotalAttempts)), stopping")
                break
            }
            
            do {
                let nfts = try await service.getNFTsForOwner(owner: account, pageKey: cursor)

                seenItems += nfts.ownedNfts.count
                itemsLoaded = seenItems
                total = nfts.totalCount

                nftMetaData.append(contentsOf: nfts.ownedNfts)

                cursor = nfts.pageKey
                currentCursor = cursor
                
                if let totalItems = total {
                    if seenItems >= totalItems {
                        cursor = nil
                        currentCursor = nil
                        break
                    }
                }
                
                attempt = 0
                self.error = nil
                
            } catch {
                attempt += 1
                print("Error fetching NFTs (attempt \(attempt)): \(error)")
                
                let wrappedError: Error
                if let urlError = error as? URLError {
                    print("URL Error code: \(urlError.code.rawValue)")
                    wrappedError = FetcherError.networkError(urlError)
                } else {
                    let nsError = error as NSError
                    if nsError.domain == NSURLErrorDomain, nsError.code == NSURLErrorCancelled {
                        break
                    }
                    if nsError.code == -1011 {
                        wrappedError = FetcherError.rateLimited
                    } else {
                        wrappedError = FetcherError.networkError(error)
                    }
                }
                
                self.error = wrappedError
                
                if shouldRetry(error: error, attempt: attempt) {
                    let delay = backoffDelay(for: attempt)
                    print("Retrying in \(Double(delay) / 1_000_000_000) seconds...")
                    try await Task.sleep(nanoseconds: delay)
                } else {
                    print("Not retrying error: \(error)")
                    if let correlationID {
                        await eventRecorder.recordFetchFailed(
                            accountAddress: account,
                            chain: chain,
                            correlationID: correlationID,
                            error: wrappedError
                        )
                    }
                    throw wrappedError
                }
            }
            
        } while cursor != nil

        if let correlationID {
            await eventRecorder.recordFetchSucceeded(
                accountAddress: account,
                chain: chain,
                correlationID: correlationID,
                itemCount: nftMetaData.count,
                totalCount: total
            )
        }

        return nftMetaData
    }

    func reset() {
        itemsLoaded = 0
        total = nil
        loading = false
        currentCursor = nil
        error = nil
    }
}
