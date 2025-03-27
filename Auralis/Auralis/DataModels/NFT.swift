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
        let normalizedMetadata: NormalizedMetadata?
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

        enum CodingKeys: String, CodingKey {
            case tokenAddress = "token_address"
            case tokenId = "token_id"
            case contractType = "contract_type"
            case ownerOf = "owner_of"
            case blockNumber = "block_number"
            case blockNumberMinted = "block_number_minted"
            case tokenUri = "token_uri"
            case metadata
            case normalizedMetadata = "normalized_metadata"
            case media
            case amount
            case name
            case symbol
            case tokenHash = "token_hash"
            case rarityRank = "rarity_rank"
            case rarityLabel = "rarity_label"
            case rarityPercentage = "rarity_percentage"
            case lastTokenUriSync = "last_token_uri_sync"
            case lastMetadataSync = "last_metadata_sync"
            case possibleSpam = "possible_spam"
            case verifiedCollection = "verified_collection"
        }

        struct Attribute: Identifiable {
            var id: String {
                traitType + value
            }
            let traitType: String
            let value: String
        }
        var parseMetadata: NFTDisplayModel? {
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

                let nftDisplayModel = NFTDisplayModel(data: jsonObject)
                #if DEBUG
                testKeys(json: nftDisplayModel.unusedAttributes)
                #endif
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


//            if !jsonObject.keys.isEmpty {
//                print("===============================")
//                print(jsonObject.keys)
//                print("===============================")
//            }
        }
    }
}




// MARK: - NormalizedMetadata
struct NormalizedMetadata: Codable {
    let normalizedMetadataAttribute: NormalizedMetadataAttribute?
    let normalizedMetadata: NormalizedMetadataClass?
}

// MARK: - NormalizedMetadataClass
struct NormalizedMetadataClass: Codable {
    let properties: NormalizedMetadataProperties
}

// MARK: - NormalizedMetadataProperties
struct NormalizedMetadataProperties: Codable {
    let name, description, image, externalLink: AnimationURL
    let animationURL: AnimationURL
    let attributes: Attributes

    enum CodingKeys: String, CodingKey {
        case name, description, image
        case externalLink = "external_link"
        case animationURL = "animation_url"
        case attributes
    }
}

// MARK: - AnimationURL
struct AnimationURL: Codable {
    let type, description: String
    let example: String
}

// MARK: - Attributes
struct Attributes: Codable {
    let type: String
    let items: Items
}

// MARK: - Items
struct Items: Codable {
    let ref: String

    enum CodingKeys: String, CodingKey {
        case ref = "$ref"
    }
}

// MARK: - NormalizedMetadataAttribute
struct NormalizedMetadataAttribute: Codable {
    let properties: NormalizedMetadataAttributeProperties
}

// MARK: - NormalizedMetadataAttributeProperties
struct NormalizedMetadataAttributeProperties: Codable {
    let traitType, value, displayType: AnimationURL
    let maxValue, traitCount, order: MaxValue

    enum CodingKeys: String, CodingKey {
        case traitType = "trait_type"
        case value
        case displayType = "display_type"
        case maxValue = "max_value"
        case traitCount = "trait_count"
        case order
    }
}

// MARK: - MaxValue
struct MaxValue: Codable {
    let type, description: String
    let example: Int
}
