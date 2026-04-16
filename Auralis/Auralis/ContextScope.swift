import Foundation

struct ContextScope: Equatable {
    let accountAddress: ContextField<String>
    let accountName: ContextField<String>
    let selectedChains: ContextField<[Chain]>
}
