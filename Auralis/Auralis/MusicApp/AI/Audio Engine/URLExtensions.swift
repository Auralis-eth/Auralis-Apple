import Foundation
import UniformTypeIdentifiers
import CryptoKit

// MARK: - Canonicalization Configuration
/// Immutable, thread-safe canonicalization configuration. Adjust at compile time.
public enum AudioURLCanonicalizationConfig {
    /// Case-insensitive exact names to drop from query during canonicalization.
    public static let volatileParamNames: Set<String> = [
        // Common AWS S3 pre-signed params
        "x-amz-algorithm", "x-amz-credential", "x-amz-date", "x-amz-expires",
        "x-amz-signedheaders", "x-amz-signature", "x-amz-security-token", "x-amz-user-agent",
        // Legacy/alt names
        "awsaccesskeyid", "signature", "expires",
        // Google Cloud Storage pre-signed params (V4)
        "x-goog-algorithm", "x-goog-credential", "x-goog-date", "x-goog-expires",
        "x-goog-signedheaders", "x-goog-signature", "x-goog-user-project",
        // Google Cloud Storage V2 style
        "googleaccessid",
        // Azure SAS parameters
        "sv", "sig", "se", "sp", "spr", "st", "sr", "srt",
        "skoid", "sktid", "skt", "ske", "sks", "skv", "sip", "si",
        // Generic tokens
        "x-token", "token", "access_token"
    ]

    /// Case-insensitive prefixes; any query name starting with one of these will be dropped.
    public static let volatileParamPrefixes: [String] = [
        "x-amz-", "x-goog-"
    ]
    public static let volatileParamPrefixesLowercased: [String] = volatileParamPrefixes.map { $0.lowercased() }
}

// MARK: - URL Cache Key (Canonical, URL-safe, Privacy-Preserving)
extension URL {
    /// Returns a canonical, URL-safe, privacy-preserving cache key for this URL.
    ///
    /// Properties:
    /// - Canonicalization: lowercases scheme/host, strips default ports, removes fragments,
    ///   normalizes percent-escapes, and stably sorts query items.
    /// - Digest: SHA-256 of the canonical string, encoded as base64url without padding.
    /// - URL-safe: Only [A-Za-z0-9-_] are used; no '/', '+', or '='.
    /// - Privacy: Non-reversible; no raw URL material is present in the key.
    var audioCacheKey: String {
        let canonical = canonicalURLString()
        let digest = SHA256.hash(data: Data(canonical.utf8))
        // Base64URL without padding
        let b64 = Data(digest).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        return b64
    }

    /// Returns a lowercased path extension if present, otherwise nil.
    /// Callers can prefer MIME (when trustworthy) over extension; when MIME is
    /// missing or generic (e.g., application/octet-stream), extension can be used
    /// to infer audio types via UTType.
    var safePathExtensionOrNil: String? {
        let ext = pathExtension
        return ext.isEmpty ? nil : ext.lowercased()
    }

    /// Builds a canonicalized string for this URL.
    /// - Lowercases scheme and host
    /// - Removes fragment
    /// - Removes default ports (80 for http, 443 for https)
    /// - Normalizes percent-encoding via URLComponents
    /// - Stably sorts query items by name then value
    private func canonicalURLString() -> String {
        guard var comps = URLComponents(url: self, resolvingAgainstBaseURL: false) else {
            // Fallback: raw absoluteString hashed will still be digested and URL-safe encoded
            return absoluteString
        }

        // Lowercase scheme and host
        if let scheme = comps.scheme { comps.scheme = scheme.lowercased() }
        if let host = comps.host { comps.host = host.lowercased() }

        // Strip fragment
        comps.fragment = nil

        // Strip default ports
        if let scheme = comps.scheme, let port = comps.port {
            let isDefaultHTTP = (scheme == "http" && port == 80)
            let isDefaultHTTPS = (scheme == "https" && port == 443)
            if isDefaultHTTP || isDefaultHTTPS { comps.port = nil }
        }

        // Normalize percent encodings by round-tripping through components
        // Drop volatile query params (case-insensitive) and stably sort remaining items
        if let items = comps.queryItems, !items.isEmpty {
            let filtered: [URLQueryItem] = items.filter { item in
                let name = item.name.lowercased()
                if AudioURLCanonicalizationConfig.volatileParamNames.contains(name) {
                    return false
                }
                for prefix in AudioURLCanonicalizationConfig.volatileParamPrefixesLowercased {
                    if name.hasPrefix(prefix) { return false }
                }
                return true
            }
            if filtered.isEmpty {
                comps.queryItems = nil
            } else {
                comps.queryItems = filtered.sorted { (a, b) -> Bool in
                    if a.name == b.name { return (a.value ?? "") < (b.value ?? "") }
                    return a.name < b.name
                }
            }
        }

        // Ensure we produce a consistent string for hashing; avoid credentials
        comps.user = nil
        comps.password = nil

        // Prefer the fully percent-encoded URL form when possible
        if let encodedURL = comps.url?.absoluteString {
            return encodedURL
        }
        // Fallbacks if URL construction fails
        if let s = comps.string { return s }
        return self.absoluteString
    }
}

