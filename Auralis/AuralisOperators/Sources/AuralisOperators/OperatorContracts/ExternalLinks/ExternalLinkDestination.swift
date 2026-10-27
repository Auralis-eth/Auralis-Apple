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

    /// The percent-encoded query, or `nil` when the URL carries none.
    ///
    /// Separate from ``pathDisplay`` because the allowlist approves a host and a path prefix and says
    /// nothing about the query, which makes it the one part of an approved URL a confirmation surface
    /// would otherwise present only buried inside ``fullURLDisplay``.
    public let queryDisplay: String?

    /// The percent-encoded fragment, or `nil` when the URL carries none.
    ///
    /// Separate for the same reason as ``queryDisplay``: the allowlist says nothing about it, and a
    /// hash-routed page decides which view it renders from it, so a fragment left inside
    /// ``fullURLDisplay`` is a part of the destination the host and route lines quietly understate.
    public let fragmentDisplay: String?
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
        queryDisplay: String? = nil,
        fragmentDisplay: String? = nil,
        routeTypeDisplay: String = "Approved route",
        fullURLDisplay: String
    ) {
        self.label = label
        self.url = url
        self.hostDisplay = hostDisplay
        self.pathDisplay = pathDisplay
        self.queryDisplay = queryDisplay
        self.fragmentDisplay = fragmentDisplay
        self.routeTypeDisplay = routeTypeDisplay
        self.fullURLDisplay = fullURLDisplay
    }
}
