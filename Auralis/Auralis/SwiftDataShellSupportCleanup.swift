import AuralisPrimaryModels
import AuralisPrimaryPersistence
import Foundation
import ReceiptStorage
import SwiftData
import TokenStorage

extension ModelContext {
    func deleteAllShellSupportData() throws {
        for receipt in try fetch(FetchDescriptor<StoredReceipt>()) {
            delete(receipt)
        }
        try delete(
            model: TokenHolding.self,
            where: #Predicate<TokenHolding> { _ in true }
        )
        for item in try fetch(FetchDescriptor<MusicLibraryItem>()) {
            delete(item)
        }
        try delete(
            model: SearchHistoryRecord.self,
            where: #Predicate<SearchHistoryRecord> { _ in true }
        )
        try delete(
            model: Playlist.self,
            where: #Predicate<Playlist> { _ in true }
        )

        for account in try fetch(FetchDescriptor<EOAccount>()) {
            account.clearAllAuraPlaySyncState()
        }
    }
}
