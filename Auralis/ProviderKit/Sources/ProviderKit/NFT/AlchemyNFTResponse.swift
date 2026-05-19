//
//  AlchemyNFTResponse.swift
//  Auralis
//
//  Created by Daniel Bell on 3/29/25.
//

import AuralisPrimaryModels
import AuralisPrimaryPersistence
import Foundation

public struct AlchemyNFTResponse: Codable {
    public let ownedNfts: [NFT]
    public let totalCount: Int?
    public let pageKey: String?
    public let validAt: BlockInfo?

    public enum CodingKeys: String, CodingKey {
        case ownedNfts
        case totalCount
        case pageKey
        case validAt
    }

    public init(
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

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        ownedNfts = try container.decodeIfPresent(LossyDecodableArray<NFT>.self, forKey: .ownedNfts)?.elements ?? []
        totalCount = try container.decodeIfPresent(Int.self, forKey: .totalCount)
        pageKey = try container.decodeIfPresent(String.self, forKey: .pageKey)
        validAt = try container.decodeIfPresent(BlockInfo.self, forKey: .validAt)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(ownedNfts, forKey: .ownedNfts)
        try container.encodeIfPresent(totalCount, forKey: .totalCount)
        try container.encodeIfPresent(pageKey, forKey: .pageKey)
        try container.encodeIfPresent(validAt, forKey: .validAt)
    }

    public struct BlockInfo: Codable {
        public let blockNumber: Int
        public let blockHash: String
        public let blockTimestamp: String

        public init(blockNumber: Int, blockHash: String, blockTimestamp: String) {
            self.blockNumber = blockNumber
            self.blockHash = blockHash
            self.blockTimestamp = blockTimestamp
        }
    }
}
