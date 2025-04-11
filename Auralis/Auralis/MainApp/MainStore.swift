//
//  MainStore.swift
//  Auralis
//
//  Created by Daniel Bell on 3/23/25.
//

import SwiftUI
import SwiftData

@Observable class MainStore {
    var chain: String = "eth-mainnet"
    var chainId: Int = 1

    //var musicNFTs: [NFT] = [] {
//        nftMetaData.filter {
//            guard let metaData = $0.metadata else {
//                return false
//            }
//
//            return metaData.audioUrl != nil || ($0.nftBaseData.tokenUri?.hasSuffix(".mp3") ?? false) || ($0.nftBaseData.tokenUri?.hasSuffix(".wav") ?? false) || metaData.audioURI != nil || metaData.losslessAudio != nil || metaData.audio != nil
//        }
//    }

    var accountAddress: String? = nil
    var isConnected: Bool = false
    var account: String = "0x5b93ff82faaf241c15997ea3975419dddd8362c5"

    init() {}
}





