//
//  NFTService.swift
//  Auralis
//
//  Created by Daniel Bell on 6/29/25.
//

import Foundation
import SwiftData

enum NFTProviderFailureKind: String, Equatable {
    case offline
    case rateLimited
    case invalidResponse
    case invalidScope
    case misconfigured
    case busy
    case unavailable
}

struct NFTProviderFailure: Equatable {
    let kind: NFTProviderFailureKind
    let message: String
    let isRetryable: Bool

    private init(
        kind: NFTProviderFailureKind,
        message: String,
        isRetryable: Bool
    ) {
        self.kind = kind
        self.message = message
        self.isRetryable = isRetryable
    }

    init?(error: Error?) {
        guard let error else {
            return nil
        }

        if let fetcherError = error as? NFTFetcher.FetcherError {
            switch fetcherError {
            case .missingAPIKey:
                self = NFTProviderFailure(
                    kind: .misconfigured,
                    message: "Auralis is missing collection-provider configuration on this build.",
                    isRetryable: false
                )
            case .loadingAlreadyInProgress:
                self = NFTProviderFailure(
                    kind: .busy,
                    message: "A refresh is already running for this collection.",
                    isRetryable: false
                )
            case .invalidAccount:
                self = NFTProviderFailure(
                    kind: .invalidScope,
                    message: "This wallet address is invalid for the current refresh request.",
                    isRetryable: false
                )
            case .rateLimited:
                self = NFTProviderFailure(
                    kind: .rateLimited,
                    message: "The collection provider is rate-limiting refreshes right now.",
                    isRetryable: true
                )
            case .networkError(let wrappedError):
                self = NFTProviderFailure.classifyNetworkOrFallback(wrappedError)
            }

            return
        }

        if error is DecodingError {
            self = NFTProviderFailure(
                kind: .invalidResponse,
                message: "The collection provider returned data Auralis could not read.",
                isRetryable: true
            )
            return
        }

        self = NFTProviderFailure.classifyNetworkOrFallback(error)
    }

    private static func classifyNetworkOrFallback(_ error: Error) -> NFTProviderFailure {
        if let urlError = error as? URLError {
            switch urlError.code {
            case .notConnectedToInternet, .networkConnectionLost:
                return NFTProviderFailure(
                    kind: .offline,
                    message: "Auralis could not reach the collection provider because this device appears to be offline.",
                    isRetryable: true
                )
            case .timedOut, .cannotConnectToHost:
                return NFTProviderFailure(
                    kind: .unavailable,
                    message: "The collection provider did not respond in time.",
                    isRetryable: true
                )
            default:
                break
            }
        }

        return NFTProviderFailure(
            kind: .unavailable,
            message: "Auralis could not reach the collection provider just now.",
            isRetryable: true
        )
    }
}

enum NFTProviderFailurePresentationMode: Equatable {
    case blocking
    case degraded
}

struct NFTProviderFailurePresentation: Equatable {
    let mode: NFTProviderFailurePresentationMode
    let title: String
    let message: String
    let systemImage: String
    let isRetryable: Bool
}

extension NFTProviderFailure {
    func presentation(
        mode: NFTProviderFailurePresentationMode
    ) -> NFTProviderFailurePresentation {
        switch mode {
        case .blocking:
            return NFTProviderFailurePresentation(
                mode: mode,
                title: blockingTitle,
                message: blockingMessage,
                systemImage: blockingSystemImage,
                isRetryable: isRetryable
            )
        case .degraded:
            return NFTProviderFailurePresentation(
                mode: mode,
                title: degradedTitle,
                message: degradedMessage,
                systemImage: "bolt.horizontal.circle",
                isRetryable: isRetryable
            )
        }
    }

    private var blockingTitle: String {
        switch kind {
        case .offline, .unavailable:
            return "Collection Unavailable"
        case .rateLimited:
            return "Refresh Delayed"
        case .invalidResponse:
            return "Provider Data Unavailable"
        case .invalidScope:
            return "Wallet Unavailable"
        case .misconfigured:
            return "Provider Unavailable"
        case .busy:
            return "Refresh In Progress"
        }
    }

