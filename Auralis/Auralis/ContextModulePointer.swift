import Foundation

struct ContextModulePointer: Equatable {
    let routeID: String
    let title: String
    let priority: ContextModulePriority
    let isPinned: Bool
    let isMounted: Bool
}
