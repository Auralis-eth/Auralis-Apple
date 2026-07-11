import Foundation

public protocol MediaEngineLogging: Sendable {
    func info(_ message: String)
    func error(_ message: String)
}

public struct NoOpMediaEngineLogger: MediaEngineLogging {
    public init() {}

    public func info(_ message: String) {}
    public func error(_ message: String) {}
}

