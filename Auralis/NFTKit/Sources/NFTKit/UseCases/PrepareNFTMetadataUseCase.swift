//
//  PrepareNFTMetadataUseCase.swift
//  Auralis
//
//  Created by Codex on 8/26/25.
//

import AuralisPrimaryModels
import Foundation

public struct PreparedNFTInventory {
    public let nfts: [NFT]

    public init(nfts: [NFT]) {
        self.nfts = nfts
    }
}

private struct NFTMetadataPreparationInput: Sendable {
    let tokenURI: String?
    let rawTokenURI: String?
    let rawMetadata: [String: JSONValue]?
}

@MainActor
public protocol PrepareNFTMetadataUsing {
    func prepareInventory(
        _ fetchedNFTs: [NFT],
        accountAddress: String,
        chain: Chain
    ) async -> PreparedNFTInventory
}

@MainActor
public struct LivePrepareNFTMetadataUseCase: PrepareNFTMetadataUsing {
    public init() { }

    public func prepareInventory(
        _ fetchedNFTs: [NFT],
        accountAddress: String,
        chain: Chain
    ) async -> PreparedNFTInventory {
        let metadataPatches = await prepareMetadataPatches(for: fetchedNFTs)

        for (index, nft) in fetchedNFTs.enumerated() {
            nft.applyRefreshScope(accountAddress: accountAddress, chain: chain)
            if let metadataPatch = metadataPatches[index] {
                NFTMetadataUpdater.applyMetadataPatch(metadataPatch, to: nft)
                nft.applyRefreshScope(accountAddress: accountAddress, chain: chain)
            }

            if index.isMultiple(of: 25) {
                await Task.yield()
            }
        }

        return PreparedNFTInventory(nfts: deduplicateFetchedNFTs(fetchedNFTs))
    }

    private func deduplicateFetchedNFTs(_ nfts: [NFT]) -> [NFT] {
        var seenIDs = Set<String>()
        var deduplicatedNFTs: [NFT] = []
        deduplicatedNFTs.reserveCapacity(nfts.count)

        for nft in nfts where seenIDs.insert(nft.id).inserted {
            deduplicatedNFTs.append(nft)
        }

        return deduplicatedNFTs
    }

    private func prepareMetadataPatches(
        for fetchedNFTs: [NFT]
    ) async -> [NFTMetadataUpdater.MetadataPatch?] {
        let inputs = fetchedNFTs.map {
            NFTMetadataPreparationInput(
                tokenURI: $0.tokenUri,
                rawTokenURI: $0.raw?.tokenUri,
                rawMetadata: $0.raw?.metadata
            )
        }

        return await Task.detached(priority: .userInitiated) {
            inputs.map { input in
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
