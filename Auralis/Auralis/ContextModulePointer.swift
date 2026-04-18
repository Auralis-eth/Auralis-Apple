import Foundation

struct ContextModulePointer: Equatable, Sendable {
    let routeID: String
    let title: String
    let priority: ContextModulePriority
    let isPinned: Bool
    let isMounted: Bool
}
