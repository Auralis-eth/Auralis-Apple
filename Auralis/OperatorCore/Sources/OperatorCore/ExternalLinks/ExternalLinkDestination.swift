import Foundation

public struct ExternalLinkCandidateDestination: Equatable, Sendable {
    public let label: String
    public let url: URL

    public init(label: String, url: URL) {
        self.label = label
        self.url = url
    }
}

public struct ExternalLinkConfirmationDestination: Identifiable, Equatable, Sendable {
    public let label: String
    public let url: URL
    public let hostDisplay: String
    public let pathDisplay: String
    public let routeTypeDisplay: String
    public let fullURLDisplay: String

    public var id: String {
        fullURLDisplay
    }

    public init(
        label: String,
        url: URL,
        hostDisplay: String,
        pathDisplay: String,
        routeTypeDisplay: String = "Approved route",
        fullURLDisplay: String
    ) {
        self.label = label
        self.url = url
        self.hostDisplay = hostDisplay
        self.pathDisplay = pathDisplay
        self.routeTypeDisplay = routeTypeDisplay
        self.fullURLDisplay = fullURLDisplay
    }
}
