public actor OperatorManifestRegistry {
    private var manifests: [String: OperatorManifest] = [:]

    public init() {}

    @discardableResult
    public func register(_ manifest: OperatorManifest) -> Bool {
        guard manifest.definitionProblems.isEmpty else { return false }
        if let existing = manifests[manifest.id] { return existing == manifest }
        manifests[manifest.id] = manifest
        return true
    }

    public func manifest(id: String) -> OperatorManifest? {
        manifests[id]
    }

    public var all: [OperatorManifest] {
        manifests.values.sorted { $0.id < $1.id }
    }
}