    private var blockingMessage: String {
        switch kind {
        case .offline:
            return "Auralis could not reach the collection provider. Check your connection and try again."
        case .rateLimited:
            return "The collection provider is rate-limiting refreshes right now. Wait a moment and try again."
        case .invalidResponse:
            return "The collection provider returned data Auralis could not read. Try again later."
        case .invalidScope, .misconfigured, .busy:
            return message
        case .unavailable:
            return "Auralis could not reach the collection provider just now. Try again in a moment."
        }
    }

    private var blockingSystemImage: String {
        switch kind {
        case .offline:
            return "wifi.slash"
        case .rateLimited:
            return "hourglass"
        case .invalidResponse:
            return "exclamationmark.arrow.trianglehead.2.clockwise.rotate.90"
        case .invalidScope, .misconfigured, .busy, .unavailable:
            return "exclamationmark.triangle"
        }
    }

    private var degradedTitle: String {
        switch kind {
        case .rateLimited:
            return "Showing Last Sync"
        default:
            return "Refresh Paused"
        }
    }

    private var degradedMessage: String {
        switch kind {
        case .offline:
            return "Auralis is offline right now. Your last synced collection is still visible so you can keep browsing safely."
        case .rateLimited:
            return "The provider is rate-limiting refreshes right now. Your last synced collection is still available while Auralis backs off."
        case .invalidResponse:
            return "The provider returned data Auralis could not read, so Auralis kept your last synced collection on screen."
        case .invalidScope:
            return "The current wallet scope is invalid, so Auralis kept your last synced collection on screen."
        case .misconfigured:
            return "This build cannot refresh the provider right now, so Auralis kept your last synced collection on screen."
        case .busy:
            return "A refresh is already running. Your last synced collection stays visible until it finishes."
        case .unavailable:
            return "Auralis could not refresh the provider just now. Your last synced collection is still visible so you can keep browsing safely."
        }
    }
}

@MainActor
@Observable
class NFTService {
    private struct RefreshScope: Equatable {
        let accountAddress: String
        let chain: Chain
    }

    private let nftFetcher: any NFTFetching
    private let eventRecorderFactory: @MainActor (ModelContext) -> any NFTRefreshEventRecording
    let refreshTTL: TimeInterval
    var isLoading: Bool { nftFetcher.loading }
    var itemsLoaded: Int? { nftFetcher.itemsLoaded }
    var total: Int? { nftFetcher.total }
    var error: Error? { nftFetcher.error }
    var providerFailure: NFTProviderFailure? { NFTProviderFailure(error: error) }
    var lastSuccessfulRefreshAt: Date?
    private var inFlightRefreshScope: RefreshScope?
    private var inFlightRefreshTask: Task<Void, Never>?
    private var inFlightRefreshToken: UUID?

    init(
        nftFetcher: (any NFTFetching)? = nil,
        refreshTTL: TimeInterval = 300,
        eventRecorderFactory: @escaping @MainActor (ModelContext) -> any NFTRefreshEventRecording = {
            NFTRefreshEventRecorders.live(modelContext: $0)
        }
    ) {
        self.nftFetcher = nftFetcher ?? NFTFetcher()
        self.refreshTTL = refreshTTL
        self.eventRecorderFactory = eventRecorderFactory
    }

    //TODO: re-arch for getting ModelContainer instead of ModelContext
//    func fetchAllNFTs(for accountAddress: String, chain: Chain, container: ModelContainer) async {
//        let newContext = ModelContext(container)
//        await fetchAllNFTs(for: accountAddress, chain: chain, modelContext: newContext)
//    }

