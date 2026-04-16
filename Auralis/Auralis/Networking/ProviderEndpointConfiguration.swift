import Foundation

struct ProviderEndpointConfiguration: Equatable {
    let chain: Chain
    let alchemyNFTBaseURL: URL?
    let alchemyDataAPIBaseURL: URL?
    let alchemyRPCURL: URL?
}
