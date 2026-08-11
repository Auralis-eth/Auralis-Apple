import Foundation

enum AuraPlayPlayerTimeFormatter {
    static func string(from seconds: TimeInterval?) -> String {
        guard let seconds, seconds.isFinite else { return "0:00" }
        let totalSeconds = max(0, Int(seconds.rounded()))
        let hours = totalSeconds / 3_600
        let minutes = (totalSeconds % 3_600) / 60
        let secondsComponent = totalSeconds % 60

        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, secondsComponent)
        }
        return String(format: "%d:%02d", minutes, secondsComponent)
    }
}
