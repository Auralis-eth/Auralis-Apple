import SwiftData

@MainActor
struct SearchAssembly {
    func makeSearchHistoryStore(modelContext: ModelContext) -> SearchHistoryStore {
        SearchHistoryStore(modelContext: modelContext)
    }
}