// MARK: - Request Construction
extension URLRequest {
    /// Builds a GET request suitable for audio downloads.
    ///
    /// Caching: Uses `.useProtocolCachePolicy` to enable validator-based revalidation (ETag/Last-Modified)
    /// which allows 304 responses and better range/resume interplay.
    ///
    /// Timeout policy: Prefer harmonizing on the URLSession configuration's timeout.
    /// Pass a `timeout` only if you explicitly want to override the session-level policy.
    /// If `timeout` is `nil` (default), this function does not set `timeoutInterval`.
    static func audioGET(_ url: URL, timeout: TimeInterval? = nil) -> URLRequest {
        var req = URLRequest(url: url)
        if let timeout { req.timeoutInterval = timeout }
        req.cachePolicy = .useProtocolCachePolicy
        req.httpMethod = "GET"
        return req
    }
}

// MARK: - Response Validation
public enum AudioResponseError: Error, CustomStringConvertible {
    case httpStatus(code: Int)
    case mimeMismatch(observed: String?)
    case htmlSniffed

    public var description: String {
        switch self {
        case .httpStatus(let code):
            return "HTTP status validation failed: \(code)"
        case .mimeMismatch(let observed):
            return "MIME mismatch: \(observed ?? "<none>")"
        case .htmlSniffed:
            return "HTML content detected in response body"
        }
    }

    /// Analytics tags to help distinguish error kinds.
    public var analyticsTag: (kind: String, code: String) {
        switch self {
        case .httpStatus(let code): return ("httpStatus", String(code))
        case .mimeMismatch(let observed): return ("mimeMismatch", observed ?? "none")
        case .htmlSniffed: return ("mimeMismatch", "html")
        }
    }
}

