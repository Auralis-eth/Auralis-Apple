public struct ContextScope: Equatable, Sendable {
    public let accountAddress: ContextField<String>
    public let accountName: ContextField<String>
    public let selectedChains: ContextField<[ContextChainReference]>

    public init(
        accountAddress: ContextField<String>,
        accountName: ContextField<String>,
        selectedChains: ContextField<[ContextChainReference]>
    ) {
        self.accountAddress = accountAddress
        self.accountName = accountName
        self.selectedChains = selectedChains
    }
}
