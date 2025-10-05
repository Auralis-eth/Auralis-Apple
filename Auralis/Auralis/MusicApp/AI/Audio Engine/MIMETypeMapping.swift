import Foundation
import UniformTypeIdentifiers

/// Maps audio MIME types to preferred filename extensions.
///
/// This mapper performs a single-pass normalization (trim, strip parameters, lowercase),
/// and routes lookups through an immutable mapping table with common aliases, falling back to UTType when possible.
///
/// Policy on aliases:
/// - Retains a small set of accepted aliases for compatibility and historical reasons,
///   including vendor-prefixed `x-` types and a few non-standard aliases like `audio/mp3`.
/// - Does not accept non-audio top-level types such as `application/ogg`
///   as audio MIME types.
/// - Mapping favors common, canonical extensions per MIME subtype.
///
/// Return semantics:
/// - `preferredExtension(for:)` returns a filename extension when the MIME is
///   recognized as audio (via table or UTType fallback), or `nil` otherwise.
/// - `lookup(_:)` returns a typed result that distinguishes non-audio MIME from
///   unknown audio subtypes.
///
/// Thread-safety & Sendability:
/// - All static data is immutable; the type is safe to use from any thread.
/// - No global state is mutated.
public enum AudioMIMEMapper {
    /// Result for detailed lookups that clarifies outcome semantics.
    public enum LookupResult: Sendable, Equatable {
        /// A successful resolution to an extension. `source` indicates where it came from.
        case success(ext: String, source: Source)
        /// The input was a MIME of a non-audio top-level type (e.g., "video/mp4").
        case nonAudio
        /// The input appears to be an audio MIME (top-level type is `audio`) but is unknown.
        case unknownAudio

        /// Origin of a successful mapping.
        public enum Source: Sendable, Equatable {
            case table
            case utType
        }
    }

    // MARK: - Public API

    /// Backward-compatible API: returns the preferred extension for a MIME type if known.
    /// - Parameter mime: A MIME type string. Parameters (e.g., `; codecs=...`) are allowed.
    /// - Returns: Preferred extension if resolvable to an audio type; otherwise `nil`.
    public static func preferredExtension(for mime: String) -> String? {
        switch lookup(mime) {
        case .success(let ext, _):
            return ext
        case .nonAudio, .unknownAudio:
            return nil
        }
    }

    /// Detailed lookup that distinguishes non-audio from unknown audio.
    /// - Parameter mime: A MIME type string. Parameters are allowed.
    /// - Returns: A `LookupResult` describing the outcome.
    @discardableResult
    public static func lookup(_ mime: String) -> LookupResult {
        let normalized = normalize(mime)
        guard let slashIdx = normalized.firstIndex(of: "/") else {
            // Not a valid type/subtype form; attempt UTType fallback as a last resort
            return utTypeLookup(forNormalizedMIME: normalized) ?? .nonAudio
        }
        let topLevel = normalized[..<slashIdx]
        let isAudioTopLevel = (topLevel == "audio")

        if let mapped = mapping[normalized] {
            return .success(ext: mapped, source: .table)
        }

        if let result = utTypeLookup(forNormalizedMIME: normalized) {
            switch result {
            case .success(let ext, _):
                return .success(ext: ext, source: .utType)
            case .nonAudio:
                return .nonAudio
            case .unknownAudio:
                return isAudioTopLevel ? .unknownAudio : .nonAudio
            }
        }

        return isAudioTopLevel ? .unknownAudio : .nonAudio
    }

    /// Reverse lookup using UTType first, then the mapping table.
    /// - Parameter ext: A filename extension (with or without leading dot).
    /// - Returns: Preferred MIME type for a known audio extension, otherwise `nil`.
    public static func preferredMIME(forExtension ext: String) -> String? {
        let cleaned = cleanExtension(ext)
        // Prefer UTType for broader coverage, guarded by audio conformance.
        if let ut = UTType(filenameExtension: cleaned), ut.conforms(to: .audio), let mime = ut.preferredMIMEType {
            return mime
        }
        // Fall back to reverse table.
        if let mime = reverseMapping[cleaned] {
            return mime
        }
        return nil
    }

    // MARK: - Implementation

