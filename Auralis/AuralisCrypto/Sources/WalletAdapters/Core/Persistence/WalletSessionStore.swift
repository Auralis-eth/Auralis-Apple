import Foundation

public struct WalletSessionRecord: Hashable, Codable, Sendable {
    public let session: WalletConnectorSession
    public let savedAt: Date

    public init(session: WalletConnectorSession, savedAt: Date = Date()) {
        self.session = session
        self.savedAt = savedAt
    }
}

public protocol WalletSessionStore: Sendable {
    func save(_ record: WalletSessionRecord) async throws
    func load(sessionID: WalletSessionID) async throws -> WalletSessionRecord?
    func loadAll() async throws -> [WalletSessionRecord]
    func delete(sessionID: WalletSessionID) async throws
}

public actor InMemoryWalletSessionStore: WalletSessionStore {
    private var records: [WalletSessionID: WalletSessionRecord] = [:]

    public init(records: [WalletSessionRecord] = []) {
        self.records = Dictionary(uniqueKeysWithValues: records.map { ($0.session.id, $0) })
    }

    public func save(_ record: WalletSessionRecord) {
        records[record.session.id] = record
    }

    public func load(sessionID: WalletSessionID) -> WalletSessionRecord? {
        records[sessionID]
    }

    public func loadAll() -> [WalletSessionRecord] {
        records.values.sorted { $0.savedAt < $1.savedAt }
    }

    public func delete(sessionID: WalletSessionID) {
        records.removeValue(forKey: sessionID)
    }
}