    func fetchAllNFTs(
        for accountAddress: String,
        chain: Chain,
        modelContext: ModelContext,
        correlationID: String
    ) async {
        let eventRecorder = eventRecorderFactory(modelContext)

        await eventRecorder.recordRefreshStarted(
            accountAddress: accountAddress,
            chain: chain,
            correlationID: correlationID
        )

        do {
            let nfts = try await nftFetcher.fetchAllNFTs(
                for: accountAddress,
                chain: chain,
                correlationID: correlationID,
                eventRecorder: eventRecorder
            )

            nfts.forEach {
                $0.parseMetadata()
            }

            if (nftFetcher.itemsLoaded ?? 0) > (nftFetcher.total ?? 0) - 200 || nftFetcher.currentCursor == nil {
                try await cleanupOldNFTs(
                    currentNFTIDs: nfts.map(\.id),
                    modelContext: modelContext,
                    accountAddress: accountAddress,
                    chain: chain,
                    correlationID: correlationID,
                    eventRecorder: eventRecorder
                )
            } else if let currentCursor = nftFetcher.currentCursor {
                UserDefaults.standard.set(currentCursor, forKey: "currentCursor")
            }

            do {
                for nft in nfts {
                    modelContext.insert(nft)
                }
                try modelContext.save()
                lastSuccessfulRefreshAt = .now
                await eventRecorder.recordPersistenceCompleted(
                    accountAddress: accountAddress,
                    chain: chain,
                    correlationID: correlationID,
                    persistedCount: nfts.count
                )
            } catch {
                await eventRecorder.recordPersistenceFailed(
                    accountAddress: accountAddress,
                    chain: chain,
                    correlationID: correlationID,
                    error: error
                )
                print("Error updating NFT in SwiftData: \(error)")
            }

        } catch {
            nftFetcher.error = error
        }

        let terminalError = nftFetcher.error
        nftFetcher.reset()
        if let terminalError {
            nftFetcher.error = terminalError
        }
    }

    func refreshNFTs(
        for currentAccount: EOAccount?,
        chain: Chain,
        modelContext: ModelContext,
        correlationID: String
    ) async {
        guard let accountAddress = currentAccount?.address else {
            return
        }

        let requestedScope = RefreshScope(accountAddress: accountAddress, chain: chain)

        if let inFlightRefreshTask {
            if inFlightRefreshScope == requestedScope {
                await inFlightRefreshTask.value
                return
            }

            await inFlightRefreshTask.value
        }

        let refreshToken = UUID()
        let task = Task { [self] in
            await fetchAllNFTs(
                for: accountAddress,
                chain: chain,
                modelContext: modelContext,
                correlationID: correlationID
            )
        }

        inFlightRefreshScope = requestedScope
        inFlightRefreshTask = task
        inFlightRefreshToken = refreshToken

        await task.value

        if inFlightRefreshToken == refreshToken {
            inFlightRefreshScope = nil
            inFlightRefreshTask = nil
            inFlightRefreshToken = nil
        }
    }

    private func cleanupOldNFTs(
        currentNFTIDs: [String],
        modelContext: ModelContext,
        accountAddress: String,
        chain: Chain,
        correlationID: String,
        eventRecorder: any NFTRefreshEventRecording
    ) async throws {
        let descriptor = FetchDescriptor<NFT>(
            predicate: #Predicate<NFT> { !currentNFTIDs.contains($0.id) }
        )
        do {
            try modelContext.enumerate(descriptor) { nft in
                modelContext.delete(nft)
            }
            try modelContext.save()
        } catch {
            print("Failed to cleanup old NFTs from SwiftData: \(error)")
            nftFetcher.error = error
            await eventRecorder.recordPersistenceFailed(
                accountAddress: accountAddress,
                chain: chain,
                correlationID: correlationID,
                error: error
            )
            throw error
        }
    }

    func reset() {
        inFlightRefreshTask?.cancel()
        inFlightRefreshTask = nil
        inFlightRefreshScope = nil
        inFlightRefreshToken = nil
        nftFetcher.reset()
    }

    func providerFailurePresentation(
        isShowingCachedContent: Bool
    ) -> NFTProviderFailurePresentation? {
        guard let providerFailure else {
            return nil
        }

        return providerFailure.presentation(
            mode: isShowingCachedContent ? .degraded : .blocking
        )
    }
}

extension NFT {
    func parseMetadata() {
        let tokenURIs = Set([tokenUri, raw?.tokenUri].compactMap(\.self))
        let siftedTokenURIs = tokenURIs.siftTokenURIs()

        guard !siftedTokenURIs.isEmpty else { return }

        if siftedTokenURIs.count > 1 {
            print("Multiple token URIs found for NFT \(id)")
        }

        for tokenURI in tokenURIs {
            if let decodedTokenURI = tokenURI.base64JSON {
                NFTMetadataUpdater.updateNFTFromMetadata(nft: self, metadata: decodedTokenURI)
            } else {
                NFTMetadataUpdater.updateNFTFromMetadata(nft: self, metadata: raw?.metadata)
            }
        }
    }
}
