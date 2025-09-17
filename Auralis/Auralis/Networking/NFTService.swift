//
//  NFTService.swift
//  Auralis
//
//  Created by Daniel Bell on 6/29/25.
//

import Foundation
import SwiftData

@Observable
class NFTService {
    private let nftFetcher = NFTFetcher()
    var isLoading: Bool { nftFetcher.loading }
    var itemsLoaded: Int? { nftFetcher.itemsLoaded }
    var total: Int? { nftFetcher.total }
    var error: Error? { nftFetcher.error }

    //TODO: re-arch for getting ModelContainer instead of ModelContext
//    func fetchAllNFTs(for accountAddress: String, chain: Chain, container: ModelContainer) async {
//        let newContext = ModelContext(container)
//        await fetchAllNFTs(for: accountAddress, chain: chain, modelContext: newContext)
//    }

    func fetchAllNFTs(for accountAddress: String, chain: Chain, modelContext: ModelContext) async {
        do {
            let nfts = try await nftFetcher.fetchAllNFTs(for: accountAddress, chain: chain)

            nfts.forEach {
                $0.parseMetadata()
            }

            if (nftFetcher.itemsLoaded ?? 0) > (nftFetcher.total ?? 0) - 200 || nftFetcher.currentCursor == nil {
                await cleanupOldNFTs(currentNFTIDs: nfts.map(\.id), modelContext: modelContext)
            } else if let currentCursor = nftFetcher.currentCursor {
                UserDefaults.standard.set(currentCursor, forKey: "currentCursor")
            }

            do {
                try await MainActor.run {
                    for nft in nfts {
                        modelContext.insert(nft)
                    }
                    try modelContext.save()
                }
            } catch {
                print("Error updating NFT in SwiftData: \(error)")
            }

        } catch {
            await MainActor.run {
                nftFetcher.error = error
            }
        }

        await MainActor.run {
            nftFetcher.reset()
        }
    }

    func refreshNFTs(for currentAccount: EOAccount?, chain: Chain, modelContext: ModelContext) async {
        guard let accountAddress = currentAccount?.address else {
            return
        }

        await fetchAllNFTs(
            for: accountAddress,
            chain: chain,
            modelContext: modelContext
        )
    }

    private func cleanupOldNFTs(currentNFTIDs: [String], modelContext: ModelContext) async {
        let descriptor = FetchDescriptor<NFT>(
            predicate: #Predicate<NFT> { !currentNFTIDs.contains($0.id) }
        )

        await MainActor.run {
            do {
                try modelContext.enumerate(descriptor) { nft in
                    modelContext.delete(nft)
                }
                try modelContext.save()
            } catch {
                print("Failed to cleanup old NFTs from SwiftData: \(error)")
                nftFetcher.error = error
            }
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
