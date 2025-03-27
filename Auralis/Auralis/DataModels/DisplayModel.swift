//
//  DisplayModel.swift
//  Auralis
//
//  Created by Daniel Bell on 3/22/25.
//


//
// Updated DisplayModel structure with all computed properties
//

import Foundation


struct NFTDisplayModel: Identifiable {
    enum ImageSource: Hashable {
        case url(URL)
        case data(Data)
        case svg(String)
    }
    
    struct Animation: Identifiable {
        enum SourceType {
            case ipfs
            case website
            case url
            case artBlocks
        }
        var id = UUID()
        
        let details: [String: Any]?
        let animations: [URL]?
        let source: SourceType
    }
    
    //TODO: update to value based
    let id: UUID = UUID()  // Unique identifier for SwiftUI List
    var identifier: String? {
        if let id = uniqueID {
            return id
        } else if let tokenRank = tokenID ?? tokenId {
            return "\(tokenRank)"
        } else {
            return nil
        }
    }

    // Basic Information
    var name: String {
        data[.name] as? String ?? "Unknown Name"
    }
    
    var arworkName: String? {
        data[.artworkName] as? String
    }
    
    var collectionName: String? {
        data[.collectionName] as? String
    }
    
    var description: String? {
        data[.description] as? String
    }
    
    //MARK: Creator/Artist Information:
    var createdBy: String? {
        data[.createdBy] as? String
    }
    
    var artistWebsite: String? {
        data[.artistWebsite] as? String
    }
    
    var artist: String? {
        data[.artist] as? String
    }
    
    var creator: String? {
        data[.creator] as? String
    }
    
    var artistRoyalty: [String: Any]? {
        data[.artistRoyalty] as? [String: Any]
    }
    
    //MARK: Collection/Project Information:
    var collectionID: String? {
        data[.collectionID] as? String
    }
    
    var projectID: String? {
        data[.projectID] as? String
    }
    
    var series: String? {
        data[.series] as? String
    }
    
    var seriesID: String? {
        data[.seriesID] as? String
    }
    
    //MARK: Identifiers
    var uniqueID: String? {
        data[.id] as? String
    }
    
    var tokenID: Int? {
        data[.tokenID] as? Int
    }
    
    var tokenId: Int? {
        data[.tokenId] as? Int
    }
    
//    var artworkIndex: String? {
//        data[.artworkIndex] as? String
    //[String: Any]
    //Int
//    }
    
    var timestamp: String? {
        data[.timestamp] as? String
    }
    
    var tokenHash: String? {
        data[.tokenHash] as? String
    }
    
    //MARK: Media
    var primaryAssetURL: ImageSource? {
        if let imageDataURLString = data[.primaryAssetUrl] as? String {
            return imageSourceFrom(imageURLString: imageDataURLString)
        } else {
            return nil
        }
    }
    
    var previewAssetURL: ImageSource? {
        if let imageDataURLString = data[.previewAssetUrl] as? String {
            return imageSourceFrom(imageURLString: imageDataURLString)
        } else {
            return nil
        }
    }
    
    //MARK: Image
    var image: ImageSource? {
        let imageURLString = data[.image] as? String
        return imageSourceFrom(imageURLString: imageURLString)
    }
    
    var imageData: ImageSource? {
        if let imageDataURLString = data[.imageData] as? String {
            return imageSourceFrom(imageURLString: imageDataURLString)
        } else {
            return nil
        }
    }
    
    var imageURL: ImageSource? {
        guard let imageDataURL = data[.imageUrl] else {
            return nil
        }
        
        if let imageDataURLString = imageDataURL as? String {
            return imageSourceFrom(imageURLString: imageDataURLString)
        } else {
            let imageDataDictionary = imageDataURL as? [String: Any]
            print(imageDataDictionary)
            return nil
        }
    }
    
    var imageHR: ImageSource? {
        guard let imageDataURL = data[.imageHrUrl] else {
            return nil
        }
        
        if let imageDataURLString = imageDataURL as? String {
            return imageSourceFrom(imageURLString: imageDataURLString)
        } else {
            let imageDataDictionary = imageDataURL as? [String: Any]
            print(imageDataDictionary)
            return nil
        }
    }
    
