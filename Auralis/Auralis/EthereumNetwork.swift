//
//  EthereumNetwork.swift
//  KickingHorse
//
//  Created by Daniel Bell on 8/24/24.
//

import Foundation
import web3

extension EthereumNetwork: CaseIterable, Identifiable, RawRepresentable, Hashable {
    public init?(rawValue: String) {
        self = EthereumNetwork.fromString(rawValue)
    }

    public var rawValue: String {
        stringValue
    }

    public var id: String {
        rawValue
    }

    public static var allCases: [EthereumNetwork] {
        [.goerli, .kovan, .mainnet, .sepolia]
    }

    public var name: String {
        switch self {
            case .mainnet:
                return "main"
            case .kovan:
                return "kovan"
            case .goerli:
                return "goerli"
            case .sepolia:
                return "sepolia"
            case .custom(let string):
                return "networkID: \(string)"
        }
    }
}
