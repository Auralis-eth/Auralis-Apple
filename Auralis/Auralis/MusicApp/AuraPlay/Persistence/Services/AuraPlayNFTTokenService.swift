import AuralisPrimaryModels
import Foundation
import SwiftData

@ModelActor
actor AuraPlayNFTTokenService {
    func replaceAll(
        walletID: String,
        requests: [AuraPlayNFTTokenUpsertRequest],
        syncedAt: Date
    ) throws {
        let wallet = try fetchWallet(id: walletID)
        let existingTokens = try fetchScopedTokens(walletID: walletID)
        var existingByID = Dictionary(uniqueKeysWithValues: existingTokens.map { ($0.compositeID, $0) })
        var retainedIDs: Set<String> = []

        for request in requests {
            let compositeID = AuraPlayNFTToken.makeCompositeID(
                walletID: walletID,
                contractAddressRawValue: request.contractAddressRawValue,
                tokenID: request.tokenID
            )
            retainedIDs.insert(compositeID)

            let token = existingByID[compositeID] ?? {
                let newToken = AuraPlayNFTToken(
                    walletID: walletID,
                    sourceNFTID: request.sourceNFTID,
                    contractAddressRawValue: request.contractAddressRawValue,
                    tokenID: request.tokenID,
                    tokenType: request.tokenType,
                    title: request.title,
                    artistName: request.artistName,
                    collectionName: request.collectionName,
                    artworkURLString: request.artworkURLString,
                    playbackURLString: request.playbackURLString,
                    contentType: request.contentType,
                    sourceUpdatedAtRawValue: request.sourceUpdatedAtRawValue,
                    createdAt: syncedAt,
                    updatedAt: syncedAt
                )
                newToken.wallet = wallet
                modelContext.insert(newToken)
                existingByID[compositeID] = newToken
                return newToken
            }()

            token.walletID = walletID
            token.wallet = wallet
            token.sourceNFTID = request.sourceNFTID
            token.contractAddressRawValue = request.contractAddressRawValue
            token.tokenID = request.tokenID
            token.tokenType = request.tokenType
            token.title = request.title
            token.artistName = request.artistName
            token.collectionName = request.collectionName
            token.artworkURLString = request.artworkURLString
            token.playbackURLString = request.playbackURLString
            token.contentType = request.contentType
            token.sourceUpdatedAtRawValue = request.sourceUpdatedAtRawValue
            token.updatedAt = syncedAt
        }

        for token in existingTokens where !retainedIDs.contains(token.compositeID) {
            modelContext.delete(token)
        }

        try modelContext.save()
    }

    private func fetchWallet(id: String) throws -> AuraPlayWallet? {
        let descriptor = FetchDescriptor<AuraPlayWallet>(
            predicate: #Predicate<AuraPlayWallet> { wallet in
                wallet.id == id
            }
        )
        return try modelContext.fetch(descriptor).first
    }

    private func fetchScopedTokens(walletID: String) throws -> [AuraPlayNFTToken] {
        let descriptor = FetchDescriptor<AuraPlayNFTToken>(
            predicate: #Predicate<AuraPlayNFTToken> { token in
                token.walletID == walletID
            }
        )
        return try modelContext.fetch(descriptor)
    }
}
