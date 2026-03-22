import Foundation

enum ProviderAbstractionError: LocalizedError, Equatable {
    case missingAPIKey(Secrets.APIKeyProvider)
    case unsupportedChain(Chain)
    case invalidURL
    case invalidResponse
    case invalidBalancePayload

    var errorDescription: String? {
        switch self {
        case .missingAPIKey(let provider):
            return "Missing API key for \(provider.rawValue)."
        case .unsupportedChain(let chain):
            return "Chain \(chain.rawValue) is not supported by this provider."
        case .invalidURL:
            return "Provider URL configuration is invalid."
        case .invalidResponse:
            return "Provider returned an invalid response."
        case .invalidBalancePayload:
            return "Provider returned an invalid native balance payload."
        }
    }
}

struct ProviderEndpointConfiguration: Equatable {
    let chain: Chain
    let alchemyNFTBaseURL: URL?
    let alchemyRPCURL: URL?
    let infuraGasURL: URL?
}

protocol ProviderConfigurationResolving {
    func configuration(for chain: Chain) throws -> ProviderEndpointConfiguration
}

struct LiveProviderConfigurationResolver: ProviderConfigurationResolving {
    private let keyProvider: (Secrets.APIKeyProvider) -> String?

    init(
        keyProvider: @escaping (Secrets.APIKeyProvider) -> String? = { Secrets.apiKeyOrNil($0) }
    ) {
        self.keyProvider = keyProvider
    }

    func configuration(for chain: Chain) throws -> ProviderEndpointConfiguration {
        let alchemyKey = keyProvider(.alchemy)
        let infuraKey = keyProvider(.infura)

        let alchemyNFTBaseURL = try alchemyKey.flatMap {
            try Self.url("https://\(chain.rawValue).g.alchemy.com/nft/v3/\($0)")
        }
        let alchemyRPCURL = try alchemyKey.flatMap {
            try Self.url("https://\(chain.rawValue).g.alchemy.com/v2/\($0)")
        }
        let infuraGasURL = try infuraKey.flatMap {
            try Self.url("https://gas.api.infura.io/v3/\($0)/networks/\(chain.chainId)/suggestedGasFees")
        }

        return ProviderEndpointConfiguration(
            chain: chain,
            alchemyNFTBaseURL: alchemyNFTBaseURL,
            alchemyRPCURL: chain.supportsEVMRPC ? alchemyRPCURL : nil,
            infuraGasURL: chain.supportsInfuraGas ? infuraGasURL : nil
        )
    }

    private static func url(_ string: String) throws -> URL {
        guard let url = URL(string: string) else {
            throw ProviderAbstractionError.invalidURL
        }

        return url
    }
}

protocol NFTInventoryProviding {
    func nftsForOwner(
        owner: String,
        pageKey: String?
    ) async throws -> AlchemyNFTResponse
}

protocol GasPricingProviding {
    func gasPriceEstimate(for chain: Chain) async throws -> GasPriceEstimate
}

protocol NativeBalanceProviding {
    func nativeBalance(for address: String, chain: Chain) async throws -> NativeBalance
}

struct NativeBalance: Equatable, Sendable {
    let weiHex: String
    let weiDecimal: String
}

struct AlchemyRPCProvider: NativeBalanceProviding {
    private let configurationResolver: any ProviderConfigurationResolving
    private let session: URLSession

    init(
        configurationResolver: any ProviderConfigurationResolving = LiveProviderConfigurationResolver(),
        session: URLSession = .shared
    ) {
        self.configurationResolver = configurationResolver
        self.session = session
    }

    func nativeBalance(for address: String, chain: Chain) async throws -> NativeBalance {
        guard chain.supportsEVMRPC else {
            throw ProviderAbstractionError.unsupportedChain(chain)
        }

        let configuration = try configurationResolver.configuration(for: chain)
        guard let rpcURL = configuration.alchemyRPCURL else {
            throw ProviderAbstractionError.missingAPIKey(.alchemy)
        }

        var request = URLRequest(url: rpcURL)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(
            RPCRequest(
                jsonrpc: "2.0",
                method: "eth_getBalance",
                params: [address, "latest"],
                id: 1
            )
        )

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw ProviderAbstractionError.invalidResponse
        }

        let payload = try JSONDecoder().decode(EthereumBalanceResponse.self, from: data)
        guard let weiDecimal = Self.decimalString(fromHexQuantity: payload.result) else {
            throw ProviderAbstractionError.invalidBalancePayload
        }

        return NativeBalance(weiHex: payload.result, weiDecimal: weiDecimal)
    }
}

private extension AlchemyRPCProvider {
    struct RPCRequest: Encodable {
        let jsonrpc: String
        let method: String
        let params: [String]
        let id: Int
    }

    struct EthereumBalanceResponse: Decodable {
        let result: String
    }

    static func decimalString(fromHexQuantity hexQuantity: String) -> String? {
        guard hexQuantity.hasPrefix("0x") else {
            return nil
        }

        let normalized = String(hexQuantity.dropFirst(2))
        guard !normalized.isEmpty else {
            return "0"
        }

        var result = "0"
        for character in normalized.lowercased() {
            guard let digit = character.hexDigitValue else {
                return nil
            }

            result = multiplyDecimalStringBySixteen(result)
            result = addDecimalString(result, digit)
        }

        return result
    }

    static func multiplyDecimalStringBySixteen(_ value: String) -> String {
        var carry = 0
        let digits = value.reversed().map { Int(String($0)) ?? 0 }
        var result: [Int] = []

        for digit in digits {
            let product = digit * 16 + carry
            result.append(product % 10)
            carry = product / 10
        }

        while carry > 0 {
            result.append(carry % 10)
            carry /= 10
        }

        return String(result.reversed().map(String.init).joined())
    }

    static func addDecimalString(_ value: String, _ addend: Int) -> String {
        guard addend > 0 else {
            return value
        }

        var carry = addend
        var digits = value.reversed().map { Int(String($0)) ?? 0 }
        var index = 0

        while carry > 0 {
            if index == digits.count {
                digits.append(0)
            }

            let sum = digits[index] + carry
            digits[index] = sum % 10
            carry = sum / 10
            index += 1
        }

        return String(digits.reversed().map(String.init).joined())
    }
}

private extension Chain {
    var supportsEVMRPC: Bool {
        switch self {
        case .solanaMainnet, .solanaDevnetTestnet:
            return false
        default:
            return true
        }
    }

    var supportsInfuraGas: Bool {
        supportsEVMRPC
    }
}
