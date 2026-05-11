import Foundation
import Testing
import UserDefaultsAdapters

@Suite
struct UserDefaultsCodableStoreTests {
    private struct Record: Codable, Equatable, Sendable {
        let id: String
        let count: Int
    }

    @Test("codable store saves and loads records")
    func saveAndLoadRecords() throws {
        let defaults = try makeDefaults()
        let store = UserDefaultsCodableStore<Record>(
            userDefaults: defaults,
            key: "records"
        )

        let records = [
            Record(id: "first", count: 1),
            Record(id: "second", count: 2),
        ]

        try store.save(records)

        #expect(try store.load() == records)
    }

    @Test("codable store returns an empty array for a missing key")
    func missingKeyReturnsEmptyArray() throws {
        let defaults = try makeDefaults()
        let store = UserDefaultsCodableStore<Record>(
            userDefaults: defaults,
            key: "records"
        )

        #expect(try store.load().isEmpty)
    }

    @Test("codable store clear removes stored data")
    func clearRemovesStoredData() throws {
        let defaults = try makeDefaults()
        let store = UserDefaultsCodableStore<Record>(
            userDefaults: defaults,
            key: "records"
        )

        try store.save([Record(id: "first", count: 1)])
        store.clear()

        #expect(defaults.data(forKey: "records") == nil)
        #expect(try store.load().isEmpty)
    }

    @Test("codable store throws for corrupt payloads when configured")
    func corruptPayloadThrowsWhenConfigured() throws {
        let defaults = try makeDefaults()
        defaults.set(Data("not-json".utf8), forKey: "records")

        let store = UserDefaultsCodableStore<Record>(
            userDefaults: defaults,
            key: "records",
            corruptionPolicy: .throwError
        )

        #expect(throws: UserDefaultsCodableStoreError.corruptedPayload(key: "records")) {
            try store.load()
        }
        #expect(defaults.data(forKey: "records") == Data("not-json".utf8))
    }

    @Test("codable store clears corrupt payloads when configured")
    func corruptPayloadReturnsEmptyAndClearsWhenConfigured() throws {
        let defaults = try makeDefaults()
        defaults.set(Data("not-json".utf8), forKey: "records")

        let store = UserDefaultsCodableStore<Record>(
            userDefaults: defaults,
            key: "records",
            corruptionPolicy: .returnEmptyAndClear
        )

        #expect(try store.load().isEmpty)
        #expect(defaults.data(forKey: "records") == nil)
    }

    private func makeDefaults() throws -> UserDefaults {
        let suiteName = "UserDefaultsCodableStoreTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }
}
