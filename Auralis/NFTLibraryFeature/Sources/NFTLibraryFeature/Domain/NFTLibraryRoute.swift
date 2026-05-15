import AuralisPrimaryModels

public enum NFTLibraryRoute: Hashable, Sendable {
    case item(id: String)
    case collection(contractAddress: String?, title: String, chain: Chain)
}
