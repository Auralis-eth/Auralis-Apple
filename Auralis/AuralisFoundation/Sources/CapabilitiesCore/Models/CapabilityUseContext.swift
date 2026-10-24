/// Optional context describing where a capability is being used.
public struct CapabilityUseContext: Equatable, Sendable {
    public let surface: String?
    public let operation: String?

    public init(surface: String? = nil, operation: String? = nil) {
        self.surface = surface
        self.operation = operation
    }
}
