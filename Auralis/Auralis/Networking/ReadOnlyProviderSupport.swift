import Foundation

enum ProviderAbstractionError: LocalizedError, Equatable {
    case missingAPIKey(Secrets.APIKeyProvider)
    case unsupportedChain(Chain)
    case invalidURL
    case invalidAddress
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
        case .invalidAddress:
            return "The wallet address is invalid."
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
    let alchemyDataAPIBaseURL: URL?
    let alchemyRPCURL: URL?
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

        let alchemyNFTBaseURL = try alchemyKey.flatMap {
            try Self.url("https://\(chain.rawValue).g.alchemy.com/nft/v3/\($0)")
        }
        let alchemyDataAPIBaseURL = try alchemyKey.flatMap {
            try Self.url("https://api.g.alchemy.com/data/v1/\($0)")
        }
        let alchemyRPCURL = try alchemyKey.flatMap {
            try Self.url("https://\(chain.rawValue).g.alchemy.com/v2/\($0)")
        }

        let configuration = ProviderEndpointConfiguration(
            chain: chain,
            alchemyNFTBaseURL: alchemyNFTBaseURL,
            alchemyDataAPIBaseURL: alchemyDataAPIBaseURL,
            alchemyRPCURL: chain.supportsEVMRPC ? alchemyRPCURL : nil
        )
        return configuration
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

protocol TokenHoldingsProviding {
    func tokenHoldings(for address: String, chain: Chain) async throws -> [ProviderTokenHolding]
}

protocol TokenBalancesProviding {
    func tokenBalances(for request: TokenBalancesRequest) async throws -> TokenBalancesPage
}

struct NativeBalance: Equatable, Sendable {
    let weiHex: String
    let weiDecimal: String

    var formattedEtherDisplay: String {
        Self.formatEtherDisplay(fromWeiDecimal: weiDecimal)
    }
}

struct ProviderTokenHolding: Equatable, Sendable {
    let contractAddress: String
    let symbol: String?
    let displayName: String
    let amountDisplay: String
    let updatedAt: Date
    let isPlaceholder: Bool
    let isAmountHidden: Bool
}

enum TokenHoldingsMetadataFreshnessPolicy {
    static let ttl: TimeInterval = 60 * 60 * 12

    static func isStale(updatedAt: Date, now: Date = .now) -> Bool {
        max(0, now.timeIntervalSince(updatedAt)) >= ttl
    }
}

struct TokenBalancesRequest: Equatable, Sendable {
    let addresses: [TokenBalancesAddress]
    let includeNativeTokens: Bool
    let includeErc20Tokens: Bool
    let pageKey: String?
}

struct TokenBalancesAddress: Equatable, Sendable {
    let address: String
    let networks: [String]
}

struct TokenBalancesPage: Equatable, Sendable {
    let tokens: [TokenBalanceRecord]
    let pageKey: String?
}

struct TokenBalanceRecord: Equatable, Sendable {
    let network: String
    let address: String
    let tokenAddress: String?
    let tokenBalance: String
}

struct ReadOnlyProviderFactory {
    private let configurationResolver: any ProviderConfigurationResolving
    private let session: URLSession

    init(
        configurationResolver: any ProviderConfigurationResolving = LiveProviderConfigurationResolver(),
        session: URLSession = .shared
    ) {
        self.configurationResolver = configurationResolver
        self.session = session
    }

    func makeNFTInventoryProvider(for chain: Chain) throws -> any NFTInventoryProviding {
        try AlchemyNFTService(
            chain: chain,
            configurationResolver: configurationResolver
        )
    }

    func makeGasPricingProvider() -> any GasPricingProviding {
        AlchemyGasPricingProvider(
            configurationResolver: configurationResolver,
            session: session
        )
    }

    func makeNativeBalanceProvider() -> any NativeBalanceProviding {
        AlchemyRPCProvider(
            configurationResolver: configurationResolver,
            session: session
        )
    }

    func makeTokenHoldingsProvider() -> any TokenHoldingsProviding {
        AlchemyTokenHoldingsProvider(
            configurationResolver: configurationResolver,
            session: session
        )
    }

