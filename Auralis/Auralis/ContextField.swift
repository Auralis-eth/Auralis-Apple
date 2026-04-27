import Foundation

struct ContextField<Value: Equatable & Sendable>: Equatable, Sendable {
    let value: Value?
    let provenance: ContextProvenance
    let updatedAt: Date?

    init(
        _ value: Value?,
        provenance: ContextProvenance,
        updatedAt: Date? = nil
    ) {
        self.value = value
        self.provenance = provenance
        self.updatedAt = updatedAt
    }
}
