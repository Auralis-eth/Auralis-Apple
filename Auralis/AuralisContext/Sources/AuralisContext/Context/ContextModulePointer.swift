public struct ContextModulePointer: Equatable, Sendable {
    public let routeID: String
    public let title: String
    public let priority: ContextModulePriority
    public let isPinned: Bool
    public let isMounted: Bool

    public init(
        routeID: String,
        title: String,
        priority: ContextModulePriority,
        isPinned: Bool,
        isMounted: Bool
    ) {
        self.routeID = routeID
        self.title = title
        self.priority = priority
        self.isPinned = isPinned
        self.isMounted = isMounted
    }
}
