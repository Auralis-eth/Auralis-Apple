import Foundation

public protocol ExplorerURLBuilding: Sendable {
    func url(for destination: ExplorerDestination) throws -> URL
}
