import Foundation
import OSLog

public enum AuraPlayLogCategory: String, Sendable {
    case library = "music.library"
    case playback = "music.playback"
    case queue = "music.queue"
    case artwork = "music.artwork"
    case sync = "music.sync"
}

public enum AuraPlayLogLevel: Sendable {
    case debug
    case info
    case warning
    case error
}

public struct AuraPlayLogEvent: Equatable, Sendable {
    public let category: AuraPlayLogCategory
    public let level: AuraPlayLogLevel
    public let message: String

    public init(category: AuraPlayLogCategory, level: AuraPlayLogLevel, message: String) {
        self.category = category
        self.level = level
        self.message = message
    }
}

public protocol AuraPlayLogging: Sendable {
    func log(_ event: AuraPlayLogEvent)
}

public struct LiveAuraPlayLogger: AuraPlayLogging, Sendable {
    private let subsystem = "Auralis"

    public init() {}

    public func log(_ event: AuraPlayLogEvent) {
        let logger = Logger(subsystem: subsystem, category: event.category.rawValue)

        switch event.level {
        case .debug:
            logger.debug("\(event.message, privacy: .public)")
        case .info:
            logger.info("\(event.message, privacy: .public)")
        case .warning:
            logger.warning("\(event.message, privacy: .public)")
        case .error:
            logger.error("\(event.message, privacy: .public)")
        }
    }
}
