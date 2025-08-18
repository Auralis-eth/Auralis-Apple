//
//  NFTMetadataUpdater.swift
//  Auralis
//
//  Created by Daniel Bell on 3/3/25.
//

import Foundation
import SwiftData

// MARK: - NFTMetadataUpdater Utility Class
class NFTMetadataUpdater {
    static func updateNFTFromMetadata(nft: NFT, metadata: [String : JSONValue]?) {
        guard let metadata else {
            return
        }
        // Basic Information
        if let name = metadata["name"] {
            nft.name = name.stringValue
        } else if let artworkName = metadata["artworkName"] {
            nft.name = artworkName.stringValue
        }

        if let description = metadata["description"] {
            nft.nftDescription = description.stringValue
        }

        // Collection Information
        if let collection = metadata["collection"], let collectionName = collection.objectValue?["name"] {
            nft.collectionName = collectionName.stringValue
        } else if let collectionName = metadata["collectionName"] {
            nft.collectionName = collectionName.stringValue
        }

        // Additional Collection Information
        if let collectionID = metadata["collectionID"] {
            nft.collectionID = collectionID.stringValue
        }
        if let projectID = metadata["projectID"] {
            nft.projectID = projectID.stringValue
        }
        if let series = metadata["series"] {
            nft.series = series.stringValue
        }
        if let seriesID = metadata["seriesID"] {
            nft.seriesID = seriesID.stringValue
        }

        // Artist/Creator Information
        if let artistName = metadata["artist_name"] {
            nft.artistName = artistName.stringValue
        } else if let artist = metadata["artist"] {
            nft.artistName = artist.stringValue
        } else if let creator = metadata["creator"] {
            nft.artistName = creator.stringValue
        } else if let createdBy = metadata["createdBy"] {
            nft.artistName = createdBy.stringValue
        }

        // Additional Artist Information
        if let artistWebsite = metadata["artistWebsite"] {
            nft.artistWebsite = artistWebsite.stringValue
        }

        // Media URLs - Optimized with helper function
        updateImageURLs(nft: nft, metadata: metadata)
        updateAnimationURLs(nft: nft, metadata: metadata)
        updateAudioURLs(nft: nft, metadata: metadata)
        updateExternalURLs(nft: nft, metadata: metadata)
        updateModelURLs(nft: nft, metadata: metadata)

        // Handle token IDs
        if let tokenID = metadata["tokenID"]?.intValue {
            nft.tokenId = String(tokenID)
        } else if let tokenID = metadata["tokenId"]?.intValue {
            nft.tokenId = String(tokenID)
        } else if let tokenIDString = metadata["tokenID"]?.stringValue ?? metadata["tokenId"]?.stringValue {
            nft.tokenId = tokenIDString
        }

        // Handle unique ID
        if let uniqueID = metadata["id"]?.stringValue {
            nft.uniqueID = uniqueID
        }

        // Handle timestamp and token hash
        if let timestamp = metadata["timestamp"]?.stringValue {
            nft.timestamp = timestamp
        }
        if let tokenHash = metadata["tokenHash"]?.stringValue {
            nft.tokenHash = tokenHash
        }

        // Handle metadata properties
        updateMetadataProperties(nft: nft, metadata: metadata)

        // Handle numeric properties
        updateNumericProperties(nft: nft, metadata: metadata)

        // Handle traits/attributes
        updateTraitsAndAttributes(nft: nft, metadata: metadata)
    }

    // MARK: - Helper Methods for URL Updates
    private static func updateImageURLs(nft: NFT, metadata: [String: JSONValue]) {
        // Handle main image URLs
        // Updated caller code with validated fallback
        if let imageURLString = metadata["image"]?.stringValue ?? metadata["imageUrl"]?.stringValue {
            switch URLConverter.convertToPreferredHTTPS(imageURLString) {
            case .success(let convertedURLString):
                nft.image?.originalUrl = convertedURLString
                if let imageURL = URL(string: convertedURLString) {
                    nft.image?.secureUrl = ensureSecureURL(imageURL)?.absoluteString
                }
            case .failure(let error):
                    print("URL conversion failed for \(imageURLString): \(error.localizedDescription)")  // Log for debugging

                // Fallback only if original is a valid URL
                if let originalURL = URL(string: imageURLString) {
                    nft.image?.originalUrl = imageURLString
                    nft.image?.secureUrl = ensureSecureURL(originalURL)?.absoluteString
                }
                // Otherwise, skip to avoid bad data
            }
        }


        // Handle specialized image URLs
        if let primaryAssetUrl = metadata["primaryAssetUrl"]?.stringValue {
            nft.primaryAssetUrl = primaryAssetUrl
            if let assetURL = URL(string: primaryAssetUrl) {
                nft.securePrimaryAssetUrl = ensureSecureURL(assetURL)?.absoluteString
            }
        }

        if let previewAssetUrl = metadata["previewAssetUrl"]?.stringValue {
            nft.previewAssetUrl = previewAssetUrl
            if let assetURL = URL(string: previewAssetUrl) {
                nft.securePreviewAssetUrl = ensureSecureURL(assetURL)?.absoluteString
            }
        }

        if let imageDataUrl = metadata["imageData"]?.stringValue {
            nft.imageDataUrl = imageDataUrl
            if let imageURL = URL(string: imageDataUrl) {
                nft.secureImageDataUrl = ensureSecureURL(imageURL)?.absoluteString
            }
        }

        if let imageHrUrl = metadata["imageHrUrl"]?.stringValue {
            nft.imageHrUrl = imageHrUrl
            if let imageURL = URL(string: imageHrUrl) {
                nft.secureImageHrUrl = ensureSecureURL(imageURL)?.absoluteString
            }
        }

        if let imageHash = metadata["imageHash"]?.stringValue {
            nft.imageHash = imageHash
        }
    }

