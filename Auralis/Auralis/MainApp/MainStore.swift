//
//  MainStore.swift
//  Auralis
//
//  Created by Daniel Bell on 3/23/25.
//

import SwiftUI
import metamask_ios_sdk

struct NFT: Identifiable {
    var id: String {
        nftBaseData.id + (metadata?.identifier ?? "")
    }

    var nftBaseData: WalletNFTResponse.NFT
    var metadata: NFTDisplayModel?
}
//                        Supported networks
//                        Arbitrum
//                        Network    Chain ID
//                        Mainnet    42161
//                        Nova    42170

//                        Base
//                        Network    Chain ID
//                        Mainnet    8453

//                        Ethereum
//                        Network    Chain ID
//                        Mainnet    1
//                        Holesky    17000
//                        Sepolia    11155111

//                        Filecoin
//                        Network    Chain ID
//                        Mainnet    314

//                        Optimism
//                        Network    Chain ID
//                        Mainnet    10

//                        Polygon
//                        Network    Network ID
//                        Mainnet    137
//                        Amoy    80002
//    @State private var chainId: Int = 1
@Observable class MainStore {
    let appMetadata = AppMetadata(
        name: "Auralis.ETH",
        url: "Auralis.eth",//"https://dubdapp.com",
        iconUrl: "https://pbs.twimg.com/profile_images/1846931552753930242/on5jhKP6_400x400.jpg"
    )
    var metamaskSDK: MetaMaskSDK

    var loading: Bool = false
    var error: Error?
    var chain: String = "eth"
    var chainId: Int = 1
    var nftMetaData: [NFT] = []
    var musicNFTs: [NFT] {
        nftMetaData.filter {
            guard let metaData = $0.metadata else {
                return false
            }

            return metaData.audioUrl != nil || ($0.nftBaseData.tokenUri?.hasSuffix(".mp3") ?? false) || ($0.nftBaseData.tokenUri?.hasSuffix(".wav") ?? false) || metaData.audioURI != nil || metaData.losslessAudio != nil || metaData.audio != nil
        }
    }
    var account: String = "0x5b93ff82faaf241c15997ea3975419dddd8362c5"
//    "0x63A65fC3a6E3714e2a210B7fE17A9d743426DA22"//"0x183AbE67478eB7E87c96CA28E2f63Dec53f22E3A"
//
//
//    0xA46128894419058F48089e5C9eB7CF6a8a932A80
    init() {
        metamaskSDK = MetaMaskSDK.shared(
            appMetadata,
            transport: .socket,
            //sdkOptions: SDKOptions(infuraAPIKey: Secrets.apiKey(.infura) ?? "", readonlyRPCMap: ["0x1": "hptts://www.testrpc.com"]) // for read-only RPC calls
            sdkOptions: SDKOptions(infuraAPIKey: Secrets.apiKey(.infura) ?? "") // for read-only RPC calls
            )

        if !account.isEmpty {
            Task {
                await fetchAllNFTs()
            }
        }
    }

    func fetchAllNFTs() async {
        guard !loading else { return }
        guard account.count == 42 else { return }
        guard account.hasPrefix("0x") else { return }
        loading = true
        error = nil

        var nftMetaData: [WalletNFTResponse.NFT]? = nil


        var currentCursor: String? = nil
        var total: Int? = nil
        var seenItems: Int = 0

        repeat {
            do {
                guard let response = try await Moralis().getNFTs(for: account, chain: chain, cursor: currentCursor, normalizeMetadata: true) else {
                    loading = false
                    return
                }
                if let itemsInResponse = Int(response.pageSize ?? "") {
                    seenItems += itemsInResponse
                }
                if let totalString = response.total, !totalString.isEmpty, let intValue = Int(totalString) {
                    total = intValue
                }

                let nftResponse = response.result

                // Append items to the collection
                let contents = nftResponse?.filter({ $0.metadata != nil }) ?? []
                if nftMetaData == nil {
                    nftMetaData = contents
                } else {
                    nftMetaData?.append(contentsOf: contents)
                }

                // Update cursor for next page
                currentCursor = response.cursor
                if let totalItems = total {
                    if seenItems >= totalItems {
                        break
                    }
                }
            } catch {
                self.error = error
            }
        } while currentCursor != nil

        let parsed = nftMetaData?.map {
            NFT(nftBaseData: $0, metadata: $0.parseMetadata)
        }

        self.nftMetaData = parsed ?? []
        loading = false
    }
}







////                .filter {
////                    $0.parseMetadata?.audioUrl != nil
////                    $0.parseMetadata?.identifier != nil
////                    || $0.parseMetadata?.projectID != nil
////                    || $0.parseMetadata?.collectionID != nil
////                    || $0.parseMetadata?.tokenId != nil
////                    || $0.parseMetadata?.tokenID != nil
////                    || $0.parseMetadata?.seriesID != nil
////                    || $0.parseMetadata?.uniqueID != nil
////                    || $0.tokenId != nil
////               }
//
//            (nftMetaData ?? []).forEach { nft in
////                print("============================")
////                guard let metadata = nft.parseMetadata else {
////                    print("no parseMetaData for this nft \(nft)")
////                    return
////                }
//                print("--------------------------------")
//                print(nft.normalizedMetadata)
//                print("````````````````````````````````````````````")
//                print(nft.parseMetadata)
//                print("--------------------------------")
//                //                print("-----------ANIMATION----------------")
//                //            print(metadata.animationData)
//                //
//                //            print("-----------IMAGE-HighRes----------------")
//                //            print(metadata.imageHR)
//                //            print(metadata.primaryAssetURL)
//                //
//                //            print("-----------IMAGE-lowres----------------")
//                //            print(metadata.previewAssetURL)
//                //            print(metadata.imageData)
//                //            print(metadata.image ?? metadata.imageURL)
//            }
