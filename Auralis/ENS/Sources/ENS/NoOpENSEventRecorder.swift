import Foundation

public struct NoOpENSEventRecorder: ENSEventRecording, Sendable {
    public init() { }

    public func recordCacheHit(
        kind: String,
        key: String,
        fetchedAt: Date,
        correlationID: String?
    ) async { }

    public func recordLookupStarted(
        kind: String,
        key: String,
        correlationID: String?
    ) async { }

    public func recordLookupSucceeded(
        kind: String,
        key: String,
        value: String,
        verification: Bool?,
        correlationID: String?
    ) async { }

    public func recordLookupFailed(
        kind: String,
        key: String,
        correlationID: String?,
        error: Error
    ) async { }

    public func recordMappingChanged(
        kind: String,
        key: String,
        oldValue: String,
        newValue: String,
        correlationID: String?
    ) async { }
}