    var imageHash: String? {
        data[.imageHash] as? String
    }
    
    var imageDetails: [String: Any]? {
        data[.imageDetails] as? [String: Any]
    }
    
    //MARK: Animation
    private var animationURL: URL? {
        if let animationURLString = data[.animationUrl] as? String {
            let parsedString = animationURLString.replacingOccurrences(of: "\n", with: "")
            return animationSourceFrom(imageURLString: parsedString)
        } else {
            return nil
        }
    }
    
    private var animation: URL? {
        if let imageDataURLString = data[.animation] as? String {
            return animationSourceFrom(imageURLString: imageDataURLString)
        } else {
            return nil
        }
    }
    
    private var animationDetails: [String: Any]? {
        data[.animationDetails] as? [String: Any]
    }
    
    var animationData: Animation? {
        let animationMetaData = [animation, animationURL].compactMap { $0 }
        let animations: [URL] = Array(Set(animationMetaData))
        if animations.isEmpty {
            return nil
        }
        
        let urls = [data[.animation] as? String, data[.animationUrl] as? String]
            .compactMap { $0 }
        
        let isIPFS = urls
            .reduce(into: false) { result, urlString in
                result = result || urlString.hasPrefix("ipfs://")
            }
        
        let isWebsite = urls
            .reduce(into: false) { result, urlString in
                result = result || isStringProbablyWebsiteRegex(urlString: urlString) || urlString.lowercased().contains("generator.artblocks.io")
            }
        
        var source: Animation.SourceType
        if isIPFS {
            source = .ipfs
        } else if isWebsite {
            source = .website
        } else {
            source = .url
        }
        
        return Animation(details: animationDetails, animations: animations, source: source)
    }
    
    //MARK: 3D Models
    public var threeDModel: String? {
        data[.usdzUrl] as? String
    }
    
    var modelGlb: String? {
        data[.modelGlb] as? String
    }
    
    var vrmUrl: String? {
        data[.vrmUrl] as? String
    }
    
    var print3DSTL: String? {
        data[.print3DSTL] as? String
    }

    var audioUrl: String? {
        data[.audioUrl] as? String
    }

    var audioURI: String? {
        data[.audioURI] as? String
    }
    var losslessAudio: String? {
        data[.losslessAudio] as? String
    }
    var audio: String? {
        data[.audio] as? String
    }

    //MARK: Additional Metadata
    var platform: [String: Any]? {
        data[.platform] as? [String: Any]//String
    }
    
    var externalUrl: [String: Any]? {
        data[.externalUrl] as? [String: Any]//String
    }
    
    var copyright: [String: Any]? {
        data[.copyright] as? [String: Any]//String
    }
    
    var license: [String: Any]? {
        data[.license] as? [String: Any]//String
    }
    
    var generatorUrl: [String: Any]? {
        data[.generatorUrl] as? [String: Any]//String
    }
    
    var termsOfService: [String: Any]? {
        data[.termsOfService] as? [String: Any]//String
    }
    
    var feeRecipient: [String: Any]? {
        data[.feeRecipient] as? [String: Any]//String
    }
    
    var backgroundColor: String? {
        data[.backgroundColor] as? String
    }
    
    var medium: String? {
        data[.medium] as? String
    }
    
    var royalties: [String: Any]? {
        data[.royalties] as? [String: Any]//String
    }
    
    var accessArtworkFiles: String? {
        data[.accessArtworkFiles] as? String
    }
    
    var metadataVersion: String? {
        data[.metadataVersion] as? String
    }
    
    var symbols: String? {
        data[.symbols] as? String
    }
    
    var seed: String? {
        data[.seed] as? String
    }
    
    var original: String? {
        data[.original] as? String
    }
    
    var agreement: String? {
        data[.agreement] as? String
    }
    
    var website: String? {
        data[.website] as? String
    }
    
