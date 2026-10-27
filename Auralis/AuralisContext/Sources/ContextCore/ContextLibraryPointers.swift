public struct ContextLibraryPointers: Equatable, Sendable {
    public let trackedNFTCount: ContextField<Int>
    public let musicCollectionCount: ContextField<Int>
    public let receiptCount: ContextField<Int>

    public init(
        trackedNFTCount: ContextField<Int>,
        musicCollectionCount: ContextField<Int>,
        receiptCount: ContextField<Int>
    ) {
        self.trackedNFTCount = trackedNFTCount
        self.musicCollectionCount = musicCollectionCount
        self.receiptCount = receiptCount
    }
}
