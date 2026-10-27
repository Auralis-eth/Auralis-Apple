import AuralisCrypto
import Foundation
import AuralisOperators
import AuralisReceipts
import SwiftData

extension ModelContext {
    func deleteAllShellSupportData() throws {
        try deleteFetchedModels(matching: FetchDescriptor<StoredReceipt>())
        try deleteFetchedModels(matching: FetchDescriptor<TokenHolding>())
        try deleteFetchedModels(matching: FetchDescriptor<MusicLibraryItem>())
        try deleteFetchedModels(matching: FetchDescriptor<SearchHistoryRecord>())
        try deleteFetchedModels(matching: FetchDescriptor<Playlist>())

        for account in try fetch(FetchDescriptor<EOAccount>()) {
            account.clearAllAuraPlaySyncState()
        }
    }
}
