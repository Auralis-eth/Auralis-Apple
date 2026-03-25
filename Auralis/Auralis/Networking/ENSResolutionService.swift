import Foundation
import OSLog
import SwiftData
import web3

enum ENSResolutionProvenance: String, Codable, Equatable, Sendable {
    case network
    case cache
    case staleCache
}

struct ENSForwardResolution: Codable, Equatable, Sendable {
    let ensName: String
    let address: String
    let provenance: ENSResolutionProvenance
    let fetchedAt: Date
    let isStale: Bool
}

struct ENSReverseResolution: Codable, Equatable, Sendable {
    let address: String
    let ensName: String
    let provenance: ENSResolutionProvenance
    let fetchedAt: Date
    let isStale: Bool
    let isForwardVerified: Bool
}

enum ENSResolutionError: LocalizedError, Equatable {
    case invalidENSName
    case invalidAddress
    case unavailableProvider
    case notFound
    case mappingChanged(ensName: String, cachedAddress: String, resolvedAddress: String)

    var errorDescription: String? {
        switch self {
        case .invalidENSName:
            return "Enter a valid ENS name ending in .eth."
        case .invalidAddress:
            return "Enter a valid Ethereum address."
        case .unavailableProvider:
            return "ENS lookup is temporarily unavailable."
        case .notFound:
            return "No ENS record was found."
        case .mappingChanged(let ensName, _, let resolvedAddress):
            return "\(ensName) now resolves to \(resolvedAddress). Confirm the updated address before continuing."
        }
    }
}

protocol ENSResolving {
    func cachedForwardResolution(forENS name: String) async -> ENSForwardResolution?
    func cachedReverseResolution(forAddress address: String) async -> ENSReverseResolution?
    func resolveAddress(forENS name: String, correlationID: String?) async throws -> ENSForwardResolution
    func reverseLookup(address: String, correlationID: String?) async -> ENSReverseResolution?
}

protocol EthereumNameServiceClient {
    func resolveAddress(forENS name: String) async throws -> String
    func resolveName(forAddress address: String) async throws -> String
}

struct Web3EthereumNameServiceClient: EthereumNameServiceClient {
    private let ethereumNameService: EthereumNameService

    init(rpcURL: URL) {
        let client = EthereumHttpClient(url: rpcURL, network: .mainnet)
        self.ethereumNameService = EthereumNameService(client: client)
    }

    func resolveAddress(forENS name: String) async throws -> String {
        let address = try await ethereumNameService.resolve(
            ens: name,
            mode: .allowOffchainLookup
        )
        return address.asString()
    }

    func resolveName(forAddress address: String) async throws -> String {
        let name = try await ethereumNameService.resolve(
            address: EthereumAddress(address),
            mode: .allowOffchainLookup
        )
        return name
    }
}

struct ENSCacheState: Codable, Equatable, Sendable {
    var forward: [String: ENSForwardCacheEntry]
    var reverse: [String: ENSReverseCacheEntry]

    static let empty = ENSCacheState(forward: [:], reverse: [:])
}

struct ENSForwardCacheEntry: Codable, Equatable, Sendable {
    let ensName: String
    let address: String
    let fetchedAt: Date
}

struct ENSReverseCacheEntry: Codable, Equatable, Sendable {
    let address: String
    let ensName: String
    let isForwardVerified: Bool
    let fetchedAt: Date
}

actor ENSResolutionCacheStore {
    private let userDefaults: UserDefaults
    private let storageKey: String
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private var state: ENSCacheState

    init(
        userDefaults: UserDefaults = .standard,
        storageKey: String = "Auralis.ENSResolutionCache.v1"
    ) {
        self.userDefaults = userDefaults
        self.storageKey = storageKey
        if let data = userDefaults.data(forKey: storageKey),
           let decoded = try? decoder.decode(ENSCacheState.self, from: data) {
            self.state = decoded
        } else {
            self.state = .empty
        }
    }

    func cachedForwardResolution(forENS name: String) -> ENSForwardCacheEntry? {
        state.forward[name]
    }

    func cachedReverseResolution(forAddress address: String) -> ENSReverseCacheEntry? {
        state.reverse[address]
    }

    func storeForwardResolution(_ entry: ENSForwardCacheEntry) {
        state.forward[entry.ensName] = entry
        persist()
    }

    func storeReverseResolution(_ entry: ENSReverseCacheEntry) {
        state.reverse[entry.address] = entry
        persist()
    }

    private func persist() {
        guard let data = try? encoder.encode(state) else {
            return
        }

        userDefaults.set(data, forKey: storageKey)
    }
}

