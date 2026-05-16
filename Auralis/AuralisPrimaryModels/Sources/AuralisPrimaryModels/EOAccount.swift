import Foundation
import OSLog
import SwiftData

private let eoAccountLogger = Logger(subsystem: "Auralis", category: "EOAccount")

@Model
/// Persisted watch-only or wallet-backed account tracked by the shell.
public final class EOAccount: Codable, Identifiable {
    #Index<EOAccount>(
        [\.address],
        [\.normalizedName],
        [\.lastSelectedAt, \.addedAt, \.address]
    )

    @Attribute(.unique) public var address: String

    public var id: String {
        address
    }

    @Attribute(originalName: "name") private var storedName: String?

    public var name: String? {
        get { storedName }
        set {
            storedName = newValue
            normalizedName = Self.normalizedName(from: newValue)
        }
    }

    public var normalizedName: String?
    public var access: EthereumAddressAccess?
    public var source: EOAccountSource
    public var addedAt: Date
    public var lastSelectedAt: Date?
    public var trackedNFTCount: Int
    public var preferredChainRawValue: String = Chain.ethMainnet.rawValue
    public var currentChainRawValue: String = Chain.ethMainnet.rawValue
    public var auraPlaySyncStateRawValue: String?

    @Relationship(deleteRule: .cascade, inverse: \NFT.account) public var nfts: [NFT] = []

    public init(
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
        self.storedName = resolvedName
        self.normalizedName = Self.normalizedName(from: resolvedName)
        self.source = source
        self.addedAt = addedAt
        self.lastSelectedAt = lastSelectedAt
        self.trackedNFTCount = trackedNFTCount
        self.preferredChainRawValue = Chain.ethMainnet.rawValue
        self.currentChainRawValue = Chain.ethMainnet.rawValue
        self.auraPlaySyncStateRawValue = nil
    }

    enum CodingKeys: String, CodingKey {
        case address
        case access
        case name
        case normalizedName
        case source
        case addedAt
        case lastSelectedAt
        case trackedNFTCount
        case preferredChainRawValue
        case currentChainRawValue
        case auraPlaySyncStateRawValue
    }

    public required init(from decoder: Decoder) throws {
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
        let decodedAuraPlaySyncStateRawValue = try container.decodeIfPresent(String.self, forKey: .auraPlaySyncStateRawValue)
        let decodedNormalizedName = try container.decodeIfPresent(String.self, forKey: .normalizedName)

        address = decodedAddress
        access = decodedAccess
        storedName = decodedName
        normalizedName = decodedNormalizedName ?? Self.normalizedName(from: decodedName)
        source = decodedSource
        addedAt = decodedAddedAt
        lastSelectedAt = decodedLastSelectedAt
        trackedNFTCount = decodedTrackedNFTCount
        preferredChainRawValue = decodedPreferred
        currentChainRawValue = decodedCurrent
        auraPlaySyncStateRawValue = decodedAuraPlaySyncStateRawValue
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(address, forKey: .address)
        try container.encodeIfPresent(access, forKey: .access)
        try container.encode(name, forKey: .name)
        try container.encodeIfPresent(normalizedName, forKey: .normalizedName)
        try container.encode(source, forKey: .source)
        try container.encode(addedAt, forKey: .addedAt)
        try container.encodeIfPresent(lastSelectedAt, forKey: .lastSelectedAt)
        try container.encode(trackedNFTCount, forKey: .trackedNFTCount)
        try container.encode(preferredChainRawValue, forKey: .preferredChainRawValue)
        try container.encode(currentChainRawValue, forKey: .currentChainRawValue)
        try container.encodeIfPresent(auraPlaySyncStateRawValue, forKey: .auraPlaySyncStateRawValue)
    }

    public var mostRecentActivityAt: Date {
        lastSelectedAt ?? addedAt
    }

    public static func defaultName(for address: String) -> String {
        "Account \(String(address.prefix(4)))"
    }

    public static func normalizedName(from rawName: String?) -> String? {
        let trimmedName = rawName?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let trimmedName, !trimmedName.isEmpty else {
            return nil
        }

        return trimmedName.lowercased()
    }

    public var preferredChainOrNil: Chain? {
        Chain.resolved(rawValue: preferredChainRawValue)
    }

    public var currentChainOrNil: Chain? {
        Chain.resolved(rawValue: currentChainRawValue)
    }

    public var preferredChain: Chain {
        get { preferredChainOrNil ?? .ethMainnet }
        set { preferredChainRawValue = newValue.rawValue }
    }

    public var currentChain: Chain {
        get { currentChainOrNil ?? preferredChainOrNil ?? .ethMainnet }
        set { currentChainRawValue = newValue.rawValue }
    }

    @discardableResult
    public func normalizeStoredChainsIfNeeded(defaultChain: Chain = .ethMainnet) -> Bool {
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

    @discardableResult
    public func normalizeStoredNameIfNeeded() -> Bool {
        let resolvedNormalizedName = Self.normalizedName(from: name)
        guard normalizedName != resolvedNormalizedName else {
            return false
        }

        eoAccountLogger.log(
            "Repairing normalizedName for account \(self.address, privacy: .public)"
        )
        normalizedName = resolvedNormalizedName
        return true
    }

    public func auraPlayLastSyncedAt(for chain: Chain) -> Date? {
        auraPlaySyncStates[chain.rawValue]
    }

    public func markAuraPlaySynced(on chain: Chain, at syncedAt: Date) {
        var states = auraPlaySyncStates
        states[chain.rawValue] = syncedAt
        auraPlaySyncStates = states
    }

    public func clearAuraPlaySyncState(for chain: Chain) {
        var states = auraPlaySyncStates
        states.removeValue(forKey: chain.rawValue)
        auraPlaySyncStates = states
    }

    public func clearAllAuraPlaySyncState() {
        auraPlaySyncStates = [:]
    }

    private var auraPlaySyncStates: [String: Date] {
        get {
            Self.decodeAuraPlaySyncStates(from: auraPlaySyncStateRawValue)
        }
        set {
            auraPlaySyncStateRawValue = Self.encodeAuraPlaySyncStates(newValue)
        }
    }

    private static func decodeAuraPlaySyncStates(from rawValue: String?) -> [String: Date] {
        guard
            let rawValue,
            let data = rawValue.data(using: .utf8)
        else {
            return [:]
        }

        do {
            return try JSONDecoder().decode([String: Date].self, from: data)
        } catch {
            eoAccountLogger.error("Failed to decode AuraPlay sync state for account metadata")
            return [:]
        }
    }

    private static func encodeAuraPlaySyncStates(_ states: [String: Date]) -> String? {
        guard !states.isEmpty else {
            return nil
        }

        do {
            let data = try JSONEncoder().encode(states)
            return String(data: data, encoding: .utf8)
        } catch {
            eoAccountLogger.error("Failed to encode AuraPlay sync state for account metadata")
            return nil
        }
    }
}

public enum EthereumAddressAccess: Codable, Sendable {
    case wallet
    case readonly

    public var canSign: Bool {
        switch self {
        case .wallet:
            return true
        case .readonly:
            return false
        }
    }
}

public enum EOAccountSource: String, Codable, Sendable {
    case manualEntry
    case qrScan
    case guestPass

    public init(from decoder: any Decoder) throws {
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
