//
//  FetchNFTInventoryUseCase.swift
//  Auralis
//
//  Created by Codex on 8/26/25.
//

import AuralisPrimaryModels
import Foundation
import NFTDomain

public struct FetchedNFTInventory: Sendable {
    public let nfts: [NFTInventoryItemSnapshot]
    public let didCompleteFullRefresh: Bool

    public init(nfts: [NFTInventoryItemSnapshot], didCompleteFullRefresh: Bool) {
        self.nfts = nfts
        self.didCompleteFullRefresh = didCompleteFullRefresh
    }
}

public protocol FetchNFTInventoryUsing: Sendable {
    func fetchInventory(
        for accountAddress: String,
        chain: Chain,
        correlationID: String,
        eventRecorder: any NFTRefreshEventRecording,
        progressHandler: NFTFetchProgressHandler?
    ) async throws -> FetchedNFTInventory
}

public struct LiveFetchNFTInventoryUseCase: FetchNFTInventoryUsing {
    private let nftFetcher: any NFTFetching

    public init(nftFetcher: any NFTFetching) {
        self.nftFetcher = nftFetcher
    }

    public func fetchInventory(
        for accountAddress: String,
        chain: Chain,
        correlationID: String,
        eventRecorder: any NFTRefreshEventRecording,
        progressHandler: NFTFetchProgressHandler? = nil
    ) async throws -> FetchedNFTInventory {
        let result = try await nftFetcher.fetchAllNFTs(
            for: accountAddress,
            chain: chain,
            correlationID: correlationID,
            eventRecorder: eventRecorder,
            progressHandler: progressHandler
        )

        return FetchedNFTInventory(
            nfts: result.nfts,
            didCompleteFullRefresh: result.didCompleteFullRefresh
        )
    }
}
