//
//  NFTService.swift
//  Auralis
//
//  Created by Daniel Bell on 6/29/25.
//

import Foundation
import SwiftData

@MainActor
@Observable
class NFTService {
    private let nftFetcher: any NFTFetching
    private let eventRecorderFactory: @MainActor (ModelContext) -> any NFTRefreshEventRecording
    var isLoading: Bool { nftFetcher.loading }
    var itemsLoaded: Int? { nftFetcher.itemsLoaded }
    var total: Int? { nftFetcher.total }
    var error: Error? { nftFetcher.error }

    init(
        nftFetcher: (any NFTFetching)? = nil,
        eventRecorderFactory: @escaping @MainActor (ModelContext) -> any NFTRefreshEventRecording = {
            NFTRefreshEventRecorders.live(modelContext: $0)
        }
    ) {
        self.nftFetcher = nftFetcher ?? NFTFetcher()
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

        nftFetcher.reset()
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

        await fetchAllNFTs(
            for: accountAddress,
            chain: chain,
            modelContext: modelContext,
            correlationID: correlationID
        )
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
        nftFetcher.reset()
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
