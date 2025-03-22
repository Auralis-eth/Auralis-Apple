//
//  NFT.swift
//  Auralis
//
//  Created by Daniel Bell on 1/6/25.
//

import Foundation

extension WalletNFTResponse {
    struct NFT: Codable, Identifiable {
        var id: String {
            (tokenAddress ?? "") + (tokenHash ?? "") + "\(rarityRank ?? Int.min)" + (blockNumberMinted ?? "") + (metadata ?? "")
        }
        let tokenAddress: String?
        let tokenId: String?
        let contractType: String?
        let ownerOf: String?
        let blockNumber: String?
        let blockNumberMinted: String?
            let tokenUri: String?
            let metadata: String?
        let normalizedMetadata: String?
            let media: String?
        let amount: String
        let name: String?
        let symbol: String?
        let tokenHash: String?
        let rarityRank: Int?
        let rarityLabel: String?
        let rarityPercentage: Double?
        let lastTokenUriSync: String?
        let lastMetadataSync: String?
        let possibleSpam: Bool?
        let verifiedCollection: Bool?
        //image
        //imageData
        //animationURL
        //attributes
        struct DisplayModel: Identifiable {
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

            enum ImageSource: Hashable {
                case url(URL)
                case data(Data)
                case svg(String)
            }

            //TODO: update to value based
            let id: UUID = UUID()  // Unique identifier for SwiftUI List
            var name: String {
                data[.name] as? String ?? "Unknown Name"
            }
            var arworkName: String? {
                data[.artworkName] as? String
            }
            var collectionName: String? {
                data[.collectionName] as? String
            }

            //MARK: Creator/Artist Information:
            var createdBy: String? {
                data[.createdBy] as? String
            }
//            var createdBy: [String: Any]? {
//                data[.createdBy] as? [String: Any]
//            }

            var artistWebsite: String? {
                data[.artistWebsite] as? String
            }
//            var artistWebsite: [String: Any]? {
//                data[.artistWebsite] as? [String: Any]
//            }

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








            var description: String? {
                data[.description] as? String
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

            public var threeDModel: String? {
                data[.usdzUrl] as? String
            }

            var attributes: [Attribute] {
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
            var unusedAttributes: [String: Any] {
                var jsonObject = data
                let stringKeys = [
                    .name,
                    .description,
                    .image,
                    .animationUrl,
                    .imageData,
                    .createdBy,
                    .collectionName,
                    "platform",
                    "external_url",
                    "copyright",
                    .imageUrl,
                    .imageHrUrl,
                    "license",
                    "generator_url",
                    "terms_of_service",
                    "fee_recipient",
                    .artistWebsite,
                    "background_color",
                    .imageHash,
                    .animation,
                    "medium",
                    .creator,
                    .artworkName,
                    .seriesID,
                    .artist,
                    "royalties",
                    "timestamp",
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


                ["traits"].forEach { key in
                    if jsonObject[key] as? [[String:String]] != nil {
                        jsonObject.removeValue(forKey: key)
                    }
                }

                ["aspect_ratio"].forEach { key in
                    if jsonObject[key] as? Double != nil {
                        jsonObject.removeValue(forKey: key)
                    }
                }
                return jsonObject
            }

            private func imageSourceFrom(imageURLString: String?) -> ImageSource? {
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
//                        guard let base64DataCollection = imageURLString?.components(separatedBy: ",") else {
//                            fatalError("Invalid data URL")
//                        }
//                        print(imageURLString ?? "NO IMAGE URL STRING ???????")
//                        guard base64DataCollection.count >= 1 else {
//                            fatalError("Invalid data URL")
//                        }
//                        guard let base64Data = base64DataCollection.last else {
//                            fatalError("Invalid data URL")
//                        }

                        //IF we pass through this we do have an SVG image
                        if let base64Data = imageURLString?.extractSVGData() {
                            imageSVG = base64Data
                        } else {
                            fatalError("Invalid data URL")
                        }
//TODO:
//  1) create a string parser to read these
//data:image/svg+xml,<svg
//data:image/svg+xml;utf8,<svg
//data:image/svg+xml;utf8,<svg
//data:image/svg+xml;utf8,<svg
                        
//data:image/svg+xml;base64,PD94bWwgd
//data:image/svg+xml;base64,PD94bWwgdmVyc2
//data:image/svg+xml;base64,PD94bWwgdmVyc2
//                        imageData = Data(base64Encoded: base64Data, options: .ignoreUnknownCharacters)
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

                var imageSource: WalletNFTResponse.NFT.DisplayModel.ImageSource?
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

        struct Attribute: Identifiable {
            var id: String {
                traitType + value
            }
            let traitType: String
            let value: String
        }
        var parseMetadata: WalletNFTResponse.NFT.DisplayModel? {
            guard metadata != "{}" else {
                return nil
            }
            guard let jsonData = metadata?.data(using: .utf8) else {
                return nil
            }

            do {
                // Parse JSON into a dictionary
                guard let jsonObject = try JSONSerialization.jsonObject(with: jsonData) as? [String: Any] else {
                    return nil
                }

                let nftDisplayModel = WalletNFTResponse.NFT.DisplayModel(data: jsonObject)

//                testKeys(json: nftDisplayModel.unusedAttributes)

                return nftDisplayModel

            } catch {
                print("Error parsing metadata JSON: \(error.localizedDescription)")
            }

            return nil
        }

        private func testKeys(json: [String: Any]) {
            let keys = [
                ""
            ]

            var jsonObject = json

            keys.forEach { key in
                if jsonObject[key] as? String != nil {
                    jsonObject.removeValue(forKey: key)
                    print("=======================================")
                    print("String")
                    print(key)
                    print("=======================================")
                } else if jsonObject[key] as? [String: Any] != nil {
                    jsonObject.removeValue(forKey: key)
                    print("=======================================")
                    print("[String:Any]")
                    print(key)
                    print("=======================================")
                } else if jsonObject[key] as? Int != nil {
                    jsonObject.removeValue(forKey: key)
                    print("=======================================")
                    print("Int")
                    print(key)
                    print("=======================================")
                } else if jsonObject[key] as? Double != nil {
                    jsonObject.removeValue(forKey: key)
                    print("=======================================")
                    print("Double")
                    print(key)
                    print("=======================================")
                } else if jsonObject[key] as? [[String:String]] != nil {
                    jsonObject.removeValue(forKey: key)
                    print("=======================================")
                    print("[[String:String]]")
                    print(key)
                    print("=======================================")
                } else if let object = jsonObject[key] {
                    print(object)
                    print(type(of: object))
                }
            }


            if !jsonObject.keys.isEmpty {
                print("===============================")
                print(jsonObject.keys)
                print("===============================")
            }
        }
    }
}

