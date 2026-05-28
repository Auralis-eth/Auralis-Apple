import Foundation

public extension String {
    var auraGroupedForSpeech: String {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 12 else {
            return trimmed
        }

        let prefix: String
        let body: Substring
        if trimmed.lowercased().hasPrefix("0x") {
            prefix = "0 x"
            body = trimmed.dropFirst(2)
        } else {
            prefix = ""
            body = Substring(trimmed)
        }

        guard body.allSatisfy(\.isHexDigit) else {
            return trimmed
        }

        let grouped = body.chunkedForSpeech(groupSize: 4)
        return prefix.isEmpty ? grouped : "\(prefix) \(grouped)"
    }

    var auraDisplayAddress: String {
        guard count > 10 else {
            return self
        }

        return "\(prefix(6))...\(suffix(4))"
    }
}

private extension Substring {
    func chunkedForSpeech(groupSize: Int) -> String {
        var chunks: [String] = []
        var current = startIndex

        while current < endIndex {
            let next = index(current, offsetBy: groupSize, limitedBy: endIndex) ?? endIndex
            chunks.append(String(self[current..<next]))
            current = next
        }

        return chunks.joined(separator: " ")
    }
}
