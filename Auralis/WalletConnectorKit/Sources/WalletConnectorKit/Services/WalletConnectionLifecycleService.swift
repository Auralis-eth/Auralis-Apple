import Foundation

public protocol WalletAccountPersisting: Sendable {
    func upsert(_ walletAddress: WalletSessionAddress, selectedAt: Date) async throws
    func deactivate(address: String, chain: WalletChain, at date: Date) async throws
    func mostRecentlyUsedActiveAddress(excluding address: String?) async throws -> String?
}

public protocol WalletPostConnectionResolving: Sendable {
    func refreshMetadata(for walletAddress: WalletSessionAddress) async
}

public protocol WalletRemovalCleaning: Sendable {
    func cleanLocalData(for address: String) async throws
}

public struct NoOpWalletPostConnectionResolver: WalletPostConnectionResolving {
    public init() {}
    public func refreshMetadata(for walletAddress: WalletSessionAddress) async {}
}

public struct NoOpWalletRemovalCleaner: WalletRemovalCleaning {
    public init() {}
    public func cleanLocalData(for address: String) async throws {}
}

public struct WalletConnectionPersistenceResult: Hashable, Sendable {
    public let persistedAddresses: [WalletSessionAddress]
    public let activeAddress: String?

    public init(persistedAddresses: [WalletSessionAddress], activeAddress: String?) {
        self.persistedAddresses = persistedAddresses
        self.activeAddress = activeAddress
    }
}

public actor WalletConnectionLifecycleService {
    private let connector: any WalletConnector
    private let accountStore: any WalletAccountPersisting
    private let topicStore: any WalletSessionTopicStoring
    private let activeWalletStore: any ActiveWalletStoring
    private let metadataResolver: any WalletPostConnectionResolving
    private let removalCleaner: any WalletRemovalCleaning
    private let now: @Sendable () -> Date

    public init(
        connector: any WalletConnector,
        accountStore: any WalletAccountPersisting,
        topicStore: any WalletSessionTopicStoring,
        activeWalletStore: any ActiveWalletStoring,
        metadataResolver: any WalletPostConnectionResolving = NoOpWalletPostConnectionResolver(),
        removalCleaner: any WalletRemovalCleaning = NoOpWalletRemovalCleaner(),
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.connector = connector
        self.accountStore = accountStore
        self.topicStore = topicStore
        self.activeWalletStore = activeWalletStore
        self.metadataResolver = metadataResolver
        self.removalCleaner = removalCleaner
        self.now = now
    }

    @discardableResult
    public func persistApprovedSession(_ session: WalletConnectorSession) async throws -> WalletConnectionPersistenceResult {
        let addresses = WalletSessionAddressExtractor.extract(from: session)
        let selectedAt = now()

        for address in addresses {
            try await accountStore.upsert(address, selectedAt: selectedAt)
            try await topicStore.save(topic: session.topic, walletAddress: address.account.address)
            activeWalletStore.set(address.account.address)
            await metadataResolver.refreshMetadata(for: address)
        }

        return WalletConnectionPersistenceResult(
            persistedAddresses: addresses,
            activeAddress: addresses.last.map(\.account.address)
        )
    }

    public func restoreSavedSessions() async throws -> WalletConnectionPersistenceResult {
        let savedTopics = try await topicStore.loadAll()
        let liveSessions = try await connector.sessions()
        let sessionsByTopic = Dictionary(uniqueKeysWithValues: liveSessions.map { ($0.topic, $0) })
        var restored: [WalletSessionAddress] = []

        for savedTopic in savedTopics {
            guard let session = sessionsByTopic[savedTopic.topic], !session.isExpired else {
                try await topicStore.delete(walletAddress: savedTopic.address)
                try await accountStore.deactivate(address: savedTopic.address, chain: .ethereum, at: now())
                continue
            }

            let sessionAddresses = WalletSessionAddressExtractor.extract(from: session)
                .filter { $0.account.address.caseInsensitiveCompare(savedTopic.address) == .orderedSame }
            for address in sessionAddresses {
                try await accountStore.upsert(address, selectedAt: now())
                await metadataResolver.refreshMetadata(for: address)
            }
            restored.append(contentsOf: sessionAddresses)
        }

        if let activeAddress = restored.last?.account.address {
            activeWalletStore.set(activeAddress)
        } else if restored.isEmpty {
            activeWalletStore.clear()
        }

        return WalletConnectionPersistenceResult(
            persistedAddresses: restored,
            activeAddress: activeWalletStore.get()
        )
    }

    public func remove(address: String, chain: WalletChain) async throws {
        if let topic = try await topicStore.load(walletAddress: address) {
            try await connector.disconnect(sessionId: WalletSessionID(rawValue: topic.rawValue))
        }

        try await topicStore.delete(walletAddress: address)
        try await accountStore.deactivate(address: address, chain: chain, at: now())
        try await removalCleaner.cleanLocalData(for: address)

        if activeWalletStore.get()?.caseInsensitiveCompare(address) == .orderedSame {
            if let fallback = try await accountStore.mostRecentlyUsedActiveAddress(excluding: address) {
                activeWalletStore.set(fallback)
            } else {
                activeWalletStore.clear()
            }
        }
    }
}
