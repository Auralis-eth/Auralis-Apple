@MainActor
struct HomeAssembly {
    func makePinnedItemsStore() -> HomePinnedItemsStore {
        HomePinnedItemsStore()
    }
}
