import Foundation

struct AlchemyGasPricingProvider: GasPricingProviding {
    enum GasPricingError: Error {
        case unsupportedChain(Chain)
        case invalidConfiguration
        case networkFailure(underlying: Error)
        case badStatus(Int)
        case invalidResponse
        case backoffOverflow
    }

    private static let session: URLSession = {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 10
        configuration.timeoutIntervalForResource = 30
        return URLSession(configuration: configuration)
    }()

    private static let nanosecondsPerSecond: UInt64 = 1_000_000_000

    private let requestThrottler = RequestThrottler(minimumInterval: 0.1)
    private let configurationResolver: any ProviderConfigurationResolving
    private let session: URLSession

    init(
        configurationResolver: any ProviderConfigurationResolving = LiveProviderConfigurationResolver(),
        session: URLSession = Self.session
    ) {
        self.configurationResolver = configurationResolver
        self.session = session
    }

    func gasPriceEstimate(for chain: Chain) async throws -> GasPriceEstimate {
        let chainId = chain.chainId
        let cacheResult = await GasPriceCache.shared.getGasPrice(for: chainId)

        switch cacheResult {
        case .hit(let estimate):
            return estimate
        case .expired(let estimate):
            do {
                try await requestThrottler.throttle()
                let refreshedEstimate = try await fetchWithRetry(chain: chain, maxAttempts: 3)
                await GasPriceCache.shared.setGasPrice(refreshedEstimate, for: chainId)
                return refreshedEstimate
            } catch {
                return estimate
            }
        case .miss:
            try await requestThrottler.throttle()
            let estimate = try await fetchWithRetry(chain: chain, maxAttempts: 3)
            await GasPriceCache.shared.setGasPrice(estimate, for: chainId)
            return estimate
        }
    }

    private func fetchWithRetry(chain: Chain, maxAttempts: Int) async throws -> GasPriceEstimate {
        var delay = Self.nanosecondsPerSecond

        for attempt in 1...maxAttempts {
            do {
                return try await fetchOnce(chain: chain)
            } catch {
                guard attempt < maxAttempts, shouldRetry(after: error) else {
                    throw error
                }

                try await Task.sleep(nanoseconds: delay)
                let (nextDelay, overflowed) = delay.multipliedReportingOverflow(by: 2)
                delay = overflowed ? 8 * Self.nanosecondsPerSecond : min(nextDelay, 8 * Self.nanosecondsPerSecond)
            }
        }

        throw GasPricingError.backoffOverflow
    }

    private func shouldRetry(after error: Error) -> Bool {
        switch error {
        case GasPricingError.networkFailure:
            return true
        case GasPricingError.badStatus(let code):
            return (500...599).contains(code) || code == 429
        default:
            return false
        }
    }

    private func fetchOnce(chain: Chain) async throws -> GasPriceEstimate {
        guard chain.supportsEVMRPC else {
            throw GasPricingError.unsupportedChain(chain)
        }

        let configuration = try configurationResolver.configuration(for: chain)
        guard let rpcURL = configuration.alchemyRPCURL else {
            throw GasPricingError.invalidConfiguration
        }

        async let feeHistoryResponse = performRPCRequest(
            FeeHistoryResponse.self,
            method: "eth_feeHistory",
            params: [AnyEncodable("0x5"), AnyEncodable("latest"), AnyEncodable([10, 50, 90])],
            rpcURL: rpcURL
        )
        async let gasPriceResponse = performRPCRequest(
            SingleValueResponse.self,
            method: "eth_gasPrice",
            params: [],
            rpcURL: rpcURL
        )

        let (feeHistory, gasPrice) = try await (feeHistoryResponse, gasPriceResponse)
        return Self.makeEstimate(feeHistory: feeHistory.result, gasPriceHex: gasPrice.result)
    }

    private func performRPCRequest<Response: Decodable>(
        _ responseType: Response.Type,
        method: String,
        params: [AnyEncodable],
        rpcURL: URL
    ) async throws -> Response {
        var request = URLRequest(url: rpcURL)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(
            RPCRequest(
                jsonrpc: "2.0",
                method: method,
                params: params,
                id: 1
            )
        )

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw GasPricingError.networkFailure(underlying: error)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw GasPricingError.invalidResponse
        }
        guard (200...299).contains(httpResponse.statusCode) else {
            throw GasPricingError.badStatus(httpResponse.statusCode)
        }

        do {
            return try JSONDecoder().decode(responseType, from: data)
        } catch {
            throw GasPricingError.invalidResponse
        }
    }
}

private extension AlchemyGasPricingProvider {
    struct RPCRequest: Encodable {
        let jsonrpc: String
        let method: String
        let params: [AnyEncodable]
        let id: Int
    }

    struct SingleValueResponse: Decodable {
        let result: String
    }

    struct FeeHistoryResponse: Decodable {
        let result: FeeHistoryResult
    }

    struct FeeHistoryResult: Decodable {
        let baseFeePerGas: [String]
        let gasUsedRatio: [Double]
        let reward: [[String]]
    }

