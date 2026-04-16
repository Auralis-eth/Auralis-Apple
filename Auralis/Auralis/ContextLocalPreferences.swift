import Foundation

struct ContextLocalPreferences: Equatable {
    let prefersDemoData: ContextField<Bool>
    let pinnedItemCount: ContextField<Int>
}
