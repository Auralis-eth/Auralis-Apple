//
//  FetchNFTInventoryUseCase.swift
//  Auralis
//
//  Created by Codex on 8/26/25.
//

import Foundation

struct FetchedNFTInventory {
    let nfts: [NFT]
    let didCompleteFullRefresh: Bool
}

@MainActor
protocol FetchNFTInventoryUsing {
    func fetchInventory(
        for accountAddress: String,
        chain: Chain,
        correlationID: String,
        eventRecorder: any NFTRefreshEventRecording
    ) async throws -> FetchedNFTInventory
}

@MainActor
struct LiveFetchNFTInventoryUseCase: FetchNFTInventoryUsing {
    private let nftFetcher: any NFTFetching

    init(nftFetcher: any NFTFetching) {
        self.nftFetcher = nftFetcher
    }

    func fetchInventory(
        for accountAddress: String,
        chain: Chain,
        correlationID: String,
        eventRecorder: any NFTRefreshEventRecording
    ) async throws -> FetchedNFTInventory {
        let nfts = try await nftFetcher.fetchAllNFTs(
            for: accountAddress,
            chain: chain,
            correlationID: correlationID,
            eventRecorder: eventRecorder
        )
        let didCompleteFullRefresh = nftFetcher.currentCursor == nil &&
            (nftFetcher.total == nil || (nftFetcher.itemsLoaded ?? 0) >= (nftFetcher.total ?? 0))

        return FetchedNFTInventory(
            nfts: nfts,
            didCompleteFullRefresh: didCompleteFullRefresh
        )
    }
}
