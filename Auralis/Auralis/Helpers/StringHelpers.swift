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

extension String {
    func extractSVGData() -> String? {
        do {
            // Regex for UTF-8, charset, and direct SVG
            let directRegex = try NSRegularExpression(pattern: "data:image/svg\\+xml(;charset=utf-8|;utf8)?,(<svg.*)", options: .caseInsensitive)
            let directMatches = directRegex.matches(in: self, range: NSRange(self.startIndex..., in: self))
            if let match = directMatches.first {
                let svgRange = match.range(at: match.numberOfRanges - 1)
                if svgRange.location != NSNotFound, let range = Range(svgRange, in: self) {
                    let svg = String(self[range])
                    // URL-decode if needed
                    return svg.removingPercentEncoding ?? svg
                }
            }

            // Regex for Base64
            let base64Regex = try NSRegularExpression(pattern: "data:image/svg\\+xml;base64,(.+)", options: .caseInsensitive)
            let base64Matches = base64Regex.matches(in: self, range: NSRange(self.startIndex..., in: self))
            if let match = base64Matches.first, match.numberOfRanges == 2 {
                let dataRange = match.range(at: 1)
                if dataRange.location != NSNotFound, let range = Range(dataRange, in: self) {
                    let base64 = String(self[range])
                    if let data = Data(base64Encoded: base64), let svg = String(data: data, encoding: .utf8) {
                        return svg
                    }
                }
            }
        } catch {
            print("Regex error: \(error)")
        }
        return nil
    }
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