    func makeTokenBalancesProvider() -> any TokenBalancesProviding {
        AlchemyTokenHoldingsProvider(
            configurationResolver: configurationResolver,
            session: session
        )
    }
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
        guard let normalizedAddress = address.extractedEthereumAddress else {
            throw ProviderAbstractionError.invalidAddress
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
                params: [normalizedAddress, "latest"],
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

struct AlchemyTokenHoldingsProvider: TokenHoldingsProviding, TokenBalancesProviding {
    private let configurationResolver: any ProviderConfigurationResolving
    private let session: URLSession
    private let nowProvider: @Sendable () -> Date

    init(
        configurationResolver: any ProviderConfigurationResolving = LiveProviderConfigurationResolver(),
        session: URLSession = .shared,
        nowProvider: @escaping @Sendable () -> Date = { .now }
    ) {
        self.configurationResolver = configurationResolver
        self.session = session
        self.nowProvider = nowProvider
    }

    func tokenBalances(for request: TokenBalancesRequest) async throws -> TokenBalancesPage {
        let dataAPIBaseURL = try resolveGlobalDataAPIBaseURL()
        let requestBody = TokenBalancesByAddressRequest(
            addresses: request.addresses.map {
                AddressRequest(address: $0.address, networks: $0.networks)
            },
            includeNativeTokens: request.includeNativeTokens,
            includeErc20Tokens: request.includeErc20Tokens,
            pageKey: request.pageKey
        )

        var urlRequest = URLRequest(url: dataAPIBaseURL.appending(path: "assets/tokens/balances/by-address"))
        urlRequest.httpMethod = "POST"
        urlRequest.addValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.addValue("application/json", forHTTPHeaderField: "Accept")
        urlRequest.httpBody = try JSONEncoder().encode(requestBody)

        let (data, response) = try await session.data(for: urlRequest)
        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw ProviderAbstractionError.invalidResponse
        }

        let payload = try JSONDecoder().decode(TokenBalancesByAddressResponse.self, from: data)
        return TokenBalancesPage(
            tokens: payload.data.tokens.map {
                TokenBalanceRecord(
                    network: $0.network,
                    address: $0.address,
                    tokenAddress: $0.tokenAddress,
                    tokenBalance: $0.tokenBalance
                )
            },
            pageKey: payload.data.pageKey?.nilIfEmpty
        )
    }

    func tokenHoldings(for address: String, chain: Chain) async throws -> [ProviderTokenHolding] {
        guard chain.supportsERC20Holdings else {
            throw ProviderAbstractionError.unsupportedChain(chain)
        }
        guard let normalizedAddress = address.extractedEthereumAddress else {
            throw ProviderAbstractionError.invalidAddress
        }

        let configuration = try configurationResolver.configuration(for: chain)
        guard let dataAPIBaseURL = configuration.alchemyDataAPIBaseURL else {
            throw ProviderAbstractionError.missingAPIKey(.alchemy)
        }

        let balances = try await fetchBalances(
            address: normalizedAddress,
            chain: chain,
            dataAPIBaseURL: dataAPIBaseURL
        )

        guard !balances.isEmpty else {
            return []
        }

        let contractAddresses = Set(balances.map(\.contractAddress))
        let enrichments = try? await fetchEnrichments(
            address: normalizedAddress,
            chain: chain,
            dataAPIBaseURL: dataAPIBaseURL,
            allowedContractAddresses: contractAddresses
        )

        return balances.map { balance in
            let enrichment = enrichments?[balance.contractAddress]
            let symbol = enrichment?.symbol
            let displayName = enrichment?.name ?? symbol ?? balance.contractAddress.displayAddress
            let amountPresentation = DecimalQuantityFormatter.tokenAmountPresentation(
                from: balance.rawBalance,
                decimals: enrichment?.decimals,
                symbol: symbol
            )
            let isPlaceholder = enrichment?.decimals == nil
                || enrichment?.name == nil
                || enrichment?.symbol == nil

            return ProviderTokenHolding(
                contractAddress: balance.contractAddress,
                symbol: symbol,
                displayName: displayName,
                amountDisplay: amountPresentation.displayText,
                updatedAt: enrichment?.updatedAt ?? nowProvider(),
                isPlaceholder: isPlaceholder,
                isAmountHidden: amountPresentation.isHidden
            )
        }
    }

    private func resolveGlobalDataAPIBaseURL() throws -> URL {
        let configuration = try configurationResolver.configuration(for: .ethMainnet)
        guard let dataAPIBaseURL = configuration.alchemyDataAPIBaseURL else {
            throw ProviderAbstractionError.missingAPIKey(.alchemy)
        }
        return dataAPIBaseURL
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

private extension AlchemyTokenHoldingsProvider {
    struct BalanceSnapshot: Equatable {
        let contractAddress: String
        let rawBalance: String
    }

    struct TokenEnrichment: Equatable {
        let decimals: Int?
        let symbol: String?
        let name: String?
        let updatedAt: Date
    }

    struct TokensByAddressRequest: Encodable {
        let addresses: [AddressRequest]
        let withMetadata: Bool
        let withPrices: Bool
        let includeNativeTokens: Bool
        let includeErc20Tokens: Bool
        let pageKey: String?
    }

    struct TokenBalancesByAddressRequest: Encodable {
        let addresses: [AddressRequest]
        let includeNativeTokens: Bool
        let includeErc20Tokens: Bool
        let pageKey: String?
    }

    struct AddressRequest: Encodable {
        let address: String
        let networks: [String]
    }

    struct TokenBalancesByAddressResponse: Decodable {
        let data: BalanceDataEnvelope
    }

    struct BalanceDataEnvelope: Decodable {
        let tokens: [BalanceToken]
        let pageKey: String?
    }

    struct BalanceToken: Decodable {
        let network: String
        let address: String
        let tokenAddress: String?
        let tokenBalance: String
    }

    struct TokensByAddressResponse: Decodable {
        let data: DataEnvelope
    }

    struct DataEnvelope: Decodable {
        let tokens: [Token]
        let pageKey: String?
    }

    struct Token: Decodable {
        let tokenAddress: String?
        let tokenBalance: String
        let tokenMetadata: TokenMetadata?
        let tokenPrices: [TokenPrice]?
        let error: String?
    }

    struct TokenMetadata: Decodable {
        let decimals: Int?
        let logo: String?
        let name: String?
        let symbol: String?
    }

    struct TokenPrice: Decodable {
        let currency: String
        let value: String
        let lastUpdatedAt: Date
    }

    static func isZeroBalance(_ balance: String) -> Bool {
        balance.allSatisfy { $0 == "0" }
    }

    func fetchBalances(
        address: String,
        chain: Chain,
        dataAPIBaseURL: URL
    ) async throws -> [BalanceSnapshot] {
        var pageKey: String?
        var balancesByContract: [String: BalanceSnapshot] = [:]

        repeat {
            let requestBody = TokenBalancesByAddressRequest(
                addresses: [
                    AddressRequest(
                        address: address,
                        networks: [chain.rawValue]
                    )
                ],
                includeNativeTokens: false,
                includeErc20Tokens: true,
                pageKey: pageKey
            )

            var request = URLRequest(url: dataAPIBaseURL.appending(path: "assets/tokens/balances/by-address"))
            request.httpMethod = "POST"
            request.addValue("application/json", forHTTPHeaderField: "Content-Type")
            request.addValue("application/json", forHTTPHeaderField: "Accept")
            request.httpBody = try JSONEncoder().encode(requestBody)

            let (data, response) = try await session.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse,
                  (200...299).contains(httpResponse.statusCode) else {
                throw ProviderAbstractionError.invalidResponse
            }

            let payload = try JSONDecoder().decode(TokenBalancesByAddressResponse.self, from: data)

            for token in payload.data.tokens {
                guard let contractAddress = NFT.normalizedScopeComponent(token.tokenAddress),
                      !Self.isZeroBalance(token.tokenBalance) else {
                    continue
                }

                balancesByContract[contractAddress] = BalanceSnapshot(
                    contractAddress: contractAddress,
                    rawBalance: token.tokenBalance
                )
            }

            pageKey = payload.data.pageKey?.nilIfEmpty
        } while pageKey != nil

        return balancesByContract.values.sorted { lhs, rhs in
            lhs.contractAddress < rhs.contractAddress
        }
    }

    func fetchEnrichments(
        address: String,
        chain: Chain,
        dataAPIBaseURL: URL,
        allowedContractAddresses: Set<String>
    ) async throws -> [String: TokenEnrichment] {
        var pageKey: String?
        var enrichmentsByContract: [String: TokenEnrichment] = [:]
        let fetchedAt = nowProvider()

        repeat {
            let requestBody = TokensByAddressRequest(
                addresses: [
                    AddressRequest(
                        address: address,
                        networks: [chain.rawValue]
                    )
                ],
                withMetadata: true,
                withPrices: false,
                includeNativeTokens: false,
                includeErc20Tokens: true,
                pageKey: pageKey
            )

            var request = URLRequest(url: dataAPIBaseURL.appending(path: "assets/tokens/by-address"))
            request.httpMethod = "POST"
            request.addValue("application/json", forHTTPHeaderField: "Content-Type")
            request.addValue("application/json", forHTTPHeaderField: "Accept")
            request.httpBody = try JSONEncoder().encode(requestBody)

            let (data, response) = try await session.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse,
                  (200...299).contains(httpResponse.statusCode) else {
                throw ProviderAbstractionError.invalidResponse
            }

            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let payload = try decoder.decode(TokensByAddressResponse.self, from: data)

            for token in payload.data.tokens {
                guard token.error == nil,
                      let contractAddress = NFT.normalizedScopeComponent(token.tokenAddress),
                      allowedContractAddresses.contains(contractAddress) else {
                    continue
                }

                enrichmentsByContract[contractAddress] = TokenEnrichment(
                    decimals: token.tokenMetadata?.decimals,
                    symbol: token.tokenMetadata?.symbol?.nilIfEmpty,
                    name: token.tokenMetadata?.name?.nilIfEmpty,
                    updatedAt: fetchedAt
                )
            }

            pageKey = payload.data.pageKey?.nilIfEmpty
        } while pageKey != nil

        return enrichmentsByContract
    }
}

private enum DecimalQuantityFormatter {
    struct TokenAmountPresentation: Equatable {
        let displayText: String
        let isHidden: Bool
    }

    static func tokenAmountPresentation(
        from rawBalance: String,
        decimals: Int?,
        symbol: String?
    ) -> TokenAmountPresentation {
        guard let decimals else {
            return TokenAmountPresentation(
                displayText: TokenHolding.hiddenAmountDisplay,
                isHidden: true
            )
        }

        let formattedAmount = formatDecimalQuantity(
            rawBalance,
            scale: max(decimals, 0),
            maxFractionDigits: 6
        )

        guard let symbol, !symbol.isEmpty else {
            return TokenAmountPresentation(
                displayText: formattedAmount,
                isHidden: false
            )
        }

        return TokenAmountPresentation(
            displayText: "\(formattedAmount) \(symbol)",
            isHidden: false
        )
    }

    static func formatEtherDisplay(fromWeiDecimal weiDecimal: String) -> String {
        let formattedAmount = formatDecimalQuantity(
            weiDecimal,
            scale: 18,
            maxFractionDigits: 6
        )
        return "\(formattedAmount) ETH"
    }

    private static func formatDecimalQuantity(
        _ rawValue: String,
        scale: Int,
        maxFractionDigits: Int
    ) -> String {
        let normalized = stripLeadingZeroes(from: rawValue)
        guard normalized != "0" else {
            return "0"
        }

        guard scale > 0 else {
            return normalized
        }

        let wholePart: String
        let fractionalPart: String

        if normalized.count <= scale {
            wholePart = "0"
            fractionalPart = String(repeating: "0", count: scale - normalized.count) + normalized
        } else {
            let splitIndex = normalized.index(normalized.endIndex, offsetBy: -scale)
            wholePart = String(normalized[..<splitIndex])
            fractionalPart = String(normalized[splitIndex...])
        }

        let visibleFraction = String(fractionalPart.prefix(maxFractionDigits))
        let trimmedFraction = visibleFraction.trimmingCharacters(in: CharacterSet(charactersIn: "0"))
        if trimmedFraction.isEmpty {
            if wholePart == "0" && fractionalPart.contains(where: { $0 != "0" }) {
                return "<0." + String(repeating: "0", count: max(maxFractionDigits - 1, 0)) + "1"
            }
            return wholePart
        }

        return "\(wholePart).\(trimmedFraction)"
    }

    private static func stripLeadingZeroes(from value: String) -> String {
        let trimmed = value.drop { $0 == "0" }
        return trimmed.isEmpty ? "0" : String(trimmed)
    }
}

private extension NativeBalance {
    static func formatEtherDisplay(fromWeiDecimal weiDecimal: String) -> String {
        DecimalQuantityFormatter.formatEtherDisplay(fromWeiDecimal: weiDecimal)
    }
}

private extension String {
    var nilIfEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

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
