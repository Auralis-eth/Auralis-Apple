import Foundation

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
