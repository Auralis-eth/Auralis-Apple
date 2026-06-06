import Foundation
import OperatorCore
import Testing

struct OperatorCoreTests {
    @Test("external link policy allows approved HTTPS routes")
    func externalLinkPolicyAllowsApprovedRoutes() throws {
        let url = try #require(URL(string: "https://opensea.io/assets/ethereum/0xabc/1"))
        let result = ExternalLinkPolicy().validate(
            ExternalLinkCandidateDestination(label: "OpenSea", url: url)
        )

        switch result {
        case .success(let destination):
            #expect(destination.hostDisplay == "opensea.io")
            #expect(destination.pathDisplay == "/assets/ethereum/0xabc/1")
            #expect(destination.routeTypeDisplay == "Marketplace")
        case .failure(let failure):
            Issue.record("Expected approved route, got \(failure).")
        }
    }

    @Test("external link policy rejects insecure or unsupported destinations")
    func externalLinkPolicyRejectsUnsupportedDestinations() throws {
        let insecure = try #require(URL(string: "http://opensea.io/assets/ethereum/0xabc/1"))
        let unsupportedHost = try #require(URL(string: "https://example.com/assets/1"))

        #expect(
            ExternalLinkPolicy().validate(.init(label: "Insecure", url: insecure)) ==
                .failure(.invalidScheme("http"))
        )
        #expect(
            ExternalLinkPolicy().validate(.init(label: "Unsupported", url: unsupportedHost)) ==
                .failure(.unsupportedHost("example.com"))
        )
    }
}
