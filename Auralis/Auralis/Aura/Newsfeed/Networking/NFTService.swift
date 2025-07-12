import Foundation
import SwiftData
import SwiftUI


@Observable
class NFTService {
    private let nftFetcher = NFTFetcher()

    var isLoading: Bool { nftFetcher.loading }
    var itemsLoaded: Int? { nftFetcher.itemsLoaded }
    var total: Int? { nftFetcher.total }
    var error: Error? { nftFetcher.error }

    func fetchAllNFTs(for accountAddress: String, chain: Chain, modelContext: ModelContext) async {
        do {
            print("========== Fetching NFTs for \(accountAddress) ==========")
            let nfts = try await nftFetcher.fetchAllNFTs(for: accountAddress, chain: chain)

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

            // Fetch metadata for all NFTs in batches
            await fetchMetadataForNFTs(nfts, chain: chain, modelContext: modelContext)

            // Clean up old NFTs
            await cleanupOldNFTs(currentNFTIDs: nfts.map(\.id), modelContext: modelContext)

        } catch {
            await MainActor.run {
                nftFetcher.error = error
            }
        }

        await MainActor.run {
            nftFetcher.reset()
        }
    }

    private func fetchMetadataForNFTs(_ nfts: [NFT], chain: Chain, modelContext: ModelContext) async {
        // Create TokenRequest objects for NFTs that need metadata
        let tokenRequests = await createTokenRequestsForNFTs(nfts, modelContext: modelContext)

        guard !tokenRequests.isEmpty else {
            return
        }

        // Fetch metadata in batches using Alchemy API
        let metadataResponses = await nftFetcher.fetchMetadataBatchLarge(for: tokenRequests, chain: chain)

        // Update NFTs with fetched metadata
        await updateNFTsWithMetadata(nfts: nfts, metadataResponses: metadataResponses, modelContext: modelContext)
    }

    private func createTokenRequestsForNFTs(_ nfts: [NFT], modelContext: ModelContext) async -> [TokenRequest] {
        var tokenRequests: [TokenRequest] = []

        for nft in nfts {
            // Check if NFT already has metadata
            if !nft.hasMetaData, let contractAddress = nft.contract.address {
                let tokenRequest = TokenRequest(
                    contractAddress: contractAddress,
                    tokenId: nft.tokenId
                )
                tokenRequests.append(tokenRequest)
            }
        }

        return tokenRequests
    }

    private func updateNFTsWithMetadata(nfts: [NFT], metadataResponses: [NFTMetadataResponse], modelContext: ModelContext) async {
        await MainActor.run {
            // Create a lookup dictionary for faster access
            var metadataLookup: [String: NFTMetadataResponse] = [:]

            for response in metadataResponses {
                if let contractAddress = response.contract?.address,
                   let tokenId = response.tokenId {
                    let key = "\(contractAddress.lowercased())_\(tokenId)"
                    metadataLookup[key] = response
                }
            }

            // Update each NFT with its corresponding metadata
            for nft in nfts {
                if let contractAddress = nft.contract.address {
                    let tokenId = nft.tokenId
                    let key = "\(contractAddress.lowercased())_\(tokenId)"

                    if let metadataResponse = metadataLookup[key],
                       let rawMetadata = metadataResponse.raw?.metadata {
                        updateNFTWithMetadata(nft: nft, metadata: rawMetadata, modelContext: modelContext)
                    }
                }
            }

            do {
                try modelContext.save()
            } catch {
                print("Error saving NFT metadata updates: \(error)")
                nftFetcher.error = error
            }
        }
    }

    private func updateNFTWithMetadata(nft: NFT, metadata: [String: JSONValue], modelContext: ModelContext) {
        // Convert JSONValue dictionary to [String: Any] for easier processing
        let metadataDict = convertJSONValueToAny(metadata)

        // Update NFT properties using the existing updateNFTProperties method
        updateNFTProperties(nft, with: metadataDict)
    }

    private func convertJSONValueToAny(_ jsonValue: [String: JSONValue]) -> [String: Any] {
        var result: [String: Any] = [:]

        for (key, value) in jsonValue {
            result[key] = convertJSONValueToAny(value)
        }

        return result
    }

