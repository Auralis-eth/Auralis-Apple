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

// MARK: - NFTMetadataUpdater Utility Type
enum NFTMetadataUpdater {
    struct ParsedAttribute: Sendable {
        let value: String
        let traitType: String?
    }

    enum MetadataUpdate<Value: Sendable>: Sendable {
        case unchanged
        case set(Value)
    }

    struct MetadataPatch: Sendable {
        var name: MetadataUpdate<String> = .unchanged
        var nftDescription: MetadataUpdate<String> = .unchanged
        var collectionName: MetadataUpdate<String> = .unchanged
        var collectionID: MetadataUpdate<String> = .unchanged
        var projectID: MetadataUpdate<String> = .unchanged
        var series: MetadataUpdate<String> = .unchanged
        var seriesID: MetadataUpdate<String> = .unchanged
        var artistName: MetadataUpdate<String> = .unchanged
        var artistWebsite: MetadataUpdate<String> = .unchanged
        var imageOriginalURL: MetadataUpdate<String?> = .unchanged
        var imageSecureURL: MetadataUpdate<String?> = .unchanged
        var primaryAssetURL: MetadataUpdate<String?> = .unchanged
        var securePrimaryAssetURL: MetadataUpdate<String?> = .unchanged
        var previewAssetURL: MetadataUpdate<String?> = .unchanged
        var securePreviewAssetURL: MetadataUpdate<String?> = .unchanged
        var imageDataURL: MetadataUpdate<String?> = .unchanged
        var secureImageDataURL: MetadataUpdate<String?> = .unchanged
        var imageHrURL: MetadataUpdate<String?> = .unchanged
        var secureImageHrURL: MetadataUpdate<String?> = .unchanged
        var imageHash: MetadataUpdate<String> = .unchanged
        var animationURL: MetadataUpdate<String?> = .unchanged
        var secureAnimationURL: MetadataUpdate<String?> = .unchanged
        var audioURL: MetadataUpdate<String?> = .unchanged
        var externalURL: MetadataUpdate<String> = .unchanged
        var modelURL: MetadataUpdate<String> = .unchanged
        var tokenId: MetadataUpdate<String> = .unchanged
        var uniqueID: MetadataUpdate<String> = .unchanged
        var timestamp: MetadataUpdate<String> = .unchanged
        var tokenHash: MetadataUpdate<String> = .unchanged
        var backgroundColor: MetadataUpdate<String> = .unchanged
        var medium: MetadataUpdate<String> = .unchanged
        var metadataVersion: MetadataUpdate<String> = .unchanged
        var symbols: MetadataUpdate<String> = .unchanged
        var seed: MetadataUpdate<String> = .unchanged
        var original: MetadataUpdate<String> = .unchanged
        var agreement: MetadataUpdate<String> = .unchanged
        var website: MetadataUpdate<String> = .unchanged
        var payoutAddress: MetadataUpdate<String> = .unchanged
        var scriptType: MetadataUpdate<String> = .unchanged
        var engineType: MetadataUpdate<String> = .unchanged
        var accessArtworkFiles: MetadataUpdate<String> = .unchanged
        var sellerFeeBasisPoints: MetadataUpdate<Int> = .unchanged
        var minted: MetadataUpdate<Int> = .unchanged
        var isStatic: MetadataUpdate<Int> = .unchanged
        var aspectRatio: MetadataUpdate<Double> = .unchanged
        var attributes: MetadataUpdate<[ParsedAttribute]> = .unchanged
    }

    static func updateNFTFromMetadata(nft: NFT, metadata: [String: JSONValue]?) {
        applyMetadataPatch(metadataPatch(from: metadata), to: nft)
    }

