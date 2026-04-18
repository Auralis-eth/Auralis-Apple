import Foundation

struct ContextScope: Equatable, Sendable {
    let accountAddress: ContextField<String>
    let accountName: ContextField<String>
    let selectedChains: ContextField<[Chain]>
}
