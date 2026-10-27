/// Human-readable metadata for a canonical capability.
public struct CapabilityDescriptor: Equatable, Sendable {
    public let id: CapabilityID
    public let category: CapabilityCategory
    public let title: String
    public let summary: String

    public init(
        id: CapabilityID,
        category: CapabilityCategory,
        title: String,
        summary: String
    ) {
        self.id = id
        self.category = category
        self.title = title
        self.summary = summary
    }
}
