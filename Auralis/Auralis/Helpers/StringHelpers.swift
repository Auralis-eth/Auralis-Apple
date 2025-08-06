//
//  String.swift
//  Auralis
//
//  Created by Daniel Bell on 3/13/25.
//

import Foundation

enum NFTImageSource: Hashable {
    case url(URL)
    case data(Data)
    case svg(String)
}

extension NFTImageSource: Equatable {
    static func == (lhs: NFTImageSource, rhs: NFTImageSource) -> Bool {
        switch (lhs, rhs) {
        case let (.url(l), .url(r)): return l == r
        case let (.data(l), .data(r)): return l == r
        case let (.svg(l), .svg(r)): return l == r
        default: return false
        }
    }
}

extension Optional where Wrapped == String {
    var imageSource: NFTImageSource? {
        // Implementation remains the same
        var imageURL = URL(string: self ?? "")
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
                if let base64Data = self?.extractSVGData() {
                    imageSVG = base64Data
                } else {
                    return nil
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
                return nil
            }
        }

        var imageSource: NFTImageSource?
        if let url = imageURL {
            imageSource = .url(url)
        } else if let imageData {
            imageSource = .data(imageData)
        } else if let imageSVG {
            imageSource = .svg(imageSVG)
        }
        return imageSource
    }
}

extension Set where Element == String {
    func siftTokenURIs() -> Set<String> {
        // Map canonical resource identifiers to their best URI representation
        var bestURIs: [String: (uri: String, priority: URIFormat)] = [:]
        var otherURIs = Set<String>()

        for uri in self where !uri.isEmpty {

            // Try to find a matching configuration
            var foundMatch = false

            for config in URIConfig.uriConfigurations {
                if uri.hasPrefix(config.prefix) {
                    guard uri.count > config.prefix.count else {
                        otherURIs.insert(uri)
                        continue
                    }

                    let startIndex = uri.index(uri.startIndex, offsetBy: config.prefix.count)
                    let remainder = String(uri[startIndex...])
                    let components = remainder.split(separator: "/", maxSplits: 1)

                    if components.count >= 1, !components[0].isEmpty {
                        let hash = String(components[0])
                        let path = components.count > 1 ? String(components[1]) : ""
                        let resource = NormalizedResource(type: config.type, identifier: hash, path: path)
                        let canonical = resource.canonicalForm

                        if let existing = bestURIs[canonical] {
                            // Keep the higher priority URI format
                            if config.format > existing.priority {
                                bestURIs[canonical] = (uri, config.format)
                            }
                        } else {
                            // First time seeing this resource
                            bestURIs[canonical] = (uri, config.format)
                        }

                        foundMatch = true
                        break
                    }
                }
            }

            if !foundMatch {
                // Not a recognized URI format, keep it as is
                otherURIs.insert(uri)
            }
        }

        // Collect the final results
        var result = Set<String>()

        // Add all the best format URIs
        for (_, uriInfo) in bestURIs {
            result.insert(uriInfo.uri)
        }

        // Add all other URIs
        result.formUnion(otherURIs)

        return result
    }
}


// Define priority for URI formats (higher = better)
enum URIFormat: Int {
    case other = 0
    case content = 1
    case location = 2
    case optimizedLocation = 3

}

extension URIFormat: Comparable {
    static func < (lhs: URIFormat, rhs: URIFormat) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

struct NormalizedResource {
    enum ResourceType: String {
        case arweave
        case ipfs
        case other
    }

    let type: ResourceType
    let identifier: String
    let path: String

    // Create a canonical representation for deduplication
    var canonicalForm: String {
        "\(type.rawValue):\(identifier):\(path)"
    }
}

struct URIConfig {
    let prefix: String
    let type: NormalizedResource.ResourceType
    let format: URIFormat
    // Define all URI configurations
    static let uriConfigurations: [URIConfig] = [
        URIConfig(prefix: "ar://", type: .arweave, format: .content),
        URIConfig(prefix: "https://arweave.net/", type: .arweave, format: .location),
        URIConfig(prefix: "ipfs://", type: .ipfs, format: .content),
        URIConfig(prefix: "https://ipfs.io/ipfs/", type: .ipfs, format: .location),
        URIConfig(prefix: "https://alchemy.mypinata.cloud/ipfs/", type: .ipfs, format: .optimizedLocation)
    ]

}



extension String {
    static var audioUrl: String {
        "audio_url"
    }
    static var id: String {
        "id"
    }

