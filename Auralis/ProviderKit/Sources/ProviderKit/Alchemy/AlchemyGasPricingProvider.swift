import AuralisPrimaryModels
import Foundation

public struct AlchemyGasPricingProvider: GasPricingProviding, Sendable {
    public enum GasPricingError: Error, LocalizedError {
        case unsupportedChain(Chain)
        case invalidConfiguration
        case networkFailure(underlying: Error)
        case badStatus(Int, message: String?)
        case invalidResponse
        case backoffOverflow
        case rateLimited(message: String, retryAfter: TimeInterval?)
        case unauthorized(message: String)
        case unsupportedMethod(message: String)
        case rpcError(code: Int, message: String)

        public var errorDescription: String? {
            switch self {
            case .unsupportedChain(let chain):
                return "Gas pricing is not supported for \(chain.networkName)."
            case .invalidConfiguration:
                return "Gas pricing provider configuration is invalid."
            case .networkFailure(let underlying):
                return "Gas pricing request failed: \(underlying.localizedDescription)"
            case .badStatus(let status, let message):
                if let message, !message.isEmpty {
                    return "Gas pricing request failed with HTTP \(status). \(message)"
                }
                return "Gas pricing request failed with HTTP \(status)."
            case .invalidResponse:
                return "Gas pricing provider returned an invalid response."
            case .backoffOverflow:
                return "Gas pricing retry scheduling overflowed."
            case .rateLimited(let message, let retryAfter):
                if let retryAfter {
                    return "Gas pricing provider is rate-limiting requests. Retry after \(retryAfter) seconds. \(message)"
                }
                return "Gas pricing provider is rate-limiting requests. \(message)"
            case .unauthorized(let message):
                return "Gas pricing provider authentication failed. \(message)"
            case .unsupportedMethod(let message):
                return "Gas pricing provider does not support this RPC method. \(message)"
            case .rpcError(_, let message):
                return "Gas pricing provider returned an RPC error. \(message)"
            }
        }
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

    public init(
        configurationResolver: any ProviderConfigurationResolving = LiveProviderConfigurationResolver(),
        session: URLSession? = nil
    ) {
        self.configurationResolver = configurationResolver
        self.session = session ?? Self.session
    }

    public func gasPriceEstimate(for chain: Chain) async throws -> GasPriceEstimateResult {
        let chainId = chain.chainId
        let cacheResult = await GasPriceCache.shared.getGasPrice(for: chainId)

        switch cacheResult {
        case .hit(let estimate, let fetchedAt):
            return GasPriceEstimateResult(
                estimate: estimate,
                fetchedAt: fetchedAt,
                source: .cache
            )
        case .expired(let staleEstimate, let fetchedAt):
            try await requestThrottler.throttle()
            do {
                let refreshedEstimate = try await fetchWithRetry(chain: chain, maxAttempts: 3)
                await GasPriceCache.shared.setGasPrice(refreshedEstimate, for: chainId)
                return GasPriceEstimateResult(
                    estimate: refreshedEstimate,
                    fetchedAt: .now,
                    source: .live
                )
            } catch {
                guard shouldUseStaleCacheFallback(after: error) else {
                    throw error
                }
                return GasPriceEstimateResult(
                    estimate: staleEstimate,
                    fetchedAt: fetchedAt,
                    source: .staleCache
                )
            }
        case .miss:
            try await requestThrottler.throttle()
            let estimate = try await fetchWithRetry(chain: chain, maxAttempts: 3)
            await GasPriceCache.shared.setGasPrice(estimate, for: chainId)
            return GasPriceEstimateResult(
                estimate: estimate,
                fetchedAt: .now,
                source: .live
            )
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

                try await Task.sleep(nanoseconds: retryDelay(after: error, fallbackDelay: delay))
                let (nextDelay, overflowed) = delay.multipliedReportingOverflow(by: 2)
                delay = overflowed ? 8 * Self.nanosecondsPerSecond : min(nextDelay, 8 * Self.nanosecondsPerSecond)
            }
        }

        throw GasPricingError.backoffOverflow
    }

    private func shouldRetry(after error: Error) -> Bool {
        switch error {
        case GasPricingError.networkFailure, GasPricingError.rateLimited:
            return true
        case GasPricingError.badStatus(let code, _):
            return (500...599).contains(code) || code == 429
        case GasPricingError.invalidResponse:
            return true
        default:
            return false
        }
    }

