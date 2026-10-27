public struct ContextLocalPreferences: Equatable, Sendable {
    public let prefersDemoData: ContextField<Bool>
    public let pinnedItemCount: ContextField<Int>

    public init(
        prefersDemoData: ContextField<Bool>,
        pinnedItemCount: ContextField<Int>
    ) {
        self.prefersDemoData = prefersDemoData
        self.pinnedItemCount = pinnedItemCount
    }
}
