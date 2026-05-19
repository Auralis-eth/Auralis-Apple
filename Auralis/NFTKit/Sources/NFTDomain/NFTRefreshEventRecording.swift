import AuralisPrimaryModels
import Foundation

@MainActor
public protocol NFTRefreshEventRecording {
    func recordRefreshStarted(
        accountAddress: String,
        chain: Chain,
        correlationID: String
    ) async

    func recordFetchSucceeded(
        accountAddress: String,
        chain: Chain,
        correlationID: String,
        itemCount: Int,
        totalCount: Int?
    ) async

    func recordFetchFailed(
        accountAddress: String,
        chain: Chain,
        correlationID: String,
        error: Error
    ) async

    func recordPersistenceCompleted(
        accountAddress: String,
        chain: Chain,
        correlationID: String,
        persistedCount: Int
    ) async

    func recordPersistenceFailed(
        accountAddress: String,
        chain: Chain,
        correlationID: String,
        error: Error
    ) async
}

public struct NoOpNFTRefreshEventRecorder: NFTRefreshEventRecording {
    public init() { }

    public func recordRefreshStarted(
        accountAddress: String,
        chain: Chain,
        correlationID: String
    ) async { }

    public func recordFetchSucceeded(
        accountAddress: String,
        chain: Chain,
        correlationID: String,
        itemCount: Int,
        totalCount: Int?
    ) async { }

    public func recordFetchFailed(
        accountAddress: String,
        chain: Chain,
        correlationID: String,
        error: Error
    ) async { }

    public func recordPersistenceCompleted(
        accountAddress: String,
        chain: Chain,
        correlationID: String,
        persistedCount: Int
    ) async { }

    public func recordPersistenceFailed(
        accountAddress: String,
        chain: Chain,
        correlationID: String,
        error: Error
    ) async { }
}