    var payoutAddress: String? {
        data[.payoutAddress] as? String
    }
    
    var scriptType: String? {
        data[.scriptType] as? String
    }
    
    var engineType: String? {
        data[.engineType] as? String
    }
    
    //MARK: Numeric Properties
    var sellerFeeBasisPoints: Int? {
        data[.sellerFeeBasisPoints] as? Int
    }
    
    var minted: Int? {
        data[.minted] as? Int
    }
    
    var isStatic: Int? {
        data[.isStatic] as? Int
    }
    
    var aspectRatio: Double? {
        data[.aspectRatio] as? Double
    }
    
    //MARK: Complex Data Structures
    var properties: [String: Any]? {
        data[.properties] as? [String: Any]
    }
    
    var exhibitionInfo: [String: Any]? {
        data[.exhibitionInfo] as? [String: Any]
    }
    
    var royaltyInfo: [String: Any]? {
        data[.royaltyInfo] as? [String: Any]
    }
    
    var features: [String: Any]? {
        data[.features] as? [String: Any]
    }
    
    var traits: [[String: String]]? {
        data[.traits] as? [[String: String]]
    }
    
    var attributes: [WalletNFTResponse.NFT.Attribute] {
        var attributes: [WalletNFTResponse.NFT.Attribute] = []
        if let attributeArray = data[.attributes] as? [[String: Any]] {
            attributes = attributeArray.compactMap { dict in
                if let traitType = dict["trait_type"] as? String, let value = dict["value"] as? String {
                    return WalletNFTResponse.NFT.Attribute(traitType: traitType, value: value)
                }
                return nil
            }
        }
        return attributes
    }
    
    init(data: [String: Any]) {
        self.data = data
    }
    
    private var data: [String: Any]
    
    func isStringProbablyWebsiteRegex(urlString: String) -> Bool {
        do {
            let regex = try NSRegularExpression(pattern: "\\.html(?=[^a-zA-Z]|$)", options: .caseInsensitive)
            let range = NSRange(location: 0, length: urlString.utf16.count)
            if regex.firstMatch(in: urlString, options: [], range: range) != nil {
                return true
            } else {
                return false
            }
        } catch {
            print("Regex error: \(error)")
            return false // In case of regex error, default to false
        }
    }
    
    // Helpers for image processing
    private func imageSourceFrom(imageURLString: String?) -> ImageSource? {
        // Implementation remains the same
        var imageURL = URL(string: imageURLString ?? "")
        var imageData: Data?
        var imageSVG: String?
        if imageURL?.isIPFS ?? false {
            if let host = imageURL?.ipfsHTML {
                imageURL = host
            } else {
                print(imageURL)
            }
        } else if imageURL?.scheme != "https" && imageURL?.scheme != "http" {
            if imageURL?.scheme == nil, let hash = imageURL?.path {
                imageURL = URL(string: "https://ipfs.io/ipfs/\(hash)/")
            } else if imageURL?.scheme == "data" {
                if let base64Data = imageURLString?.extractSVGData() {
                    imageSVG = base64Data
                } else {
                    fatalError("Invalid data URL")
                }
                imageURL = nil
            }
            else if let imageURL {
                print(imageURL)
            }
        } else {
            if imageURL?.scheme == "http" {
                if let url = imageURL, var components = URLComponents(url: url, resolvingAgainstBaseURL: false) {
                    if components.scheme?.lowercased() == "http" {
                        components.scheme = "https"
                    }
                    
                    // Return the modified URL or fall back to the original URL
                    imageURL = components.url ?? url
                } else {
                    print(imageURL)
                }
                
            }
            if let imageURL, imageURL.host == nil {
                print(imageURL)
            }
        }
        
        var imageSource: NFTDisplayModel.ImageSource?
        if let url = imageURL {
            imageSource = .url(url)
        } else if let imageData {
            imageSource = .data(imageData)
        } else if let imageSVG {
            imageSource = .svg(imageSVG)
        }
        return imageSource
    }
    
