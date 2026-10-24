import Foundation
import OperatorsFeature

/// Durable, identity-scoped configuration for the bounded on-chain watch operator.
@MainActor
public protocol OperatorWatchlistStoring: AnyObject {
    func load(identityID: String?) throws -> [WatchTarget]
    func save(_ targets: [WatchTarget], identityID: String?) throws
}

public enum OperatorWatchlistStoreError: LocalizedError, Equatable {
    case corruptedData
    case encodingFailed

    public var errorDescription: String? {
        switch self {
        case .corruptedData:
            return "Saved operator watch targets could not be read. The existing data was preserved."
        case .encodingFailed:
            return "Operator watch targets could not be encoded, so the change was not saved."
        }
    }
}

@MainActor
public final class UserDefaultsOperatorWatchlistStore: OperatorWatchlistStoring {
    private let defaults: UserDefaults
    private let keyPrefix: String

    public init(defaults: UserDefaults = .standard, keyPrefix: String = "missionControl.operatorWatchlist") {
        self.defaults = defaults
        self.keyPrefix = keyPrefix
    }

    public func load(identityID: String?) throws -> [WatchTarget] {
        guard let data = defaults.data(forKey: key(identityID: identityID)) else { return [] }
        do {
            return try JSONDecoder().decode([WatchTarget].self, from: data)
        } catch {
            throw OperatorWatchlistStoreError.corruptedData
        }
    }

    public func save(_ targets: [WatchTarget], identityID: String?) throws {
        let data: Data
        do {
            data = try JSONEncoder().encode(targets)
        } catch {
            throw OperatorWatchlistStoreError.encodingFailed
        }
        defaults.set(data, forKey: key(identityID: identityID))
    }

    private func key(identityID: String?) -> String {
        let scope = identityID?.lowercased() ?? "no-active-identity"
        return "\(keyPrefix).\(scope)"
    }
}

@MainActor
final class InMemoryOperatorWatchlistStore: OperatorWatchlistStoring {
    private var targetsByIdentity: [String: [WatchTarget]] = [:]

    func load(identityID: String?) -> [WatchTarget] {
        targetsByIdentity[identityID?.lowercased() ?? "no-active-identity"] ?? []
    }

    func save(_ targets: [WatchTarget], identityID: String?) {
        targetsByIdentity[identityID?.lowercased() ?? "no-active-identity"] = targets
    }
}
