import Foundation
import web3

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
