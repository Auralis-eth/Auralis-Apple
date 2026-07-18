import AuralisPrimaryModels
import Foundation
import SwiftData

@ModelActor
public actor AuraPlayNFTTokenService: NFTTokenPersisting {
    public func upsertAll(_ tokens: [NFTTokenDTO]) async throws {
        let now = Date()
        for token in tokens {
            if let existing = try fetchToken(id: token.compositeID) {
                existing.apply(token, now: now)
            } else {
                modelContext.insert(AuraPlayNFTToken(dto: token, now: now))
            }
        }
        try modelContext.save()
    }

    public func activeIDs(walletAddress: String, chain: Chain) async throws -> Set<String> {
        let normalizedWallet = NFTTokenDTO.normalizedScopeComponent(walletAddress) ?? walletAddress
        let chainRawValue = chain.rawValue
        let descriptor = FetchDescriptor<AuraPlayNFTToken>(
            predicate: #Predicate<AuraPlayNFTToken> { token in
                token.walletAddress == normalizedWallet &&
                token.chainRawValue == chainRawValue &&
                token.isActive
            }
        )
        return Set(try modelContext.fetch(descriptor).map(\.compositeID))
    }

    public func markInactive(ids: Set<String>) async throws {
        guard !ids.isEmpty else {
            return
        }
        let now = Date()
        for id in ids {
            guard let token = try fetchToken(id: id) else {
                continue
            }
            token.isActive = false
            token.updatedAt = now
        }
        try modelContext.save()
    }

    public func fetchAll(walletAddress: String, chain: Chain) throws -> [AuraPlayNFTToken] {
        let normalizedWallet = NFTTokenDTO.normalizedScopeComponent(walletAddress) ?? walletAddress
        let chainRawValue = chain.rawValue
        let descriptor = FetchDescriptor<AuraPlayNFTToken>(
            predicate: #Predicate<AuraPlayNFTToken> { token in
                token.walletAddress == normalizedWallet &&
                token.chainRawValue == chainRawValue
            },
            sortBy: [SortDescriptor(\.compositeID)]
        )
        return try modelContext.fetch(descriptor)
    }

    private func fetchToken(id: String) throws -> AuraPlayNFTToken? {
        var descriptor = FetchDescriptor<AuraPlayNFTToken>(
            predicate: #Predicate<AuraPlayNFTToken> { token in
                token.compositeID == id
            }
        )
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first
    }
}
