import AuralisPrimaryModels

public extension Chain {
    var supportsEVMRPC: Bool {
        switch self {
        case .ethMainnet,
             .ethSepoliaTestnet,
             .baseMainnet,
             .baseSepoliaTestnet,
             .arbMainnet,
             .arbSepoliaTestnet,
             .arbNovaMainnet,
             .optMainnet,
             .optSepoliaTestnet,
             .polygonMainnet,
             .polygonAmoyTestnet,
             .worldchainMainnet,
             .worldchainSepoliaTestnet,
             .shapeMainnet,
             .shapeSepoliaTestnet,
             .inkMainnet,
             .inkSepoliaTestnet,
             .unichainMainnet,
             .unichainSepoliaTestnet,
             .soneiumMainnet,
             .soneiumMinatoTestnet,
             .berachainMainnet,
             .zoraMainnet,
             .zoraSepoliaTestnet,
             .polynomialMainnet,
             .polynomialSepoliaTestnet:
            return true
        case .solanaMainnet, .solanaDevnetTestnet:
            return false
        }
    }

    var supportsERC20Holdings: Bool {
        switch self {
        case .ethMainnet,
             .ethSepoliaTestnet,
             .baseMainnet,
             .baseSepoliaTestnet,
             .arbMainnet,
             .arbSepoliaTestnet,
             .arbNovaMainnet,
             .optMainnet,
             .optSepoliaTestnet,
             .polygonMainnet,
             .polygonAmoyTestnet,
             .worldchainMainnet,
             .worldchainSepoliaTestnet,
             .shapeMainnet,
             .shapeSepoliaTestnet,
             .inkMainnet,
             .inkSepoliaTestnet,
             .unichainMainnet,
             .unichainSepoliaTestnet,
             .soneiumMainnet,
             .soneiumMinatoTestnet,
             .berachainMainnet,
             .zoraMainnet,
             .zoraSepoliaTestnet,
             .polynomialMainnet,
             .polynomialSepoliaTestnet:
            return true
        case .solanaMainnet, .solanaDevnetTestnet:
            return false
        }
    }
}
