import AccountStorage
import MusicFeature

@MainActor
func makeAppAccountScopedPersistenceParticipants() -> [AccountScopedPersistenceParticipant] {
    [
        AccountScopedPersistenceParticipant(
            identifier: "music",
            participant: MusicLibraryAccountPersistenceParticipant.self
        ),
        AccountScopedPersistenceParticipant(
            identifier: "search",
            participant: SearchHistoryAccountPersistenceParticipant.self
        )
    ]
}
