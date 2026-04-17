import Foundation

protocol ENSEventRecording {
    func recordCacheHit(
        kind: String,
        key: String,
        fetchedAt: Date,
        correlationID: String?
    ) async

    func recordLookupStarted(
        kind: String,
        key: String,
        correlationID: String?
    ) async

    func recordLookupSucceeded(
        kind: String,
        key: String,
        value: String,
        verification: Bool?,
        correlationID: String?
    ) async

    func recordLookupFailed(
        kind: String,
        key: String,
        correlationID: String?,
        error: Error
    ) async

    func recordMappingChanged(
        kind: String,
        key: String,
        oldValue: String,
        newValue: String,
        correlationID: String?
    ) async
}
