//
//  FetchNFTInventoryUseCase.swift
//  Auralis
//
//  Created by Codex on 8/26/25.
//

import AuralisPrimaryModels
import AuralisPrimaryPersistence
import Foundation

public struct FetchedNFTInventory {
    public let nfts: [NFT]
    public let didCompleteFullRefresh: Bool

    public init(nfts: [NFT], didCompleteFullRefresh: Bool) {
        self.nfts = nfts
        self.didCompleteFullRefresh = didCompleteFullRefresh
    }
}

@MainActor
public protocol FetchNFTInventoryUsing {
    func fetchInventory(
        for accountAddress: String,
        chain: Chain,
        correlationID: String,
        eventRecorder: any NFTRefreshEventRecording
    ) async throws -> FetchedNFTInventory
}

@MainActor
public struct LiveFetchNFTInventoryUseCase: FetchNFTInventoryUsing {
    private let nftFetcher: any NFTFetching

    public init(nftFetcher: any NFTFetching) {
        self.nftFetcher = nftFetcher
    }

    public func fetchInventory(
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