    private func shouldUseStaleCacheFallback(after error: Error) -> Bool {
        switch error {
        case GasPricingError.networkFailure,
                GasPricingError.rateLimited,
                GasPricingError.invalidResponse:
            return true
        case GasPricingError.badStatus(let statusCode, _):
            return statusCode == 429 || (500...599).contains(statusCode)
        default:
            return false
        }
    }

    private func fetchOnce(chain: Chain) async throws -> GasPriceEstimate {
        guard chain.supportsProviderKitEVMRPC else {
            throw GasPricingError.unsupportedChain(chain)
        }

        let configuration = try configurationResolver.configuration(for: chain)
        guard let rpcURL = configuration.alchemyRPCURL else {
            throw GasPricingError.invalidConfiguration
        }

        async let feeHistoryResponse = performRPCRequest(
            FeeHistoryResult.self,
            method: "eth_feeHistory",
            params: [AnyEncodable("0x5"), AnyEncodable("latest"), AnyEncodable([10, 50, 90])],
            rpcURL: rpcURL
        )
        async let gasPriceResponse = performRPCRequest(
            String.self,
            method: "eth_gasPrice",
            params: [],
            rpcURL: rpcURL
        )

        let (feeHistory, gasPrice) = try await (feeHistoryResponse, gasPriceResponse)
        return Self.makeEstimate(feeHistory: feeHistory, gasPriceHex: gasPrice)
    }

    private func performRPCRequest<ResultType: Decodable>(
        _ resultType: ResultType.Type,
        method: String,
        params: [AnyEncodable],
        rpcURL: URL
    ) async throws -> ResultType {
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
            let message = parseErrorMessage(from: data)
            if httpResponse.statusCode == 429 {
                throw GasPricingError.rateLimited(
                    message: message ?? "HTTP 429",
                    retryAfter: parseRetryAfter(from: httpResponse)
                )
            }
            if httpResponse.statusCode == 401 || httpResponse.statusCode == 403 {
                throw GasPricingError.unauthorized(message: message ?? "HTTP \(httpResponse.statusCode)")
            }
            throw GasPricingError.badStatus(httpResponse.statusCode, message: message)
        }

        do {
            let envelope = try JSONDecoder().decode(RPCEnvelope<ResultType>.self, from: data)
            if let error = envelope.error {
                throw mapRPCError(error)
            }

            guard let result = envelope.result else {
                throw GasPricingError.invalidResponse
            }

            return result
        } catch let error as GasPricingError {
            throw error
        } catch {
            throw GasPricingError.invalidResponse
        }
    }

    private func mapRPCError(_ error: RPCErrorPayload) -> GasPricingError {
        let normalizedMessage = error.message.lowercased()

        if error.code == 429 || normalizedMessage.contains("rate limit") {
            return .rateLimited(message: error.message, retryAfter: nil)
        }

        if error.code == -32601 || normalizedMessage.contains("method not found") {
            return .unsupportedMethod(message: error.message)
        }

        if normalizedMessage.contains("unauthorized")
            || normalizedMessage.contains("forbidden")
            || normalizedMessage.contains("api key") {
            return .unauthorized(message: error.message)
        }

        return .rpcError(code: error.code, message: error.message)
    }

    private func retryDelay(after error: Error, fallbackDelay: UInt64) -> UInt64 {
        guard case .rateLimited(_, let retryAfter?) = error as? GasPricingError else {
            return fallbackDelay
        }

        return UInt64(max(0, retryAfter) * Double(Self.nanosecondsPerSecond))
    }

    private func parseRetryAfter(from response: HTTPURLResponse) -> TimeInterval? {
        RetryAfterSupport.parse(from: response)
    }

    private func parseErrorMessage(from data: Data) -> String? {
        if let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            return object["message"] as? String
                ?? object["detail"] as? String
                ?? object["error"] as? String
        }

        let rawMessage = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return rawMessage?.isEmpty == false ? rawMessage : nil
    }
}

private extension AlchemyGasPricingProvider {
    struct RPCEnvelope<Result: Decodable>: Decodable {
        let result: Result?
        let error: RPCErrorPayload?
    }

    struct RPCErrorPayload: Decodable {
        let code: Int
        let message: String
    }

    struct RPCRequest: Encodable {
        let jsonrpc: String
        let method: String
        let params: [AnyEncodable]
        let id: Int
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
