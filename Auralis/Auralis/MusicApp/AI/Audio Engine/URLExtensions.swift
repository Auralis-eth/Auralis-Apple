import Foundation

extension URL {
    var audioCacheKey: String {
        Data(absoluteString.utf8).base64EncodedString()
    }

    var safePathExtensionOrNil: String? {
        pathExtension.isEmpty ? nil : pathExtension
    }
}

extension URLRequest {
    static func audioGET(_ url: URL, timeout: TimeInterval = 30.0) -> URLRequest {
        var req = URLRequest(url: url)
        req.timeoutInterval = timeout
        req.cachePolicy = .reloadIgnoringLocalCacheData
        req.httpMethod = "GET"
        return req
    }
}

extension URLResponse {
    func validateAudioResponse() throws {
        if let http = self as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            throw URLError(.badServerResponse)
        }
        if let mime = mimeType, !mime.lowercased().hasPrefix("audio/") {
            throw URLError(.cannotDecodeContentData)
        }
    }
}