    static func metadataPatch(from metadata: [String: JSONValue]?) -> MetadataPatch {
        var patch = MetadataPatch()
        guard let metadata else {
            return patch
        }

        // Basic Information
        if let name = metadata["name"] {
            if let resolvedName = name.stringValue {
                patch.name = .set(resolvedName)
            }
        } else if let artworkName = metadata["artworkName"] {
            if let resolvedName = artworkName.stringValue {
                patch.name = .set(resolvedName)
            }
        }

        if let description = metadata["description"] {
            if let resolvedDescription = description.stringValue {
                patch.nftDescription = .set(resolvedDescription)
            }
        }

        // Collection Information
        if let collection = metadata["collection"], let collectionName = collection.objectValue?["name"] {
            if let resolvedCollectionName = collectionName.stringValue {
                patch.collectionName = .set(resolvedCollectionName)
            }
        } else if let collectionName = metadata["collectionName"] {
            if let resolvedCollectionName = collectionName.stringValue {
                patch.collectionName = .set(resolvedCollectionName)
            }
        }

        // Additional Collection Information
        if let collectionID = metadata["collectionID"] {
            if let resolvedCollectionID = collectionID.stringValue {
                patch.collectionID = .set(resolvedCollectionID)
            }
        }
        if let projectID = metadata["projectID"] {
            if let resolvedProjectID = projectID.stringValue {
                patch.projectID = .set(resolvedProjectID)
            }
        }
        if let series = metadata["series"] {
            if let resolvedSeries = series.stringValue {
                patch.series = .set(resolvedSeries)
            }
        }
        if let seriesID = metadata["seriesID"] {
            if let resolvedSeriesID = seriesID.stringValue {
                patch.seriesID = .set(resolvedSeriesID)
            }
        }

        // Artist/Creator Information
        if let artistName = metadata["artist_name"] {
            if let resolvedArtistName = artistName.stringValue {
                patch.artistName = .set(resolvedArtistName)
            }
        } else if let artist = metadata["artist"] {
            if let resolvedArtistName = artist.stringValue {
                patch.artistName = .set(resolvedArtistName)
            }
        } else if let creator = metadata["creator"] {
            if let resolvedArtistName = creator.stringValue {
                patch.artistName = .set(resolvedArtistName)
            }
        } else if let createdBy = metadata["createdBy"] {
            if let resolvedArtistName = createdBy.stringValue {
                patch.artistName = .set(resolvedArtistName)
            }
        }

        // Additional Artist Information
        if let artistWebsite = metadata["artistWebsite"] {
            if let resolvedArtistWebsite = artistWebsite.stringValue {
                patch.artistWebsite = .set(resolvedArtistWebsite)
            }
        }

        // Media URLs - Optimized with helper function
        updateImageURLs(patch: &patch, metadata: metadata)
        updateAnimationURLs(patch: &patch, metadata: metadata)
        updateAudioURLs(patch: &patch, metadata: metadata)
        updateExternalURLs(patch: &patch, metadata: metadata)
        updateModelURLs(patch: &patch, metadata: metadata)

        // Handle token IDs
        if let tokenID = metadata["tokenID"]?.intValue {
            patch.tokenId = .set(String(tokenID))
        } else if let tokenID = metadata["tokenId"]?.intValue {
            patch.tokenId = .set(String(tokenID))
        } else if let tokenIDString = metadata["tokenID"]?.stringValue ?? metadata["tokenId"]?.stringValue {
            patch.tokenId = .set(tokenIDString)
        }

        // Handle unique ID
        if let uniqueID = metadata["id"]?.stringValue {
            patch.uniqueID = .set(uniqueID)
        }

        // Handle timestamp and token hash
        if let timestamp = metadata["timestamp"]?.stringValue {
            patch.timestamp = .set(timestamp)
        }
        if let tokenHash = metadata["tokenHash"]?.stringValue {
            patch.tokenHash = .set(tokenHash)
        }

        // Handle metadata properties
        updateMetadataProperties(patch: &patch, metadata: metadata)

        // Handle numeric properties
        updateNumericProperties(patch: &patch, metadata: metadata)

        // Handle traits/attributes
        updateTraitsAndAttributes(patch: &patch, metadata: metadata)

        return patch
    }

