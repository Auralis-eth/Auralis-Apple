//
//  NFTRefreshStateComputer.swift
//  Auralis
//
//  Created by Codex on 8/26/25.
//

import AuralisPrimaryModels
import Foundation

public struct NFTRefreshScope: Hashable, Sendable {
    public let accountAddress: String
    public let chain: Chain

    public init?(accountAddress: String?, chain: Chain) {
        guard let normalizedAccountAddress = Self.normalizedScopeComponent(accountAddress) else {
            return nil
        }

        self.accountAddress = normalizedAccountAddress
        self.chain = chain
    }

    private static func normalizedScopeComponent(_ value: String?) -> String? {
        let normalizedValue = value?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        guard let normalizedValue, !normalizedValue.isEmpty else {
            return nil
        }

        return normalizedValue
    }
}

@MainActor
public final class NFTRefreshStateComputer {
    public let refreshTTL: TimeInterval

    private var successfulRefreshTimestamps: [NFTRefreshScope: Date] = [:]

    public init(refreshTTL: TimeInterval) {
        self.refreshTTL = refreshTTL
    }

    public func lastSuccessfulRefreshAt(
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

    public func markRefreshSucceeded(
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

    public func isFresh(
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

    public func isStale(
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

    public func reset() {
        successfulRefreshTimestamps.removeAll()
    }
}
