//
//  EOAccount.swift
//  Auralis
//
//  Created by Daniel Bell on 5/9/25.
//

import Foundation
import SwiftData


@Model
class EOAccount: Codable, Identifiable {
    #Index<EOAccount>([\.address])
    @Attribute(.unique) var address: String
    var id: String {
        address
    }
    var name: String?
    var access: EthereumAddressAccess?

    @Relationship(deleteRule: .cascade) var nfts: [NFT] = []

    init(address: String, access: EthereumAddressAccess? = nil, name: String? = nil) {
        self.address = address
        self.access = access
        self.name = name ?? "Account \(String(address.prefix(4)))"
    }

    enum CodingKeys: String, CodingKey {
        case address
        case access
        case name
    }

    required init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        address = try container.decode(String.self, forKey: .address)
        access = try container.decode(EthereumAddressAccess.self, forKey: .access)

        do {
            name = try container.decodeIfPresent(String.self, forKey: .name) ?? "Account \(String(address.prefix(4)))"
        } catch {
            name = "Account \(String(address.prefix(4)))"
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(address, forKey: .address)
        try container.encode(access, forKey: .access)
        try container.encode(name, forKey: .name)
    }
}






enum EthereumAddressAccess: Codable {
    case wallet
    case readonly

    /// Whether this address can sign transactions
    var canSign: Bool {
        switch self {
            case .wallet:
                return true
            case .readonly:
                return false
        }
    }
}