    private static func updateAnimationURLs(nft: NFT, metadata: [String: JSONValue]) {
        if let animationURLString = metadata["animation_url"]?.stringValue ?? metadata["animationUrl"]?.stringValue ?? metadata["animation"]?.stringValue {
            nft.animationUrl = animationURLString
            if let animationURL = URL(string: animationURLString) {
                nft.secureAnimationUrl = ensureSecureURL(animationURL)?.absoluteString
            }
        }
    }

    private static func updateAudioURLs(nft: NFT, metadata: [String: JSONValue]) {
        let audioURLString = metadata["audioUrl"]?.stringValue ??
                           metadata["audioURI"]?.stringValue ??
                           metadata["audio"]?.stringValue ??
                           metadata["losslessAudio"]?.stringValue
        if let audioURLString = audioURLString {
            nft.audioUrl = audioURLString
        }
    }

    private static func updateExternalURLs(nft: NFT, metadata: [String: JSONValue]) {
        if let externalURLString = metadata["external_url"]?.stringValue ?? metadata["externalUrl"]?.stringValue ?? metadata["external_link"]?.stringValue {
            nft.externalUrl = externalURLString
        } else if let externals = metadata["external_url"]?.objectValue ?? metadata["externalUrl"]?.objectValue,
                  let externalURLString = externals["url"]?.stringValue {
            nft.externalUrl = externalURLString
        }
    }

    private static func updateModelURLs(nft: NFT, metadata: [String: JSONValue]) {
        let modelURLString = metadata["modelGlb"]?.stringValue ??
                           metadata["vrmUrl"]?.stringValue ??
                           metadata["usdzUrl"]?.stringValue ??
                           metadata["print3DSTL"]?.stringValue
        if let modelURLString = modelURLString {
            nft.modelUrl = modelURLString
        }
    }

    private static func updateMetadataProperties(nft: NFT, metadata: [String: JSONValue]) {
        if let backgroundColor = metadata["background_color"]?.stringValue ?? metadata["backgroundColor"]?.stringValue {
            nft.backgroundColor = backgroundColor
        }
        if let medium = metadata["medium"]?.stringValue {
            nft.medium = medium
        }
        if let metadataVersion = metadata["metadataVersion"]?.stringValue {
            nft.metadataVersion = metadataVersion
        }
        if let symbols = metadata["symbols"]?.stringValue {
            nft.symbols = symbols
        }
        if let seed = metadata["seed"]?.stringValue {
            nft.seed = seed
        }
        if let original = metadata["original"]?.stringValue {
            nft.original = original
        }
        if let agreement = metadata["agreement"]?.stringValue {
            nft.agreement = agreement
        }
        if let website = metadata["website"]?.stringValue {
            nft.website = website
        }
        if let payoutAddress = metadata["payoutAddress"]?.stringValue {
            nft.payoutAddress = payoutAddress
        }
        if let scriptType = metadata["scriptType"]?.stringValue {
            nft.scriptType = scriptType
        }
        if let engineType = metadata["engineType"]?.stringValue {
            nft.engineType = engineType
        }
        if let accessArtworkFiles = metadata["accessArtworkFiles"]?.stringValue {
            nft.accessArtworkFiles = accessArtworkFiles
        }
    }

    private static func updateNumericProperties(nft: NFT, metadata: [String: JSONValue]) {
        if let sellerFeeBasisPoints = metadata["sellerFeeBasisPoints"]?.intValue {
            nft.sellerFeeBasisPoints = sellerFeeBasisPoints
        }
        if let minted = metadata["minted"]?.intValue {
            nft.minted = minted
        }
        if let isStatic = metadata["isStatic"]?.intValue {
            nft.isStatic = isStatic
        }
        if let aspectRatio = metadata["aspectRatio"]?.doubleValue {
            nft.aspectRatio = aspectRatio
        }
    }

    private static func updateTraitsAndAttributes(nft: NFT, metadata: [String: JSONValue]) {
        if let attributesArray = metadata["attributes"]?.arrayValue  {//as? [[String: Any]]
            nft.attributes = attributesArray.compactMap {
                guard let attribute = $0.objectValue else {
                    return nil
                }

                guard let value = attribute["value"]?.stringValue else {
                    return nil
                }

                return NFT.Attribute(
                    value: value,
                    traitType: attribute["type"]?.stringValue ?? attribute["trait_type"]?.stringValue
                )
            }
        } else if let traitsArray = metadata["traits"]?.arrayValue {
            nft.attributes = traitsArray.compactMap {
                guard let traitDict = $0.objectValue else {
                    return nil
                }

                guard let value = traitDict["value"]?.stringValue else {
                    return nil
                }
                return NFT.Attribute(
                    value: value,
                    traitType: traitDict["type"]?.stringValue ?? traitDict["trait_type"]?.stringValue
                )
            }
        }
    }

    // Helper function to ensure URLs are secure (HTTPS) or point to a gateway
    private static func ensureSecureURL(_ url: URL) -> URL? {
        if url.isIPFS, let ipfsGatewayURL = url.ipfsHTML {
            return ipfsGatewayURL
        } else if url.scheme?.lowercased() == "http", var components = URLComponents(url: url, resolvingAgainstBaseURL: false) {
            components.scheme = "https"
            return components.url
        }
        return url
    }
}
