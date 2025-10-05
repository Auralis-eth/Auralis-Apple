import Foundation

struct CacheMetadata: Codable, Sendable {
    var originalURL: String
    var etag: String?
    var lastModified: String?
    var createdAt: Date
    var updatedAt: Date
}

struct CacheMetadataStore {
    let sidecarExtension: String

    func url(forFileURL fileURL: URL) -> URL {
        fileURL.appendingPathExtension(sidecarExtension)
    }

    func save(from response: URLResponse, forFileURL fileURL: URL, originalURL: URL) {
        guard let http = response as? HTTPURLResponse else { return }
        let meta = CacheMetadata(
            originalURL: originalURL.absoluteString,
            etag: http.value(forHTTPHeaderField: "ETag"),
            lastModified: http.value(forHTTPHeaderField: "Last-Modified"),
            createdAt: Date(),
            updatedAt: Date()
        )
        do {
            let data = try JSONEncoder().encode(meta)
            try data.write(to: url(forFileURL: fileURL), options: [.atomic])
        } catch {
            // best effort
        }
    }

    func load(forFileURL fileURL: URL) -> CacheMetadata? {
        let url = url(forFileURL: fileURL)
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(CacheMetadata.self, from: data)
    }

    func delete(forFileURL fileURL: URL) {
        try? FileManager.default.removeItem(at: url(forFileURL: fileURL))
    }
}

extension URLRequest {
    mutating func applyConditionalHeaders(from meta: CacheMetadata?) {
        guard let meta else { return }
        if let etag = meta.etag { addValue(etag, forHTTPHeaderField: "If-None-Match") }
        if let lm = meta.lastModified { addValue(lm, forHTTPHeaderField: "If-Modified-Since") }
    }
}
