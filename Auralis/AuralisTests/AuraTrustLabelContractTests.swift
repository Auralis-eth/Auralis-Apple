@testable import Auralis
import Testing

@Suite
struct AuraTrustLabelContractTests {
    @Test("untrusted value kinds use specific trust-forward titles")
    func trustKindsUseSpecificTitles() {
        #expect(AuraUntrustedValueKind.metadata.title == "Untrusted metadata")
        #expect(AuraUntrustedValueKind.link.title == "Untrusted link")
        #expect(AuraUntrustedValueKind.scan.title == "Untrusted scan")
        #expect(AuraUntrustedValueKind.deepLink.title == "Untrusted deep link")
    }

    @Test("route errors only surface the deep-link trust label when raw URL input is present")
    func routeErrorsInferDeepLinkTrustOnlyWhenNeeded() {
        let routeErrorWithURL = AppRouteError(
            title: "Invalid Link",
            message: "The link could not be parsed.",
            urlString: "auralis://bad-link"
        )
        let routeErrorWithoutURL = AppRouteError(
            title: "NFT Not Found",
            message: "The requested NFT could not be resolved.",
            urlString: nil
        )

        #expect(routeErrorWithURL.trustLabelKind == .deepLink)
        #expect(routeErrorWithoutURL.trustLabelKind == nil)
    }
}
