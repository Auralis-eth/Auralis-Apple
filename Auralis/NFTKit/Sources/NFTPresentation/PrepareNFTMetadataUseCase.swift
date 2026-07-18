//
//  PrepareNFTMetadataUseCase.swift
//  Auralis
//
//  Created by Codex on 8/26/25.
//

import AuralisPrimaryModels
import AuralisPrimaryPersistence
import Foundation
import NFTDomain
import NFTPersistence

private struct NFTMetadataPreparationInput: Sendable {
    let tokenURI: String?
    let rawTokenURI: String?
    let rawMetadata: [String: JSONValue]?
}

public protocol PrepareNFTMetadataUsing: Sendable {
    func prepareInventory(
        _ fetchedNFTs: [NFTInventoryItemSnapshot],
        accountAddress: String,
        chain: Chain
    ) async -> PreparedNFTInventory
}

public struct LivePrepareNFTMetadataUseCase: PrepareNFTMetadataUsing, Sendable {
    private let metadataFetcher: (any TokenMetadataJSONFetching)?

    public init(metadataFetcher: (any TokenMetadataJSONFetching)? = nil) {
        self.metadataFetcher = metadataFetcher
    }

    public func prepareInventory(
        _ fetchedNFTs: [NFTInventoryItemSnapshot],
        accountAddress: String,
        chain: Chain
    ) async -> PreparedNFTInventory {
        let metadataPatches = await prepareMetadataPatches(for: fetchedNFTs)

        var preparedNFTs = fetchedNFTs

        for index in preparedNFTs.indices {
            preparedNFTs[index].applyRefreshScope(accountAddress: accountAddress, chain: chain)
            if let metadataPatch = metadataPatches[index] {
                NFTMetadataUpdater.applyMetadataPatch(metadataPatch, to: &preparedNFTs[index])
                preparedNFTs[index].applyRefreshScope(accountAddress: accountAddress, chain: chain)
            }

            if index.isMultiple(of: 25) {
                await Task.yield()
            }
        }

        return PreparedNFTInventory(nfts: deduplicateFetchedNFTs(preparedNFTs))
    }

    private func deduplicateFetchedNFTs(_ nfts: [NFTInventoryItemSnapshot]) -> [NFTInventoryItemSnapshot] {
        var seenIDs = Set<String>()
        var deduplicatedNFTs: [NFTInventoryItemSnapshot] = []
        deduplicatedNFTs.reserveCapacity(nfts.count)

        for nft in nfts where seenIDs.insert(nft.id).inserted {
            deduplicatedNFTs.append(nft)
        }

        return deduplicatedNFTs
    }

    private func prepareMetadataPatches(
        for fetchedNFTs: [NFTInventoryItemSnapshot]
    ) async -> [NFTMetadataUpdater.MetadataPatch?] {
        let inputs = fetchedNFTs.map {
            NFTMetadataPreparationInput(
                tokenURI: $0.tokenURI,
                rawTokenURI: $0.raw?.tokenURI,
                rawMetadata: $0.raw?.metadata
            )
        }

        var patches: [NFTMetadataUpdater.MetadataPatch?] = []
        patches.reserveCapacity(inputs.count)

        for input in inputs {
            guard !Task.isCancelled else {
                patches.append(nil)
                continue
            }

            let emptyPatch = NFTMetadataUpdater.MetadataPatch()
            let tokenURIs = Set([input.tokenURI, input.rawTokenURI].compactMap(\.self))
            let siftedTokenURIs = tokenURIs.siftTokenURIs()

            if let decodedTokenURI = siftedTokenURIs.lazy.compactMap(\.base64JSON).first {
                patches.append(NFTMetadataUpdater.metadataPatch(from: decodedTokenURI))
                continue
            }

            if let rawMetadata = input.rawMetadata {
                patches.append(NFTMetadataUpdater.metadataPatch(from: rawMetadata))
                continue
            }

            if let metadataURL = siftedTokenURIs.first,
               let fetchedMetadata = await metadataFetcher?.fetchMetadataJSON(from: metadataURL) {
                patches.append(NFTMetadataUpdater.metadataPatch(from: fetchedMetadata))
                continue
            }

            patches.append(emptyPatch)
        }

        return patches
    }
}
