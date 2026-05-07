import AuralisPrimaryModels
import web3

extension Chain {
    var web3EthereumNetwork: EthereumNetwork {
        EthereumNetwork.fromString("\(chainId)")
    }
}
