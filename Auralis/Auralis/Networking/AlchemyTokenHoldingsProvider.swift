import Foundation

private enum BalanceDataEnvelopeCodingKeys: String, CodingKey {
    case tokens
    case pageKey
}

private enum TokensByAddressDataEnvelopeCodingKeys: String, CodingKey {
    case tokens
    case pageKey
}

private struct AlchemyTokenEnrichmentResult {
    let enrichments: [String: AlchemyTokenEnrichment]?
    let warning: TokenHoldingsProviderWarning?
}

private struct AlchemyBalanceSnapshot: Equatable {
    let contractAddress: String
    let rawBalance: String
}

private struct AlchemyTokenEnrichment: Equatable {
    let decimals: Int?
    let symbol: String?
    let name: String?
    let updatedAt: Date
}

private struct AlchemyTokensByAddressRequest: Encodable {
    let addresses: [AlchemyAddressRequest]
    let withMetadata: Bool
    let withPrices: Bool
    let includeNativeTokens: Bool
    let includeErc20Tokens: Bool
    let pageKey: String?
}

private struct AlchemyTokenBalancesByAddressRequest: Encodable {
    let addresses: [AlchemyAddressRequest]
    let includeNativeTokens: Bool
    let includeErc20Tokens: Bool
    let pageKey: String?
}

private struct AlchemyAddressRequest: Encodable {
    let address: String
    let networks: [String]
}

private struct AlchemyTokenBalancesByAddressResponse: Decodable {
    let data: AlchemyBalanceDataEnvelope
}

private struct AlchemyBalanceDataEnvelope: Decodable {
    let tokens: [AlchemyBalanceToken]
    let pageKey: String?

    init(tokens: [AlchemyBalanceToken], pageKey: String?) {
        self.tokens = tokens
        self.pageKey = pageKey
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: BalanceDataEnvelopeCodingKeys.self)
        tokens = try container.decodeIfPresent(LossyDecodableArray<AlchemyBalanceToken>.self, forKey: .tokens)?.elements ?? []
        pageKey = try container.decodeIfPresent(String.self, forKey: .pageKey)
    }
}

private struct AlchemyBalanceToken: Decodable {
    let network: String
    let address: String
    let tokenAddress: String?
    let tokenBalance: String
}

private struct AlchemyTokensByAddressResponse: Decodable {
    let data: AlchemyTokensDataEnvelope
}

private struct AlchemyTokensDataEnvelope: Decodable {
    let tokens: [AlchemyTokenPayload]
    let pageKey: String?

    init(tokens: [AlchemyTokenPayload], pageKey: String?) {
        self.tokens = tokens
        self.pageKey = pageKey
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: TokensByAddressDataEnvelopeCodingKeys.self)
        tokens = try container.decodeIfPresent(LossyDecodableArray<AlchemyTokenPayload>.self, forKey: .tokens)?.elements ?? []
        pageKey = try container.decodeIfPresent(String.self, forKey: .pageKey)
    }
}

private struct AlchemyTokenPayload: Decodable {
    let tokenAddress: String?
    let tokenBalance: String
    let tokenMetadata: AlchemyTokenMetadata?
    let tokenPrices: [AlchemyTokenPrice]?
    let error: String?
}

private struct AlchemyTokenMetadata: Decodable {
    let decimals: Int?
    let logo: String?
    let name: String?
    let symbol: String?
}

private struct AlchemyTokenPrice: Decodable {
    let currency: String
    let value: String
    let lastUpdatedAt: Date
}

struct AlchemyTokenHoldingsProvider: TokenHoldingsProviding, TokenBalancesProviding {
    private enum RequestError: Error {
        case badStatus(Int, message: String?, retryAfter: TimeInterval?)
        case invalidResponse
    }

    private static let maxConsecutiveEmptyPages = 3
    private static let session: URLSession = {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 15
        configuration.timeoutIntervalForResource = 30
        return URLSession(configuration: configuration)
    }()
    private static let nanosecondsPerSecond: UInt64 = 1_000_000_000

