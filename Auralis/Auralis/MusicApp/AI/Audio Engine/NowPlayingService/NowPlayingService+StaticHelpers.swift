import Foundation
import CoreGraphics

extension NowPlayingService {
    nonisolated static func normalizeHostASCII(_ host: String) -> String? {
        guard !host.isEmpty else { return nil }
        if let url = URL(string: "https://\(host)/"), let h = url.host { return h.lowercased() }
        var comps = URLComponents()
        comps.scheme = "https"
        comps.host = host
        if let h = comps.url?.host { return h.lowercased() }
        return host.lowercased()
    }

    nonisolated static func isStrictSubdomain(_ host: String, of parent: String) -> Bool {
        let h = host.lowercased()
        let p = parent.lowercased()
        return h != p && h.hasSuffix("." + p)
    }

    nonisolated static func host(_ host: String, isSubdomainOf parent: String) -> Bool {
        let h = host.lowercased()
        let p = parent.lowercased()
        return h == p || h.hasSuffix("." + p)
    }

    nonisolated static func effectiveTLDPlusOne(_ host: String) -> String? {
        let h = normalizeHostASCII(host) ?? ""
        guard !h.isEmpty else { return nil }
        let labels = h.split(separator: ".").map(String.init)
        guard labels.count >= 2 else { return h }
        let multiLabelSuffixes: Set<String> = [
            "co.uk", "org.uk", "gov.uk", "ac.uk",
            "com.au", "net.au", "org.au", "edu.au",
            "co.jp", "ne.jp", "or.jp",
            "co.nz", "org.nz", "govt.nz"
        ]
        let lastTwo = labels.suffix(2).joined(separator: ".")
        if multiLabelSuffixes.contains(lastTwo), labels.count >= 3 {
            return labels.suffix(3).joined(separator: ".")
        } else {
            return lastTwo
        }
    }

    nonisolated static func isFinalURLAllowed(finalURL: URL?, originalHostASCII: String?, redirectAllowlist: [String]?, orgDomains: [String]?) -> (allowed: Bool, finalHostASCII: String?) {
        guard let url = finalURL, url.scheme?.lowercased() == "https" else { return (false, nil) }
        let finalHostRaw = url.host
        let finalHostASCII = finalHostRaw.flatMap { normalizeHostASCII($0) }
        guard let fh = finalHostASCII else { return (false, nil) }
        if let orig = originalHostASCII, fh == orig { return (true, fh) }
        if let list = redirectAllowlist, list.contains(fh) { return (true, fh) }
        if let orgs = orgDomains, !orgs.isEmpty {
            if let fhETLD1 = effectiveTLDPlusOne(fh) {
                for p in orgs {
                    if isStrictSubdomain(fh, of: p), let pETLD1 = effectiveTLDPlusOne(p), pETLD1 == fhETLD1 {
                        return (true, fh)
                    }
                }
            }
        }
        return (false, fh)
    }
}
