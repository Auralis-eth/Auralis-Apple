import Foundation

public struct ContextField<Value: Equatable & Sendable>: Equatable, Sendable {
    public let value: Value?
    public let provenance: ContextProvenance
    public let updatedAt: Date?

    public init(
        _ value: Value?,
        provenance: ContextProvenance,
        updatedAt: Date? = nil
    ) {
        self.value = value
        self.provenance = provenance
        self.updatedAt = updatedAt
    }
}