extension URLResponse {
    /// Validates that the response appears to be audio content.
    ///
    /// Acceptance rules:
    /// - HTTP 2xx, including 206 Partial Content, are allowed; non-2xx throw `.httpStatus`.
    /// - MIME types starting with `audio/` are accepted.
    /// - `application/octet-stream` or missing MIME are accepted if the URL extension or UTType suggests audio.
    /// - If provided, a lightweight HTML sniff rejects clearly non-audio content (e.g., bodies starting with "<html" or "<!DOCTYPE html").
    /// - 3xx should be handled upstream; this validator expects a final response.
    ///
    /// - Parameter body: Optional body data for lightweight sniffing.
    public func validateAudioResponse(body: Data? = nil, url: URL? = nil) throws {
        // HTTP status handling
        if let http = self as? HTTPURLResponse {
            // Reject 204/205 explicitly (no-body success is invalid for audio GETs)
            if http.statusCode == 204 || http.statusCode == 205 {
                throw AudioResponseError.httpStatus(code: http.statusCode)
            }
            // Accept other 2xx including 206; reject others with structured error
            if !(200...299).contains(http.statusCode) {
                throw AudioResponseError.httpStatus(code: http.statusCode)
            }
        }

        // MIME evaluation
        let observedMIME = mimeType?.lowercased()
        let isAudioMIME = observedMIME?.hasPrefix("audio/") == true
        let isOctetStream = observedMIME == "application/octet-stream"
        let isMissingMIME = observedMIME == nil

        // Extension/UTType heuristics (URL path extension and Content-Disposition filename)
        let extIsAudio: Bool = {
            var candidates: [String] = []
            // URL/path extension
            if let urlExt = (url?.safePathExtensionOrNil) ?? (self.url?.pathExtension.lowercased()).flatMap({ $0.isEmpty ? nil : $0 }) {
                candidates.append(urlExt)
            }
            // Content-Disposition filename / filename*
            if let http = self as? HTTPURLResponse {
                let cdHeader: String? = http.value(forHTTPHeaderField: "Content-Disposition")
                    ?? http.allHeaderFields.first(where: { (key, _) in
                        String(describing: key).lowercased() == "content-disposition"
                    }).map { pair in
                        if let s = pair.value as? String { return s }
                        if let ns = pair.value as? NSString { return String(ns) }
                        return nil
                    } ?? nil
                if let cdHeader, let fname = parseContentDispositionFilename(cdHeader) {
                    let ext = URL(fileURLWithPath: fname).pathExtension.lowercased()
                    if !ext.isEmpty { candidates.append(ext) }
                }
            }
            // Check any candidate against UTType.audio
            for ext in candidates {
                if let ut = UTType(filenameExtension: ext), ut.conforms(to: .audio) {
                    return true
                }
            }
            return false
        }()

        // Lightweight HTML sniff if body provided
        if let body, !body.isEmpty {
            // Check small prefix for HTML signatures
            let prefixLen = min(body.count, 1024)
            let snippet = body.prefix(prefixLen)
            if let s = String(data: snippet, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
                if s.hasPrefix("<html") || s.hasPrefix("<!doctype html") {
                    throw AudioResponseError.htmlSniffed
                }
            }
        }

        // Decide acceptance
        if isAudioMIME {
            return
        }
        if isOctetStream || isMissingMIME {
            if extIsAudio { return }
            // For generic/missing MIME, peek at body to detect obvious non-audio kinds
            if let body, !body.isEmpty, let kind = sniffGenericErrorBodyKind(body) {
                throw AudioResponseError.mimeMismatch(observed: kind)
            }
            // If we cannot establish audio via extension or sniffing, treat as mismatch
            throw AudioResponseError.mimeMismatch(observed: observedMIME)
        }

        // Explicit non-audio MIME
        throw AudioResponseError.mimeMismatch(observed: observedMIME)
    }
}

