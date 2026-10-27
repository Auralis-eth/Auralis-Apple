import AuralisCrypto
import AuralisOperators

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
