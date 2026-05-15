import Foundation

@MainActor
public protocol AuraPlayLibrarySyncing {
    func syncLibrary(in scope: AuraPlayLibraryScope, accountName: String?) async throws
}

@MainActor
public struct NoOpAuraPlayLibrarySyncService: AuraPlayLibrarySyncing {
    public init() {}

    public func syncLibrary(in scope: AuraPlayLibraryScope, accountName: String?) async throws {}
}
