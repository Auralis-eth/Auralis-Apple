//
//  AlchemyNFTResponse.swift
//  Auralis
//
//  Created by Daniel Bell on 3/29/25.
//

import Foundation

struct AlchemyNFTResponse: Codable {
    let ownedNfts: [NFT]
    let totalCount: Int
    let pageKey: String?
    let validAt: BlockInfo

    struct BlockInfo: Codable {
        let blockNumber: Int
        let blockHash: String
        let blockTimestamp: String
    }
}
