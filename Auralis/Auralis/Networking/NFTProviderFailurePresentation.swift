import Foundation

struct NFTProviderFailurePresentation: Equatable {
    let mode: NFTProviderFailurePresentationMode
    let title: String
    let message: String
    let systemImage: String
    let isRetryable: Bool
}
