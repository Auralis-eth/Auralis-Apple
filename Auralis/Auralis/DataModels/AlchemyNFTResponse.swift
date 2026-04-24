//
//  AlchemyNFTResponse.swift
//  Auralis
//
//  Created by Daniel Bell on 3/29/25.
//

import Foundation

struct AlchemyNFTResponse: Codable {
    let ownedNfts: [NFT]
    let totalCount: Int?
    let pageKey: String?
    let validAt: BlockInfo?

    enum CodingKeys: String, CodingKey {
        case ownedNfts
        case totalCount
        case pageKey
        case validAt
    }

    init(
        ownedNfts: [NFT],
        totalCount: Int?,
        pageKey: String?,
        validAt: BlockInfo?
    ) {
        self.ownedNfts = ownedNfts
        self.totalCount = totalCount
        self.pageKey = pageKey
        self.validAt = validAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        ownedNfts = try container.decodeIfPresent(LossyDecodableArray<NFT>.self, forKey: .ownedNfts)?.elements ?? []
        totalCount = try container.decodeIfPresent(Int.self, forKey: .totalCount)
        pageKey = try container.decodeIfPresent(String.self, forKey: .pageKey)
        validAt = try container.decodeIfPresent(BlockInfo.self, forKey: .validAt)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(ownedNfts, forKey: .ownedNfts)
        try container.encodeIfPresent(totalCount, forKey: .totalCount)
        try container.encodeIfPresent(pageKey, forKey: .pageKey)
        try container.encodeIfPresent(validAt, forKey: .validAt)
    }

    struct BlockInfo: Codable {
        let blockNumber: Int
        let blockHash: String
        let blockTimestamp: String
    }
}
