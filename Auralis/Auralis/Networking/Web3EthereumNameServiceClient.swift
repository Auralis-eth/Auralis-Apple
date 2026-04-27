import Foundation
@preconcurrency import web3

final class Web3EthereumNameServiceClient: EthereumNameServiceClient, Sendable {
    private enum ClientError: Error {
        case timedOut
    }

    private let rpcURL: URL
    let allowsOffchainLookup: Bool
    private let requestTimeout: Duration
    private let maxAttempts: Int
    private let initialRetryDelay: Duration
    private let maxRetryDelay: Duration

    init(
        rpcURL: URL,
        allowsOffchainLookup: Bool = true,
        requestTimeout: Duration = .seconds(15),
        maxAttempts: Int = 3,
        initialRetryDelay: Duration = .milliseconds(500),
        maxRetryDelay: Duration = .seconds(2)
    ) {
        self.rpcURL = rpcURL
        self.allowsOffchainLookup = allowsOffchainLookup
        self.requestTimeout = requestTimeout
        self.maxAttempts = max(1, maxAttempts)
        self.initialRetryDelay = initialRetryDelay
        self.maxRetryDelay = maxRetryDelay
    }

    func resolveAddress(forENS name: String) async throws -> String {
        try await performWithRetry {
            if self.allowsOffchainLookup {
                let address = try await self.makeEthereumNameService().resolve(
                    ens: name,
                    mode: .allowOffchainLookup
                )
                return address.asString()
            } else {
                let address = try await self.makeEthereumNameService().resolve(
                    ens: name,
                    mode: .onchain
                )
                return address.asString()
            }
        }
    }

    func resolveName(forAddress address: String) async throws -> String {
        try await performWithRetry {
            if self.allowsOffchainLookup {
                return try await self.makeEthereumNameService().resolve(
                    address: EthereumAddress(address),
                    mode: .allowOffchainLookup
                )
            }

            return try await self.makeEthereumNameService().resolve(
                address: EthereumAddress(address),
                mode: .onchain
            )
        }
    }

    private func makeEthereumNameService() -> EthereumNameService {
        let client = EthereumHttpClient(url: rpcURL, network: .mainnet)
        return EthereumNameService(client: client)
    }

    private func performWithRetry(
        operation: @escaping @Sendable () async throws -> String
    ) async throws -> String {
        var attempt = 0
        var retryDelay = initialRetryDelay

        while true {
            do {
                return try await withTimeout(operation: operation)
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                attempt += 1
                guard attempt < maxAttempts, shouldRetry(after: error) else {
                    throw error
                }

                try await Task.sleep(for: retryDelay)
                retryDelay = min(retryDelay * 2, maxRetryDelay)
            }
        }
    }

    private func withTimeout(
        operation: @escaping @Sendable () async throws -> String
    ) async throws -> String {
        try await withThrowingTaskGroup(of: String.self) { group in
            group.addTask(operation: operation)
            group.addTask {
                try await Task.sleep(for: self.requestTimeout)
                throw ClientError.timedOut
            }

            guard let result = try await group.next() else {
                group.cancelAll()
                throw ClientError.timedOut
            }

            group.cancelAll()
            return result
        }
    }

    private func shouldRetry(after error: Error) -> Bool {
        if error is ClientError {
            return true
        }

        if let urlError = error as? URLError {
            switch urlError.code {
            case .timedOut, .cannotConnectToHost, .networkConnectionLost:
                return true
            case .notConnectedToInternet:
                return false
            default:
                return false
            }
        }

        if let nsError = error as NSError?,
           nsError.domain == NSURLErrorDomain {
            switch nsError.code {
            case NSURLErrorTimedOut,
                    NSURLErrorCannotConnectToHost,
                    NSURLErrorNetworkConnectionLost:
                return true
            case NSURLErrorNotConnectedToInternet:
                return false
            default:
                return false
            }
        }

        if let ensError = error as? EthereumNameServiceError {
            switch ensError {
            case .noNetwork:
                return false
            case .invalidInput, .ensUnknown, .decodeIssue, .tooManyRedirections:
                return false
            }
        }

        return false
    }
}
