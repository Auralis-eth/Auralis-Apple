import Foundation
@testable import MusicFeature
import Testing

struct AuraPlayErrorPresentationTests {
    @Test(
        "AuraPlay user-facing error messages do not include raw underlying descriptions",
        arguments: [
            AuraPlayErrorPresentationContext.librarySync,
            .librarySummary,
            .playlistMutation,
            .playlistGeneration,
            .playlistSave,
            .recommendation,
            .search,
            .artwork,
            .playback
        ]
    )
    func messagesHideUnderlyingDescriptions(context: AuraPlayErrorPresentationContext) {
        let rawDescription = "SQLITE_CORRUPT: database disk image is malformed"
        let message = AuraPlayErrorPresentation.message(
            for: NSError(
                domain: "MigrationTest",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: rawDescription]
            ),
            context: context
        )

        #expect(message.isEmpty == false)
        #expect(message.contains(rawDescription) == false)
        #expect(message.contains("SQLITE") == false)
    }

    @Test("AuraPlay wrapped errors use reviewed product copy")
    func wrappedErrorsUseReviewedCopy() {
        let error = AuraPlayError.library(
            NSError(
                domain: "Provider",
                code: 429,
                userInfo: [NSLocalizedDescriptionKey: "HTTP 429 raw provider body"]
            )
        )

        #expect(error.localizedDescription.contains("HTTP 429") == false)
        #expect(error.localizedDescription == AuraPlayErrorPresentation.message(for: error, context: .librarySummary))
    }

    @Test(
        "AuraPlay errors provide actionable recovery guidance",
        arguments: [
            AuraPlayError.network(.rateLimited),
            .library("Library unavailable."),
            .playback("Playback unavailable."),
            .queue("Queue unavailable."),
            .artwork("Artwork unavailable."),
            .configuration("Configuration unavailable."),
            .mediaResolution("Media unavailable."),
            .unknown("Request unavailable.")
        ]
    )
    func errorsProvideRecoveryGuidance(error: AuraPlayError) {
        #expect(error.recoverySuggestion?.isEmpty == false)
    }

    @Test("Unknown errors normalize without exposing underlying details")
    func unknownErrorsNormalizeSafely() {
        let rawDescription = "provider-secret-response-body"
        let normalized = AuraPlayError.normalized(
            NSError(domain: "Provider", code: 500, userInfo: [NSLocalizedDescriptionKey: rawDescription])
        )

        #expect(normalized == .unknown("AuraPlay could not complete the request."))
        #expect(normalized.localizedDescription.contains(rawDescription) == false)
    }

    @Test("Known AuraPlay errors retain their typed identity during normalization")
    func knownErrorsRemainTyped() {
        let original = AuraPlayError.network(.rateLimited)

        #expect(AuraPlayError.normalized(original) == original)
    }
}
