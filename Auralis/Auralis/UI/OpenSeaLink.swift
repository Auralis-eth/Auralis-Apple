//
//  OpenSeaLink.swift
//  Auralis
//
//  Created by Daniel Bell on 3/24/25.
//

import SwiftUI

struct OpenSeaLink: View {
    let contractAddress: String
    let tokenId: String

    // Default values matching your example
    init(contractAddress: String,
         tokenId: String) {
        self.contractAddress = contractAddress
        self.tokenId = tokenId
    }

    var openSeaURL: URL {
        URL(string: "https://opensea.io/assets/ethereum/\(contractAddress)/\(tokenId)")!
    }

    var body: some View {
        Link(destination: openSeaURL) {
            HStack {
                // OpenSea logo
                SystemImage("water.waves")
                    .font(.system(size: 18, weight: .bold))

                SystemFontText(
                    text: "View on OpenSea",
                    size: 16,
                    weight: .semibold
                )
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(
                LinearGradient(
                    gradient: Gradient(colors: [
                        Color(hexString: "2081E2"),  // OpenSea blue
                        Color(hexString: "2081E2").opacity(0.8)
                    ]),
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .cornerRadius(12)
            .shadow(color: Color.black.opacity(0.15), radius: 4, x: 0, y: 2)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.white.opacity(0.2), lineWidth: 1)
            )
        }
    }
}

struct EtherscanLink: View {
    let contractAddress: String
    let tokenId: String

    init(contractAddress: String, tokenId: String) {
        self.contractAddress = contractAddress
        self.tokenId = tokenId
    }

    var etherscanURL: URL {
        // Etherscan URL for a specific token ID
        URL(string: "https://etherscan.io/token/\(contractAddress)?a=\(tokenId)")!
    }

    var body: some View {
        Link(destination: etherscanURL) {
            HStack {
                // Etherscan-related icon (you can choose a more specific one if available)
                SystemImage("link.circle.fill") // Example icon
                    .font(.system(size: 18, weight: .bold))

                SystemFontText(
                    text: "View on Etherscan",
                    size: 16,
                    weight: .semibold
                )
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(
                LinearGradient(
                    gradient: Gradient(colors: [
                        Color(hexString: "3498DB"),  // Etherscan-like blue
                        Color(hexString: "2980B9").opacity(0.8) // Darker blue
                    ]),
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .cornerRadius(12)
            .shadow(color: Color.black.opacity(0.15), radius: 4, x: 0, y: 2)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.white.opacity(0.2), lineWidth: 1)
            )
        }
    }
}