    static func makeEstimate(feeHistory: FeeHistoryResult, gasPriceHex: String) -> GasPriceEstimate {
        let baseFeeSeries = feeHistory.baseFeePerGas.compactMap(gweiString)
        let historicalBaseFees = Array(baseFeeSeries.dropLast())
        let estimatedBaseFee = baseFeeSeries.last ?? gweiString(gasPriceHex) ?? "0"

        let priorityRewardBuckets = feeHistory.reward
            .map { row in row.compactMap(gweiString) }
            .filter { !$0.isEmpty }
        let lowPrioritySeries = priorityRewardBuckets.compactMap { $0[safe: 0] }
        let mediumPrioritySeries = priorityRewardBuckets.compactMap { $0[safe: 1] ?? $0[safe: 0] }
        let highPrioritySeries = priorityRewardBuckets.compactMap { $0[safe: 2] ?? $0.last }
        let latestPriorityRow = priorityRewardBuckets.last ?? []

        let networkCongestion = feeHistory.gasUsedRatio.isEmpty
            ? 0
            : feeHistory.gasUsedRatio.reduce(0, +) / Double(feeHistory.gasUsedRatio.count)
        let baseFeeTrend = trendDescription(for: historicalBaseFees)
        let priorityFeeTrend = trendDescription(for: mediumPrioritySeries)
        let gasPriceGwei = decimal(fromGweiString: gweiString(gasPriceHex) ?? estimatedBaseFee)
        let estimatedBaseFeeDecimal = decimal(fromGweiString: estimatedBaseFee)

        let lowPriority = seriesAverage(lowPrioritySeries)
        let mediumPriority = max(seriesAverage(mediumPrioritySeries), lowPriority)
        let highPriority = max(seriesAverage(highPrioritySeries), mediumPriority)

        return GasPriceEstimate(
            version: "alchemy-rpc-v1",
            high: feeDetails(
                priorityFee: max(highPriority, mediumPriority * 1.15),
                baseFee: estimatedBaseFeeDecimal,
                floorGasPrice: gasPriceGwei,
                waitRange: (15_000, 30_000)
            ),
            networkCongestion: min(max(networkCongestion, 0), 1),
            historicalPriorityFeeRange: rangeStrings(from: lowPrioritySeries + mediumPrioritySeries + highPrioritySeries),
            estimatedBaseFee: estimatedBaseFee,
            baseFeeTrend: baseFeeTrend,
            latestPriorityFeeRange: latestPriorityRange(from: latestPriorityRow),
            medium: feeDetails(
                priorityFee: max(mediumPriority, lowPriority * 1.1),
                baseFee: estimatedBaseFeeDecimal,
                floorGasPrice: gasPriceGwei,
                waitRange: (30_000, 60_000)
            ),
            priorityFeeTrend: priorityFeeTrend,
            low: feeDetails(
                priorityFee: max(lowPriority, 0.01),
                baseFee: estimatedBaseFeeDecimal,
                floorGasPrice: gasPriceGwei,
                waitRange: (60_000, 120_000)
            ),
            historicalBaseFeeRange: rangeStrings(from: historicalBaseFees)
        )
    }

    static func feeDetails(
        priorityFee: Decimal,
        baseFee: Decimal,
        floorGasPrice: Decimal,
        waitRange: (Int, Int)
    ) -> GasPriceEstimate.FeeDetails {
        let suggestedMaxFee = max(baseFee + priorityFee * 2, floorGasPrice)
        return GasPriceEstimate.FeeDetails(
            maxWaitTimeEstimate: waitRange.1,
            minWaitTimeEstimate: waitRange.0,
            suggestedMaxFeePerGas: normalizedString(from: suggestedMaxFee),
            suggestedMaxPriorityFeePerGas: normalizedString(from: priorityFee)
        )
    }

    static func latestPriorityRange(from values: [String]) -> [String] {
        let decimals = values.map(decimal(fromGweiString:))
        if let minimum = decimals.min(), let maximum = decimals.max() {
            return [normalizedString(from: minimum), normalizedString(from: maximum)]
        }
        return ["0", "0"]
    }

    static func rangeStrings(from values: [String]) -> [String] {
        let decimals = values.map(decimal(fromGweiString:))
        if let minimum = decimals.min(), let maximum = decimals.max() {
            return [normalizedString(from: minimum), normalizedString(from: maximum)]
        }
        return ["0", "0"]
    }

    static func trendDescription(for values: [String]) -> String {
        guard let first = values.first.map(decimal(fromGweiString:)),
              let last = values.last.map(decimal(fromGweiString:)) else {
            return "stable"
        }

        let delta = last - first
        if delta > 0.05 { return "up" }
        if delta < -0.05 { return "down" }
        return "stable"
    }

    static func seriesAverage(_ values: [String]) -> Decimal {
        guard !values.isEmpty else { return 0 }
        let total = values.map(decimal(fromGweiString:)).reduce(0, +)
        return total / Decimal(values.count)
    }

    static func gweiString(_ hexQuantity: String) -> String? {
        guard let wei = UInt64(hexQuantity.drop0xPrefix, radix: 16) else {
            return nil
        }

        let gwei = Decimal(wei) / 1_000_000_000
        return normalizedString(from: gwei)
    }

    static func decimal(fromGweiString value: String) -> Decimal {
        Decimal(string: value, locale: Locale(identifier: "en_US_POSIX")) ?? 0
    }

    static func normalizedString(from decimal: Decimal) -> String {
        let number = NSDecimalNumber(decimal: decimal)
        return number.stringValue
    }
}

private struct AnyEncodable: Encodable {
    private let encodeImpl: (Encoder) throws -> Void

    init<T: Encodable>(_ value: T) {
        encodeImpl = value.encode(to:)
    }

    func encode(to encoder: Encoder) throws {
        try encodeImpl(encoder)
    }
}

private extension String {
    var drop0xPrefix: String {
        hasPrefix("0x") ? String(dropFirst(2)) : self
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        guard indices.contains(index) else { return nil }
        return self[index]
    }
}