    static func applyMetadataPatch(_ patch: MetadataPatch, to nft: NFT) {
        apply(patch.name, to: &nft.name)
        apply(patch.nftDescription, to: &nft.nftDescription)
        apply(patch.collectionName, to: &nft.collectionName)
        apply(patch.collectionID, to: &nft.collectionID)
        apply(patch.projectID, to: &nft.projectID)
        apply(patch.series, to: &nft.series)
        apply(patch.seriesID, to: &nft.seriesID)
        apply(patch.artistName, to: &nft.artistName)
        apply(patch.artistWebsite, to: &nft.artistWebsite)
        applyImagePatch(patch, to: nft)
        apply(patch.primaryAssetURL, to: &nft.primaryAssetUrl)
        apply(patch.securePrimaryAssetURL, to: &nft.securePrimaryAssetUrl)
        apply(patch.previewAssetURL, to: &nft.previewAssetUrl)
        apply(patch.securePreviewAssetURL, to: &nft.securePreviewAssetUrl)
        apply(patch.imageDataURL, to: &nft.imageDataUrl)
        apply(patch.secureImageDataURL, to: &nft.secureImageDataUrl)
        apply(patch.imageHrURL, to: &nft.imageHrUrl)
        apply(patch.secureImageHrURL, to: &nft.secureImageHrUrl)
        apply(patch.imageHash, to: &nft.imageHash)
        apply(patch.animationURL, to: &nft.animationUrl)
        apply(patch.secureAnimationURL, to: &nft.secureAnimationUrl)
        apply(patch.audioURL, to: &nft.audioUrl)
        apply(patch.externalURL, to: &nft.externalUrl)
        apply(patch.modelURL, to: &nft.modelUrl)
        apply(patch.tokenId, to: &nft.tokenId)
        apply(patch.uniqueID, to: &nft.uniqueID)
        apply(patch.timestamp, to: &nft.timestamp)
        apply(patch.tokenHash, to: &nft.tokenHash)
        apply(patch.backgroundColor, to: &nft.backgroundColor)
        apply(patch.medium, to: &nft.medium)
        apply(patch.metadataVersion, to: &nft.metadataVersion)
        apply(patch.symbols, to: &nft.symbols)
        apply(patch.seed, to: &nft.seed)
        apply(patch.original, to: &nft.original)
        apply(patch.agreement, to: &nft.agreement)
        apply(patch.website, to: &nft.website)
        apply(patch.payoutAddress, to: &nft.payoutAddress)
        apply(patch.scriptType, to: &nft.scriptType)
        apply(patch.engineType, to: &nft.engineType)
        apply(patch.accessArtworkFiles, to: &nft.accessArtworkFiles)
        apply(patch.sellerFeeBasisPoints, to: &nft.sellerFeeBasisPoints)
        apply(patch.minted, to: &nft.minted)
        apply(patch.isStatic, to: &nft.isStatic)
        apply(patch.aspectRatio, to: &nft.aspectRatio)
        applyAttributesPatch(patch.attributes, to: nft)
    }

    // MARK: - Helper Methods for URL Updates
    private static func updateImageURLs(patch: inout MetadataPatch, metadata: [String: JSONValue]) {
        // Handle main image URLs
        if let imageURLString = metadata["image"]?.stringValue ?? metadata["imageUrl"]?.stringValue {
            if let sanitizedURL = sanitizedMediaURL(from: imageURLString) {
                patch.imageOriginalURL = .set(sanitizedURL.absoluteString)
                patch.imageSecureURL = .set(sanitizedURL.absoluteString)
            } else {
                patch.imageOriginalURL = .set(nil)
                patch.imageSecureURL = .set(nil)
                logRejectedMediaURL(imageURLString, field: "image")
            }
        }

        // Handle specialized image URLs
        if let primaryAssetUrl = metadata["primaryAssetUrl"]?.stringValue {
            let sanitizedURL = sanitizedMediaURL(from: primaryAssetUrl)
            patch.primaryAssetURL = .set(sanitizedURL?.absoluteString)
            patch.securePrimaryAssetURL = .set(sanitizedURL?.absoluteString)
            if sanitizedURL == nil {
                logRejectedMediaURL(primaryAssetUrl, field: "primaryAssetUrl")
            }
        }

        if let previewAssetUrl = metadata["previewAssetUrl"]?.stringValue {
            let sanitizedURL = sanitizedMediaURL(from: previewAssetUrl)
            patch.previewAssetURL = .set(sanitizedURL?.absoluteString)
            patch.securePreviewAssetURL = .set(sanitizedURL?.absoluteString)
            if sanitizedURL == nil {
                logRejectedMediaURL(previewAssetUrl, field: "previewAssetUrl")
            }
        }

        if let imageDataUrl = metadata["imageData"]?.stringValue {
            let sanitizedURL = sanitizedMediaURL(from: imageDataUrl)
            patch.imageDataURL = .set(sanitizedURL?.absoluteString)
            patch.secureImageDataURL = .set(sanitizedURL?.absoluteString)
            if sanitizedURL == nil {
                logRejectedMediaURL(imageDataUrl, field: "imageData")
            }
        }

        if let imageHrUrl = metadata["imageHrUrl"]?.stringValue {
            let sanitizedURL = sanitizedMediaURL(from: imageHrUrl)
            patch.imageHrURL = .set(sanitizedURL?.absoluteString)
            patch.secureImageHrURL = .set(sanitizedURL?.absoluteString)
            if sanitizedURL == nil {
                logRejectedMediaURL(imageHrUrl, field: "imageHrUrl")
            }
        }

        if let imageHash = metadata["imageHash"]?.stringValue {
            patch.imageHash = .set(imageHash)
        }
    }

