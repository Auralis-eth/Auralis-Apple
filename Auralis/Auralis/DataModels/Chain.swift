//
//  Chain.swift
//  Auralis
//
//  Created by Daniel Bell on 5/9/25.
//

import SwiftData
import web3

enum Chain: String, Codable, Equatable, CaseIterable, Identifiable {
    // Ethereum
    case ethMainnet = "eth-mainnet"
    case ethSepoliaTestnet = "eth-sepolia"

    // Base
    case baseMainnet = "base-mainnet"
    case baseSepoliaTestnet = "base-sepolia"

    // Arbitrum
    case arbMainnet = "arb-mainnet"
    case arbSepoliaTestnet = "arb-sepolia"
    case arbNovaMainnet = "arbnova-mainnet"

    // Optimism
    case optMainnet = "opt-mainnet"
    case optSepoliaTestnet = "opt-sepolia"

    // Polygon
    case polygonMainnet = "polygon-mainnet"
    case polygonAmoyTestnet = "polygon-amoy"

    // WorldChain
    case worldchainMainnet = "worldchain-mainnet"
    case worldchainSepoliaTestnet = "worldchain-sepolia"

    // Shape
    case shapeMainnet = "shape-mainnet"
    case shapeSepoliaTestnet = "shape-sepolia"

    // Ink
    case inkMainnet = "ink-mainnet"
    case inkSepoliaTestnet = "ink-sepolia"

    // UniChain
    case unichainMainnet = "unichain-mainnet"
    case unichainSepoliaTestnet = "unichain-sepolia"

    // Soneium
    case soneiumMainnet = "soneium-mainnet"
    case soneiumMinatoTestnet = "soneium-minato"

    // Solana
    case solanaMainnet = "solana-mainnet"
    case solanaDevnetTestnet = "solana-devnet"

    // BeraChain
    case berachainMainnet = "berachain-mainnet"

    // Zora
    case zoraMainnet = "zora-mainnet"
    case zoraSepoliaTestnet = "zora-sepolia"

    // Polynomial
    case polynomialMainnet = "polynomial-mainnet"
    case polynomialSepoliaTestnet = "polynomial-sepolia"

    var id: Int {
        chainId
    }

    var networkName: String {
        switch self {
        case .ethMainnet:
            return "Ethereum Mainnet"
        case .ethSepoliaTestnet:
            return "Ethereum Sepolia Testnet"
        case .baseMainnet:
            return "Base Mainnet"
        case .baseSepoliaTestnet:
            return "Base Sepolia Testnet"
        case .arbMainnet:
            return "Arbitrum One Mainnet"
        case .arbSepoliaTestnet:
            return "Arbitrum Sepolia Testnet"
        case .arbNovaMainnet:
            return "Arbitrum Nova Mainnet"
        case .optMainnet:
            return "Optimism Mainnet"
        case .optSepoliaTestnet:
            return "Optimism Sepolia Testnet"
        case .polygonMainnet:
            return "Polygon Mainnet"
        case .polygonAmoyTestnet:
            return "Polygon Amoy Testnet"
        case .worldchainMainnet:
            return "WorldChain Mainnet"
        case .worldchainSepoliaTestnet:
            return "WorldChain Sepolia Testnet"
        case .shapeMainnet:
            return "Shape Mainnet"
        case .shapeSepoliaTestnet:
            return "Shape Sepolia Testnet"
        case .inkMainnet:
            return "Ink Mainnet"
        case .inkSepoliaTestnet:
            return "Ink Sepolia Testnet"
        case .unichainMainnet:
            return "UniChain Mainnet"
        case .unichainSepoliaTestnet:
            return "UniChain Sepolia Testnet"
        case .soneiumMainnet:
            return "Soneium Mainnet"
        case .soneiumMinatoTestnet:
            return "Soneium Minato Testnet"
        case .solanaMainnet:
            return "Solana Mainnet"
        case .solanaDevnetTestnet:
            return "Solana Devnet"
        case .berachainMainnet:
            return "BeraChain Mainnet"
        case .zoraMainnet:
            return "Zora Mainnet"
        case .zoraSepoliaTestnet:
            return "Zora Sepolia Testnet"
        case .polynomialMainnet:
            return "Polynomial Mainnet"
        case .polynomialSepoliaTestnet:
            return "Polynomial Sepolia Testnet"
        }
    }

    var chainId: Int {
        switch self {
        case .ethMainnet:
            return 1
        case .ethSepoliaTestnet:
            return 11155111
        case .baseMainnet:
            return 8453
        case .baseSepoliaTestnet:
            return 84532
        case .arbMainnet:
            return 42161
        case .arbSepoliaTestnet:
            return 421614
        case .arbNovaMainnet:
            return 42170
        case .optMainnet:
            return 10
        case .optSepoliaTestnet:
            return 11155420
        case .polygonMainnet:
            return 137
        case .polygonAmoyTestnet:
            return 80002
        case .worldchainMainnet:
            return 480
        case .worldchainSepoliaTestnet:
            return 4801
        case .shapeMainnet:
            return 360
        case .shapeSepoliaTestnet:
            return 11011
        case .inkMainnet:
            return 57073
        case .inkSepoliaTestnet:
            return 763373
        case .unichainMainnet:
            return 130
        case .unichainSepoliaTestnet:
            return 1301
        case .soneiumMainnet:
            return 1868
        case .soneiumMinatoTestnet:
            return 1946
        case .solanaMainnet:
            return 10_000_000_001
        case .solanaDevnetTestnet:
            return 10_000_000_002
        case .berachainMainnet:
            return 80094
        case .zoraMainnet:
            return 7777777
        case .zoraSepoliaTestnet:
            return 999999999
        case .polynomialMainnet:
            return 8008
        case .polynomialSepoliaTestnet:
            return 8009
        }
    }

    var web3EthereumNetwork: EthereumNetwork {
        EthereumNetwork.fromString("\(chainId)")
    }

    var formattedChainId: String {
        if case .solanaMainnet = self {
            return "Solana Network"
        }
        if case .solanaDevnetTestnet = self {
            return "Solana Network"
        }
        return "Chain ID: \(chainId)"
    }

    var isMainnet: Bool {
        switch self {
        case .ethMainnet, .baseMainnet, .arbMainnet, .arbNovaMainnet, .optMainnet,
             .polygonMainnet, .worldchainMainnet, .shapeMainnet, .inkMainnet,
             .unichainMainnet, .soneiumMainnet, .solanaMainnet, .berachainMainnet,
             .zoraMainnet, .polynomialMainnet:
            return true
        default:
            return false
        }
    }
    
    var routingDisplayName: String {
        switch self {
        case .ethMainnet:
            return "Ethereum"
        case .polygonMainnet:
            return "Polygon"
        case .arbMainnet:
            return "Arbitrum"
        case .optMainnet:
            return "Optimism"
        case .baseMainnet:
            return "Base"
        default:
            return rawValue.capitalized
        }
    }
}
