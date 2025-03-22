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
        if let host = host() {
            let gateway = "gateway.pinata.cloud"//"dweb.link"
            return URL(string: "https://\(gateway)/ipfs/\(host)\(path)")
        } else {
            return nil
        }
    }

    /// Checks if the URL path ends with ".mp4".
    ///
    /// - Returns: `true` if the URL path has a suffix of ".mp4", `false` otherwise.
    var isVideoMP4: Bool {
        path.hasSuffix(".mp4")
    }
}
