import AuralisPrimaryModels

extension Chain {
    var supportsProviderKitEVMRPC: Bool {
        supportsProviderKitEVMChain
    }

    var supportsProviderKitERC20Holdings: Bool {
        supportsProviderKitEVMChain
    }

    private var supportsProviderKitEVMChain: Bool {
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
