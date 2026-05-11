import Foundation

public enum UserDefaultsCodableStoreCorruptionPolicy: Sendable {
    case throwError
    case returnEmptyAndClear
}

public enum UserDefaultsCodableStoreError: Error, Equatable, Sendable {
    case corruptedPayload(key: String)
}

public struct UserDefaultsCodableStore<Record: Codable & Sendable> {
    private let userDefaults: UserDefaults
    private let key: String
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private let corruptionPolicy: UserDefaultsCodableStoreCorruptionPolicy

    public init(
        userDefaults: UserDefaults,
        key: String,
        encoder: JSONEncoder = JSONEncoder(),
        decoder: JSONDecoder = JSONDecoder(),
        corruptionPolicy: UserDefaultsCodableStoreCorruptionPolicy = .returnEmptyAndClear
    ) {
        self.userDefaults = userDefaults
        self.key = key
        self.encoder = encoder
        self.decoder = decoder
        self.corruptionPolicy = corruptionPolicy
    }

    public func load() throws -> [Record] {
        guard let data = userDefaults.data(forKey: key) else {
            return []
        }

        do {
            return try decoder.decode([Record].self, from: data)
        } catch {
            switch corruptionPolicy {
            case .throwError:
                throw UserDefaultsCodableStoreError.corruptedPayload(key: key)

            case .returnEmptyAndClear:
                userDefaults.removeObject(forKey: key)
                return []
            }
        }
    }

    public func save(_ records: [Record]) throws {
        let data = try encoder.encode(records)
        userDefaults.set(data, forKey: key)
    }

    public func clear() {
        userDefaults.removeObject(forKey: key)
    }
}
