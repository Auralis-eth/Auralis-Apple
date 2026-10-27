import Foundation
import SwiftData

@Model
public final class AuraPlayMediaEmbedding {
    @Attribute(.unique) public var mediaItemID: String
    @Attribute(.externalStorage) public var vectorData: Data?
    public var embeddingModelVersion: String
    public var sourceFingerprint: String
    public var indexedAt: Date

    public init(
        mediaItemID: String,
        vectorData: Data?,
        embeddingModelVersion: String,
        sourceFingerprint: String,
        indexedAt: Date = .now
    ) {
        self.mediaItemID = mediaItemID
        self.vectorData = vectorData
        self.embeddingModelVersion = embeddingModelVersion
        self.sourceFingerprint = sourceFingerprint
        self.indexedAt = indexedAt
    }
}
