@testable import MusicFeature
import Foundation
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
            .playback,
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
}
