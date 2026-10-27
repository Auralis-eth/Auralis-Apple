import AuralisFoundation
import Foundation

public struct IntentID: Hashable, Codable, Sendable, RawRepresentable {
    public let rawValue: UUID

    public init(rawValue: UUID) {
        self.rawValue = rawValue
    }
}

public enum IntentSource: String, Codable, Sendable {
    case explicitHuman = "explicit_human"
    case inferred
    case imported
}

public struct IntentAuthorization: Equatable, Codable, Sendable {
    public let principalID: PrincipalID
    public let authorizedAt: Date
    public let evidenceReference: String

    public init(principalID: PrincipalID, authorizedAt: Date, evidenceReference: String) {
        self.principalID = principalID
        self.authorizedAt = authorizedAt
        self.evidenceReference = evidenceReference
    }
}

public struct Intent: Identifiable, Equatable, Codable, Sendable {
    public let id: IntentID
    public let summary: String
    public let desiredOutcome: String
    public let source: IntentSource
    public let capturedAt: Date
    public let authorization: IntentAuthorization?

    public init(
        id: IntentID = IntentID(rawValue: UUID()),
        summary: String,
        desiredOutcome: String,
        source: IntentSource,
        capturedAt: Date = .now,
        authorization: IntentAuthorization? = nil
    ) {
        self.id = id
        self.summary = summary
        self.desiredOutcome = desiredOutcome
        self.source = source
        self.capturedAt = capturedAt
        self.authorization = authorization
    }

    public func authorized(
        by principalID: PrincipalID,
        at date: Date = .now,
        evidenceReference: String
    ) -> Intent {
        Intent(
            id: id,
            summary: summary,
            desiredOutcome: desiredOutcome,
            source: source,
            capturedAt: capturedAt,
            authorization: IntentAuthorization(
                principalID: principalID,
                authorizedAt: date,
                evidenceReference: evidenceReference
            )
        )
    }
}
