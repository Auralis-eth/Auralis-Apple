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
    var source: EOAccountSource
    var addedAt: Date
    var lastSelectedAt: Date?
    var trackedNFTCount: Int

    @Relationship(deleteRule: .cascade) var nfts: [NFT] = []

    init(
        address: String,
        access: EthereumAddressAccess? = nil,
        name: String? = nil,
        source: EOAccountSource = .manualEntry,
        addedAt: Date = .now,
        lastSelectedAt: Date? = nil,
        trackedNFTCount: Int = 0
    ) {
        let resolvedName = name ?? EOAccount.defaultName(for: address)
        self.address = address
        self.access = access
        self.name = resolvedName
        self.source = source
        self.addedAt = addedAt
        self.lastSelectedAt = lastSelectedAt
        self.trackedNFTCount = trackedNFTCount
    }

    enum CodingKeys: String, CodingKey {
        case address
        case access
        case name
        case source
        case addedAt
        case lastSelectedAt
        case trackedNFTCount
    }

    required init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let decodedAddress = try container.decode(String.self, forKey: .address)
        let decodedAccess = try container.decodeIfPresent(EthereumAddressAccess.self, forKey: .access)
        let decodedName: String
        let decodedSource = try container.decodeIfPresent(EOAccountSource.self, forKey: .source) ?? .manualEntry
        let decodedAddedAt = try container.decodeIfPresent(Date.self, forKey: .addedAt) ?? .distantPast
        let decodedLastSelectedAt = try container.decodeIfPresent(Date.self, forKey: .lastSelectedAt)
        let decodedTrackedNFTCount = try container.decodeIfPresent(Int.self, forKey: .trackedNFTCount) ?? 0

        do {
            decodedName = try container.decodeIfPresent(String.self, forKey: .name) ?? EOAccount.defaultName(for: decodedAddress)
        } catch {
            decodedName = EOAccount.defaultName(for: decodedAddress)
        }

        address = decodedAddress
        access = decodedAccess
        name = decodedName
        source = decodedSource
        addedAt = decodedAddedAt
        lastSelectedAt = decodedLastSelectedAt
        trackedNFTCount = decodedTrackedNFTCount
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(address, forKey: .address)
        try container.encodeIfPresent(access, forKey: .access)
        try container.encode(name, forKey: .name)
        try container.encode(source, forKey: .source)
        try container.encode(addedAt, forKey: .addedAt)
        try container.encodeIfPresent(lastSelectedAt, forKey: .lastSelectedAt)
        try container.encode(trackedNFTCount, forKey: .trackedNFTCount)
    }

    var mostRecentActivityAt: Date {
        lastSelectedAt ?? addedAt
    }

    static func defaultName(for address: String) -> String {
        "Account \(String(address.prefix(4)))"
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

enum EOAccountSource: String, Codable {
    case manualEntry
    case qrScan
    case guestPass
}
