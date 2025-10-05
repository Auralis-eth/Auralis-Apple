import Foundation

extension FileManager {
    /// Touches a file by updating its modification date. Optionally creates the file if it doesn't exist.
    /// - Parameters:
    ///   - url: The file URL to touch.
    ///   - createIfMissing: If `true`, creates an empty file when it doesn't exist. Defaults to `true`.
    ///   - now: The timestamp to set as the content modification date. Defaults to `Date()`.
    /// - Returns: `true` if the file existed or was created and the modification date was updated; `false` if the file was missing and `createIfMissing` was `false`.
    /// - Throws: An error if updating resource values fails or file creation fails when requested.
    @discardableResult
    func touch(
        at url: URL,
        createIfMissing: Bool = true,
        now: Date = Date()
    ) throws -> Bool {
        // Create an empty file if missing (do not create parent directories; match typical `touch` semantics)
        if !fileExists(atPath: url.path) {
            guard createIfMissing else { return false }
            guard createFile(atPath: url.path, contents: Data(), attributes: nil) else {
                throw NSError(
                    domain: NSCocoaErrorDomain,
                    code: NSFileWriteUnknownError,
                    userInfo: [NSURLErrorKey: url]
                )
            }
        }

        // Only update the modification date (do not modify creation date)
        var values = URLResourceValues()
        values.contentModificationDate = now
        var mutableURL = url
        try mutableURL.setResourceValues(values)
        return true
    }

    /// Non-throwing convenience wrapper for `touch(at:createIfMissing:now:)` that swallows errors.
    @discardableResult
    func tryTouch(
        at url: URL,
        createIfMissing: Bool = true,
        now: Date = Date()
    ) -> Bool {
        (try? touch(at: url, createIfMissing: createIfMissing, now: now)) ?? false
    }

    /// Backwards-compatible path-based API that performs a "true touch":
    /// creates the file if missing and only updates the modification date.
    /// Errors are intentionally ignored for best-effort behavior.
    func touch(atPath path: String) {
        _ = tryTouch(at: URL(fileURLWithPath: path), createIfMissing: true)
    }
}
