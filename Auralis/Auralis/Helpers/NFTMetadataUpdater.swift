//
//  NFTMetadataUpdater.swift
//  Auralis
//
//  Created by Daniel Bell on 3/3/25.
//

import Foundation
import OSLog

private let nftMetadataUpdaterLogger = Logger(subsystem: "Auralis", category: "NFTMetadataUpdater")
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
        if let imageURLString = metadata["image"]?.stringValue ?? metadata["imageUrl"]?.stringValue {
            if nft.image == nil {
                nft.image = NFT.Image()
            }

            if let sanitizedURL = sanitizedMediaURL(from: imageURLString) {
                nft.image?.originalUrl = sanitizedURL.absoluteString
                nft.image?.secureUrl = sanitizedURL.absoluteString
            } else {
                nft.image?.originalUrl = nil
                nft.image?.secureUrl = nil
                logRejectedMediaURL(imageURLString, field: "image")
            }
        }


        // Handle specialized image URLs
        if let primaryAssetUrl = metadata["primaryAssetUrl"]?.stringValue {
            let sanitizedURL = sanitizedMediaURL(from: primaryAssetUrl)
            nft.primaryAssetUrl = sanitizedURL?.absoluteString
            nft.securePrimaryAssetUrl = sanitizedURL?.absoluteString
            if sanitizedURL == nil {
                logRejectedMediaURL(primaryAssetUrl, field: "primaryAssetUrl")
            }
        }

        if let previewAssetUrl = metadata["previewAssetUrl"]?.stringValue {
            let sanitizedURL = sanitizedMediaURL(from: previewAssetUrl)
            nft.previewAssetUrl = sanitizedURL?.absoluteString
            nft.securePreviewAssetUrl = sanitizedURL?.absoluteString
            if sanitizedURL == nil {
                logRejectedMediaURL(previewAssetUrl, field: "previewAssetUrl")
            }
        }

        if let imageDataUrl = metadata["imageData"]?.stringValue {
            let sanitizedURL = sanitizedMediaURL(from: imageDataUrl)
            nft.imageDataUrl = sanitizedURL?.absoluteString
            nft.secureImageDataUrl = sanitizedURL?.absoluteString
            if sanitizedURL == nil {
                logRejectedMediaURL(imageDataUrl, field: "imageData")
            }
        }

        if let imageHrUrl = metadata["imageHrUrl"]?.stringValue {
            let sanitizedURL = sanitizedMediaURL(from: imageHrUrl)
            nft.imageHrUrl = sanitizedURL?.absoluteString
            nft.secureImageHrUrl = sanitizedURL?.absoluteString
            if sanitizedURL == nil {
                logRejectedMediaURL(imageHrUrl, field: "imageHrUrl")
            }
        }

        if let imageHash = metadata["imageHash"]?.stringValue {
            nft.imageHash = imageHash
        }
    }

    private static func updateAnimationURLs(nft: NFT, metadata: [String: JSONValue]) {
        if let animationURLString = metadata["animation_url"]?.stringValue ?? metadata["animationUrl"]?.stringValue ?? metadata["animation"]?.stringValue {
            if let sanitizedURL = sanitizedMediaURL(from: animationURLString) {
                nft.animationUrl = sanitizedURL.absoluteString
                nft.secureAnimationUrl = sanitizedURL.absoluteString
            } else {
                nft.animationUrl = nil
                nft.secureAnimationUrl = nil
                logRejectedMediaURL(animationURLString, field: "animation")
            }
        }
    }

    private static func updateAudioURLs(nft: NFT, metadata: [String: JSONValue]) {
        let audioURLString = metadata["audioUrl"]?.stringValue ??
                           metadata["audioURI"]?.stringValue ??
                           metadata["audio"]?.stringValue ??
                           metadata["losslessAudio"]?.stringValue
        if let audioURLString = audioURLString {
            if let sanitizedURL = sanitizedMediaURL(from: audioURLString) {
                nft.audioUrl = sanitizedURL.absoluteString
            } else {
                nft.audioUrl = nil
                logRejectedMediaURL(audioURLString, field: "audio")
            }
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

                guard let value = attribute["value"]?.stringifiedValue else {
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

                guard let value = traitDict["value"]?.stringifiedValue else {
                    return nil
                }
                return NFT.Attribute(
                    value: value,
                    traitType: traitDict["type"]?.stringValue ?? traitDict["trait_type"]?.stringValue
                )
            }
        }
    }

    private static func sanitizedMediaURL(from rawValue: String) -> URL? {
        URL.sanitizedRemoteMediaURL(from: rawValue)
    }

    private static func logRejectedMediaURL(_ rawValue: String, field: String) {
        let trimmedValue = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedValue.isEmpty else {
            return
        }

        nftMetadataUpdaterLogger.notice("Rejected \(field, privacy: .public) URL: \(trimmedValue, privacy: .private(mask: .hash))")
    }
}

private extension JSONValue {
    var stringifiedValue: String? {
        switch self {
        case .string(let value):
            return value
        case .int(let value):
            return String(value)
        case .double(let value):
            return String(value)
        case .bool(let value):
            return String(value)
        case .null, .object, .array:
            return nil
        }
    }
}