    private static func updateAnimationURLs(patch: inout MetadataPatch, metadata: [String: JSONValue]) {
        if let animationURLString = metadata["animation_url"]?.stringValue ?? metadata["animationUrl"]?.stringValue ?? metadata["animation"]?.stringValue {
            if let sanitizedURL = sanitizedMediaURL(from: animationURLString) {
                patch.animationURL = .set(sanitizedURL.absoluteString)
                patch.secureAnimationURL = .set(sanitizedURL.absoluteString)
            } else {
                patch.animationURL = .set(nil)
                patch.secureAnimationURL = .set(nil)
                logRejectedMediaURL(animationURLString, field: "animation")
            }
        }
    }

    private static func updateAudioURLs(patch: inout MetadataPatch, metadata: [String: JSONValue]) {
        let audioURLString = metadata["audioUrl"]?.stringValue ??
                           metadata["audioURI"]?.stringValue ??
                           metadata["audio"]?.stringValue ??
                           metadata["losslessAudio"]?.stringValue
        if let audioURLString = audioURLString {
            if let sanitizedURL = sanitizedMediaURL(from: audioURLString) {
                patch.audioURL = .set(sanitizedURL.absoluteString)
            } else {
                patch.audioURL = .set(nil)
                logRejectedMediaURL(audioURLString, field: "audio")
            }
        }
    }

    private static func updateExternalURLs(patch: inout MetadataPatch, metadata: [String: JSONValue]) {
        if let externalURLString = metadata["external_url"]?.stringValue ?? metadata["externalUrl"]?.stringValue ?? metadata["external_link"]?.stringValue {
            patch.externalURL = .set(externalURLString)
        } else if let externals = metadata["external_url"]?.objectValue ?? metadata["externalUrl"]?.objectValue,
                  let externalURLString = externals["url"]?.stringValue {
            patch.externalURL = .set(externalURLString)
        }
    }

    private static func updateModelURLs(patch: inout MetadataPatch, metadata: [String: JSONValue]) {
        let modelURLString = metadata["modelGlb"]?.stringValue ??
                           metadata["vrmUrl"]?.stringValue ??
                           metadata["usdzUrl"]?.stringValue ??
                           metadata["print3DSTL"]?.stringValue
        if let modelURLString = modelURLString {
            patch.modelURL = .set(modelURLString)
        }
    }

