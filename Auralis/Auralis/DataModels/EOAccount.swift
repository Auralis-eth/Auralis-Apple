//
//  EOAccount.swift
//  Auralis
//
//  Created by Daniel Bell on 5/9/25.
//

import Foundation
import OSLog
import SwiftData

private let eoAccountLogger = Logger(subsystem: "Auralis", category: "EOAccount")

@Model
/// Persisted watch-only or wallet-backed account tracked by the shell.
class EOAccount: Codable, Identifiable {
    #Index<EOAccount>(
        [\.address],
        [\.lastSelectedAt, \.addedAt, \.address]
    )
    /// Canonical wallet address for the account.
    @Attribute(.unique) var address: String
    /// Stable identifier that matches the canonical address.
    var id: String {
        address
    }
    /// Optional ENS or user-facing label shown in account switchers and summaries.
    var name: String?
    /// Capability level describing whether the address can sign.
    var access: EthereumAddressAccess?
    /// The onboarding path that created the account record.
    var source: EOAccountSource
    /// Timestamp when the account was first saved on-device.
    var addedAt: Date
    /// Timestamp of the most recent shell selection for this account.
    var lastSelectedAt: Date?
    /// Count of NFTs currently persisted for this account.
    var trackedNFTCount: Int

    /// Persisted preferred chain raw value for restoring account scope.
    var preferredChainRawValue: String = Chain.ethMainnet.rawValue
    /// Persisted currently active chain raw value for restoring the live shell scope.
    var currentChainRawValue: String = Chain.ethMainnet.rawValue

    /// NFTs currently associated with this account in SwiftData.
    @Relationship(deleteRule: .cascade, inverse: \NFT.account) var nfts: [NFT] = []

    /// Creates a persisted account record with normalized defaults for naming and chain scope.
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

    /// Most recent activity timestamp used to order accounts in switchers.
    var mostRecentActivityAt: Date {
        lastSelectedAt ?? addedAt
    }

    /// Fallback display name when no ENS or explicit label exists.
    static func defaultName(for address: String) -> String {
        "Account \(String(address.prefix(4)))"
    }

    var preferredChainOrNil: Chain? {
        Chain.resolved(rawValue: preferredChainRawValue)
    }

    var currentChainOrNil: Chain? {
        Chain.resolved(rawValue: currentChainRawValue)
    }

    /// Preferred chain restored when the account becomes active again.
    var preferredChain: Chain {
        get { preferredChainOrNil ?? .ethMainnet }
        set { preferredChainRawValue = newValue.rawValue }
    }

    /// Current chain last used for this account in the shell.
    var currentChain: Chain {
        get { currentChainOrNil ?? preferredChainOrNil ?? .ethMainnet }
        set { currentChainRawValue = newValue.rawValue }
    }

    @discardableResult
    func normalizeStoredChainsIfNeeded(defaultChain: Chain = .ethMainnet) -> Bool {
        let resolvedPreferred = preferredChainOrNil ?? defaultChain
        let resolvedCurrent = currentChainOrNil ?? preferredChainOrNil ?? defaultChain
        let preferredWasInvalid = preferredChainOrNil == nil
        let currentWasInvalid = currentChainOrNil == nil

        if preferredWasInvalid {
            eoAccountLogger.error(
                "Repairing invalid preferredChainRawValue for account \(self.address, privacy: .public): \(self.preferredChainRawValue, privacy: .public)"
            )
            preferredChainRawValue = resolvedPreferred.rawValue
        }

        if currentWasInvalid {
            eoAccountLogger.error(
                "Repairing invalid currentChainRawValue for account \(self.address, privacy: .public): \(self.currentChainRawValue, privacy: .public)"
            )
            currentChainRawValue = resolvedCurrent.rawValue
        }

        return preferredWasInvalid || currentWasInvalid
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
    /// Account added by pasting or typing an address.
    case manualEntry
    /// Account added from a scanned QR code.
    case qrScan
    /// Account added from a curated guest-pass shortcut.
    case guestPass

    init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        let rawValue = try container.decode(String.self)
        switch rawValue {
        case Self.manualEntry.rawValue:
            self = .manualEntry
        case Self.qrScan.rawValue:
            self = .qrScan
        case "guestPass":
            self = .guestPass
        default:
            eoAccountLogger.error("Unknown EOAccountSource raw value encountered during decode: \(rawValue, privacy: .public)")
            self = .manualEntry
        }
    }
}
