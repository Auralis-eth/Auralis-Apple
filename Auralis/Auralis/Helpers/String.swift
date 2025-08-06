//
//  String.swift
//  KickingHorse
//
//  Created by Daniel Bell on 8/24/24.
//

import Foundation

extension String {
    var isHexIgnorePrefix: Bool {
        guard !isEmpty else {
            return false
        }
        let updatedValue = hasPrefix("0x") ? self : "0x" + self
        return updatedValue.isHex
    }

    var isHex: Bool {
        range(of: #"^0x[0-9A-Fa-f]*$"#, options: .regularExpression) != nil
    }
}

extension String {
    var displayAddress: String {
        if count > 10 {
            let start = prefix(6)
            let end = suffix(4)
            return "\(start)...\(end)"
        }
        return self
    }
}

extension String {
    /// Initializes a URL with a string and converts it to an IPFS gateway URL
    /// - Parameter string: The URL string to convert
    /// - Returns: An IPFS gateway URL or nil if conversion fails
    func ipfsGatewayURL() -> URL? {
        guard contains("ipfs") else {
            return nil
        }
        guard !isEmpty, let url = URL(string: self) else {
            return nil
        }

        return url.toPinataGatewayURL()
    }
}


extension String {
    func extractSVGData() -> String? {
        do {
            // Regex for UTF-8, charset, and direct SVG
            let directRegex = try NSRegularExpression(pattern: "data:image/svg\\+xml(;charset=utf-8|;utf8)?,(<svg.*)", options: .caseInsensitive)
            let directMatches = directRegex.matches(in: self, range: NSRange(self.startIndex..., in: self))
            if let match = directMatches.first {
                let svgRange = match.range(at: match.numberOfRanges - 1)
                if svgRange.location != NSNotFound, let range = Range(svgRange, in: self) {
                    let svg = String(self[range])
                    // URL-decode if needed
                    return svg.removingPercentEncoding ?? svg
                }
            }

            // Regex for Base64
            let base64Regex = try NSRegularExpression(pattern: "data:image/svg\\+xml;base64,(.+)", options: .caseInsensitive)
            let base64Matches = base64Regex.matches(in: self, range: NSRange(self.startIndex..., in: self))
            if let match = base64Matches.first, match.numberOfRanges == 2 {
                let dataRange = match.range(at: 1)
                if dataRange.location != NSNotFound, let range = Range(dataRange, in: self) {
                    let base64 = String(self[range])
                    if let data = Data(base64Encoded: base64), let svg = String(data: data, encoding: .utf8) {
                        return svg
                    }
                }
            }
        } catch {
            print("Regex error: \(error)")
        }
        return nil
    }
}

extension String {
    //// Function to decode a raw token URI string to a dictionary
    var base64JSON: [String: JSONValue]? {
        // Extract the base64 part from the URI
        // Format is: data:application/json;base64,<BASE64_ENCODED_JSON>
        guard let base64StartRange = self.range(of: "base64,") else {
            print("Failed to decode token URI: Missing base64 prefix")
            return nil
        }

        let base64StartIndex = base64StartRange.upperBound
        let base64String = String(self[base64StartIndex...])

        // Decode the base64 string to data
        guard let jsonData = Data(base64Encoded: base64String.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            print("Failed to decode token URI: Invalid base64 encoding")
            return nil
        }

        // Parse the JSON as dictionary
        do {
            guard let jsonDict = try JSONSerialization.jsonObject(with: jsonData) as? [String: JSONValue] else {
                print("Failed to decode token URI: JSON could not be converted to dictionary")
                return nil
            }
            return jsonDict
        } catch {
            print("Failed to decode token URI: \(error.localizedDescription)")
            return nil
        }
    }
}
