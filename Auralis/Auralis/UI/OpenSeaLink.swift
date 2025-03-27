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
                Image(systemName: "water.waves")
                    .font(.system(size: 18, weight: .bold))

                Text("View on OpenSea")
                    .font(.system(size: 16, weight: .semibold))
            }
            .foregroundColor(.white)
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
