import Foundation

struct AlchemyRPCProvider: NativeBalanceProviding {
    private enum RPCRequestError: Error {
        case badStatus(Int, retryAfter: TimeInterval?)
        case invalidResponse
    }

    private static let session: URLSession = {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 10
        configuration.timeoutIntervalForResource = 30
        return URLSession(configuration: configuration)
    }()

    private static let nanosecondsPerSecond: UInt64 = 1_000_000_000

    private let configurationResolver: any ProviderConfigurationResolving
    private let session: URLSession
    private let maxRetryCount: Int
    private let baseDelayNanoseconds: UInt64
    private let maxDelayNanoseconds: UInt64

    init(
        configurationResolver: any ProviderConfigurationResolving = LiveProviderConfigurationResolver(),
        session: URLSession = Self.session,
        maxRetryCount: Int = 3,
        baseDelayNanoseconds: UInt64 = Self.nanosecondsPerSecond,
        maxDelayNanoseconds: UInt64 = 8 * Self.nanosecondsPerSecond
    ) {
        self.configurationResolver = configurationResolver
        self.session = session
        self.maxRetryCount = maxRetryCount
        self.baseDelayNanoseconds = baseDelayNanoseconds
        self.maxDelayNanoseconds = maxDelayNanoseconds
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

        return try await fetchWithRetry(
            address: normalizedAddress,
            rpcURL: rpcURL
        )
    }
}

extension AlchemyRPCProvider {
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
        let params: [String]
        let id: Int
    }

    private func fetchWithRetry(
        address: String,
        rpcURL: URL
    ) async throws -> NativeBalance {
        var delay = baseDelayNanoseconds

        for attempt in 1...maxRetryCount {
            do {
                return try await fetchOnce(address: address, rpcURL: rpcURL)
            } catch {
                guard attempt < maxRetryCount, shouldRetry(after: error) else {
                    throw mapTransportError(error)
                }

                try await Task.sleep(nanoseconds: retryDelay(after: error, fallbackDelay: delay))
                let (nextDelay, overflowed) = delay.multipliedReportingOverflow(by: 2)
                delay = overflowed ? maxDelayNanoseconds : min(nextDelay, maxDelayNanoseconds)
            }
        }

        throw ProviderAbstractionError.invalidResponse
    }

    private func fetchOnce(
        address: String,
        rpcURL: URL
    ) async throws -> NativeBalance {
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

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw error
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw RPCRequestError.invalidResponse
        }
        guard (200...299).contains(httpResponse.statusCode) else {
            throw RPCRequestError.badStatus(
                httpResponse.statusCode,
                retryAfter: parseRetryAfter(from: httpResponse)
            )
        }

        let payload = try JSONDecoder().decode(RPCEnvelope<String>.self, from: data)
        if let error = payload.error {
            throw mapRPCError(error)
        }

        guard let result = payload.result,
              let weiDecimal = Self.decimalString(fromHexQuantity: result) else {
            throw ProviderAbstractionError.invalidBalancePayload
        }

        return NativeBalance(weiHex: result, weiDecimal: weiDecimal)
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

        if let requestError = error as? RPCRequestError {
            switch requestError {
            case .badStatus(let statusCode, _):
                return statusCode == 429 || (500...599).contains(statusCode)
            case .invalidResponse:
                return false
            }
        }

        if let providerError = error as? ProviderAbstractionError {
            switch providerError {
            case .rateLimited, .unavailable:
                return true
            default:
                return false
            }
        }

        return false
    }

    private func mapRPCError(_ error: RPCErrorPayload) -> ProviderAbstractionError {
        let normalizedMessage = error.message.lowercased()

        if error.code == 429 || normalizedMessage.contains("rate limit") {
            return .rateLimited
        }

        if error.code == -32601 || normalizedMessage.contains("method not found") {
            return .unsupportedMethod
        }

        if normalizedMessage.contains("unauthorized")
            || normalizedMessage.contains("forbidden")
            || normalizedMessage.contains("api key") {
            return .unauthorized
        }

        return .providerError(error.message)
    }

    private func mapTransportError(_ error: Error) -> Error {
        if let requestError = error as? RPCRequestError {
            switch requestError {
            case .badStatus(let statusCode, _) where statusCode == 429:
                return ProviderAbstractionError.rateLimited
            case .badStatus(let statusCode, _) where statusCode == 401 || statusCode == 403:
                return ProviderAbstractionError.unauthorized
            case .badStatus(let statusCode, _) where (500...599).contains(statusCode):
                return ProviderAbstractionError.unavailable
            case .badStatus, .invalidResponse:
                return ProviderAbstractionError.invalidResponse
            }
        }

        return error
    }

    private func retryDelay(after error: Error, fallbackDelay: UInt64) -> UInt64 {
        guard case .badStatus(_, let retryAfter?) = error as? RPCRequestError else {
            return fallbackDelay
        }

        return UInt64(max(0, retryAfter) * Double(Self.nanosecondsPerSecond))
    }

    private func parseRetryAfter(from response: HTTPURLResponse) -> TimeInterval? {
        guard let header = response.value(forHTTPHeaderField: "Retry-After") else {
            return nil
        }

        return TimeInterval(header.trimmingCharacters(in: .whitespacesAndNewlines))
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