    static var tokenID: String {
        "tokenID"
    }

    static var tokenId: String {
        "tokenId"
    }

    static var artworkIndex: String {
        "artwork_index"
    }

    static var timestamp: String {
        "timestamp"
    }
    static var platform: String {
        "platform"
    }

    static var externalUrl: String {
        "external_url"
    }

    static var copyright: String {
        "copyright"
    }

    static var license: String {
        "license"
    }

    static var generatorUrl: String {
        "generator_url"
    }

    static var termsOfService: String {
        "terms_of_service"
    }

    static var feeRecipient: String {
        "fee_recipient"
    }

    static var backgroundColor: String {
        "background_color"
    }

    static var medium: String {
        "medium"
    }

    static var royalties: String {
        "royalties"
    }

    static var accessArtworkFiles: String {
        "access_artwork_files"
    }

    static var metadataVersion: String {
        "metadata_version"
    }

    static var symbols: String {
        "symbols"
    }

    static var vrmUrl: String {
        "vrm_url"
    }

    static var seed: String {
        "seed"
    }

    static var original: String {
        "original"
    }

    static var print3DSTL: String {
        "print3D_STL"
    }

    static var agreement: String {
        "agreement"
    }

    static var modelGlb: String {
        "model_glb"
    }

    static var tokenHash: String {
        "token_hash"
    }

    static var website: String {
        "website"
    }

    static var payoutAddress: String {
        "payout_address"
    }

    static var scriptType: String {
        "script_type"
    }

    static var engineType: String {
        "engine_type"
    }

    static var sellerFeeBasisPoints: String {
        "seller_fee_basis_points"
    }

    static var minted: String {
        "minted"
    }

    static var isStatic: String {
        "is_static"
    }

    static var aspectRatio: String {
        "aspect_ratio"
    }

    static var properties: String {
        "properties"
    }

    static var exhibitionInfo: String {
        "exhibition_info"
    }

    static var royaltyInfo: String {
        "royaltyInfo"
    }

    static var features: String {
        "features"
    }

    static var traits: String {
        "traits"
    }
    static var createdBy: String {
        "created_by"
    }

    static var artist: String {
        "artist"
    }

    static var creator: String {
        "creator"
    }

    static var artistWebsite: String {
        "artist_website"
    }

    static var artistRoyalty: String {
        "artistRoyaltyInfo"
    }

    static var collectionID: String {
        "collectionId"
    }

    static var projectID: String {
        "project_id"
    }

    static var series: String {
        "series"
    }

    static var seriesID: String {
        "series_id"
    }

    static var name: String {
        "name"
    }
    static var image: String {
        "image"
    }
    static var attributes: String {
        "attributes"
    }

    static var description: String {
        "description"
    }
    static var imageData: String {
        "image_data"
    }
    static var animationUrl: String {
        "animation_url"
    }

    static var artworkName: String {
        "artwork_name"
    }
    static var collectionName: String {
        "collection_name"
    }
    static var imageUrl: String {
        "image_url"
    }
    static var imageHrUrl: String {
        "image_hr"
    }
    static var primaryAssetUrl: String {
        "primary_asset_url"
    }
    static var previewAssetUrl: String {
        "preview_asset_url"
    }
    static var animation: String {
        "animation"
    }
    static var imageHash: String {
        "image_hash"
    }
    static var imageDetails: String {
        "image_details"
    }
    static var animationDetails: String {
        "animation_details"
    }

    static var usdzUrl: String {
        "model_usdz"
    }

    static var audioURI: String {
        "audioURI"
    }
    static var losslessAudio: String {
        "losslessAudio"
    }
    static var audio: String {
        "audio"
    }
}

