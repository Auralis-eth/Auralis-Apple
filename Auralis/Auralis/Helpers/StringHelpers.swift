//
//  String.swift
//  Auralis
//
//  Created by Daniel Bell on 3/13/25.
//

import Foundation

extension String {
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
}

extension String {
    func extractSVGData() -> String? {
        do {
            // Regex for utf8 and //data variants
            let utf8Regex = try NSRegularExpression(pattern: "data:image/svg\\+xml(;utf8)?,(<svg.*)", options: .caseInsensitive)
            let utf8Matches = utf8Regex.matches(in: self, range: NSRange(self.startIndex..., in: self))
            if let match = utf8Matches.first {
                let svgRange = match.range(at: match.numberOfRanges - 1)
                if svgRange.location != NSNotFound, let range = Range(svgRange, in: self){
                    return String(self[range])
                }
            }

            // Regex for base64
            let base64Regex = try NSRegularExpression(pattern: "data:image/svg\\+xml;base64,(.+)", options: .caseInsensitive)
            let base64Matches = base64Regex.matches(in: self, range: NSRange(self.startIndex..., in: self))
            if let match = base64Matches.first, match.numberOfRanges == 2 {
                let dataRange = match.range(at: 1)
                if dataRange.location != NSNotFound, let range = Range(dataRange, in: self){
                    return String(self[range])
                }
            }

        } catch {
            print("Regex error: \(error)")
        }
        return nil
    }
}



