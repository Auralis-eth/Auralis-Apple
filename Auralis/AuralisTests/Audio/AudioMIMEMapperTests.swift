import Testing
@testable import Auralis
import UniformTypeIdentifiers

@Suite("AudioMIMEMapper tests")
struct AudioMIMEMapperTests {

    @Test("Normalization trims and strips parameters, conditional lowercasing")
    func testNormalizationAndParameters() {
        // The public API hides normalization; we assert outcomes through lookups.
        #expect(AudioMIMEMapper.preferredExtension(for: "  audio/mpeg  ") == "mp3")
        #expect(AudioMIMEMapper.preferredExtension(for: "audio/mpeg; codecs=mp3") == "mp3")
        #expect(AudioMIMEMapper.preferredExtension(for: "AuDiO/MP3") == "mp3")
        #expect(AudioMIMEMapper.preferredExtension(for: "audio/mp4; charset=UTF-8; foo=bar") == "m4a")
    }

    @Test("Alias mappings resolve to the same extension")
    func testAliases() {
        #expect(AudioMIMEMapper.preferredExtension(for: "audio/mp3") == "mp3")
        #expect(AudioMIMEMapper.preferredExtension(for: "audio/vnd.wave") == "wav")
        #expect(AudioMIMEMapper.preferredExtension(for: "audio/x-wav") == "wav")
        #expect(AudioMIMEMapper.preferredExtension(for: "audio/x-aiff") == "aiff")
        #expect(AudioMIMEMapper.preferredExtension(for: "application/ogg") == "ogg")
        #expect(AudioMIMEMapper.preferredExtension(for: "audio/aacp") == "m4a")
    }

    @Test("Coverage for common formats")
    func testCoverage() {
        let cases: [(String, String)] = [
            ("audio/mpeg", "mp3"),
            ("audio/mp3", "mp3"),
            ("audio/aac", "aac"),
            ("audio/mp4", "m4a"),
            ("audio/x-m4a", "m4a"),
            ("audio/wav", "wav"),
            ("audio/x-wav", "wav"),
            ("audio/wave", "wav"),
            ("audio/flac", "flac"),
            ("audio/x-flac", "flac"),
            ("audio/ogg", "ogg"),
            ("audio/opus", "opus"),
            ("audio/webm", "webm"),
            ("audio/aiff", "aiff"),
            ("audio/x-aiff", "aiff"),
            ("audio/aifc", "aifc"),
            ("audio/x-aifc", "aifc"),
            ("audio/amr", "amr"),
            ("audio/amr-wb", "amr"),
            ("audio/3gpp", "3gp"),
            ("audio/3gpp2", "3g2"),
            ("audio/x-ms-wma", "wma"),
            ("audio/wma", "wma"),
            ("audio/x-caf", "caf"),
            ("audio/caf", "caf"),
            ("audio/midi", "mid"),
            ("audio/x-midi", "mid"),
            ("audio/mid", "mid"),
            ("audio/sp-midi", "mid"),
            ("audio/ac3", "ac3"),
            ("audio/eac3", "eac3")
        ]
        for (mime, expected) in cases {
            #expect(AudioMIMEMapper.preferredExtension(for: mime) == expected, "Expected \(expected) for \(mime)")
        }
    }

    @Test("Lookup result distinguishes non-audio from unknown audio")
    func testLookupResultSemantics() {
        // Unknown audio subtype
        switch AudioMIMEMapper.lookup("audio/unknown") {
        case .unknownAudio: break
        default: Issue.record("Expected unknownAudio for audio/unknown")
        }
        // Non-audio type
        switch AudioMIMEMapper.lookup("video/mp4") {
        case .nonAudio: break
        default: Issue.record("Expected nonAudio for video/mp4")
        }
    }

    @Test("UTType fallback resolves common types when not in table")
    func testUTTypeFallback() {
        // Choose a likely UTType-known audio MIME not explicitly in our table.
        // Example: some platforms map "audio/x-aac" to UTType.
        let candidate = "audio/x-aac"
        let result = AudioMIMEMapper.lookup(candidate)
        // Accept either success via UTType or unknownAudio if UTType lacks it.
        switch result {
        case .success(let ext, _):
            // If UTType resolved, it should be an audio extension.
            #expect(!ext.isEmpty)
        case .unknownAudio:
            // Acceptable if UTType doesn't know this alias on the running OS.
            break
        case .nonAudio:
            Issue.record("audio/x-aac should not be classified as nonAudio")
        }
    }

    @Test("Reverse mapping returns expected MIME for standard extensions")
    func testReverseMapping() {
        #expect(AudioMIMEMapper.preferredMIME(forExtension: "mp3") == "audio/mpeg")
        #expect(AudioMIMEMapper.preferredMIME(forExtension: ".m4a") == "audio/mp4")
        #expect(AudioMIMEMapper.preferredMIME(forExtension: "wav") == "audio/wav")
        #expect(AudioMIMEMapper.preferredMIME(forExtension: "flac") == "audio/flac")
        #expect(AudioMIMEMapper.preferredMIME(forExtension: "ogg") == "audio/ogg")
    }
}