    /// Canonical mapping table from MIME to preferred extension. Include accepted aliases.
    /// Keys are normalized: lowercased, no parameters.
    private static let mapping: [String: String] = [
        "audio/mpeg": "mp3",
        "audio/mp3": "mp3", // compatibility alias (non-standard)
        "audio/aac": "aac",
        "audio/aacp": "aac", // HE-AAC streaming profile; prefer raw AAC extension for files
        "audio/mp4": "m4a",
        "audio/x-m4a": "m4a", // vendor alias
        "audio/wav": "wav",
        "audio/x-wav": "wav", // vendor alias
        "audio/wave": "wav", // historical alias
        "audio/vnd.wave": "wav", // historical alias
        "audio/flac": "flac",
        "audio/x-flac": "flac", // vendor alias
        "audio/ogg": "ogg",
        "audio/opus": "opus",
        "audio/webm": "webm",
        "audio/aiff": "aiff",
        "audio/x-aiff": "aiff", // vendor alias
        "audio/aifc": "aifc",
        "audio/x-aifc": "aifc", // vendor alias
        "audio/amr": "amr",
        "audio/amr-wb": "awb", // map wideband to .awb
        "audio/3gpp": "3gp",
        "audio/3gpp2": "3g2",
        "audio/x-ms-wma": "wma", // vendor/common alias
        "audio/wma": "wma", // compatibility alias
        "audio/x-caf": "caf", // Apple historical
        "audio/caf": "caf",
        "audio/midi": "mid",
        "audio/x-midi": "mid", // alias
        "audio/sp-midi": "mid", // alias
        "audio/mid": "mid", // alias
        "audio/ac3": "ac3",
        "audio/eac3": "eac3"
    ]

    /// Reverse mapping from extension to a preferred MIME type.
    /// Derived automatically from `mapping` with heuristics to pick canonical MIME.
    private static let reverseMapping: [String: String] = {
        var r: [String: String] = [:]

        func isAudioMime(_ mime: String) -> Bool {
            return mime.hasPrefix("audio/")
        }

        func isVendorPrefixed(_ mime: String) -> Bool {
            // Check if subtype part starts with "x-"
            if let slashIndex = mime.firstIndex(of: "/") {
                let subtypeStart = mime.index(after: slashIndex)
                return mime[subtypeStart...].hasPrefix("x-")
            }
            return false
        }

        func canonicalMime(for ext: String, current: String?, candidate: String) -> String {
            // Prefer audio/ types and non-vendor prefixes
            // Also apply explicit canonical overrides for some extensions

            // Explicit canonical overrides for known extensions:
            let canonicalOverrides: [String: String] = [
                "m4a": "audio/mp4",
                "aiff": "audio/aiff",
                "aif": "audio/aiff",
                "caf": "audio/x-caf",
                "wma": "audio/x-ms-wma",
                "awb": "audio/amr-wb"
            ]

            if let override = canonicalOverrides[ext] {
                return override
            }

            guard let current = current else {
                return candidate
            }

            let currentIsAudio = isAudioMime(current)
            let candidateIsAudio = isAudioMime(candidate)

            if currentIsAudio != candidateIsAudio {
                return candidateIsAudio ? candidate : current
            }

            let currentIsVendor = isVendorPrefixed(current)
            let candidateIsVendor = isVendorPrefixed(candidate)

            if currentIsVendor != candidateIsVendor {
                return candidateIsVendor ? current : candidate
            }

            // Prefer lexicographically smaller mime as tie breaker for determinism
            return current < candidate ? current : candidate
        }

        for (mime, ext) in mapping {
            if let existing = r[ext] {
                r[ext] = canonicalMime(for: ext, current: existing, candidate: mime)
            } else {
                r[ext] = mime
            }
        }
        return r
    }()

    /// Normalize an input MIME once per call, using a single pass:
    /// - Trims whitespace
    /// - Strips parameters after ';'
    /// - Lowercases the entire result
    private static func normalize(_ mime: String) -> String {
        let trimmed = mime.trimmingCharacters(in: .whitespacesAndNewlines)
        let core: Substring
        if let semi = trimmed.firstIndex(of: ";") {
            core = trimmed[..<semi]
        } else {
            core = Substring(trimmed)
        }
        return core.lowercased()
    }

    /// Clean a filename extension: remove leading dot and lowercase.
    private static func cleanExtension(_ ext: String) -> String {
        let noDot: Substring
        if ext.first == "." {
            noDot = ext.dropFirst()
        } else {
            noDot = Substring(ext)
        }
        return noDot.lowercased()
    }

    /// UTType fallback, guarded by audio conformance. Expects a normalized MIME.
    private static func utTypeLookup(forNormalizedMIME mime: String) -> LookupResult? {
        if let ut = UTType(mimeType: mime) {
            if ut.conforms(to: .audio), let ext = ut.preferredFilenameExtension {
                return .success(ext: ext, source: .utType)
            } else {
                return .nonAudio
            }
        }
        return nil
    }
}
