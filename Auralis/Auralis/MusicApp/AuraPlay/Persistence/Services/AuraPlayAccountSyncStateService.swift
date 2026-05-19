import AuralisPrimaryModels
import AuralisPrimaryPersistence
import Foundation
import MusicFeature
import SwiftData

@ModelActor
actor AuraPlayAccountSyncStateService {
    func markSynced(_ request: AuraPlayAccountSyncUpdateRequest) throws {
        let address = request.address
        let descriptor = FetchDescriptor<EOAccount>(
            predicate: #Predicate<EOAccount> { account in
                account.address == address
            }
        )

        let account = try modelContext.fetch(descriptor).first ?? {
            let newAccount = EOAccount(
                address: request.address,
                access: .readonly,
                name: request.displayName
            )
            modelContext.insert(newAccount)
            return newAccount
        }()

        if let displayName = request.displayName, !displayName.isEmpty {
            account.name = displayName
        }
        account.markAuraPlaySynced(on: request.chain, at: request.syncedAt)

        try modelContext.save()
    }
}
