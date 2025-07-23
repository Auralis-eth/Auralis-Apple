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

    //                NFTService
    //                    try recovery
    //                        store pageKey in user defaults
    //                            nil when success
    //                        show collected NFTs
    //                        in the UI have a button to retry continuation
    //                    Redundancy Providers
    //                        Backfill or failover with Reservoir, Zora API, or Moralis, QuickNode, Chainstack, BlockSpan, Coinbase, NFTScan
    //
    //
    //

    //move parsing from the other code over

    //TODO: 3) in the NFTService have the metadata parse out whats there
    //      parse metadata
    //      move more fetching and processing to the background
    //TODO: re-arch for getting ModelContainer instead of ModelContext
//    func fetchAllNFTs(for accountAddress: String, chain: Chain, container: ModelContainer) async {
//        let newContext = ModelContext(container)
//        await fetchAllNFTs(for: accountAddress, chain: chain, modelContext: newContext)
//    }

    func fetchAllNFTs(for accountAddress: String, chain: Chain, modelContext: ModelContext) async {
        do {
            let nfts = try await nftFetcher.fetchAllNFTs(for: accountAddress, chain: chain)//NFT.sampleData

            guard let nfts else {
                return
            }

            // Insert new NFTs
            await MainActor.run {
                for nft in nfts {
                    modelContext.insert(nft)
                }

                do {
                    try modelContext.save()
                } catch {
                    nftFetcher.error = error
                }
            }

            await withTaskGroup(of: Void.self) { group in
                // Parse metadata for each NFT
                group.addTask {
                    // Parse metadata for each NFT
                    await withTaskGroup(of: Void.self) { group in
                        for nft in nfts {
                            group.addTask {
                                await self.parseNFTMetadata(nft: nft, modelContext: modelContext)
                            }
                        }
                    }
                }

                if nftFetcher.currentCursor == nil {
                    // Clean up old NFTs that are no longer owned
                    group.addTask {
                        // Clean up old NFTs that are no longer owned
                        await self.cleanupOldNFTs(currentNFTIDs: nfts.map(\.id), modelContext: modelContext)
                    }
                }
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

    private func parseNFTMetadata(nft: NFT, modelContext: ModelContext) async {
        let tokenURIs = Set([nft.tokenUri, nft.raw?.tokenUri].compactMap(\.self))
        let siftedTokenURIs = tokenURIs.siftTokenURIs()

        guard !siftedTokenURIs.isEmpty else { return }

        if siftedTokenURIs.count > 1 {
            print("Multiple token URIs found for NFT \(nft.id)")
        }

        for tokenURI in tokenURIs {
            if let decodedTokenURI = tokenURI.base64JSON {
                // Handle base64 JSON token URI
                await processBase64TokenURI(decodedTokenURI, for: nft, modelContext: modelContext)
            } else if let url = URL(string: tokenURI) {
                // Handle URL-based token URI
                await MainActor.run {
                    NFTMetaParser(
                        url: url,
                        tokenURI: tokenURI,
                        nftID: nft.id,
                        modelContext: modelContext
                    ).startParsing()
                }
            }
        }
    }

    private func processBase64TokenURI(_ decodedURI: [String : Any], for nft: NFT, modelContext: ModelContext) async {
        // Add your base64 JSON processing logic here
        // This might involve parsing JSON and updating the NFT metadata
        print("Processing base64 token URI for NFT: \(nft.id)")
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
