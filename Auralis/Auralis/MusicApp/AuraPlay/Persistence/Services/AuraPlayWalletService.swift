import Foundation
import SwiftData

@ModelActor
actor AuraPlayWalletService {
    func upsert(_ request: AuraPlayWalletUpsertRequest) throws -> String {
        let walletID = AuraPlayWallet.scopedID(address: request.address, chain: request.chain)
        let descriptor = FetchDescriptor<AuraPlayWallet>(
            predicate: #Predicate<AuraPlayWallet> { wallet in
                wallet.id == walletID
            }
        )

        let wallet = try modelContext.fetch(descriptor).first ?? {
            let newWallet = AuraPlayWallet(
                address: request.address,
                chain: request.chain,
                displayName: request.displayName,
                createdAt: request.syncedAt,
                updatedAt: request.syncedAt,
                lastSyncedAt: request.syncedAt
            )
            modelContext.insert(newWallet)
            return newWallet
        }()

        wallet.addressRawValue = request.address
        wallet.chain = request.chain
        wallet.displayName = request.displayName
        wallet.updatedAt = request.syncedAt
        wallet.lastSyncedAt = request.syncedAt

        try modelContext.save()
        return walletID
    }
}
