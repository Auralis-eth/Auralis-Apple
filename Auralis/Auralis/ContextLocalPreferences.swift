import Foundation

struct ContextLocalPreferences: Equatable, Sendable {
    let prefersDemoData: ContextField<Bool>
    let pinnedItemCount: ContextField<Int>
}
