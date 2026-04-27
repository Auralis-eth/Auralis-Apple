import Foundation

enum RetryAfterSupport {
    static func parse(_ header: String, now: Date = .now) -> TimeInterval? {
        let trimmedHeader = header.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedHeader.isEmpty else {
            return nil
        }

        if let seconds = TimeInterval(trimmedHeader) {
            return seconds
        }

        guard let retryDate = httpDateParsers.lazy.compactMap({ $0.date(from: trimmedHeader) }).first else {
            return nil
        }

        return max(0, retryDate.timeIntervalSince(now))
    }

    static func parse(from response: HTTPURLResponse, now: Date = .now) -> TimeInterval? {
        guard let header = response.value(forHTTPHeaderField: "Retry-After") else {
            return nil
        }

        return parse(header, now: now)
    }

    private static let httpDateParsers: [DateFormatter] = [
        makeFormatter("EEE',' dd MMM yyyy HH':'mm':'ss zzz"),
        makeFormatter("EEEE',' dd'-'MMM'-'yy HH':'mm':'ss zzz"),
        makeFormatter("EEE MMM d HH':'mm':'ss yyyy")
    ]

    private static func makeFormatter(_ format: String) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = format
        return formatter
    }
}
