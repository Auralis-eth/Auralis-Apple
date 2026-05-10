import AuralisPrimaryModels
import Foundation

public struct ProviderEndpointConfiguration: Equatable, Sendable {
    public let chain: Chain
    public let alchemyNFTBaseURL: URL?
    public let alchemyDataAPIBaseURL: URL?
    public let alchemyRPCURL: URL?

    public init(
        chain: Chain,
        alchemyNFTBaseURL: URL?,
        alchemyDataAPIBaseURL: URL?,
        alchemyRPCURL: URL?
    ) {
        self.chain = chain
        self.alchemyNFTBaseURL = alchemyNFTBaseURL
        self.alchemyDataAPIBaseURL = alchemyDataAPIBaseURL
        self.alchemyRPCURL = alchemyRPCURL
    }
}
