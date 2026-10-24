@testable import Auralis
import Foundation
import SwiftData
import Testing

/// The background refresh handler's container lifetime.
///
/// `RuntimeAssembly.sharedHost` memoizes hosts on `ObjectIdentifier(modelContext.container)` and
/// never evicts, so *where the background task's container comes from* decides whether this app
/// holds two runtime hosts for its lifetime or one more on every refresh.
///
/// Everything here runs against an **in-memory** store. The first version of this suite opened the
/// real primary store, which contended with the rest of the app test plan under its parallel
/// simulator clones and failed the clone — passing in isolation and red in the full plan.
@Suite("RuntimeBackgroundScheduler container lifetime")
@MainActor
struct RuntimeBackgroundSchedulerTests {
    private func makeInMemoryContainer() throws -> ModelContainer {
        try ModelContainer(
            for: PrimaryStoreSchema.schema,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        )
    }

    /// The fix, stated as the property that actually matters: the store is opened **once**.
    /// Pre-fix, `runInBackground()` called `ModelContainer(for:)` inline on every invocation, so
    /// this counter reached the number of refreshes and each one minted another `RuntimeHost`.
    @Test("the background container is opened once and reused")
    func backgroundContainerIsOpenedOnce() throws {
        RuntimeBackgroundScheduler.resetBackgroundStateForTesting()
        defer { RuntimeBackgroundScheduler.resetBackgroundStateForTesting() }

        var opens = 0
        let factory = {
            opens += 1
            return try self.makeInMemoryContainer()
        }

        let first = try #require(RuntimeBackgroundScheduler.resolveBackgroundContainer(makeContainer: factory))
        let second = try #require(RuntimeBackgroundScheduler.resolveBackgroundContainer(makeContainer: factory))
        let third = try #require(RuntimeBackgroundScheduler.resolveBackgroundContainer(makeContainer: factory))

        #expect(opens == 1)
        #expect(first === second)
        #expect(second === third)
    }

    /// A failure to open must not be cached — the usual causes (locked device under data
    /// protection, storage pressure) clear on their own, and caching `nil` would disable background
    /// routines for the rest of the process.
    @Test("a failed open is retried rather than cached")
    func failedOpenIsRetried() throws {
        RuntimeBackgroundScheduler.resetBackgroundStateForTesting()
        defer { RuntimeBackgroundScheduler.resetBackgroundStateForTesting() }

        struct OpenFailure: Error { }
        var shouldFail = true
        let factory = { () throws -> ModelContainer in
            if shouldFail { throw OpenFailure() }
            return try self.makeInMemoryContainer()
        }

        #expect(RuntimeBackgroundScheduler.resolveBackgroundContainer(makeContainer: factory) == nil)

        shouldFail = false
        #expect(RuntimeBackgroundScheduler.resolveBackgroundContainer(makeContainer: factory) != nil)
    }

    /// Why the per-call container was not merely wasteful. This pins the mechanism the fix depends
    /// on: two separately-opened containers are distinct objects, so keying a host cache on
    /// container identity makes a freshly-opened container a guaranteed cache miss — and therefore
    /// a guaranteed additional `RuntimeHost`, retained for the life of the process.
    @Test("separately-opened containers are distinct objects, so each would miss the host cache")
    func separatelyOpenedContainersAreDistinctObjects() throws {
        let first = try makeInMemoryContainer()
        let second = try makeInMemoryContainer()

        #expect(ObjectIdentifier(first) != ObjectIdentifier(second))
    }

    /// The property the memoized container buys: every `ModelContext` over one container keys to
    /// the same host, so repeated refreshes reuse the host they built the first time.
    @Test("contexts over one container share a cache key")
    func contextsOverOneContainerShareACacheKey() throws {
        let container = try makeInMemoryContainer()

        #expect(ObjectIdentifier(ModelContext(container).container)
            == ObjectIdentifier(ModelContext(container).container))
    }
}
