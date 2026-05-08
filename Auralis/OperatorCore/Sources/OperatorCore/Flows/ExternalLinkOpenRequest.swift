import AuralisPrimaryModels
import Foundation

public struct ExternalLinkOpenRequest: Equatable, Sendable {
    public let label: String
    public let url: URL
    public let surface: String
    public let accountAddress: String?
    public let chain: Chain?
    public let provenance: ExternalLinkOpenProvenance

    public init(
        label: String,
        url: URL,
        surface: String,
        accountAddress: String? = nil,
        chain: Chain? = nil,
        provenance: ExternalLinkOpenProvenance = .userConfirmedTap
    ) {
        self.label = label
        self.url = url
        self.surface = surface
        self.accountAddress = accountAddress
        self.chain = chain
        self.provenance = provenance
    }
}
