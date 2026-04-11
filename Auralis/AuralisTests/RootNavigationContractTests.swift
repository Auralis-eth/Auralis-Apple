import Testing
@testable import Auralis

@Suite
struct RootNavigationContractTests {
    @Test("root router exposes receipts and search as first-class shell destinations")
    func rootRouterSupportsReceiptsAndSearchTabs() {
        let router = AppRouter()

        router.showReceipts()
        #expect(router.selectedTab == .receipts)
        #expect(router.currentRouteDepth == 0)
        #expect(router.selectedTabName == "receipts")

        router.showSearch()
        #expect(router.selectedTab == .search)
        #expect(router.currentRouteDepth == 0)
        #expect(router.selectedTabName == "search")
    }

    @Test("receipt detail routing stays on the receipts root and replaces stale detail state")
    func receiptRoutingUsesReceiptsRootOwnership() {
        let router = AppRouter()

        router.showReceipt(id: "receipt-1")
        #expect(router.selectedTab == .receipts)
        #expect(router.receiptsPath == [ReceiptRoute(id: "receipt-1")])
        #expect(router.currentRouteDepth == 1)

        router.showReceipt(id: "receipt-2")
        #expect(router.selectedTab == .receipts)
        #expect(router.receiptsPath == [ReceiptRoute(id: "receipt-2")])
        #expect(router.currentRouteDepth == 1)
    }

    @Test("route errors retain raw URL input only when the shell received an untrusted link")
    func routeErrorTrustLabelingMatchesInputContract() {
        let trusted = AppRouteError(
            title: "NFT Not Found",
            message: "The requested NFT could not be resolved.",
            urlString: nil
        )
        let untrusted = AppRouteError(
            title: "Invalid Link",
            message: "The link could not be parsed.",
            urlString: "auralis://bad-link"
        )

        #expect(trusted.trustLabelKind == nil)
        #expect(untrusted.trustLabelKind == .deepLink)
    }
}
