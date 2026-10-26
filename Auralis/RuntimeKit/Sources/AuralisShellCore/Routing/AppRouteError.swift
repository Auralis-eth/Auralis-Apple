import Foundation

public struct AppRouteError: Error, Identifiable, Hashable, Sendable {
    public let id: UUID
    public let title: String
    public let message: String
    public let urlString: String?

    public init(
        id: UUID = UUID(),
        title: String,
        message: String,
        urlString: String?
    ) {
        self.id = id
        self.title = title
        self.message = message
        self.urlString = urlString
    }
}
