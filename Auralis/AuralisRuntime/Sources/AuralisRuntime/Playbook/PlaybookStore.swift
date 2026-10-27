import Foundation

/// A library operation that could not be applied.
public enum PlaybookStoreError: Error, Equatable, Sendable, LocalizedError {
    /// No playbook is stored under this ID.
    ///
    /// Raised rather than returning quietly because every caller of
    /// ``PlaybookStore/setInstallState(id:to:)`` is a user-facing install/pause control. A silent
    /// no-op let the Routine Manager report a playbook paused while the store still held it
    /// installed — and with two hosts over one library, the host handling the tap can legitimately
    /// not know the ID at all, which is precisely the case that must surface rather than succeed.
    case notFound(id: String)

    public var errorDescription: String? {
        switch self {
        case let .notFound(id):
            return "No playbook is installed under the ID \(id)."
        }
    }
}

/// The playbook library surface: browse, install/pause, inspect. (P1-502/504)
public protocol PlaybookStore: Sendable {
    func all() async throws -> [Playbook]
    func playbook(id: String) async throws -> Playbook?
    func playbooks(inState state: PlaybookInstallState) async throws -> [Playbook]
    func upsert(_ playbook: Playbook) async throws
    /// Moves a stored playbook to `state`.
    ///
    /// - Throws: ``PlaybookStoreError/notFound(id:)`` when no playbook is stored under `id`.
    func setInstallState(id: String, to state: PlaybookInstallState) async throws
}

/// In-memory playbook library seeded with the caller's playbooks.
public actor InMemoryPlaybookStore: PlaybookStore {
    private var playbooks: [String: Playbook]

    /// Seeds the library, keeping the last playbook declared under any repeated ID.
    ///
    /// Last-wins rather than `Dictionary(uniqueKeysWithValues:)`, which *traps* on a repeated key.
    /// This is the store `RuntimeHost` falls back to when no persistent one is injected, seeded from
    /// `SystemPlaybooks.all` — so a single copy-pasted ID in that catalogue would have turned every
    /// such bootstrap into a launch crash. Last-wins also matches ``upsert(_:)``, which is the other
    /// way two declarations of one ID resolve here.
    public init(seed: [Playbook] = []) {
        playbooks = Dictionary(seed.map { ($0.id, $0) }, uniquingKeysWith: { _, last in last })
    }

    public func all() -> [Playbook] {
        playbooks.values.sorted { $0.name < $1.name }
    }

    public func playbook(id: String) -> Playbook? {
        playbooks[id]
    }

    public func playbooks(inState state: PlaybookInstallState) -> [Playbook] {
        all().filter { $0.installState == state }
    }

    public func upsert(_ playbook: Playbook) {
        playbooks[playbook.id] = playbook
    }

    public func setInstallState(id: String, to state: PlaybookInstallState) throws {
        guard var playbook = playbooks[id] else { throw PlaybookStoreError.notFound(id: id) }
        playbook.installState = state
        playbooks[id] = playbook
    }
}