protocol ENSEventRecording {
    func recordCacheHit(
        kind: String,
        key: String,
        fetchedAt: Date,
        correlationID: String?
    ) async

    func recordLookupStarted(
        kind: String,
        key: String,
        correlationID: String?
    ) async

    func recordLookupSucceeded(
        kind: String,
        key: String,
        value: String,
        verification: Bool?,
        correlationID: String?
    ) async

    func recordLookupFailed(
        kind: String,
        key: String,
        correlationID: String?,
        error: Error
    ) async

    func recordMappingChanged(
        kind: String,
        key: String,
        oldValue: String,
        newValue: String,
        correlationID: String?
    ) async
}

struct NoOpENSEventRecorder: ENSEventRecording {
    func recordCacheHit(
        kind: String,
        key: String,
        fetchedAt: Date,
        correlationID: String?
    ) async { }

    func recordLookupStarted(
        kind: String,
        key: String,
        correlationID: String?
    ) async { }

    func recordLookupSucceeded(
        kind: String,
        key: String,
        value: String,
        verification: Bool?,
        correlationID: String?
    ) async { }

    func recordLookupFailed(
        kind: String,
        key: String,
        correlationID: String?,
        error: Error
    ) async { }

    func recordMappingChanged(
        kind: String,
        key: String,
        oldValue: String,
        newValue: String,
        correlationID: String?
    ) async { }
}

@MainActor
final class ReceiptBackedENSEventRecorder: ENSEventRecording {
    private let receiptStore: any ReceiptStore
    private let payloadSanitizer: any ReceiptPayloadSanitizing
    private let logger = Logger(subsystem: "Auralis", category: "ENSReceipts")

    init(
        receiptStore: any ReceiptStore,
        payloadSanitizer: any ReceiptPayloadSanitizing = DefaultReceiptPayloadSanitizer()
    ) {
        self.receiptStore = receiptStore
        self.payloadSanitizer = payloadSanitizer
    }

    func recordCacheHit(
        kind: String,
        key: String,
        fetchedAt: Date,
        correlationID: String?
    ) async {
        append(
            trigger: "ens.\(kind).cache_hit",
            summary: "Used cached ENS resolution",
            correlationID: correlationID,
            isSuccess: true,
            rawPayload: RawReceiptPayload(values: [
                "lookupKind": .string(kind),
                "key": .string(key),
                "fetchedAt": .string(ISO8601DateFormatter().string(from: fetchedAt))
            ])
        )
    }

    func recordLookupStarted(
        kind: String,
        key: String,
        correlationID: String?
    ) async {
        append(
            trigger: "ens.\(kind).started",
            summary: "Started ENS lookup",
            correlationID: correlationID,
            isSuccess: true,
            rawPayload: RawReceiptPayload(values: [
                "lookupKind": .string(kind),
                "key": .string(key)
            ])
        )
    }

    func recordLookupSucceeded(
        kind: String,
        key: String,
        value: String,
        verification: Bool?,
        correlationID: String?
    ) async {
        var payload: [String: ReceiptJSONValue] = [
            "lookupKind": .string(kind),
            "key": .string(key),
            "value": .string(value)
        ]
        if let verification {
            payload["isForwardVerified"] = .bool(verification)
        }

        append(
            trigger: "ens.\(kind).succeeded",
            summary: "ENS lookup succeeded",
            correlationID: correlationID,
            isSuccess: true,
            rawPayload: RawReceiptPayload(values: payload)
        )
    }

