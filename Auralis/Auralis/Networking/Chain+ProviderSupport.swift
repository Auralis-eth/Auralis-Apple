import Foundation

extension Chain {
    var supportsEVMRPC: Bool {
        switch self {
        case .solanaMainnet, .solanaDevnetTestnet:
            return false
        default:
            return true
        }
    }

    var supportsERC20Holdings: Bool {
        switch self {
        case .solanaMainnet, .solanaDevnetTestnet:
            return false
        default:
            return true
        }
    }
}
