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

    var preferredChainRawValue: String = Chain.ethMainnet.rawValue
    var currentChainRawValue: String = Chain.ethMainnet.rawValue

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
        self.preferredChainRawValue = Chain.ethMainnet.rawValue
        self.currentChainRawValue = Chain.ethMainnet.rawValue
    }

    enum CodingKeys: String, CodingKey {
        case address
        case access
        case name
        case source
        case addedAt
        case lastSelectedAt
        case trackedNFTCount
        case preferredChainRawValue
        case currentChainRawValue
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

        let decodedPreferred = try container.decodeIfPresent(String.self, forKey: .preferredChainRawValue) ?? Chain.ethMainnet.rawValue
        let decodedCurrent = try container.decodeIfPresent(String.self, forKey: .currentChainRawValue) ?? Chain.ethMainnet.rawValue

        address = decodedAddress
        access = decodedAccess
        name = decodedName
        source = decodedSource
        addedAt = decodedAddedAt
        lastSelectedAt = decodedLastSelectedAt
        trackedNFTCount = decodedTrackedNFTCount
        preferredChainRawValue = decodedPreferred
        currentChainRawValue = decodedCurrent
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
        try container.encode(preferredChainRawValue, forKey: .preferredChainRawValue)
        try container.encode(currentChainRawValue, forKey: .currentChainRawValue)
    }

    var mostRecentActivityAt: Date {
        lastSelectedAt ?? addedAt
    }

    static func defaultName(for address: String) -> String {
        "Account \(String(address.prefix(4)))"
    }

    var preferredChain: Chain { get { Chain(rawValue: preferredChainRawValue) ?? .ethMainnet } set { preferredChainRawValue = newValue.rawValue } }

    var currentChain: Chain { get { Chain(rawValue: currentChainRawValue) ?? .ethMainnet } set { currentChainRawValue = newValue.rawValue } }
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