    func recordLookupFailed(
        kind: String,
        key: String,
        correlationID: String?,
        error: Error
    ) async {
        append(
            trigger: "ens.\(kind).failed",
            summary: "ENS lookup failed",
            correlationID: correlationID,
            isSuccess: false,
            rawPayload: RawReceiptPayload(values: [
                "lookupKind": .string(kind),
                "key": .string(key),
                "error": .string(String(describing: error))
            ])
        )
    }

    func recordMappingChanged(
        kind: String,
        key: String,
        oldValue: String,
        newValue: String,
        correlationID: String?
    ) async {
        append(
            trigger: "ens.\(kind).mapping_changed",
            summary: "ENS mapping changed",
            correlationID: correlationID,
            isSuccess: true,
            rawPayload: RawReceiptPayload(values: [
                "lookupKind": .string(kind),
                "key": .string(key),
                "oldValue": .string(oldValue),
                "newValue": .string(newValue)
            ])
        )
    }
}

@MainActor
private extension ReceiptBackedENSEventRecorder {
    func append(
        trigger: String,
        summary: String,
        correlationID: String?,
        isSuccess: Bool,
        rawPayload: RawReceiptPayload
    ) {
        let payload = payloadSanitizer.sanitize(rawPayload)

        do {
            _ = try receiptStore.append(
                ReceiptDraft(
                    actor: .system,
                    mode: .observe,
                    trigger: trigger,
                    scope: "identity.ens",
                    summary: summary,
                    provenance: "network",
                    isSuccess: isSuccess,
                    correlationID: correlationID,
                    details: payload
                )
            )
        } catch {
            logger.error(
                "Failed to append ENS receipt trigger=\(trigger, privacy: .public) correlationID=\(correlationID ?? "nil", privacy: .public) error=\(error.localizedDescription, privacy: .public)"
            )
        }
    }
}