    private func convertJSONValueToAny(_ jsonValue: JSONValue) -> Any {
        switch jsonValue {
        case .string(let value):
            return value
        case .int(let value):
            return value
        case .double(let value):
            return value
        case .bool(let value):
            return value
        case .object(let dict):
            return convertJSONValueToAny(dict)
        case .array(let array):
            return array.map { convertJSONValueToAny($0) }
        case .null:
            return NSNull()
        }
    }

    private func updateNFTProperties(_ nft: NFT, with json: [String: Any]) {
        // Basic Information
        if let name = json["name"] as? String {
            nft.name = name
        } else if let artworkName = json["artworkName"] as? String {
            nft.name = artworkName
        }

        if let description = json["description"] as? String {
            nft.nftDescription = description
        }

        // Collection Information
        if let collection = json["collection"] as? [String: Any], let collectionName = collection["name"] as? String {
            nft.collectionName = collectionName
        } else if let collectionName = json["collectionName"] as? String {
            nft.collectionName = collectionName
        }

        // Additional Collection Information
        if let collectionID = json["collectionID"] as? String {
            nft.collectionID = collectionID
        }

        if let projectID = json["projectID"] as? String {
            nft.projectID = projectID
        }

        if let series = json["series"] as? String {
            nft.series = series
        }

        if let seriesID = json["seriesID"] as? String {
            nft.seriesID = seriesID
        }

        // Artist/Creator Information
        if let artistName = json["artist_name"] as? String {
            nft.artistName = artistName
        } else if let artist = json["artist"] as? String {
            nft.artistName = artist
        } else if let creator = json["creator"] as? String {
            nft.artistName = creator
        } else if let createdBy = json["createdBy"] as? String {
            nft.artistName = createdBy
        }

        // Additional Artist Information
        if let artistWebsite = json["artistWebsite"] as? String {
            nft.artistWebsite = artistWebsite
        }

        // Media URLs
        // First handle image URLs
        if let imageURLString = json["image"] as? String {
            nft.image?.originalUrl = imageURLString
            if let imageURL = URL(string: imageURLString) {
                nft.image?.secureUrl = ensureSecureURL(imageURL)?.absoluteString
            }
        }

        if let imageURLString = json["imageUrl"] as? String {
            nft.image?.originalUrl = imageURLString
            if let imageURL = URL(string: imageURLString) {
                nft.image?.secureUrl = ensureSecureURL(imageURL)?.absoluteString
            }
        }

        // Handle primary asset URLs
        if let primaryAssetUrl = json["primaryAssetUrl"] as? String {
            nft.primaryAssetUrl = primaryAssetUrl
            if let imageURL = URL(string: primaryAssetUrl) {
                nft.securePrimaryAssetUrl = ensureSecureURL(imageURL)?.absoluteString
            }
        }

        // Handle preview asset URLs
        if let previewAssetUrl = json["previewAssetUrl"] as? String {
            nft.previewAssetUrl = previewAssetUrl
            if let imageURL = URL(string: previewAssetUrl) {
                nft.securePreviewAssetUrl = ensureSecureURL(imageURL)?.absoluteString
            }
        }

        // Handle image data
        if let imageDataUrl = json["imageData"] as? String {
            nft.imageDataUrl = imageDataUrl
            if let imageURL = URL(string: imageDataUrl) {
                nft.secureImageDataUrl = ensureSecureURL(imageURL)?.absoluteString
            }
        }

        // Handle high-resolution image
        if let imageHrUrl = json["imageHrUrl"] as? String {
            nft.imageHrUrl = imageHrUrl
            if let imageURL = URL(string: imageHrUrl) {
                nft.secureImageHrUrl = ensureSecureURL(imageURL)?.absoluteString
            }
        }

        // Handle image hash and details
        if let imageHash = json["imageHash"] as? String {
            nft.imageHash = imageHash
        }

        // Then handle animation URLs
        if let animationURLString = json["animationUrl"] as? String, let animationURL = URL(string: animationURLString) {
            nft.animationUrl = animationURLString
            nft.secureAnimationUrl = ensureSecureURL(animationURL)?.absoluteString
        } else if let animationURLString = json["animation"] as? String, let animationURL = URL(string: animationURLString) {
            nft.animationUrl = animationURLString
            nft.secureAnimationUrl = ensureSecureURL(animationURL)?.absoluteString
        }

        // Handle audio URLs
        if let audioURLString = json["audioUrl"] as? String {
            nft.audioUrl = audioURLString
        } else if let audioURLString = json["audioURI"] as? String {
            nft.audioUrl = audioURLString
        } else if let audioURLString = json["audio"] as? String {
            nft.audioUrl = audioURLString
        } else if let audioURLString = json["losslessAudio"] as? String {
            nft.audioUrl = audioURLString
        }

        // Handle external URLs/links
        if let externalURLString = json["externalUrl"] as? String {
            nft.externalUrl = externalURLString
        } else if let externalURLString = json["external_link"] as? String {
            nft.externalUrl = externalURLString
        } else if let externals = json["externalUrl"] as? [String: Any],
                  let externalURLString = externals["url"] as? String {
            nft.externalUrl = externalURLString
        }

        // Handle 3D model URLs
        if let modelURLString = json["modelGlb"] as? String {
            nft.modelUrl = modelURLString
        } else if let modelURLString = json["vrmUrl"] as? String {
            nft.modelUrl = modelURLString
        } else if let modelURLString = json["usdzUrl"] as? String {
            nft.modelUrl = modelURLString
        } else if let modelURLString = json["print3DSTL"] as? String {
            nft.modelUrl = modelURLString
        }

        // Handle token IDs
        if let tokenID = json["tokenID"] as? Int {
            nft.tokenId = String(tokenID)
        } else if let tokenID = json["tokenId"] as? Int {
            nft.tokenId = String(tokenID)
        } else if let tokenIDString = json["tokenID"] as? String {
            nft.tokenId = tokenIDString
        } else if let tokenIDString = json["tokenId"] as? String {
            nft.tokenId = tokenIDString
        }

        // Handle unique ID
        if let uniqueID = json["id"] as? String {
            nft.uniqueID = uniqueID
        }

        // Handle timestamp and token hash
        if let timestamp = json["timestamp"] as? String {
            nft.timestamp = timestamp
        }

        if let tokenHash = json["tokenHash"] as? String {
            nft.tokenHash = tokenHash
        }

        // Handle metadata for background color
        if let backgroundColor = json["backgroundColor"] as? String {
            nft.backgroundColor = backgroundColor
        }

        // Additional metadata
        if let medium = json["medium"] as? String {
            nft.medium = medium
        }

        if let metadataVersion = json["metadataVersion"] as? String {
            nft.metadataVersion = metadataVersion
        }

        if let symbols = json["symbols"] as? String {
            nft.symbols = symbols
        }

        if let seed = json["seed"] as? String {
            nft.seed = seed
        }

        if let original = json["original"] as? String {
            nft.original = original
        }

        if let agreement = json["agreement"] as? String {
            nft.agreement = agreement
        }

        if let website = json["website"] as? String {
            nft.website = website
        }

        if let payoutAddress = json["payoutAddress"] as? String {
            nft.payoutAddress = payoutAddress
        }

        if let scriptType = json["scriptType"] as? String {
            nft.scriptType = scriptType
        }

        if let engineType = json["engineType"] as? String {
            nft.engineType = engineType
        }

        if let accessArtworkFiles = json["accessArtworkFiles"] as? String {
            nft.accessArtworkFiles = accessArtworkFiles
        }

        // Handle numeric properties
        if let sellerFeeBasisPoints = json["sellerFeeBasisPoints"] as? Int {
            nft.sellerFeeBasisPoints = sellerFeeBasisPoints
        }

        if let minted = json["minted"] as? Int {
            nft.minted = minted
        }

        if let isStatic = json["isStatic"] as? Int {
            nft.isStatic = isStatic
        }

        if let aspectRatio = json["aspectRatio"] as? Double {
            nft.aspectRatio = aspectRatio
        }
    }

    private func ensureSecureURL(_ url: URL) -> URL? {
        if url.scheme?.lowercased() == "http", var components = URLComponents(url: url, resolvingAgainstBaseURL: false) {
            components.scheme = "https"
            return components.url
        } else if url.isIPFS, let ipfsURL = url.ipfsHTML {
            return ipfsURL
        }
        return url
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

    func reset() {
        nftFetcher.reset()
    }
}
