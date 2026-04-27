import Foundation

extension NFT {
    func parseMetadata() {
        let tokenURIs = Set([tokenUri, raw?.tokenUri].compactMap(\.self))
        let siftedTokenURIs = tokenURIs.siftTokenURIs()

        guard !siftedTokenURIs.isEmpty else { return }

        if let decodedTokenURI = siftedTokenURIs.lazy.compactMap(\.base64JSON).first {
            NFTMetadataUpdater.updateNFTFromMetadata(nft: self, metadata: decodedTokenURI)
            return
        }

        NFTMetadataUpdater.updateNFTFromMetadata(nft: self, metadata: raw?.metadata)
    }
}