actor Web3EthereumNameServiceResolver: ENSResolving {
    private let client: any EthereumNameServiceClient
    private let cacheStore: ENSResolutionCacheStore
    private let eventRecorder: any ENSEventRecording
    private let freshnessTTL: TimeInterval
    private let nowProvider: @Sendable () -> Date

    init(
        client: any EthereumNameServiceClient,
        cacheStore: ENSResolutionCacheStore = ENSResolutionCacheStore(),
        eventRecorder: any ENSEventRecording = NoOpENSEventRecorder(),
        freshnessTTL: TimeInterval = 60 * 60 * 24,
        nowProvider: @escaping @Sendable () -> Date = { Date.now }
    ) {
        self.client = client
        self.cacheStore = cacheStore
        self.eventRecorder = eventRecorder
        self.freshnessTTL = freshnessTTL
        self.nowProvider = nowProvider
    }

    func cachedForwardResolution(forENS name: String) async -> ENSForwardResolution? {
        guard let normalizedName = Self.normalizedENSName(name),
              let entry = await cacheStore.cachedForwardResolution(forENS: normalizedName) else {
            return nil
        }

        return ENSForwardResolution(
            ensName: entry.ensName,
            address: entry.address,
            provenance: isFresh(entry.fetchedAt) ? .cache : .staleCache,
            fetchedAt: entry.fetchedAt,
            isStale: !isFresh(entry.fetchedAt)
        )
    }

    func cachedReverseResolution(forAddress address: String) async -> ENSReverseResolution? {
        guard let normalizedAddress = Self.normalizedAddress(address),
              let entry = await cacheStore.cachedReverseResolution(forAddress: normalizedAddress) else {
            return nil
        }

        return ENSReverseResolution(
            address: entry.address,
            ensName: entry.ensName,
            provenance: isFresh(entry.fetchedAt) ? .cache : .staleCache,
            fetchedAt: entry.fetchedAt,
            isStale: !isFresh(entry.fetchedAt),
            isForwardVerified: entry.isForwardVerified
        )
    }

    func resolveAddress(forENS name: String, correlationID: String?) async throws -> ENSForwardResolution {
        guard let normalizedName = Self.normalizedENSName(name) else {
            throw ENSResolutionError.invalidENSName
        }

        if let cached = await cachedForwardResolution(forENS: normalizedName), !cached.isStale {
            await eventRecorder.recordCacheHit(
                kind: "forward",
                key: normalizedName,
                fetchedAt: cached.fetchedAt,
                correlationID: correlationID
            )
            return cached
        }

        await eventRecorder.recordLookupStarted(
            kind: "forward",
            key: normalizedName,
            correlationID: correlationID
        )

        do {
            try Task.checkCancellation()
            let resolvedAddress = try await client.resolveAddress(forENS: normalizedName)
            try Task.checkCancellation()
            guard let normalizedAddress = Self.normalizedAddress(resolvedAddress) else {
                throw ENSResolutionError.invalidAddress
            }

            if let previous = await cacheStore.cachedForwardResolution(forENS: normalizedName),
               previous.address != normalizedAddress {
                await eventRecorder.recordMappingChanged(
                    kind: "forward",
                    key: normalizedName,
                    oldValue: previous.address,
                    newValue: normalizedAddress,
                    correlationID: correlationID
                )
                throw ENSResolutionError.mappingChanged(
                    ensName: normalizedName,
                    cachedAddress: previous.address,
                    resolvedAddress: normalizedAddress
                )
            }

            let fetchedAt = nowProvider()
            await cacheStore.storeForwardResolution(
                ENSForwardCacheEntry(
                    ensName: normalizedName,
                    address: normalizedAddress,
                    fetchedAt: fetchedAt
                )
            )
            await eventRecorder.recordLookupSucceeded(
                kind: "forward",
                key: normalizedName,
                value: normalizedAddress,
                verification: nil,
                correlationID: correlationID
            )

            return ENSForwardResolution(
                ensName: normalizedName,
                address: normalizedAddress,
                provenance: .network,
                fetchedAt: fetchedAt,
                isStale: false
            )
        } catch {
            await eventRecorder.recordLookupFailed(
                kind: "forward",
                key: normalizedName,
                correlationID: correlationID,
                error: error
            )

            if let resolutionError = error as? ENSResolutionError,
               case .mappingChanged = resolutionError {
                throw resolutionError
            }

            if let cached = await cachedForwardResolution(forENS: normalizedName) {
                return ENSForwardResolution(
                    ensName: cached.ensName,
                    address: cached.address,
                    provenance: .staleCache,
                    fetchedAt: cached.fetchedAt,
                    isStale: true
                )
            }

            throw Self.mapError(error)
        }
    }

    func reverseLookup(address: String, correlationID: String?) async -> ENSReverseResolution? {
        guard let normalizedAddress = Self.normalizedAddress(address) else {
            return nil
        }

        if let cached = await cachedReverseResolution(forAddress: normalizedAddress), !cached.isStale {
            await eventRecorder.recordCacheHit(
                kind: "reverse",
                key: normalizedAddress,
                fetchedAt: cached.fetchedAt,
                correlationID: correlationID
            )
            return cached.isForwardVerified ? cached : nil
        }

        await eventRecorder.recordLookupStarted(
            kind: "reverse",
            key: normalizedAddress,
            correlationID: correlationID
        )

        do {
            try Task.checkCancellation()
            let resolvedName = try await client.resolveName(forAddress: normalizedAddress)
            try Task.checkCancellation()
            guard let normalizedName = Self.normalizedENSName(resolvedName) else {
                throw ENSResolutionError.invalidENSName
            }

            let forwardResult = try await client.resolveAddress(forENS: normalizedName)
            guard let verifiedAddress = Self.normalizedAddress(forwardResult) else {
                throw ENSResolutionError.invalidAddress
            }
            let isVerified = verifiedAddress == normalizedAddress

            if let previous = await cacheStore.cachedReverseResolution(forAddress: normalizedAddress),
               previous.ensName != normalizedName {
                await eventRecorder.recordMappingChanged(
                    kind: "reverse",
                    key: normalizedAddress,
                    oldValue: previous.ensName,
                    newValue: normalizedName,
                    correlationID: correlationID
                )
            }

            let fetchedAt = nowProvider()
            let entry = ENSReverseCacheEntry(
                address: normalizedAddress,
                ensName: normalizedName,
                isForwardVerified: isVerified,
                fetchedAt: fetchedAt
            )
            await cacheStore.storeReverseResolution(entry)
            await eventRecorder.recordLookupSucceeded(
                kind: "reverse",
                key: normalizedAddress,
                value: normalizedName,
                verification: isVerified,
                correlationID: correlationID
            )

            guard isVerified else {
                return nil
            }

            return ENSReverseResolution(
                address: normalizedAddress,
                ensName: normalizedName,
                provenance: .network,
                fetchedAt: fetchedAt,
                isStale: false,
                isForwardVerified: true
            )
        } catch {
            await eventRecorder.recordLookupFailed(
                kind: "reverse",
                key: normalizedAddress,
                correlationID: correlationID,
                error: error
            )

            if let cached = await cachedReverseResolution(forAddress: normalizedAddress),
               cached.isForwardVerified {
                return ENSReverseResolution(
                    address: cached.address,
                    ensName: cached.ensName,
                    provenance: .staleCache,
                    fetchedAt: cached.fetchedAt,
                    isStale: true,
                    isForwardVerified: true
                )
            }

            return nil
        }
    }
}

