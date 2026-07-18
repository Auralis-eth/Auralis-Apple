//
//  AlchemyNFTResponse.swift
//  Auralis
//
//  Created by Daniel Bell on 3/29/25.
//

import AuralisPrimaryModels
import Foundation

public struct AlchemyNFTResponse: Codable, Sendable {
    public let ownedNfts: [OwnedNFT]
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
        ownedNfts: [OwnedNFT],
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
        ownedNfts = try container.decodeIfPresent(LossyDecodableArray<OwnedNFT>.self, forKey: .ownedNfts)?.elements ?? []
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

    public struct OwnedNFT: Codable, Sendable {
        public struct Contract: Codable, Sendable {
            public var address: String?
            public var chain: Chain?

            public init(address: String?, chain: Chain? = nil) {
                self.address = address
                self.chain = chain
            }
        }

        public struct Image: Codable, Sendable {
            public var originalURL: String?
            public var thumbnailURL: String?
            public var secureURL: String?

            private enum CodingKeys: String, CodingKey {
                case originalURL = "originalUrl"
                case thumbnailURL = "thumbnailUrl"
                case secureURL = "secureUrl"
            }

            public init(originalURL: String?, thumbnailURL: String?, secureURL: String?) {
                self.originalURL = originalURL
                self.thumbnailURL = thumbnailURL
                self.secureURL = secureURL
            }
        }

        public struct Raw: Codable, Sendable {
            public var tokenURI: String?
            public var metadata: [String: JSONValue]?
            public var error: String?

            private enum CodingKeys: String, CodingKey {
                case tokenURI = "tokenUri"
                case metadata
                case error
            }

            public init(tokenURI: String?, metadata: [String: JSONValue]?, error: String?) {
                self.tokenURI = tokenURI
                self.metadata = metadata
                self.error = error
            }
        }

        public struct Collection: Codable, Sendable {
            public var name: String?
            public var chain: Chain?
            public var contractAddress: String?

            public init(name: String?, chain: Chain? = nil, contractAddress: String?) {
                self.name = name
                self.chain = chain
                self.contractAddress = contractAddress
            }
        }

        public struct AcquiredAt: Codable, Sendable {
            public var blockTimestamp: String?

            public init(blockTimestamp: String?) {
                self.blockTimestamp = blockTimestamp
            }
        }

        public var contract: Contract?
        public var tokenId: String
        public var tokenType: String?
        public var name: String?
        public var nftDescription: String?
        public var image: Image?
        public var raw: Raw?
        public var collection: Collection?
        public var tokenURI: String?
        public var timeLastUpdated: String?
        public var acquiredAt: AcquiredAt?

        private enum CodingKeys: String, CodingKey {
            case contract
            case tokenId
            case tokenType
            case name
            case nftDescription = "description"
            case image
            case raw
            case collection
            case tokenURI = "tokenUri"
            case timeLastUpdated
            case acquiredAt
        }

        public init(
            contract: Contract?,
            tokenId: String,
            tokenType: String? = nil,
            name: String? = nil,
            nftDescription: String? = nil,
            image: Image? = nil,
            raw: Raw? = nil,
            collection: Collection? = nil,
            tokenURI: String? = nil,
            timeLastUpdated: String? = nil,
            acquiredAt: AcquiredAt? = nil
        ) {
            self.contract = contract
            self.tokenId = tokenId
            self.tokenType = tokenType
            self.name = name
            self.nftDescription = nftDescription
            self.image = image
            self.raw = raw
            self.collection = collection
            self.tokenURI = tokenURI
            self.timeLastUpdated = timeLastUpdated
            self.acquiredAt = acquiredAt
        }
    }

    public struct BlockInfo: Codable, Sendable {
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
