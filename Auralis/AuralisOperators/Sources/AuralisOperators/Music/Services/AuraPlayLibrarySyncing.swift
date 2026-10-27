import AuralisPrimaryModels
import Foundation

public protocol AuraPlayLibrarySyncing: Sendable {
    func syncLibrary(in scope: AuraPlayLibraryScope, accountName: String?) async throws
}

@MainActor
public protocol AuraPlayNFTDiscoverySyncing: Sendable {
    func sync(walletAddress: String, chain: Chain) async throws
    func syncAll() async throws
    func syncAllIfNeeded() async throws
}

@MainActor
public protocol AuraPlaySyncProgressProviding: Sendable {
    var syncProgress: SyncProgress { get }
}

public struct NoOpAuraPlayLibrarySyncService: AuraPlayLibrarySyncing {
    public init() {}

    public func syncLibrary(in scope: AuraPlayLibraryScope, accountName: String?) async throws {}
}

public struct NoOpAuraPlayNFTDiscoverySyncService: AuraPlayNFTDiscoverySyncing {
    public init() {}

    public func sync(walletAddress: String, chain: Chain) async throws {}
    public func syncAll() async throws {}
    public func syncAllIfNeeded() async throws {}
}

public struct NoOpAuraPlaySyncProgressProvider: AuraPlaySyncProgressProviding {
    public init() {}

    public var syncProgress: SyncProgress { SyncProgress() }
}
