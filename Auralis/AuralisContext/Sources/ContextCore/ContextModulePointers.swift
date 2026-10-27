public struct ContextModulePointers: Equatable, Sendable {
    public let items: [ContextModulePointer]

    public init(items: [ContextModulePointer]) {
        self.items = items
    }
}
