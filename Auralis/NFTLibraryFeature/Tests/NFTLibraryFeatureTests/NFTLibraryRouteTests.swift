import AuralisPrimaryModels
import AuralisPrimaryPersistence
import NFTLibraryFeature
import Testing

struct NFTLibraryRouteTests {
    @Test("item route stores the NFT identifier")
    func itemRouteStoresIdentifier() {
        #expect(NFTLibraryRoute.item(id: "abc") == .item(id: "abc"))
    }

    @Test("collection route is hashable")
    func collectionRouteIsHashable() {
        let route = NFTLibraryRoute.collection(
            contractAddress: "0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
            title: "Moonpunks",
            chain: .ethMainnet
        )

        #expect(Set([route]).contains(route))
    }
}
