//
//  URL.swift
//  Auralis
//
//  Created by Daniel Bell on 3/13/25.
//

import Foundation

extension URL {
    var isIPFS: Bool {
        scheme == "ipfs"
    }
    var ipfsHTML: URL? {
        toPinataGatewayURL()
    }

    /// Checks if the URL path ends with ".mp4".
    ///
    /// - Returns: `true` if the URL path has a suffix of ".mp4", `false` otherwise.
    var isVideoMP4: Bool {
        let lowercasePath = path.lowercased()
        return lowercasePath.hasSuffix(".mp4")
    }

    var isVideo: Bool {
        let lowercasePath = path.lowercased()
        return [".mp4", ".mov", ".m4v", ".avi"].contains { lowercasePath.hasSuffix($0) }
    }


    /// Converts the URL to its Pinata IPFS gateway representation.
    ///
    /// This method takes the host and path of the current URL and constructs
    /// a new URL pointing to the Pinata IPFS gateway. Query parameters and
    /// fragments from the original URL are preserved.
    ///
    /// - Returns: A new `URL` object for the Pinata IPFS gateway, or `nil` if the
    ///            original URL does not have a scheme or a non-empty host.
    ///
    public func toPinataGatewayURL() -> URL? {
        // 1. The original URL must have a scheme.
        //    This handles cases like "://example.com", where `self.scheme` would be nil.
        guard scheme != nil else {
            return nil
        }

        // 2. The original URL must have a host, and it must not be empty.
        //    This handles cases like "ipfs://" or "http://" (if host is missing or empty),
        //    where `self.host` might be nil or an empty string.
        guard let originalHost = host, !originalHost.isEmpty else {
            return nil
        }

        var components = URLComponents()
        components.scheme = "https"
        components.host = "gateway.pinata.cloud"

        // Construct the new path using "/ipfs/", the original host, and the original path.
        // `self.path` from a URL object correctly includes a leading "/" if the path segment
        // is not empty (e.g., "/folder/file.txt"), or is an empty string if there's no path
        // (e.g., for "ipfs://QmHash"), or "/" if the URL ends with a slash (e.g., "ipfs://QmHash/").
        // Examples of `components.path` construction:
        // - If original URL is "ipfs://QmHash" (self.path is ""), new path: "/ipfs/QmHash"
        // - If original URL is "ipfs://QmHash/" (self.path is "/"), new path: "/ipfs/QmHash/"
        // - If original URL is "ipfs://QmHash/file.txt" (self.path is "/file.txt"), new path: "/ipfs/QmHash/file.txt"
        components.path = "/ipfs/\(originalHost)"

        if path() != "/" {
            components.path += path()
        }

        // Preserve original query parameters and fragment.
        components.query = query
        components.fragment = fragment

        return components.url
    }
}