// MARK: - Content-Disposition Parsing Helpers
private func parseContentDispositionFilename(_ header: String) -> String? {
    // Parse Content-Disposition header parameters with quote-aware splitting.
    // Return filename* (RFC 5987) if present, else filename.

    // Split into parts by semicolons not inside quotes
    var parts: [String] = []
    var current = ""
    var inQuotes = false
    var prevWasBackslash = false
    for ch in header {
        if ch == "\"" && !prevWasBackslash {
            inQuotes.toggle()
            current.append(ch)
        } else if ch == ";" && !inQuotes {
            parts.append(current.trimmingCharacters(in: .whitespacesAndNewlines))
            current.removeAll(keepingCapacity: true)
        } else {
            current.append(ch)
        }
        prevWasBackslash = (ch == "\\" && !prevWasBackslash)
    }
    if !current.isEmpty {
        parts.append(current.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    // First token is disposition type; parameters follow
    let paramParts = parts.dropFirst()

    var filenameStar: String?
    var filename: String?

    for part in paramParts {
        // Split only on the first '=' outside of quotes
        var key = ""
        var value = ""
        var seenEquals = false
        inQuotes = false
        prevWasBackslash = false
        for ch in part {
            if ch == "\"" && !prevWasBackslash { inQuotes.toggle() }
            if ch == "=" && !inQuotes && !seenEquals {
                seenEquals = true
                continue
            }
            if seenEquals { value.append(ch) } else { key.append(ch) }
            prevWasBackslash = (ch == "\\" && !prevWasBackslash)
        }
        key = key.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        value = value.trimmingCharacters(in: .whitespacesAndNewlines)

        // Strip surrounding quotes if present (RFC 2616 quoted-string)
        var wasQuoted = false
        if value.hasPrefix("\"") && value.hasSuffix("\"") && value.count >= 2 {
            value = String(value.dropFirst().dropLast())
            wasQuoted = true
        }

        if key == "filename*" {
            if let decoded = decodeRFC5987FilenameStar(value) { filenameStar = decoded }
        } else if key == "filename" {
            // If the parameter was a quoted-string, unescape quoted-pairs (\\" -> ", \\\\ -> \\)
            let final = wasQuoted ? unescapeHTTPQuotedPair(value) : value
            filename = final
        }
    }

    return filenameStar ?? filename
}

private func decodeRFC5987FilenameStar(_ value: String) -> String? {
    // RFC 5987: value is charset'lang'%XX-encoded bytes. We must interpret percent-escapes into raw bytes
    // and then decode those bytes using the specified charset.
    let components = value.split(separator: "'", maxSplits: 2).map(String.init)
    guard components.count == 3 else {
        // Some servers may omit charset/lang; try strict percent-to-bytes decode as UTF-8
        let bytes = percentDecodeToBytes(value)
        return String(data: bytes, encoding: .utf8)
    }
    let charset = components[0].trimmingCharacters(in: .whitespacesAndNewlines)
    let encodedBytes = components[2]

    let data = percentDecodeToBytes(encodedBytes)

    // Map IANA charset name to NSStringEncoding via CoreFoundation
    let cfEncoding = CFStringConvertIANACharSetNameToEncoding(charset as CFString)
    if cfEncoding != kCFStringEncodingInvalidId {
        let nsEncoding = CFStringConvertEncodingToNSStringEncoding(cfEncoding)
        let encoding = String.Encoding(rawValue: nsEncoding)
        if let s = String(data: data, encoding: encoding) { return s }
    }

    // Fallbacks: try UTF-8 then ISO-8859-1
    if let s = String(data: data, encoding: .utf8) { return s }
    if let s = String(data: data, encoding: .isoLatin1) { return s }
    return nil
}

/// Percent-decode a string into raw bytes (Data). Non-hex or incomplete escapes are treated literally.
private func percentDecodeToBytes(_ s: String) -> Data {
    var out = Data()
    let scalars = Array(s.utf8)
    var i = 0
    while i < scalars.count {
        let b = scalars[i]
        if b == 0x25 /* '%' */ && i + 2 < scalars.count {
            let h1 = scalars[i+1]
            let h2 = scalars[i+2]
            let v1 = hexNibble(h1)
            let v2 = hexNibble(h2)
            if let n1 = v1, let n2 = v2 {
                out.append(UInt8(n1 << 4 | n2))
                i += 3
                continue
            }
        }
        out.append(b)
        i += 1
    }
    return out
}

@inline(__always)
private func hexNibble(_ c: UInt8) -> Int? {
    switch c {
    case 48...57:   return Int(c - 48)        // '0'-'9'
    case 65...70:   return Int(c - 55)        // 'A'-'F'
    case 97...102:  return Int(c - 87)        // 'a'-'f'
    default:        return nil
    }
}

/// Unescape RFC 2616 quoted-pair sequences in a quoted-string value.
/// Converts \" -> " and \\ -> \\ while leaving other characters intact.
private func unescapeHTTPQuotedPair(_ s: String) -> String {
    var out = String()
    out.reserveCapacity(s.count)
    var escaping = false
    for ch in s {
        if escaping {
            out.append(ch)
            escaping = false
        } else if ch == "\\" {
            escaping = true
        } else {
            out.append(ch)
        }
    }
    if escaping { out.append("\\") }
    return out
}

/// Sniff a small body prefix to classify obvious non-audio generic payloads.
/// Returns a lowercase kind string like "json", "xml", or "text" if detected; otherwise nil.
private func sniffGenericErrorBodyKind(_ data: Data) -> String? {
    let prefixLen = min(data.count, 2048)
    let snippet = data.prefix(prefixLen)
    // Best-effort decode to a string for inspection
    let s: String? = String(data: snippet, encoding: .utf8)
        ?? String(data: snippet, encoding: .isoLatin1)
    guard let str = s?.trimmingCharacters(in: .whitespacesAndNewlines), !str.isEmpty else {
        return nil
    }
    let lower = str.lowercased()

    // JSON/JSONP-like payloads
    if lower.hasPrefix("{") || lower.hasPrefix("[") || lower.hasPrefix("(") {
        return "json"
    }

    // XML or HTML-like (HTML is already handled earlier, but we still detect XML here)
    if lower.hasPrefix("<") {
        if lower.hasPrefix("<?xml") { return "xml" }
        if lower.hasPrefix("<!doctype") { return "xml" }
        if lower.hasPrefix("<rss") || lower.hasPrefix("<feed") { return "xml" }
        // If it's clearly HTML, earlier sniff should have caught it; fall through otherwise
    }

    // Common plaintext error markers from cloud providers
    if lower.contains("accessdenied") || lower.contains("signaturedoesnotmatch") {
        return "text"
    }

    return nil
}

