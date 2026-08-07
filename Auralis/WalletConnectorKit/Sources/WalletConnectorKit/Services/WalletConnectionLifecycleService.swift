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

public enum WalletSessionOwnershipPolicy: Hashable, Codable, Sendable {
    case allowUnverified
    case requireVerified
}

public struct WalletConnectionPersistenceResult: Hashable, Sendable {
    public let persistedAddresses: [WalletSessionAddress]
    public let activeAddress: String?
    public let removedSessionTopics: [WalletSessionTopicRecord]
    public let unverifiedSessionTopics: [WalletSessionTopicRecord]

    public init(
        persistedAddresses: [WalletSessionAddress],
        activeAddress: String?,
        removedSessionTopics: [WalletSessionTopicRecord] = [],
        unverifiedSessionTopics: [WalletSessionTopicRecord] = []
    ) {
        self.persistedAddresses = persistedAddresses
        self.activeAddress = activeAddress
        self.removedSessionTopics = removedSessionTopics
        self.unverifiedSessionTopics = unverifiedSessionTopics
    }
}

public actor WalletConnectionLifecycleService {
    private let connector: any WalletConnector
    private let accountStore: any WalletAccountPersisting
    private let topicStore: any WalletSessionTopicStoring
    private let activeWalletStore: any ActiveWalletStoring
    private let metadataResolver: any WalletPostConnectionResolving
    private let removalCleaner: any WalletRemovalCleaning
    private let ownershipPolicy: WalletSessionOwnershipPolicy
    private let now: @Sendable () -> Date
    /// Optional sink for otherwise-silent restore hiccups — e.g. one persisted
    /// record whose per-record cleanup/rehydrate failed while the rest of the
    /// restore continued. Lets a host surface a partial restore instead of the
    /// failure being swallowed.
    private let onDiagnostic: (@Sendable (String) -> Void)?

    public init(
        connector: any WalletConnector,
        accountStore: any WalletAccountPersisting,
        topicStore: any WalletSessionTopicStoring,
        activeWalletStore: any ActiveWalletStoring,
        metadataResolver: any WalletPostConnectionResolving = NoOpWalletPostConnectionResolver(),
        removalCleaner: any WalletRemovalCleaning = NoOpWalletRemovalCleaner(),
        ownershipPolicy: WalletSessionOwnershipPolicy = .requireVerified,
        now: @escaping @Sendable () -> Date = Date.init,
        onDiagnostic: (@Sendable (String) -> Void)? = nil
    ) {
        self.connector = connector
        self.accountStore = accountStore
        self.topicStore = topicStore
        self.activeWalletStore = activeWalletStore
        self.metadataResolver = metadataResolver
        self.removalCleaner = removalCleaner
        self.ownershipPolicy = ownershipPolicy
        self.now = now
        self.onDiagnostic = onDiagnostic
    }

    @discardableResult
    public func persistApprovedSession(_ session: WalletConnectorSession) async throws -> WalletConnectionPersistenceResult {
        let addresses = WalletSessionAddressExtractor.extract(from: session)
        if ownershipPolicy == .requireVerified {
            try await verifyOwnershipIfNeeded(for: addresses, in: session)
        }

        let selectedAt = now()
        let previouslyActiveAddress = activeWalletStore.get()
        var upsertedAddresses: [WalletSessionAddress] = []
        var savedTopicAddresses: [WalletSessionAddress] = []
        // Ownership is proven here when the session already carries the flag or
        // when the strict policy just verified it (verifyOwnershipIfNeeded would
        // have thrown otherwise). Persisting it lets restore re-trust SDK sessions
        // whose vendor store cannot carry `addressVerified`.
        let ownershipProven = session.addressVerified || ownershipPolicy == .requireVerified

        do {
            for address in addresses {
                try await accountStore.upsert(address, selectedAt: selectedAt)
                upsertedAddresses.append(address)
                try await topicStore.save(topic: session.topic, walletAddress: address.account.address, chain: address.chain, verified: ownershipProven)
                savedTopicAddresses.append(address)
            }

            if let activeAddress = addresses.last?.account.address {
                activeWalletStore.set(activeAddress)
            }

            for address in addresses {
                await metadataResolver.refreshMetadata(for: address)
            }
        } catch {
            await rollbackPartialPersist(
                upsertedAddresses: upsertedAddresses,
                savedTopicAddresses: savedTopicAddresses,
                activeAddress: previouslyActiveAddress,
                at: selectedAt
            )
            throw error
        }

        return WalletConnectionPersistenceResult(
            persistedAddresses: addresses,
            activeAddress: addresses.last.map(\.account.address)
        )
    }

    public func restoreSavedSessions() async throws -> WalletConnectionPersistenceResult {
        let savedTopics = try await topicStore.loadAll()
        let liveSessions = try await connector.sessions()
        // A connector is an external boundary; two sessions sharing a topic would
        // trap `uniqueKeysWithValues`. Keep the first and drop duplicates instead.
        let sessionsByTopic = Dictionary(liveSessions.map { ($0.topic, $0) }, uniquingKeysWith: { first, _ in first })
        var restored: [WalletSessionAddress] = []
        var removedSessionTopics: [WalletSessionTopicRecord] = []
        var unverifiedSessionTopics: [WalletSessionTopicRecord] = []

        for savedTopic in savedTopics {
            // Isolate each record: a transient store error on one persisted topic
            // must not abort the whole restore (which would strand every later
            // record and leave the user apparently logged out from one flaky item).
            // The top-level `topicStore.loadAll()` above still fails closed — if the
            // index itself is unreadable we do not wipe — but a per-record cleanup or
            // rehydrate failure is logged and skipped so the rest still restores.
            do {
                guard let session = sessionsByTopic[savedTopic.topic], !session.isExpired else {
                    let chain = savedTopic.chain
                        ?? Self.chain(forExpiredSession: sessionsByTopic[savedTopic.topic], address: savedTopic.address)
                        ?? Self.chain(forSavedAddress: savedTopic.address)
                    try await topicStore.delete(walletAddress: savedTopic.address, chain: savedTopic.chain)
                    try await accountStore.deactivate(address: savedTopic.address, chain: chain, at: now())
                    removedSessionTopics.append(savedTopic)
                    continue
                }

                // An SDK connector (Reown/Coinbase) restores sessions with
                // `addressVerified == false` because its vendor store cannot carry the
                // flag; merge the connect-time proof persisted on the topic record so a
                // previously verified wallet is not dropped from the active set on every
                // cold launch. Legacy records default `verified` to false (fail-closed).
                //
                // The topic record's `verified` bit is written at connect and is NOT
                // reset when a wallet later swaps accounts via `wc_sessionUpdate`. For
                // the custom IRN transport the *session's* `addressVerified` is
                // authoritative (it is cleared on an account-changing update), so
                // OR-ing in the stale topic bit there would re-trust the swapped
                // accounts across relaunch — an ownership bypass. Only fall back to the
                // topic bit for families whose session flag is non-authoritative.
                let ownershipProven = connector.runtimeFamily.restoredVerificationIsAuthoritative
                    ? session.addressVerified
                    : (session.addressVerified || savedTopic.verified)
                guard ownershipPolicy == .allowUnverified || ownershipProven else {
                    unverifiedSessionTopics.append(savedTopic)
                    continue
                }

                let sessionAddresses = WalletSessionAddressExtractor.extract(from: session)
                    .filter {
                        Self.matchesStoredAddress($0.account.address, savedTopic.address, chain: $0.chain)
                            && (savedTopic.chain == nil || savedTopic.chain == $0.chain)
                    }
                for address in sessionAddresses {
                    try await accountStore.upsert(address, selectedAt: now())
                    await metadataResolver.refreshMetadata(for: address)
                }
                restored.append(contentsOf: sessionAddresses)
            } catch {
                onDiagnostic?("WalletConnect restore: skipped topic record for \(savedTopic.address) after a store error (\(error.localizedDescription)); remaining sessions were still restored.")
                continue
            }
        }

        // Preserve the user's previously-active wallet across a cold launch when it
        // is still among the restored addresses. `restored` is ordered by the topic
        // store's account-key sort (not by selection recency), so blindly setting
        // `restored.last` silently switched the active wallet to an arbitrary,
        // address-lexicographic pick on every relaunch for any user with more than
        // one connected wallet. Only fall back to the most-recent restored address
        // when the prior active wallet is genuinely gone, and clear when nothing
        // restored (unchanged behavior).
        let previouslyActive = activeWalletStore.get()
        if let previouslyActive,
           restored.contains(where: { Self.matchesStoredAddress($0.account.address, previouslyActive, chain: $0.chain) }) {
            activeWalletStore.set(previouslyActive)
        } else if let fallbackActive = restored.last?.account.address {
            activeWalletStore.set(fallbackActive)
        } else {
            activeWalletStore.clear()
        }

        return WalletConnectionPersistenceResult(
            persistedAddresses: restored,
            activeAddress: activeWalletStore.get(),
            removedSessionTopics: removedSessionTopics,
            unverifiedSessionTopics: unverifiedSessionTopics
        )
    }

    private func verifyOwnershipIfNeeded(for addresses: [WalletSessionAddress], in session: WalletConnectorSession) async throws {
        guard !session.addressVerified else { return }

        // Verify each distinct signing key once, not each (chain, address) pair.
        // A wallet commonly surfaces the *same* address across several chains in a
        // namespace (e.g. one EVM address on eip155:1/137/8453) — those share a
        // private key, so proving one proves all and one signature prompt is
        // enough. A genuinely distinct account is still challenged on its own.
        var verifiedKeys = Set<String>()
        for address in addresses {
            let keyIdentity = Self.signingKeyIdentity(address)
            guard verifiedKeys.insert(keyIdentity).inserted else { continue }
            let verified = try await connector.verifyOwnership(
                of: address.account.address,
                chain: address.chain,
                in: session.id,
                statement: "Verify wallet ownership before saving this wallet.",
                expiryDate: now().addingTimeInterval(300)
            )
            guard verified else {
                throw WalletConnectionError.unavailable("Wallet session ownership could not be verified for \(address.account.address).")
            }
        }
    }

    /// A signing key's identity within a namespace: EVM addresses are folded to
    /// lowercase (checksum-insensitive), other namespaces compared verbatim.
    private static func signingKeyIdentity(_ address: WalletSessionAddress) -> String {
        let namespace = address.chain.namespace
        let account = namespace == "eip155" ? address.account.address.lowercased() : address.account.address
        return "\(namespace):\(account)"
    }

    private func rollbackPartialPersist(
        upsertedAddresses: [WalletSessionAddress],
        savedTopicAddresses: [WalletSessionAddress],
        activeAddress: String?,
        at date: Date
    ) async {
        for address in savedTopicAddresses.reversed() {
            try? await topicStore.delete(walletAddress: address.account.address, chain: address.chain)
        }

        for address in upsertedAddresses.reversed() {
            try? await accountStore.deactivate(address: address.account.address, chain: address.chain, at: date)
        }

        if let activeAddress {
            activeWalletStore.set(activeAddress)
        } else {
            activeWalletStore.clear()
        }
    }

    public func remove(address: String, chain: WalletChain) async throws {
        // The keychain topic store keys records by exact address, but EVM
        // addresses vary in case (checksummed vs lowercase). Resolve the stored
        // record with the same case-insensitive matching used elsewhere so a
        // differently-cased address still tears down the relay session and
        // clears the keychain record instead of orphaning it.
        let storedRecord = try await topicStore.loadAll().first {
            Self.matchesStoredAddress($0.address, address, chain: chain)
                && ($0.chain == nil || $0.chain == chain)
        }

        if let storedRecord {
            try await connector.disconnect(sessionId: WalletSessionID(rawValue: storedRecord.topic.rawValue))
            try await topicStore.delete(walletAddress: storedRecord.address, chain: storedRecord.chain)
        }

        try await accountStore.deactivate(address: address, chain: chain, at: now())
        try await removalCleaner.cleanLocalData(for: address)

        if activeWalletStore.get().map({ Self.matchesStoredAddress($0, address, chain: chain) }) == true {
            if let fallback = try await accountStore.mostRecentlyUsedActiveAddress(excluding: address) {
                activeWalletStore.set(fallback)
            } else {
                activeWalletStore.clear()
            }
        }
    }

    private static func matchesStoredAddress(_ lhs: String, _ rhs: String, chain: WalletChain) -> Bool {
        if chain.namespace == "eip155" {
            return lhs.caseInsensitiveCompare(rhs) == .orderedSame
        }
        return lhs == rhs
    }

    private static func chain(forExpiredSession session: WalletConnectorSession?, address: String) -> WalletChain? {
        guard let session else { return nil }
        return WalletSessionAddressExtractor.extract(from: session)
            .first { matchesStoredAddress($0.account.address, address, chain: $0.chain) }?
            .chain
    }

    private static func chain(forSavedAddress address: String) -> WalletChain {
        if address.hasPrefix("0x") {
            return .ethereum
        }
        return .solana
    }
}