    private static func updateMetadataProperties(patch: inout MetadataPatch, metadata: [String: JSONValue]) {
        if let backgroundColor = metadata["background_color"]?.stringValue ?? metadata["backgroundColor"]?.stringValue {
            patch.backgroundColor = .set(backgroundColor)
        }
        if let medium = metadata["medium"]?.stringValue {
            patch.medium = .set(medium)
        }
        if let metadataVersion = metadata["metadataVersion"]?.stringValue {
            patch.metadataVersion = .set(metadataVersion)
        }
        if let symbols = metadata["symbols"]?.stringValue {
            patch.symbols = .set(symbols)
        }
        if let seed = metadata["seed"]?.stringValue {
            patch.seed = .set(seed)
        }
        if let original = metadata["original"]?.stringValue {
            patch.original = .set(original)
        }
        if let agreement = metadata["agreement"]?.stringValue {
            patch.agreement = .set(agreement)
        }
        if let website = metadata["website"]?.stringValue {
            patch.website = .set(website)
        }
        if let payoutAddress = metadata["payoutAddress"]?.stringValue {
            patch.payoutAddress = .set(payoutAddress)
        }
        if let scriptType = metadata["scriptType"]?.stringValue {
            patch.scriptType = .set(scriptType)
        }
        if let engineType = metadata["engineType"]?.stringValue {
            patch.engineType = .set(engineType)
        }
        if let accessArtworkFiles = metadata["accessArtworkFiles"]?.stringValue {
            patch.accessArtworkFiles = .set(accessArtworkFiles)
        }
    }

    private static func updateNumericProperties(patch: inout MetadataPatch, metadata: [String: JSONValue]) {
        if let sellerFeeBasisPoints = metadata["sellerFeeBasisPoints"]?.intValue {
            patch.sellerFeeBasisPoints = .set(sellerFeeBasisPoints)
        }
        if let minted = metadata["minted"]?.intValue {
            patch.minted = .set(minted)
        }
        if let isStatic = metadata["isStatic"]?.intValue {
            patch.isStatic = .set(isStatic)
        }
        if let aspectRatio = metadata["aspectRatio"]?.doubleValue {
            patch.aspectRatio = .set(aspectRatio)
        }
    }

    private static func updateTraitsAndAttributes(patch: inout MetadataPatch, metadata: [String: JSONValue]) {
        if let attributesArray = metadata["attributes"]?.arrayValue { // as? [[String: Any]]
            patch.attributes = .set(attributesArray.compactMap {
                guard let attribute = $0.objectValue else {
                    return nil
                }

                guard let value = attribute["value"]?.stringifiedValue else {
                    return nil
                }

                return ParsedAttribute(
                    value: value,
                    traitType: attribute["type"]?.stringValue ?? attribute["trait_type"]?.stringValue
                )
            })
        } else if let traitsArray = metadata["traits"]?.arrayValue {
            patch.attributes = .set(traitsArray.compactMap {
                guard let traitDict = $0.objectValue else {
                    return nil
                }

                guard let value = traitDict["value"]?.stringifiedValue else {
                    return nil
                }
                return ParsedAttribute(
                    value: value,
                    traitType: traitDict["type"]?.stringValue ?? traitDict["trait_type"]?.stringValue
                )
            })
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

    private static func apply<Value>(_ update: MetadataUpdate<Value>, to value: inout Value) {
        switch update {
        case .unchanged:
            break
        case .set(let newValue):
            value = newValue
        }
    }

    private static func apply<Value>(_ update: MetadataUpdate<Value>, to value: inout Value?) {
        switch update {
        case .unchanged:
            break
        case .set(let newValue):
            value = newValue
        }
    }

    private static func applyImagePatch(_ patch: MetadataPatch, to nft: NFT) {
        let hasImageChange = switch (patch.imageOriginalURL, patch.imageSecureURL) {
        case (.unchanged, .unchanged):
            false
        default:
            true
        }

        guard hasImageChange else {
            return
        }

        if nft.image == nil {
            nft.image = NFT.Image()
        }

        guard let image = nft.image else {
            return
        }

        apply(patch.imageOriginalURL, to: &image.originalUrl)
        apply(patch.imageSecureURL, to: &image.secureUrl)
        nft.image = image
    }

    private static func applyAttributesPatch(_ update: MetadataUpdate<[ParsedAttribute]>, to nft: NFT) {
        switch update {
        case .unchanged:
            break
        case .set(let attributes):
            nft.attributes = attributes.map {
                NFT.Attribute(value: $0.value, traitType: $0.traitType)
            }
        }
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