    private let configurationResolver: any ProviderConfigurationResolving
    private let session: URLSession
    private let nowProvider: @Sendable () -> Date
    private let maxRetryCount: Int
    private let baseDelayNanoseconds: UInt64
    private let maxDelayNanoseconds: UInt64

    init(
        configurationResolver: any ProviderConfigurationResolving = LiveProviderConfigurationResolver(),
        session: URLSession = Self.session,
        maxRetryCount: Int = 3,
        baseDelayNanoseconds: UInt64 = 200_000_000,
        maxDelayNanoseconds: UInt64 = 2 * Self.nanosecondsPerSecond,
        nowProvider: @escaping @Sendable () -> Date = { .now }
    ) {
        self.configurationResolver = configurationResolver
        self.session = session
        self.maxRetryCount = maxRetryCount
        self.baseDelayNanoseconds = baseDelayNanoseconds
        self.maxDelayNanoseconds = maxDelayNanoseconds
        self.nowProvider = nowProvider
    }

    func tokenBalances(for request: TokenBalancesRequest) async throws -> TokenBalancesPage {
        let dataAPIBaseURL = try resolveGlobalDataAPIBaseURL()
        let requestBody = AlchemyTokenBalancesByAddressRequest(
            addresses: request.addresses.map {
                AlchemyAddressRequest(address: $0.address, networks: $0.networks)
            },
            includeNativeTokens: request.includeNativeTokens,
            includeErc20Tokens: request.includeErc20Tokens,
            pageKey: request.pageKey
        )

        let urlRequest = try makePOSTRequest(
            url: dataAPIBaseURL.appending(path: "assets/tokens/balances/by-address"),
            body: requestBody
        )
        let payload: AlchemyTokenBalancesByAddressResponse = try await performRequest(
            urlRequest,
            decoder: JSONDecoder()
        )
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

    func tokenHoldings(for address: String, chain: Chain) async throws -> TokenHoldingsFetchResult {
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
            return TokenHoldingsFetchResult(holdings: [], warning: nil)
        }

        let enrichmentResult = try await fetchEnrichmentResult(
            for: balances,
            address: normalizedAddress,
            chain: chain,
            dataAPIBaseURL: dataAPIBaseURL
        )
        let enrichments = enrichmentResult.enrichments

        let holdings = balances.map { balance in
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

        return TokenHoldingsFetchResult(
            holdings: holdings,
            warning: enrichmentResult.warning
        )
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
    static func isZeroBalance(_ balance: String) -> Bool {
        balance.allSatisfy { $0 == "0" }
    }

    func fetchEnrichmentResult(
        for balances: [AlchemyBalanceSnapshot],
        address: String,
        chain: Chain,
        dataAPIBaseURL: URL
    ) async throws -> AlchemyTokenEnrichmentResult {
        let contractAddresses = Set(balances.map(\.contractAddress))

        do {
            let enrichments = try await fetchEnrichments(
                address: address,
                chain: chain,
                dataAPIBaseURL: dataAPIBaseURL,
                allowedContractAddresses: contractAddresses
            )
            return AlchemyTokenEnrichmentResult(enrichments: enrichments, warning: nil)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            if shouldSurfaceEnrichmentFailure(error) {
                throw error
            }
            return AlchemyTokenEnrichmentResult(
                enrichments: nil,
                warning: TokenHoldingsProviderWarning(
                    message: "Auralis refreshed token balances, but token metadata is temporarily unavailable. Names, symbols, and formatted amounts may stay limited until the provider recovers."
                )
            )
        }
    }

    func fetchBalances(
        address: String,
        chain: Chain,
        dataAPIBaseURL: URL
    ) async throws -> [AlchemyBalanceSnapshot] {
        var pageKey: String?
        var balancesByContract: [String: AlchemyBalanceSnapshot] = [:]
        var consecutiveEmptyPages = 0

        repeat {
            let requestedPageKey = pageKey
            let requestBody = AlchemyTokenBalancesByAddressRequest(
                addresses: [
                    AlchemyAddressRequest(
                        address: address,
                        networks: [chain.rawValue]
                    )
                ],
                includeNativeTokens: false,
                includeErc20Tokens: true,
                pageKey: pageKey
            )

            let request = try makePOSTRequest(
                url: dataAPIBaseURL.appending(path: "assets/tokens/balances/by-address"),
                body: requestBody
            )
            let payload: AlchemyTokenBalancesByAddressResponse = try await performRequest(
                request,
                decoder: JSONDecoder()
            )

            for token in payload.data.tokens {
                guard let contractAddress = NFT.normalizedScopeComponent(token.tokenAddress),
                      !Self.isZeroBalance(token.tokenBalance) else {
                    continue
                }

                balancesByContract[contractAddress] = AlchemyBalanceSnapshot(
                    contractAddress: contractAddress,
                    rawBalance: token.tokenBalance
                )
            }

            let nextPageKey = payload.data.pageKey?.nilIfEmpty
            consecutiveEmptyPages = try Self.updatedEmptyPageCount(
                currentCount: consecutiveEmptyPages,
                requestedPageKey: requestedPageKey,
                nextPageKey: nextPageKey,
                returnedItemCount: payload.data.tokens.count
            )
            pageKey = nextPageKey
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
    ) async throws -> [String: AlchemyTokenEnrichment] {
        var pageKey: String?
        var enrichmentsByContract: [String: AlchemyTokenEnrichment] = [:]
        let fetchedAt = nowProvider()
        var consecutiveEmptyPages = 0

        repeat {
            let requestedPageKey = pageKey
            let requestBody = AlchemyTokensByAddressRequest(
                addresses: [
                    AlchemyAddressRequest(
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

            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let request = try makePOSTRequest(
                url: dataAPIBaseURL.appending(path: "assets/tokens/by-address"),
                body: requestBody
            )
            let payload: AlchemyTokensByAddressResponse = try await performRequest(
                request,
                decoder: decoder
            )

            for token in payload.data.tokens {
                guard token.error == nil,
                      let contractAddress = NFT.normalizedScopeComponent(token.tokenAddress),
                      allowedContractAddresses.contains(contractAddress) else {
                    continue
                }

                enrichmentsByContract[contractAddress] = AlchemyTokenEnrichment(
                    decimals: token.tokenMetadata?.decimals,
                    symbol: token.tokenMetadata?.symbol?.nilIfEmpty,
                    name: token.tokenMetadata?.name?.nilIfEmpty,
                    updatedAt: fetchedAt
                )
            }

            let nextPageKey = payload.data.pageKey?.nilIfEmpty
            consecutiveEmptyPages = try Self.updatedEmptyPageCount(
                currentCount: consecutiveEmptyPages,
                requestedPageKey: requestedPageKey,
                nextPageKey: nextPageKey,
                returnedItemCount: payload.data.tokens.count
            )
            pageKey = nextPageKey
        } while pageKey != nil

        return enrichmentsByContract
    }

}

extension AlchemyTokenHoldingsProvider {
    static func updatedEmptyPageCount(
        currentCount: Int,
        requestedPageKey: String?,
        nextPageKey: String?,
        returnedItemCount: Int
    ) throws -> Int {
        guard let nextPageKey else {
            return 0
        }

        if nextPageKey == requestedPageKey {
            throw ProviderAbstractionError.paginationStalled
        }

        guard returnedItemCount == 0 else {
            return 0
        }

        let updatedCount = currentCount + 1
        if updatedCount >= Self.maxConsecutiveEmptyPages {
            throw ProviderAbstractionError.paginationStalled
        }

        return updatedCount
    }

    private func makePOSTRequest<Body: Encodable>(
        url: URL,
        body: Body
    ) throws -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.addValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = try JSONEncoder().encode(body)
        return request
    }

    private func performRequest<Response: Decodable>(
        _ request: URLRequest,
        decoder: JSONDecoder
    ) async throws -> Response {
        var delay = baseDelayNanoseconds

        for attempt in 1...maxRetryCount {
            do {
                return try await performRequestOnce(request, decoder: decoder)
            } catch {
                guard attempt < maxRetryCount, shouldRetry(after: error) else {
                    throw mapRequestError(error)
                }

                try await Task.sleep(nanoseconds: retryDelay(after: error, fallbackDelay: delay))
                let (nextDelay, overflowed) = delay.multipliedReportingOverflow(by: 2)
                delay = overflowed ? maxDelayNanoseconds : min(nextDelay, maxDelayNanoseconds)
            }
        }

        throw ProviderAbstractionError.invalidResponse
    }

    private func performRequestOnce<Response: Decodable>(
        _ request: URLRequest,
        decoder: JSONDecoder
    ) async throws -> Response {
        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw RequestError.invalidResponse
        }
        guard (200...299).contains(httpResponse.statusCode) else {
            throw RequestError.badStatus(
                httpResponse.statusCode,
                message: parseErrorMessage(from: data),
                retryAfter: parseRetryAfter(from: httpResponse)
            )
        }

        do {
            return try decoder.decode(Response.self, from: data)
        } catch {
            throw RequestError.invalidResponse
        }
    }

    private func shouldRetry(after error: Error) -> Bool {
        if let urlError = error as? URLError {
            switch urlError.code {
            case .timedOut, .cannotConnectToHost, .networkConnectionLost, .notConnectedToInternet:
                return true
            default:
                return false
            }
        }

        if let requestError = error as? RequestError {
            switch requestError {
            case .badStatus(let statusCode, _, _):
                return statusCode == 429 || (500...599).contains(statusCode)
            case .invalidResponse:
                return false
            }
        }

        return false
    }

    private func mapRequestError(_ error: Error) -> Error {
        if let urlError = error as? URLError {
            switch urlError.code {
            case .notConnectedToInternet, .networkConnectionLost:
                return ProviderAbstractionError.offline
            case .timedOut, .cannotConnectToHost:
                return ProviderAbstractionError.unavailable
            default:
                return urlError
            }
        }

        if let requestError = error as? RequestError {
            switch requestError {
            case .badStatus(let statusCode, _, _) where statusCode == 429:
                return ProviderAbstractionError.rateLimited
            case .badStatus(let statusCode, _, _) where statusCode == 401 || statusCode == 403:
                return ProviderAbstractionError.unauthorized
            case .badStatus(let statusCode, _, _) where (500...599).contains(statusCode):
                return ProviderAbstractionError.unavailable
            case .badStatus(let statusCode, let message, _):
                return ProviderAbstractionError.badStatus(statusCode, message: message)
            case .invalidResponse:
                return ProviderAbstractionError.invalidResponse
            }
        }

        return error
    }

    private func retryDelay(after error: Error, fallbackDelay: UInt64) -> UInt64 {
        guard case .badStatus(_, _, let retryAfter?) = error as? RequestError else {
            return fallbackDelay
        }

        return UInt64(max(0, retryAfter) * Double(Self.nanosecondsPerSecond))
    }

    private func shouldSurfaceEnrichmentFailure(_ error: Error) -> Bool {
        if let providerError = error as? ProviderAbstractionError {
            switch providerError {
            case .missingAPIKey,
                    .unsupportedChain,
                    .invalidURL,
                    .invalidAddress,
                    .badStatus,
                    .unauthorized,
                    .unsupportedMethod,
                    .providerError:
                return true
            case .offline,
                    .invalidResponse,
                    .unavailable,
                    .invalidBalancePayload,
                    .paginationStalled,
                    .rateLimited:
                return false
            }
        }

        return false
    }

    private func parseErrorMessage(from data: Data) -> String? {
        if let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            return object["message"] as? String
                ?? object["detail"] as? String
                ?? object["error"] as? String
        }

        return String(data: data, encoding: .utf8)
    }

    private func parseRetryAfter(from response: HTTPURLResponse) -> TimeInterval? {
        RetryAfterSupport.parse(from: response)
    }
}
