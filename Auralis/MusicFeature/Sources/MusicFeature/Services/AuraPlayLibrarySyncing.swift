import Foundation

public protocol AuraPlayLibrarySyncing: Sendable {
    func syncLibrary(in scope: AuraPlayLibraryScope, accountName: String?) async throws
}

public struct NoOpAuraPlayLibrarySyncService: AuraPlayLibrarySyncing {
    public init() {}

    public func syncLibrary(in scope: AuraPlayLibraryScope, accountName: String?) async throws {}
}
