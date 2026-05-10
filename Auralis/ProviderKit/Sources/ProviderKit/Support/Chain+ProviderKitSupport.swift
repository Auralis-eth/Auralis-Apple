import AuralisPrimaryModels

extension Chain {
    var supportsProviderKitEVMRPC: Bool {
        switch self {
        case .solanaMainnet, .solanaDevnetTestnet:
            return false
        default:
            return true
        }
    }
}
