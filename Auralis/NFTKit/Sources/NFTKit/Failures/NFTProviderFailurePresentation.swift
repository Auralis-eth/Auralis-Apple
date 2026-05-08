import AuralisPrimaryModels
import Foundation

public struct NFTProviderFailurePresentation: Equatable {
    public let mode: NFTProviderFailurePresentationMode
    public let title: String
    public let message: String
    public let systemImage: String
    public let isRetryable: Bool

    public init(
        mode: NFTProviderFailurePresentationMode,
        title: String,
        message: String,
        systemImage: String,
        isRetryable: Bool
    ) {
        self.mode = mode
        self.title = title
        self.message = message
        self.systemImage = systemImage
        self.isRetryable = isRetryable
    }
}
