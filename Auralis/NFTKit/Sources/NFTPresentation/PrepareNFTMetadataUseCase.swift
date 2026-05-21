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
    public init() { }

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

        // Base64 metadata decoding can be CPU-heavy; keep it off any inherited actor.
        return await Task.detached(priority: .userInitiated) {
            inputs.map { input in
                guard !Task.isCancelled else {
                    return nil
                }

                let emptyPatch = NFTMetadataUpdater.MetadataPatch()
                let tokenURIs = Set([input.tokenURI, input.rawTokenURI].compactMap(\.self))
                let siftedTokenURIs = tokenURIs.siftTokenURIs()

                guard !siftedTokenURIs.isEmpty else {
                    return emptyPatch
                }

                if let decodedTokenURI = siftedTokenURIs.lazy.compactMap(\.base64JSON).first {
                    return NFTMetadataUpdater.metadataPatch(from: decodedTokenURI)
                }

                return NFTMetadataUpdater.metadataPatch(from: input.rawMetadata)
            }
        }.value
    }
}