private extension Web3EthereumNameServiceResolver {
    func isFresh(_ fetchedAt: Date) -> Bool {
        nowProvider().timeIntervalSince(fetchedAt) <= freshnessTTL
    }

    static func normalizedENSName(_ rawValue: String) -> String? {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard trimmed.range(
            of: #"^[A-Za-z0-9-]+(\.[A-Za-z0-9-]+)*\.eth$"#,
            options: .regularExpression
        ) != nil else {
            return nil
        }
        return trimmed
    }

    static func normalizedAddress(_ rawValue: String) -> String? {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        if trimmed.range(of: #"^0x[a-f0-9]{40}$"#, options: .regularExpression) != nil {
            return trimmed
        }

        if trimmed.range(of: #"^[a-f0-9]{40}$"#, options: .regularExpression) != nil {
            return "0x" + trimmed
        }

        return nil
    }

    static func mapError(_ error: Error) -> ENSResolutionError {
        if let ensError = error as? ENSResolutionError {
            return ensError
        }

        if let web3Error = error as? EthereumNameServiceError {
            switch web3Error {
            case .invalidInput:
                return .invalidENSName
            case .noNetwork:
                return .unavailableProvider
            case .ensUnknown, .decodeIssue, .tooManyRedirections:
                return .notFound
            }
        }

        return .unavailableProvider
    }
}

@MainActor
enum ENSResolvers {
    static func live(
        modelContext: ModelContext,
        configurationResolver: any ProviderConfigurationResolving = LiveProviderConfigurationResolver()
    ) -> any ENSResolving {
        let client = makeLiveClient(configurationResolver: configurationResolver)
        return Web3EthereumNameServiceResolver(
            client: client,
            eventRecorder: ReceiptBackedENSEventRecorder(
                receiptStore: ReceiptStores.live(modelContext: modelContext)
            )
        )
    }

    static func makeLiveClient(
        configurationResolver: any ProviderConfigurationResolving = LiveProviderConfigurationResolver()
    ) -> any EthereumNameServiceClient {
        let configuration = try? configurationResolver.configuration(for: .ethMainnet)
        guard let rpcURL = configuration?.alchemyRPCURL else {
            return UnavailableEthereumNameServiceClient()
        }

        return Web3EthereumNameServiceClient(rpcURL: rpcURL)
    }
}

struct UnavailableEthereumNameServiceClient: EthereumNameServiceClient {
    func resolveAddress(forENS name: String) async throws -> String {
        throw ENSResolutionError.unavailableProvider
    }

    func resolveName(forAddress address: String) async throws -> String {
        throw ENSResolutionError.unavailableProvider
    }
}
