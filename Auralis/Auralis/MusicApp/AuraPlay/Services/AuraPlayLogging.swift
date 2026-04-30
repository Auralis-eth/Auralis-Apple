import Foundation
import OSLog

enum AuraPlayLogCategory: String, Sendable {
    case library = "music.library"
    case playback = "music.playback"
    case queue = "music.queue"
    case artwork = "music.artwork"
    case sync = "music.sync"
}

enum AuraPlayLogLevel: Sendable {
    case debug
    case info
    case error
}

struct AuraPlayLogEvent: Equatable, Sendable {
    let category: AuraPlayLogCategory
    let level: AuraPlayLogLevel
    let message: String
}

@MainActor
protocol AuraPlayLogging {
    func log(_ event: AuraPlayLogEvent)
}

@MainActor
struct LiveAuraPlayLogger: AuraPlayLogging {
    private let subsystem = "Auralis"

    func log(_ event: AuraPlayLogEvent) {
        let logger = Logger(subsystem: subsystem, category: event.category.rawValue)

        switch event.level {
        case .debug:
            logger.debug("\(event.message, privacy: .public)")
        case .info:
            logger.info("\(event.message, privacy: .public)")
        case .error:
            logger.error("\(event.message, privacy: .public)")
        }
    }
}