    private func animationSourceFrom(imageURLString: String?) -> URL? {
        // Implementation remains the same
        var imageURL = URL(string: imageURLString ?? "")
        
        if imageURL?.isIPFS ?? false {
            if let host = imageURL?.ipfsHTML {
                imageURL = host
            } else {
                print(imageURL)
            }
        } else if imageURL?.scheme != "https" && imageURL?.scheme != "http" {
            if imageURL?.scheme == nil, let hash = imageURL?.path {
                imageURL = URL(string: "https://ipfs.io/ipfs/\(hash)/")
            } else if imageURL?.scheme == "data" {
                imageURL = nil
            }
            else if let imageURL {
                print(imageURL)
            }
        } else {
            if imageURL?.scheme == "http" {
                if let url = imageURL, var components = URLComponents(url: url, resolvingAgainstBaseURL: false) {
                    if components.scheme?.lowercased() == "http" {
                        components.scheme = "https"
                    }
                    
                    // Return the modified URL or fall back to the original URL
                    imageURL = components.url ?? url
                } else {
                    print(imageURL)
                }
                
            }
            if let imageURL, imageURL.host == nil {
                print(imageURL)
            }
        }
        
        return imageURL
    }
}

extension NFTDisplayModel {
    var unusedAttributes: [String: Any] {
        var jsonObject = data
        let stringKeys = [
            "audioURI",
            "audio",
            "losslessAudio",
            .name,
            .audioUrl,
            .description,
            .image,
            .animationUrl,
            .imageData,
            .createdBy,
            .collectionName,
            .platform,
            .externalUrl,
            .copyright,
            .imageUrl,
            .imageHrUrl,
            .license,
            .generatorUrl,
            .termsOfService,
            .feeRecipient,
            .artistWebsite,
            .backgroundColor,
            .imageHash,
            .animation,
            .medium,
            .creator,
            .artworkName,
            .seriesID,
            .artist,
            .royalties,
            .timestamp,
            "access_artwork_files",
            "metadata_version",
            "symbols",
            "id",
            "tokenID",
            "vrm_url",
            .collectionID,
            "seed",
            "original",
            "print3D_STL",
            "agreement",
            .usdzUrl,
            "model_glb",
            "token_hash",
            "website",
            .primaryAssetUrl,
            .projectID,
            .series,
            "payout_address",
            "script_type",
            .previewAssetUrl,
            "engine_type",
        ]

        stringKeys.forEach { stringKey in
            if jsonObject[stringKey] as? String != nil {
                jsonObject.removeValue(forKey: stringKey)
            }
        }

        [
            "tokenID",
             "artwork_index",
             "seller_fee_basis_points",
             "minted",
             "is_static",
             "aspect_ratio",
             "tokenId",
        ]
            .forEach { key in
            if jsonObject[key] as? Int != nil {
                jsonObject.removeValue(forKey: key)
            }
        }

        if jsonObject[.attributes] as? [[String: Any]] != nil {
            jsonObject.removeValue(forKey: .attributes)
        }

        let dictionaryKeys =
        [
        .createdBy,
        "collection_name",
        "platform",
        "external_url",
        "copyright",
        .imageUrl,
        .imageHrUrl,
        "license",
        .imageDetails,
        "generator_url",
        "terms_of_service",
        "seller_fee_basis_points",
        "fee_recipient",
        .animationDetails,
        .attributes,
        .artistWebsite,
        .artistRoyalty,
        "properties",
        "artwork_index",
         "exhibition_info",
        "royaltyInfo",
        "features",
        "royalties",
        ]

        dictionaryKeys.forEach { key in
            if jsonObject[key] as? [String: Any] != nil {
                jsonObject.removeValue(forKey: key)
            }
        }


        [String.traits].forEach { key in
            if jsonObject[key] as? [[String:String]] != nil {
                jsonObject.removeValue(forKey: key)
            }
        }

        [String.aspectRatio].forEach { key in
            if jsonObject[key] as? Double != nil {
                jsonObject.removeValue(forKey: key)
            }
        }
        return jsonObject
    }
}
