//
//  NFTRefreshStateComputer.swift
//  Auralis
//
//  Created by Codex on 8/26/25.
//

import AuralisPrimaryModels
import Foundation

struct NFTRefreshScope: Hashable, Sendable {
    let accountAddress: String
    let chain: Chain

    init?(accountAddress: String?, chain: Chain) {
        guard let normalizedAccountAddress = NFT.normalizedScopeComponent(accountAddress) else {
            return nil
        }

        self.accountAddress = normalizedAccountAddress
        self.chain = chain
    }
}

@MainActor
final class NFTRefreshStateComputer {
    let refreshTTL: TimeInterval

    private var successfulRefreshTimestamps: [NFTRefreshScope: Date] = [:]

    init(refreshTTL: TimeInterval) {
        self.refreshTTL = refreshTTL
    }

    func lastSuccessfulRefreshAt(
        for accountAddress: String?,
        chain: Chain
    ) -> Date? {
        guard let refreshScope = NFTRefreshScope(
            accountAddress: accountAddress,
            chain: chain
        ) else {
            return nil
        }

        return successfulRefreshTimestamps[refreshScope]
    }

    func markRefreshSucceeded(
        for accountAddress: String?,
        chain: Chain,
        at date: Date = .now
    ) {
        guard let refreshScope = NFTRefreshScope(
            accountAddress: accountAddress,
            chain: chain
        ) else {
            return
        }

        successfulRefreshTimestamps[refreshScope] = date
    }

    func isFresh(
        for accountAddress: String?,
        chain: Chain,
        referenceDate: Date = .now
    ) -> Bool {
        guard let lastSuccessfulRefreshAt = lastSuccessfulRefreshAt(
            for: accountAddress,
            chain: chain
        ) else {
            return false
        }

        return referenceDate.timeIntervalSince(lastSuccessfulRefreshAt) <= refreshTTL
    }

    func isStale(
        for accountAddress: String?,
        chain: Chain,
        referenceDate: Date = .now
    ) -> Bool {
        !isFresh(
            for: accountAddress,
            chain: chain,
            referenceDate: referenceDate
        )
    }

    func reset() {
        successfulRefreshTimestamps.removeAll()
    }
}
